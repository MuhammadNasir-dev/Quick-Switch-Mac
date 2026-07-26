import AppKit
import Combine
import CoreGraphics
import Foundation
import os

/// System-wide keyboard interception for the switcher.
///
/// ## Bugs this replaces
///
/// The original tap had four defects that each break the app in production:
///
/// 1. `Unmanaged.passRetained(event)` on the pass-through path — this leaked a
///    retain on **every key event typed anywhere on the system**, an unbounded
///    leak that grows for as long as the app runs.
/// 2. `Unmanaged.passRetained(self)` for `userInfo` — permanently leaked the
///    `AppDelegate`.
/// 3. No handling of `.tapDisabledByTimeout` / `.tapDisabledByUserInput`. macOS
///    disables a tap whose callback is slow, and never re-enables it: the
///    hotkey dies silently and the only fix is relaunching the app.
/// 4. The tap ran on the **main** run loop, so every keystroke on the system
///    was gated behind SwiftUI layout. That is also what caused the timeouts in
///    (3).
///
/// This implementation runs the tap on a dedicated thread, decodes events into
/// `SwitcherCommand`s, and hands them to the main actor asynchronously. The
/// consume/pass-through decision is made synchronously from an atomically
/// mirrored copy of the switcher's state, so the callback never waits on the
/// main thread.
@MainActor
final class HotKeyMonitor {
    /// Why the tap gave up.
    enum Failure: Equatable {
        /// Accessibility trust was revoked while the tap was installed.
        case trustRevoked
        /// macOS disabled the tap for slowness repeatedly; re-arming it would
        /// risk locking the user's keyboard out.
        case repeatedTimeouts
    }

    /// Called on the main actor for each decoded command.
    var onCommand: ((SwitcherCommand) -> Void)?
    /// Fires whenever the system disables the tap, so any visible UI that
    /// depends on owning the keyboard can be torn down immediately.
    var onTapDisabled: (() -> Void)?
    /// Fires when the tap has been abandoned and will not be retried.
    var onTapFailed: ((Failure) -> Void)?
    /// Reports whether the tap is currently installed and enabled.
    @Published private(set) var isRunning = false

    /// `nonisolated` because the tap callback reads it from the input thread;
    /// `TapState` is itself lock-guarded and `Sendable`.
    private nonisolated let state = TapState()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var thread: Thread?
    private var threadRunLoop: CFRunLoop?
    private var threadContext: TapThreadContext?
    private var healthTimer: Timer?
    private var consecutiveDisables = 0
    private var lastDisableTime = Date.distantPast

    /// Weak self-reference handed to the C callback.
    ///
    /// `Unmanaged.passUnretained` is correct because `HotKeyMonitor` is owned by
    /// `AppServices` for the lifetime of the process and always calls `stop()`
    /// before deallocating.
    private var callbackContext: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    init(modifier: SwitcherModifier = .option) {
        state.setModifier(modifier)
    }

    deinit {
        // `stop()` is main-actor isolated; the tap objects themselves are
        // thread-safe CF types, so tear them down directly as a safety net.
        state.endRunning()
        healthTimer?.invalidate()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let threadRunLoop {
            CFRunLoopStop(threadRunLoop)
        }
    }

    // MARK: - Configuration

    func setModifier(_ modifier: SwitcherModifier) {
        state.setModifier(modifier)
    }

    /// Mirrors panel visibility into the tap thread.
    ///
    /// While `true`, the tap swallows navigation and text keys so they never
    /// reach the focused application.
    func setSwitcherVisible(_ visible: Bool) {
        state.setSwitcherVisible(visible)
    }

    /// While `true`, releasing the modifier confirms the selection.
    func setHoldModeActive(_ active: Bool) {
        state.setHoldModeActive(active)
    }

    // MARK: - Lifecycle

    /// Installs the tap. Returns `false` when Accessibility trust is missing.
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        guard AXIsProcessTrusted() else {
            Log.input.error("Cannot install event tap without Accessibility trust")
            return false
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: HotKeyMonitor.tapCallback,
            userInfo: callbackContext
        ) else {
            Log.input.error("CGEvent.tapCreate failed")
            return false
        }

