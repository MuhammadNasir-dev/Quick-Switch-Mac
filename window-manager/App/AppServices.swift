import AppKit
import Combine
import Foundation
import os

/// Composition root.
///
/// Every service is constructed here and injected downward; nothing reaches for
/// a global. The one long-lived instance is owned by `AppDelegate`, which is
/// itself owned by `NSApplication` — so there is a single, explicit ownership
/// chain and no singletons to reason about.
///
/// It also owns the *authorization state machine*: Accessibility trust can be
/// granted or revoked at any moment (notably on every rebuild, because the code
/// signature changes), and the whole input/observation stack has to be brought
/// up and torn down in response.
@MainActor
final class AppServices: ObservableObject {
    let preferences: Preferences
    let authorizer: AccessibilityAuthorizer
    let iconProvider: IconProvider
    let windowIndex: WindowIndex
    let hotKeyMonitor: HotKeyMonitor
    let switcher: SwitcherController
    let launchAtLogin: LaunchAtLoginService

    /// Set when the event tap has been abandoned; surfaced in the menu bar so
    /// a silently dead shortcut is never a mystery.
    @Published private(set) var inputFailure: HotKeyMonitor.Failure?

    private var cancellables = Set<AnyCancellable>()
    private var isActive = false

    /// - Parameter preferences: injected by tests; `nil` builds the standard
    ///   `UserDefaults`-backed instance. A default *expression* cannot be used
    ///   because it would be evaluated outside the main actor.
    init(preferences injectedPreferences: Preferences? = nil) {
        let preferences = injectedPreferences ?? Preferences()
        self.preferences = preferences
        self.authorizer = AccessibilityAuthorizer()
        self.iconProvider = IconProvider()
        self.windowIndex = WindowIndex()
        self.hotKeyMonitor = HotKeyMonitor(modifier: preferences.modifier)
        self.launchAtLogin = LaunchAtLoginService()

        self.switcher = SwitcherController(
            preferences: preferences,
            windowIndex: windowIndex,
            authorizer: authorizer,
            hotKeyMonitor: hotKeyMonitor,
            iconProvider: iconProvider
        )

        hotKeyMonitor.onCommand = { [weak self] command in
            self?.switcher.handle(command)
        }

        // The tap owns the keyboard while the panel is up. If the system takes
        // the tap away, the panel must come down in the same breath — otherwise
        // it sits on screen above everything with no way to dismiss it.
        hotKeyMonitor.onTapDisabled = { [weak self] in
            self?.switcher.dismiss()
        }

        hotKeyMonitor.onTapFailed = { [weak self] failure in
            guard let self else { return }
            self.switcher.dismiss()
            self.inputFailure = failure
            switch failure {
            case .trustRevoked:
                // The authorizer's own poll will confirm this and tear the rest
                // down; refreshing here just makes it immediate.
                self.authorizer.refresh()
            case .repeatedTimeouts:
                Log.input.error("Global shortcut disabled after repeated tap timeouts")
            }
        }

        authorizer.$status
            .removeDuplicates()
            .sink { [weak self] status in
                switch status {
                case .trusted: self?.activate()
                case .notTrusted: self?.deactivate()
                }
            }
            .store(in: &cancellables)
    }

    /// Reinstalls the event tap after it was abandoned, on explicit request.
    ///
    /// Recovery is user-initiated rather than automatic: the tap is only ever
    /// abandoned because re-arming it was making things worse, so retrying on a
    /// timer would reproduce exactly the loop that was escaped.
    func restartInput() {
        inputFailure = nil
        authorizer.refresh()
        guard authorizer.isTrusted else {
            authorizer.openSystemSettings()
            return
        }
        hotKeyMonitor.stop()
        if !hotKeyMonitor.start() {
            inputFailure = .trustRevoked
        }
    }

    /// Brings up input interception and window observation.
    private func activate() {
        guard !isActive else { return }
        isActive = true
        inputFailure = nil
        windowIndex.start()
        if !hotKeyMonitor.start() {
            // Trust was reported but the tap was refused — retry shortly rather
            // than leaving the app permanently deaf.
            Log.input.error("Event tap refused despite trust; retrying")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.isActive else { return }
                _ = self.hotKeyMonitor.start()
            }
        }
        Log.permissions.notice("Services active")
    }

    /// Tears everything down when trust is revoked, so no stale observers or
    /// taps survive.
    private func deactivate() {
        guard isActive else { return }
        isActive = false
        switcher.dismiss()
        hotKeyMonitor.stop()
        windowIndex.stop()
        iconProvider.removeAll()
        Log.permissions.notice("Services suspended — Accessibility trust missing")
    }
}
