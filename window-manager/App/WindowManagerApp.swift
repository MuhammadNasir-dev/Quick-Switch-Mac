import AppKit
import Combine
import SwiftUI

@main
struct WindowManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The app has no primary window: it is a background agent whose UI is a
        // floating panel plus a menu-bar item. `Settings` is the only scene, so
        // ⌘, and the menu-bar item both have somewhere to go.
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
    private var onboarding: OnboardingWindowController?
    private var windowCloseObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            // Background agent: no Dock icon, no menu bar of our own.
            NSApp.setActivationPolicy(.accessory)

            let services = AppServices()
            self.services = services

            let onboarding = OnboardingWindowController(
                authorizer: services.authorizer,
                preferences: services.preferences
            )
            self.onboarding = onboarding

            self.statusItem = StatusItemController(services: services) { [weak onboarding] in
                onboarding?.show()
            }

            observeWindowClosing()

            // First run, or trust revoked by a rebuild: explain rather than
            // silently doing nothing.
            if !services.authorizer.isTrusted {
                services.authorizer.requestTrust()
                onboarding.show()
            }
        }
    }

    /// Returns the app to `.accessory` once its last ordinary window closes.
    ///
    /// Showing Settings or the setup guide requires `.regular` (an accessory
    /// app cannot bring a normal window forward), but staying `.regular` would
    /// leave a Dock icon behind for a background utility. `OnboardingWindow`
    /// handles its own case; this covers the SwiftUI `Settings` scene, whose
    /// window this app never gets a direct reference to.
    private func observeWindowClosing() {
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                guard let closing = notification.object as? NSWindow, closing.canBecomeMain else { return }
                // The closing window is still in `NSApp.windows` at this point.
                let remaining = NSApp.windows.contains {
                    $0 !== closing && $0.isVisible && $0.canBecomeMain
                }
                guard !remaining else { return }
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
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