        self.tap = tap
        consecutiveDisables = 0
        lastDisableTime = .distantPast
        state.setTap(tap)
        startTapThread(with: tap)
        startHealthTimer()
        isRunning = true
        Log.input.notice("Event tap installed")
        return true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        healthTimer?.invalidate()
        healthTimer = nil

        // Signal the exit condition *before* waking the loop, otherwise the
        // thread re-enters `CFRunLoopRunInMode` and lives on for another second.
        state.endRunning()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let threadRunLoop, let runLoopSource {
            CFRunLoopRemoveSource(threadRunLoop, runLoopSource, .commonModes)
            CFRunLoopStop(threadRunLoop)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        state.setTap(nil)
        tap = nil
        runLoopSource = nil
        threadRunLoop = nil
        threadContext = nil
        thread = nil
        Log.input.notice("Event tap removed")
    }

    /// Runs the tap on its own thread so keystroke latency is never coupled to
    /// SwiftUI rendering on the main thread.
    ///
    /// The thread's exit condition lives in `TapState` (which is `nonisolated`
    /// and lock-guarded) rather than on `self`, because touching a `@MainActor`
    /// property from the tap thread would be a data race — and because the
    /// thread must be able to observe the stop request without hopping actors.
    private func startTapThread(with tap: CFMachPort) {
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            Log.input.error("CFMachPortCreateRunLoopSource failed")
            return
        }
        runLoopSource = source

        let state = self.state
        let context = TapThreadContext(tap: tap, source: source)
        let ready = DispatchSemaphore(value: 0)

        state.beginRunning()

        let thread = Thread {
            context.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(context.runLoop, context.source, .commonModes)
            CGEvent.tapEnable(tap: context.tap, enable: true)
            ready.signal()
            // A one-second bounded run keeps the loop responsive to `stop()`
            // even though the Mach port source itself never times out.
            while state.shouldKeepRunning {
                CFRunLoopRunInMode(.defaultMode, 1.0, false)
            }
        }
        thread.name = "com.window-manager.event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread

