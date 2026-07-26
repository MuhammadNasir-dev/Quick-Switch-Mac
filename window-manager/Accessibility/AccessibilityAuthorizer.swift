import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import Foundation
import os

/// Tracks — and helps the user grant — the Accessibility (AXUIElement) trust
/// that the switcher cannot function without.
///
/// Trust can be revoked at any time from System Settings, and it is *always*
/// revoked when the app binary is replaced (a rebuild from Xcode changes the
/// code signature, so macOS invalidates the existing grant). Production
/// behaviour therefore has to be reactive in both directions:
///
/// * granted → install the event tap and window observers,
/// * revoked → tear everything down and re-show onboarding,
///
/// instead of checking once at launch.
///
/// macOS posts the distributed notification `com.apple.accessibility.api` when
/// the trust database changes, but it is undocumented, coalesced, and not
/// delivered to every process reliably — so a timer polls as well, in **both**
/// directions.
///
/// Detecting *revocation* is the safety-critical half. While trusted, this app
/// holds a session-wide event tap and can put a borderless panel above every
/// other window; if access is withdrawn and nothing notices, both are left in
/// place with no way to dismiss them. `AXIsProcessTrusted()` is a cached lookup
/// costing microseconds, so polling it steadily is free insurance.
@MainActor
final class AccessibilityAuthorizer: ObservableObject {
    enum Status: Equatable {
        case trusted
        case notTrusted
    }

    @Published private(set) var status: Status

    /// `true` when secure keyboard entry is active somewhere in the session.
    ///
    /// While secure input is on (a password field in Terminal, a login prompt),
    /// `CGEventTap` receives no key events at all, so the hotkey appears dead
    /// through no fault of ours. Surfacing it is the difference between a bug
    /// report and a one-line explanation.
    @Published private(set) var isSecureInputActive: Bool = false

    private var backstopTimer: Timer?
    private var secureInputTimer: Timer?
    private let distributedCenter = DistributedNotificationCenter.default()

    init() {
        status = AXIsProcessTrusted() ? .trusted : .notTrusted
        distributedCenter.addObserver(
            self,
            selector: #selector(accessibilityDatabaseChanged),
            name: NSNotification.Name("com.apple.accessibility.api"),
            object: nil
        )
        // The distributed notification fires slightly before the trust database
        // is readable, so re-check on app activation too (the user comes back
        // from System Settings, which activates us).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshFromNotification),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        updateBackstopTimer()
        startSecureInputMonitoring()
    }

    deinit {
        // `Timer` retains its target; invalidation must not be left to ARC.
        backstopTimer?.invalidate()
        secureInputTimer?.invalidate()
        distributedCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    var isTrusted: Bool { status == .trusted }

    /// Re-reads the trust database and publishes any change.
    func refresh() {
        let newStatus: Status = AXIsProcessTrusted() ? .trusted : .notTrusted
        guard newStatus != status else { return }
        Log.permissions.notice("Accessibility trust changed to \(String(describing: newStatus), privacy: .public)")
        status = newStatus
        updateBackstopTimer()
    }

    /// Shows the system's "grant access" prompt. Safe to call repeatedly: macOS
    /// only surfaces the alert once per app version.
    func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        hasRequestedTrust = true
        updateBackstopTimer()
    }

    /// Deep-links to the Accessibility pane of System Settings.
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    /// Reveals the app bundle in Finder so it can be dragged into the
    /// Accessibility list.
    ///
    /// Needed because macOS shows the "grant access" prompt only **once per
    /// code signature**. Once an entry exists — even a denied or stale one from
    /// a previous build — `AXIsProcessTrustedWithOptions` stops prompting and
    /// returns silently, which is why toggling the switch on can appear to do
    /// nothing. Removing the entry with "−" and adding this bundle back is the
    /// only reliable recovery, and it needs the bundle in hand.
    func revealApplicationInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    /// `true` when a prompt would be shown; `false` once macOS has recorded a
    /// decision for this signature and will stay silent.
    ///
    /// There is no API for this, so it is inferred: the prompt only appears
    /// while the process is untrusted *and* has never asked.
    private(set) var hasRequestedTrust = false

    // MARK: - Private

    @objc private func accessibilityDatabaseChanged() {
        // The database write and the notification race; a short hop is enough.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refresh()
        }
    }

    @objc private func refreshFromNotification() {
        refresh()
    }

    /// Polls the trust database in **both** directions.
    ///
    /// An earlier version only polled while untrusted, on the theory that once
    /// granted the distributed notification would report any revocation. It does
    /// not do so reliably, and the consequence was severe: revoking access left
    /// the event tap installed and the panel on screen with nothing able to tear
    /// them down, so the switcher sat there swallowing the keyboard.
    ///
    /// Detecting revocation is a safety requirement, not an optimisation.
    /// `AXIsProcessTrusted()` is a cached lookup costing microseconds, so a
    /// steady 2-second check while trusted is free; while untrusted the
    /// interval tightens because the user is actively in System Settings
    /// waiting for the app to notice.
    private func updateBackstopTimer() {
        backstopTimer?.invalidate()
        let interval: TimeInterval = status == .trusted ? 2.0 : 1.0
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        backstopTimer = timer
    }

    private func startSecureInputMonitoring() {
        isSecureInputActive = IsSecureEventInputEnabled()
        // There is no notification for secure input; a 2 s check is negligible
        // (a single Mach call) and only feeds a status-item warning.
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let active = IsSecureEventInputEnabled()
                if active != self.isSecureInputActive {
                    self.isSecureInputActive = active
                    Log.permissions.notice("Secure input active: \(active, privacy: .public)")
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        secureInputTimer = timer
    }
}
