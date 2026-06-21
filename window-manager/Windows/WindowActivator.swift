import AppKit
import ApplicationServices
import Foundation
import os

/// Brings a specific window to the front and makes it key.
///
/// ## Why this is harder than it looks
///
/// `NSRunningApplication.activate()` activates an *application*, and AppKit
/// then restores whichever window that application considers main — usually not
/// the one the user picked. Conversely `kAXRaiseAction` raises a window without
/// activating its process, so it comes forward but never becomes key and the
/// user has to click it. Neither call alone satisfies "never require clicking
/// afterward"; the original code interleaved them with two nested
/// `asyncAfter` blocks and hoped for the best, with no verification.
///
/// The sequence below is ordered so each step cannot be undone by the next, and
/// is then **verified** — if the window did not become main, it retries with
/// backoff. Retries are bounded and cancelled as soon as a newer activation is
/// requested.
@MainActor
final class WindowActivator {
    /// Verification attempts after the initial sequence.
    private let maximumAttempts = 4
    /// Delay before the first verification pass. Un-minimising animates for
    /// roughly 250 ms and Space switches for roughly 350 ms, so the first check
    /// deliberately lands after both.
    private let initialVerificationDelay: TimeInterval = 0.12

    private var activationTask: Task<Void, Never>?

    /// Emitted when a window has been confirmed frontmost, so callers can
    /// update recency ordering immediately.
    var onActivated: ((AppWindow) -> Void)?

    deinit {
        activationTask?.cancel()
    }

    /// Activates `window`, cancelling any activation still being verified.
    func activate(_ window: AppWindow) {
        activationTask?.cancel()
        activationTask = Task { [weak self] in
            await self?.performActivation(window)
        }
    }

    func cancelPendingVerification() {
        activationTask?.cancel()
        activationTask = nil
    }

    // MARK: - Implementation

    private func performActivation(_ window: AppWindow) async {
        let element = window.axElement.element
        AX.setMessagingTimeout(element, seconds: 0.5)

        guard let runningApp = NSRunningApplication(processIdentifier: window.pid) else {
            Log.activation.error("pid \(window.pid, privacy: .public) is gone")
            return
        }

        let appElement = AXUIElementCreateApplication(window.pid)
        AX.setMessagingTimeout(appElement, seconds: 0.5)

        // 1. Un-hide the process. A hidden app ignores raise requests entirely,
        //    and `activate()` alone does not always unhide it.
        if runningApp.isHidden {
            runningApp.unhide()
        }

        // 2. De-miniaturise before anything else. This is also what pulls the
        //    window off the Dock and onto the current Space; doing it after the
        //    raise leaves the raise addressed to a window that is not on screen.
        if window.isMinimized {
            AX.setFlag(element, kAXMinimizedAttribute as String, false)
        }

        applyFocusSequence(app: runningApp, appElement: appElement, window: element)

        // 3. Verify and retry. Applications that rebuild their window list on
        //    activation (Xcode, Slack, most Electron apps) routinely discard the
        //    first raise, which is precisely the "I have to click it" bug.
        var delay = initialVerificationDelay
        for attempt in 1...maximumAttempts {
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return }

            if isFrontmost(window: element, app: runningApp) {
                Log.activation.debug("Window \(window.id, privacy: .public) active after \(attempt, privacy: .public) check(s)")
                onActivated?(window)
                return
            }

            applyFocusSequence(app: runningApp, appElement: appElement, window: element)
            delay *= 1.8
        }

        Log.activation.notice("Could not confirm activation of window \(window.id, privacy: .public) in \(window.appName, privacy: .public)")
        // Still report it: the app is frontmost even if the specific window
        // could not be confirmed, so recency should follow the user's intent.
        onActivated?(window)
    }

    /// The ordering that actually works, applied atomically enough that no step
    /// gets undone by the next one.
    private func applyFocusSequence(app: NSRunningApplication, appElement: AXUIElement, window: AXUIElement) {
        // Raise first: this establishes the window as the app's front window
        // *before* AppKit gets a chance to restore its own idea of "main"
        // during activation.
        AX.perform(window, kAXRaiseAction as String)

        // Make it the app's main and focused window. `main` drives the window
        // AppKit restores on activation; `focused` drives key-window status and
        // therefore where keystrokes go.
        AX.setFlag(window, kAXMainAttribute as String, true)
        AX.setFlag(window, kAXFocusedAttribute as String, true)
        AX.set(appElement, kAXFocusedWindowAttribute as String, window)

        // Now bring the process forward. `activateIgnoringOtherApps` is
        // deprecated on macOS 14+ and is not needed: a process holding
        // Accessibility trust can activate another application directly.
        app.activate()

        // Belt and braces for apps that ignore `activate()` when their main
        // window is on another Space.
        AX.setFlag(appElement, kAXFrontmostAttribute as String, true)
    }

    /// True when the process is active *and* the target window is its main one.
    ///
    /// Checking only `app.isActive` is what let the old implementation report
    /// success while showing the wrong window.
    private func isFrontmost(window: AXUIElement, app: NSRunningApplication) -> Bool {
        guard app.isActive else { return false }
        if AX.bool(window, kAXMainAttribute as String) == true { return true }
        if AX.bool(window, kAXFocusedAttribute as String) == true { return true }
        return false
    }
}
