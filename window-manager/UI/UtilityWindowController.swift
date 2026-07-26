import AppKit
import SwiftUI

/// Hosts an auxiliary SwiftUI window for a background (`LSUIElement`) app.
///
/// ## Why not the SwiftUI `Settings` scene
///
/// Opening `Settings` from outside a menu bar means sending the private
/// `showSettingsWindow:` action and hoping something in the responder chain
/// handles it. For an `.accessory` app it frequently does not: SwiftUI installs
/// that handler on an internal responder rather than on `NSApplication`, and
/// the app has no main menu of its own to route it. The result is a menu item
/// that silently does nothing.
///
/// Owning the window outright removes the guesswork — the same approach the
/// setup guide already uses successfully — and puts activation policy under
/// explicit control.
///
/// ## Activation policy
///
/// An `.accessory` app cannot bring an ordinary window forward, so the policy is
/// raised to `.regular` while a utility window is open and dropped back when the
/// last one closes, leaving no stray Dock icon.
@MainActor
final class UtilityWindowController<Content: View>: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let title: String
    private let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    // No `deinit` clean-up: `NSWindow.delegate` is a weak reference, and the
    // controller is owned by `AppDelegate` for the process lifetime. Clearing
    // it here would need a main-actor hop that `deinit` cannot perform.

    /// Shows the window, creating it on first use and reusing it afterwards.
    func show() {
        NSApp.setActivationPolicy(.regular)

        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: content())
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        // Return to a background agent once nothing else is on screen. The
        // closing window is still listed in `NSApp.windows` at this point.
        let othersVisible = NSApp.windows.contains {
            $0 !== closing && $0.isVisible && $0.canBecomeMain
        }
        if !othersVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
