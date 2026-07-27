import AppKit
import ApplicationServices
import Combine
import Foundation
import os

/// Reasons the window index may be stale.
enum WindowChange: Sendable, Equatable {
    /// Structural change: a window appeared, vanished, or (un)minimised.
    case structural
    /// Cosmetic change: a title was edited.
    case metadata
    /// Focus moved; recency must be updated even if the list is unchanged.
    case focus(pid: pid_t)
}

/// Push-based observation of window lifecycle across every running application.
///
/// The original design re-enumerated the entire system on every hotkey press,
/// on the main thread. That is both the reason the panel could not hit a 50 ms
/// budget and the reason it showed stale titles.
///
/// Here, an `AXObserver` is attached per process and per window, so the app is
/// *told* when something changes and the cached index is refreshed in the
/// background before the user ever opens the panel.
///
/// ### Why there is still a slow timer
///
/// `AXObserver` delivery is best-effort. Some applications (notably ones that
/// recycle window elements, and anything that crashes) never emit
/// `kAXUIElementDestroyedNotification`. A 5-second revalidation compares only a
/// cheap `CGWindowListCopyWindowInfo` fingerprint and triggers a real refresh
/// solely when it differs — roughly 0.3 ms of work, and nothing at all when the
/// system is idle. This is a correctness backstop, not the primary mechanism.
@MainActor
final class WindowObservationCenter {
    /// Fires when something may have changed. Consumers coalesce.
    let changes = PassthroughSubject<WindowChange, Never>()

    private let filter: WindowFilter
    private var observers: [pid_t: ApplicationObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private var revalidationTimer: Timer?
    private var lastFingerprint: WindowFingerprint?
    private var isRunning = false

    /// Notifications observed on the application element itself.
    private static let applicationNotifications: [String] = [
        kAXWindowCreatedNotification as String,
        kAXFocusedWindowChangedNotification as String,
        kAXMainWindowChangedNotification as String,
        kAXApplicationHiddenNotification as String,
        kAXApplicationShownNotification as String,
        kAXApplicationActivatedNotification as String
    ]

    /// Notifications observed on each individual window element.
    ///
    /// `kAXUIElementDestroyedNotification` only fires for the element it is
    /// registered on, which is why per-window registration is necessary and
    /// app-level registration is not enough.
    private static let windowNotifications: [String] = [
        kAXUIElementDestroyedNotification as String,
        kAXWindowMiniaturizedNotification as String,
        kAXWindowDeminiaturizedNotification as String,
        kAXTitleChangedNotification as String
    ]

    init(filter: WindowFilter = WindowFilter()) {
        self.filter = filter
    }

    deinit {
        // `deinit` cannot hop actors; the timer and tokens are the only things
        // that outlive the object, and both are cleaned up in `stop()`, which
        // the owning service always calls. This is a belt-and-braces release
        // of the workspace tokens, which is safe from any thread.
        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        subscribeToWorkspace()
        for app in NSWorkspace.shared.runningApplications where filter.allowsApplication(app) {
            attachObserver(to: app.processIdentifier)
        }
        startRevalidationTimer()
        Log.windows.notice("Observation started for \(self.observers.count, privacy: .public) processes")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        revalidationTimer?.invalidate()
        revalidationTimer = nil
        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceTokens.removeAll()
        observers.values.forEach { $0.invalidate() }
        observers.removeAll()
        Log.windows.notice("Observation stopped")
    }

    /// Keeps per-window `destroyed`/`titleChanged` registrations in sync with
    /// the latest snapshot.
    ///
    /// Called after every successful enumeration. Registrations are diffed, so
    /// a steady-state refresh performs no Accessibility calls at all.
    func syncWindowObservations(with windows: [AppWindow]) {
        guard isRunning else { return }
        var byProcess: [pid_t: Set<AXElementRef>] = [:]
        for window in windows {
            // Windows found only through CoreGraphics have no element to watch;
            // the app-level observer still reports when they appear or vanish.
            guard let element = window.axElement else { continue }
            byProcess[window.pid, default: []].insert(element)
        }
        for (pid, elements) in byProcess {
            if observers[pid] == nil { attachObserver(to: pid) }
            observers[pid]?.syncWindows(elements, notifications: Self.windowNotifications)
        }
        // Processes that no longer contribute windows keep their app-level
        // observer (cheap, and they may open a window again) but shed their
        // per-window registrations.
        for (pid, observer) in observers where byProcess[pid] == nil {
            observer.syncWindows([], notifications: Self.windowNotifications)
        }
    }

    // MARK: - Workspace

    private func subscribeToWorkspace() {
        let center = NSWorkspace.shared.notificationCenter

        func observe(_ name: NSNotification.Name, _ handler: @escaping (Notification) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { handler(note) }
            }
            workspaceTokens.append(token)
        }

        observe(NSWorkspace.didLaunchApplicationNotification) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  self.filter.allowsApplication(app) else { return }
            // Freshly launched processes usually reject AXObserverCreate for a
            // few hundred milliseconds while they finish bootstrapping.
            self.attachObserver(to: app.processIdentifier, retriesRemaining: 8)
            self.changes.send(.structural)
        }

