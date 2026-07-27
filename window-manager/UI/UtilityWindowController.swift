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
    private let isResizable: Bool
    private let content: () -> Content

    /// - Parameter isResizable: content that can grow — a settings pane with a
    ///   user-managed list, say — needs a resize handle. Fixed-size panels such
    ///   as About do not, and look wrong with one.
    init(
        title: String,
        isResizable: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.isResizable = isResizable
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
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if isResizable { style.insert(.resizable) }
        window.styleMask = style
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        // A SwiftUI root that sizes itself to its content can ask for a window
        // taller than the display, which puts the bottom of the pane behind the
        // Dock where it cannot be reached — and without a resize handle there is
        // no way out of that. Clamping to the visible frame makes that state
        // unreachable however much content a pane grows.
        constrainToScreen(window)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Shrinks the window to the screen's usable area and re-centres it.
    ///
    /// `visibleFrame` already excludes the menu bar and the Dock, so fitting
    /// inside it is exactly the guarantee needed.
    private func constrainToScreen(_ window: NSWindow) {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }

        var frame = window.frame
        frame.size.width = min(frame.width, visible.width - 40)
        frame.size.height = min(frame.height, visible.height - 40)
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = visible.midY - frame.height / 2

        guard frame != window.frame else { return }
        window.setFrame(frame, display: false)
    }

    /// Re-clamps when the display arrangement changes while the window is open;
    /// unplugging a large external monitor is the usual way a window ends up
    /// bigger than the screen it lands on.
    func windowDidChangeScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        constrainToScreen(window)
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
