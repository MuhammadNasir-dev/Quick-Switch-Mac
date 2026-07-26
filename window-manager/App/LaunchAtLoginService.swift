import AppKit
import Combine
import Foundation
import ServiceManagement
import os

/// Registers QuickSwitch to start automatically when the user logs in.
///
/// Uses `SMAppService`, the modern replacement for the deprecated
/// `SMLoginItemSetEnabled` and for writing login items into
/// `~/Library/LaunchAgents` by hand. macOS owns the registration, shows it in
/// System Settings → General → Login Items, and lets the user revoke it there.
///
/// ## Why there is no `UserDefaults` mirror
///
/// The system is the single source of truth. If the preference were duplicated
/// locally the two would drift the moment the user toggled the switch in System
/// Settings, and the app would confidently display the wrong state. `status` is
/// read back from `SMAppService` every time it might have changed.
@MainActor
final class LaunchAtLoginService: ObservableObject {
    enum State: Equatable {
        /// Registered and will launch at login.
        case enabled
        /// Not registered.
        case disabled
        /// Registered, but the user must approve it in System Settings. macOS
        /// returns this when a previous registration was revoked by the user.
        case requiresApproval
        /// Registration is impossible in this location — see `reason`.
        case unavailable(reason: String)

        var isOn: Bool { self == .enabled || self == .requiresApproval }
    }

    @Published private(set) var state: State = .disabled
    /// Set when the last toggle attempt failed, for display next to the switch.
    @Published private(set) var lastError: String?

    private let service = SMAppService.mainApp

    init() {
        refresh()
        // Returning from System Settings is the usual way this changes behind
        // our back.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var isEnabled: Bool { state.isOn }

    /// Re-reads the registration from the system.
    func refresh() {
        switch service.status {
        case .enabled:
            state = .enabled
        case .requiresApproval:
            state = .requiresApproval
        case .notRegistered:
            state = .disabled
        case .notFound:
            state = .unavailable(reason: "QuickSwitch must be in /Applications to launch at login.")
        @unknown default:
            state = .disabled
        }
    }

    /// Registers or unregisters, reporting failures rather than silently
    /// leaving the switch in a state the system disagrees with.
    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            Log.permissions.notice("Launch at login set to \(enabled, privacy: .public)")
        } catch {
            // The usual cause is running from a location the system will not
            // register — a build directory, a disk image, or Downloads with
            // quarantine still applied.
            lastError = Self.describe(error)
            Log.permissions.error("Launch at login toggle failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    /// Opens the Login Items pane, which is where `requiresApproval` is resolved.
    func openLoginItemsSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    /// Human-readable explanation for the switch's subtitle, or `nil` when the
    /// state needs no explanation.
    var explanation: String? {
        if let lastError { return lastError }
        switch state {
        case .enabled, .disabled:
            return nil
        case .requiresApproval:
            return "Approve QuickSwitch in System Settings → General → Login Items."
        case .unavailable(let reason):
            return reason
        }
    }

    @objc private func applicationDidBecomeActive() {
        refresh()
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        // `kSMErrorLaunchDeniedByUser` and friends are not exposed to Swift, so
        // fall back to the localised description with a hint about the most
        // common cause.
        if nsError.domain == "SMAppServiceErrorDomain" || nsError.code == 1 {
            return "macOS refused the request. Move QuickSwitch to /Applications and try again."
        }
        return nsError.localizedDescription
    }
}