        observe(NSWorkspace.didTerminateApplicationNotification) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self.observers.removeValue(forKey: app.processIdentifier)?.invalidate()
            self.changes.send(.structural)
        }

        observe(NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self.changes.send(.focus(pid: app.processIdentifier))
        }

        for name in [
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification
        ] {
            observe(name) { [weak self] _ in self?.changes.send(.structural) }
        }

        // Display topology changes alter which Space windows report as active.
        let screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.changes.send(.structural) }
        }
        workspaceTokens.append(screenToken)
    }

    // MARK: - Accessibility observers

    private func attachObserver(to pid: pid_t, retriesRemaining: Int = 0) {
        guard isRunning, observers[pid] == nil, pid > 0 else { return }

        guard let observer = ApplicationObserver(
            pid: pid,
            notifications: Self.applicationNotifications,
            onChange: { [weak self] change in
                self?.changes.send(change)
            }
        ) else {
            guard retriesRemaining > 0 else {
                Log.windows.debug("No AX observer for pid \(pid, privacy: .public)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.attachObserver(to: pid, retriesRemaining: retriesRemaining - 1)
            }
            return
        }

        observers[pid] = observer
    }

    // MARK: - Revalidation backstop

    private func startRevalidationTimer() {
        revalidationTimer?.invalidate()
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.revalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        revalidationTimer = timer
    }

    private func revalidate() {
        let fingerprint = WindowFingerprint.current()
        defer { lastFingerprint = fingerprint }
        guard let lastFingerprint else { return }
        if fingerprint != lastFingerprint {
            changes.send(.structural)
        }
    }
}

/// A cheap hash of the CoreGraphics window list, used to detect changes that
/// Accessibility notifications failed to deliver.
private struct WindowFingerprint: Equatable {
    let count: Int
    let hash: Int

    static func current() -> WindowFingerprint {
        let options = CGWindowListOption([.optionAll, .excludeDesktopElements])
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return WindowFingerprint(count: 0, hash: 0)
        }
        var hasher = Hasher()
        for info in list {
            hasher.combine(info[kCGWindowNumber as String] as? CGWindowID ?? 0)
        }
        return WindowFingerprint(count: list.count, hash: hasher.finalize())
    }
}

/// Owns one `AXObserver` and all notification registrations for one process.
///
/// Lifetime is explicit: `invalidate()` removes the run-loop source and every
/// registration. Relying on `deinit` alone would leak the run-loop source,
/// which is the classic `AXObserver` leak.
@MainActor
private final class ApplicationObserver {
    private let pid: pid_t
    private let element: AXUIElement
    private let observer: AXObserver
    private let onChange: (WindowChange) -> Void
    private var observedWindows: Set<AXElementRef> = []
    /// The per-window notifications this observer registers; captured on each
    /// sync so `invalidate()` cannot fall out of step with what was registered.
    private var windowNotifications: [String] = []
    private var isValid = true

    init?(pid: pid_t, notifications: [String], onChange: @escaping (WindowChange) -> Void) {
        var rawObserver: AXObserver?
        let status = AXObserverCreate(pid, ApplicationObserver.callback, &rawObserver)
        guard status == .success, let rawObserver else { return nil }

        self.pid = pid
        self.element = AXUIElementCreateApplication(pid)
        self.observer = rawObserver
        self.onChange = onChange

        AX.setMessagingTimeout(element, seconds: WindowEnumerator.messagingTimeout)

        // `refcon` is unretained: the observer is owned by
        // `WindowObservationCenter`, which always calls `invalidate()` before
        // releasing it, so the pointer can never outlive the object.
        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in notifications {
            AXObserverAddNotification(rawObserver, element, notification as CFString, context)
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(rawObserver),
            .commonModes
        )
    }

    deinit {
        // Nothing actor-isolated is touched here; CFRunLoop and AXObserver
        // teardown are thread-safe C calls.
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    func invalidate() {
        guard isValid else { return }
        isValid = false
        // Reuse the very list the registrations were made from, so the two can
        // never drift apart and leak a registration.
        for window in observedWindows {
            for notification in windowNotifications {
                AXObserverRemoveNotification(observer, window.element, notification as CFString)
            }
        }
        observedWindows.removeAll()
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
    }

    /// Diffs per-window registrations so steady state costs nothing.
    func syncWindows(_ windows: Set<AXElementRef>, notifications: [String]) {
        guard isValid else { return }
        windowNotifications = notifications

        for stale in observedWindows.subtracting(windows) {
            for notification in notifications {
                AXObserverRemoveNotification(observer, stale.element, notification as CFString)
            }
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        for fresh in windows.subtracting(observedWindows) {
            for notification in notifications {
                AXObserverAddNotification(observer, fresh.element, notification as CFString, context)
            }
        }

        observedWindows = windows
    }

    /// C trampoline. Runs on the main run loop because that is where the
    /// observer's source is scheduled.
    private static let callback: AXObserverCallback = { _, _, notification, refcon in
        guard let refcon else { return }
        let observer = Unmanaged<ApplicationObserver>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated {
            observer.handle(notification as String)
        }
    }

    private func handle(_ notification: String) {
        guard isValid else { return }
        switch notification {
        case kAXTitleChangedNotification:
            onChange(.metadata)
        case kAXFocusedWindowChangedNotification,
             kAXMainWindowChangedNotification,
             kAXApplicationActivatedNotification:
            onChange(.focus(pid: pid))
        default:
            onChange(.structural)
        }
    }
}
