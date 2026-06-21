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
/// the trust database changes, but the notification is undocumented, coalesced,
/// and not delivered to every process reliably. A slow timer is kept as a
/// backstop and, importantly, **only runs while the state is unresolved or the
/// app is untrusted** — once trusted, the app settles into pure notification
/// observation and does no polling at all.
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
        updateBackstopTimer()
    }

    /// Deep-links to the Accessibility pane of System Settings.
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

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

    /// Runs a 1.5 s backstop poll only while untrusted; stops once granted.
    private func updateBackstopTimer() {
        backstopTimer?.invalidate()
        backstopTimer = nil
        guard status == .notTrusted else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
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