        // Wait for the run loop to exist so `stop()` always has something to
        // tear down; the timeout keeps a wedged thread from blocking launch.
        _ = ready.wait(timeout: .now() + 1.0)
        threadContext = context
        threadRunLoop = context.runLoop
    }

    /// Recovers a tap that macOS disabled, with strict limits.
    ///
    /// A tap can also be dropped when the trust database changes, which
    /// produces no event at all — hence the periodic check as well as the
    /// event-driven path.
    private func startHealthTimer() {
        healthTimer?.invalidate()
        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let tap = self.tap, self.isRunning else { return }

                // Trust can be revoked at any moment. Without it the tap is
                // useless, and re-arming it forever would be pure churn.
                guard AXIsProcessTrusted() else {
                    Log.input.notice("Accessibility trust lost; stopping the event tap")
                    self.stop()
                    self.onTapFailed?(.trustRevoked)
                    return
                }

                guard !CGEvent.tapIsEnabled(tap: tap) else {
                    // Healthy for a while: forgive historical timeouts so a
                    // rare hiccup never accumulates into a permanent give-up.
                    if Date().timeIntervalSince(self.lastDisableTime) > Self.disableForgivenessInterval {
                        self.consecutiveDisables = 0
                    }
                    return
                }

                self.attemptReenable(reason: "periodic check")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    /// How many disables in quick succession before the tap is abandoned.
    private static let maximumConsecutiveDisables = 4
    /// A tap healthy for this long has its disable count reset.
    private static let disableForgivenessInterval: TimeInterval = 30

    /// Responds to the system disabling the tap.
    ///
    /// The dangerous case is `.tapDisabledByTimeout` in a loop: macOS disables a
    /// tap whose callback is too slow, and if the app immediately re-arms it the
    /// system routes all keyboard input back through a tap that still cannot
    /// service it. Repeated blindly — which the previous implementation did,
    /// from both the callback and a timer — that locks the keyboard out
    /// system-wide with no way for the user to break the cycle.
    ///
    /// So: dismiss the panel, back off, and after a handful of failures stop
    /// entirely and report it. A switcher that has stopped working is a bug; a
    /// Mac that has stopped accepting input is an emergency.
    fileprivate func handleTapDisabled(timedOut: Bool) {
        guard isRunning else { return }
        _ = state.consumeReenableRequest()

        // The panel must not be left on screen owning nothing.
        onTapDisabled?()

        guard timedOut else {
            // `.tapDisabledByUserInput` is a transient security transition, not
            // a fault of ours; restore without counting it against the budget.
            attemptReenable(reason: "user-input transition")
            return
        }

        consecutiveDisables += 1
        lastDisableTime = Date()

        guard consecutiveDisables <= Self.maximumConsecutiveDisables else {
            Log.input.error("Event tap timed out repeatedly; abandoning it to keep the keyboard usable")
            stop()
            onTapFailed?(.repeatedTimeouts)
            return
        }

        // Exponential backoff gives a busy main thread room to recover instead
        // of being handed the entire keystroke stream again immediately.
        let delay = pow(2.0, Double(consecutiveDisables - 1)) * 0.25
        Log.input.notice("Event tap timed out (\(self.consecutiveDisables, privacy: .public)); retrying in \(delay, privacy: .public)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isRunning else { return }
            self.attemptReenable(reason: "timeout backoff")
        }
    }

    private func attemptReenable(reason: String) {
        guard isRunning, let tap, AXIsProcessTrusted() else { return }
        guard !CGEvent.tapIsEnabled(tap: tap) else { return }
        Log.input.notice("Re-enabling event tap (\(reason, privacy: .public))")
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Tap callback

    /// Runs on the tap thread. Must be fast and allocation-light.
    private nonisolated static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

        // macOS disables taps whose callback is too slow, and on certain
        // security transitions. Release the keyboard synchronously, then let
        // the main actor decide whether re-arming is safe.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            monitor.state.noteDisabled()
            let timedOut = type == .tapDisabledByTimeout
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    monitor.handleTapDisabled(timedOut: timedOut)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard let decision = monitor.state.decide(type: type, event: event) else {
            // Pass-through. `passUnretained` — the previous `passRetained` here
            // leaked one CGEvent per system-wide keystroke.
            return Unmanaged.passUnretained(event)
        }

        if let command = decision.command {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    monitor.onCommand?(command)
                }
            }
        }

        return decision.consume ? nil : Unmanaged.passUnretained(event)
    }
}

/// Non-`Sendable` CoreFoundation handles shared with the tap thread.
///
/// `CFMachPort` and `CFRunLoopSource` are thread-safe but not marked `Sendable`
/// by the CoreFoundation overlay. Boxing them keeps the unchecked conformance
/// in one auditable place instead of scattering `@preconcurrency` imports.
private nonisolated final class TapThreadContext: @unchecked Sendable {
    let tap: CFMachPort
    let source: CFRunLoopSource
    /// Written once by the tap thread before it signals readiness, then only
    /// read by the main actor — the semaphore is the happens-before edge.
    var runLoop: CFRunLoop?

    init(tap: CFMachPort, source: CFRunLoopSource) {
        self.tap = tap
        self.source = source
    }
}

