import AppKit
import Combine
import SwiftUI

@main
struct WindowManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The app has no primary window: it is a background agent whose UI is a
        // floating panel plus a menu-bar item.
        //
        // `Settings` is declared because `App` requires at least one scene, and
        // it renders the real settings so ⌘, is correct if macOS ever routes it
        // here. The menu-bar item does *not* rely on it — see
        // `UtilityWindowController` for why.
        Settings {
            if let services = appDelegate.services {
                SettingsView(
                    preferences: services.preferences,
                    authorizer: services.authorizer
                )
            } else {
                // Only reachable if the scene body runs before
                // `applicationDidFinishLaunching`, which SwiftUI is free to do.
                ProgressView().frame(width: 460, height: 120)
            }
        }
    }
}

/// Application lifecycle.
///
/// Kept deliberately thin: it owns `AppServices` (the composition root) and the
/// two pieces of chrome that need an `NSApplication` to exist. All behaviour
/// lives in the services themselves. The original delegate embedded the entire
/// event-tap implementation, which is why the tap's lifetime, its leaks and its
/// failure modes were untestable.
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private(set) var services: AppServices?
    private var statusItem: StatusItemController?
    private var onboarding: UtilityWindowController<OnboardingView>?
    private var settings: UtilityWindowController<SettingsView>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            // Background agent: no Dock icon, no menu bar of our own.
            NSApp.setActivationPolicy(.accessory)

            let services = AppServices()
            self.services = services

            let onboarding = UtilityWindowController(title: "Window Switcher Setup") {
                OnboardingView(
                    authorizer: services.authorizer,
                    preferences: services.preferences
                ) { [weak self] in
                    self?.onboarding?.close()
                }
            }
            self.onboarding = onboarding

            let settings = UtilityWindowController(title: "Window Switcher Settings") {
                SettingsView(
                    preferences: services.preferences,
                    authorizer: services.authorizer
                )
            }
            self.settings = settings

            self.statusItem = StatusItemController(
                services: services,
                onOpenSettings: { [weak settings] in settings?.show() },
                onOpenOnboarding: { [weak onboarding] in onboarding?.show() }
            )

            // First run, or trust revoked by a rebuild: explain rather than
            // silently doing nothing.
            if !services.authorizer.isTrusted {
                services.authorizer.requestTrust()
                onboarding.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            // Explicit teardown: the event tap is a system-wide resource and
            // the AX observers hold run-loop sources, neither of which should
            // be left to process exit.
            services?.hotKeyMonitor.stop()
            services?.windowIndex.stop()
        }
    }

    /// Re-opening from Finder (or a second launch attempt) surfaces the setup
    /// window instead of doing nothing visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated {
            onboarding?.show()
        }
        return true
    }
}
