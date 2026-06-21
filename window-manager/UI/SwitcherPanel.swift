import AppKit
import SwiftUI

/// The floating window that hosts the switcher.
///
/// Configuration notes, each of which is load-bearing:
///
/// * `.nonactivatingPanel` — showing the switcher must not activate our
///   process, otherwise the app the user is switching *away from* deactivates
///   and hold-to-preview cannot work.
/// * `level = .screenSaver` — the only level reliably above a native
///   full-screen window's own level.
/// * `.canJoinAllSpaces` + `.fullScreenAuxiliary` — the panel follows the user
///   across Spaces and can appear over a full-screen app instead of forcing a
///   Space switch just to show a list. `.stationary` stops Mission Control from
///   animating it.
/// * `.ignoresCycle` — keeps the panel out of the system's own window cycling.
/// * `isReleasedWhenClosed = false` — the panel is created once and reused;
///   without this, `orderOut` on a closed panel would over-release it.
final class SwitcherPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: SwitcherLayout.list.panelWidth, height: 200),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        // The panel never becomes key, so AppKit's automatic restoration and
        // tabbing machinery is pure overhead.
        tabbingMode = .disallowed
        isMovable = false
    }

    /// A borderless panel would otherwise refuse mouse tracking in some
    /// configurations; it still never *takes* key focus because the style mask
    /// is non-activating and we only ever use `orderFrontRegardless()`.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Top edge of the panel for the current session, in screen coordinates.
    ///
    /// Fixed once per invocation so the panel grows and shrinks *downward* as
    /// the search narrows. Recomputing a centred frame on every keystroke — the
    /// obvious implementation — makes the whole panel slide up and down under
    /// the user's eyes while they type.
    private var sessionTopY: CGFloat?

    /// Places the panel for a newly summoned session.
    ///
    /// The anchor is derived from the tallest layout the session can reach, so
    /// a list that starts short and grows still never overflows the screen.
    ///
    /// The target screen is the one containing the pointer, falling back to the
    /// main screen. `NSWindow.center()` — which the original used — always
    /// lands on the primary display, which is wrong on every multi-monitor setup.
    func beginSession(size: CGSize, maximumHeight: CGFloat) {
        let visible = Self.targetScreen().visibleFrame
        let cappedMaximum = min(maximumHeight, visible.height - 24)
        // Slightly above the optical centre reads better and keeps the list
        // clear of the Dock.
        let centredBottom = visible.midY - cappedMaximum / 2 + visible.height * 0.08
        let top = min(centredBottom + cappedMaximum, visible.maxY - 12)
        sessionTopY = top.rounded()
        apply(size: size, in: visible)
    }

    /// Resizes within the current session, keeping the top edge anchored.
    func updateSize(_ size: CGSize) {
        apply(size: size, in: Self.targetScreen().visibleFrame)
    }

    func endSession() {
        sessionTopY = nil
    }

    private func apply(size: CGSize, in visible: NSRect) {
        let top = sessionTopY ?? (visible.midY + size.height / 2)
        let originY = max(top - size.height, visible.minY + 12)
        let frame = NSRect(
            x: (visible.midX - size.width / 2).rounded(),
            y: originY.rounded(),
            width: size.width,
            height: size.height
        )
        setFrame(frame, display: false)
    }

    private static func targetScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return screen
        }
        if let main = NSScreen.main {
            return main
        }
        // `NSScreen.screens` is empty only in a headless session; a zero-sized
        // fallback is still better than a crash.
        return NSScreen.screens.first ?? NSScreen()
    }
}