/// Thread-shared switcher state plus the pure event-decoding logic.
///
/// Guarded by `os_unfair_lock`: the critical sections are a handful of loads
/// and stores, and this is on the path of every keystroke in the system, so a
/// lock with no syscall in the uncontended case is the right primitive.
private nonisolated final class TapState: @unchecked Sendable {
    struct Decision {
        var consume: Bool
        var command: SwitcherCommand?
    }

    private var lock = os_unfair_lock_s()
    private var modifierFlag: CGEventFlags = .maskCommand
    private var isSwitcherVisible = false
    private var isHoldModeActive = false
    private var keepRunning = false
    private var reenableRequested = false
    private var tapPort: CFMachPort?

    /// Exit condition for the tap thread's run loop.
    var shouldKeepRunning: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return keepRunning
    }

    func beginRunning() {
        os_unfair_lock_lock(&lock)
        keepRunning = true
        os_unfair_lock_unlock(&lock)
    }

    func endRunning() {
        os_unfair_lock_lock(&lock)
        keepRunning = false
        isSwitcherVisible = false
        isHoldModeActive = false
        os_unfair_lock_unlock(&lock)
    }

    /// `true` (once) if the tap reported itself disabled since the last check.
    func consumeReenableRequest() -> Bool {
        os_unfair_lock_lock(&lock)
        defer {
            reenableRequested = false
            os_unfair_lock_unlock(&lock)
        }
        return reenableRequested
    }

    func setModifier(_ modifier: SwitcherModifier) {
        os_unfair_lock_lock(&lock)
        modifierFlag = modifier.flag
        os_unfair_lock_unlock(&lock)
    }

    func setSwitcherVisible(_ visible: Bool) {
        os_unfair_lock_lock(&lock)
        isSwitcherVisible = visible
        os_unfair_lock_unlock(&lock)
    }

    func setHoldModeActive(_ active: Bool) {
        os_unfair_lock_lock(&lock)
        isHoldModeActive = active
        os_unfair_lock_unlock(&lock)
    }

    func setTap(_ port: CFMachPort?) {
        os_unfair_lock_lock(&lock)
        tapPort = port
        os_unfair_lock_unlock(&lock)
    }

    /// Handles the system disabling the tap, from the tap thread.
    ///
    /// **Releases the keyboard first.** While `isSwitcherVisible` is true the
    /// decision table swallows every key, including Escape. If the tap is
    /// re-armed while that flag is still set — and the panel is stuck because
    /// the main thread is wedged — the user has no keyboard at all and no way
    /// to dismiss anything. Clearing the flag here guarantees that a disabled
    /// tap always fails *open*.
    ///
    /// Re-enabling is deliberately **not** done here. The old code re-armed the
    /// tap immediately from this callback and again from a 3-second timer, so a
    /// tap that kept timing out was instantly put back in the input path,
    /// wedging keyboard input system-wide in a loop the user could not break.
    /// The decision now belongs to `HotKeyMonitor`, which applies backoff and
    /// gives up rather than fighting the system.
    func noteDisabled() {
        os_unfair_lock_lock(&lock)
        isSwitcherVisible = false
        isHoldModeActive = false
        reenableRequested = true
        os_unfair_lock_unlock(&lock)
    }

    /// Decodes an event. Returns `nil` to pass the event through untouched.
    func decide(type: CGEventType, event: CGEvent) -> Decision? {
        os_unfair_lock_lock(&lock)
        let modifier = modifierFlag
        let visible = isSwitcherVisible
        let holdMode = isHoldModeActive
        os_unfair_lock_unlock(&lock)

        let flags = event.flags

        if type == .flagsChanged {
            // Only interesting while holding the switcher open.
            guard visible, holdMode, !flags.contains(modifier) else { return nil }
            return Decision(consume: false, command: .modifierReleased)
        }

        guard type == .keyDown else {
            // Swallow key-up for keys we consumed on key-down, otherwise the
            // focused app sees an unmatched key-up.
            if visible, type == .keyUp {
                return Decision(consume: true, command: nil)
            }
            return nil
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Summon / advance.
        if keyCode == KeyCode.tab, flags.contains(modifier) {
            return Decision(consume: true, command: .invoke(reverse: flags.contains(.maskShift)))
        }
        // ⌘` is the system's "cycle windows within app" and a common muscle
        // memory, so mirror it — but only for the Command binding. ⌥` is the
        // dead key for grave accents on several layouts and must not be eaten.
        if keyCode == KeyCode.graveAccent, modifier == .maskCommand, flags.contains(modifier) {
            return Decision(consume: true, command: .invoke(reverse: flags.contains(.maskShift)))
        }

        guard visible else { return nil }

        // Everything below happens while the panel owns the keyboard.
        switch keyCode {
        case KeyCode.escape:
            return Decision(consume: true, command: .cancel)
        case KeyCode.return, KeyCode.keypadEnter:
            return Decision(consume: true, command: .confirm)
        case KeyCode.arrowDown:
            return Decision(consume: true, command: .moveVertical(1))
        case KeyCode.arrowUp:
            return Decision(consume: true, command: .moveVertical(-1))
        case KeyCode.arrowRight:
            return Decision(consume: true, command: .move(1))
        case KeyCode.arrowLeft:
            return Decision(consume: true, command: .move(-1))
        case KeyCode.pageDown:
            return Decision(consume: true, command: .moveVertical(4))
        case KeyCode.pageUp:
            return Decision(consume: true, command: .moveVertical(-4))
        case KeyCode.home:
            return Decision(consume: true, command: .moveToEdge(first: true))
        case KeyCode.end:
            return Decision(consume: true, command: .moveToEdge(first: false))
        case KeyCode.tab:
            return Decision(consume: true, command: .move(flags.contains(.maskShift) ? -1 : 1))
        case KeyCode.delete:
            if flags.contains(.maskAlternate) || flags.contains(.maskCommand) {
                return Decision(consume: true, command: .clearQuery)
            }
            return Decision(consume: true, command: .deleteBackward)
        default:
            break
        }

        // ⌘L flips between list and grid in place.
        if keyCode == KeyCode.letterL, flags.contains(.maskCommand) {
            return Decision(consume: true, command: .toggleLayout)
        }

        // ⌘1…⌘9 jump straight to a row.
        if flags.contains(.maskCommand), let digit = KeyCode.digit(for: keyCode) {
            return Decision(consume: true, command: .selectIndex(digit))
        }
        // While the summoning modifier is held it also acts as the index
        // modifier, so ⌥Tab then ⌥3 works for a non-Command binding too.
        if flags.contains(modifier), let digit = KeyCode.digit(for: keyCode) {
            return Decision(consume: true, command: .selectIndex(digit))
        }

        // Control-modified keys are left to the system (⌃F2 menu-bar focus and
        // friends); Command-modified letters are swallowed rather than
        // forwarded, so a stray ⌘Q cannot quit the app behind the panel.
        if flags.contains(.maskControl) {
            return Decision(consume: true, command: nil)
        }

        if let text = Self.characters(from: event), !text.isEmpty {
            return Decision(consume: true, command: .insertText(text))
        }

        // Unknown key while visible: consume so nothing leaks to the app below.
        return Decision(consume: true, command: nil)
    }

    /// Extracts the typed characters, honouring the active keyboard layout.
    ///
    /// The modifiers are stripped from a copy of the event first. This matters
    /// because the summoning modifier is still held while the user types their
    /// query: on a US layout, Option-o produces "ø" and Option-p produces "π",
    /// so reading the event as-is would put accented junk in the search field.
    /// Clearing the flags asks the layout for the *base* character instead,
    /// while still going through `keyboardGetUnicodeString` so non-QWERTY
    /// layouts (AZERTY, Dvorak, Cyrillic) keep working.
    private static func characters(from event: CGEvent) -> String? {
        let source: CGEvent
        if event.flags.isDisjoint(with: [.maskAlternate, .maskCommand, .maskControl]) {
            source = event
        } else if let stripped = event.copy() {
            stripped.flags = event.flags.intersection(.maskShift)
            source = stripped
        } else {
            source = event
        }

        var length = 0
        source.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else { return nil }

        var buffer = [UniChar](repeating: 0, count: length)
        source.keyboardGetUnicodeString(
            maxStringLength: length,
            actualStringLength: &length,
            unicodeString: &buffer
        )
        guard length > 0 else { return nil }

        let string = String(utf16CodeUnits: buffer, count: length)
        // Reject control characters, which are not meaningful search input.
        guard string.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return string
    }
}
