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
final class AppServices {
    let preferences: Preferences
    let authorizer: AccessibilityAuthorizer
    let iconProvider: IconProvider
    let windowIndex: WindowIndex
    let hotKeyMonitor: HotKeyMonitor
    let switcher: SwitcherController

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

    /// Brings up input interception and window observation.
    private func activate() {
        guard !isActive else { return }
        isActive = true
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
