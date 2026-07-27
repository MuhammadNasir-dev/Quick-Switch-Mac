import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Decides which processes and windows are switchable.
///
/// The previous implementation matched *localised* application names
/// ("Control Centre") against a hard-coded list, so the filter silently stopped
/// working outside en-GB. Bundle identifiers are locale-invariant and stable
/// across macOS releases, so they are the primary key here; the structural
/// rules (layer, subrole, alpha, size) then catch everything the identifier
/// list cannot know about.
nonisolated struct WindowFilter: Sendable {
    /// Processes that own windows the user can never meaningfully switch to.
    ///
    /// Spotlight, Notification Centre, Control Centre, the Dock and
    /// `loginwindow` all publish `kCGWindowLayer == 0` windows in some states,
    /// so layer filtering alone is not sufficient.
    static let excludedBundleIdentifiers: Set<String> = [
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.systemuiserver",
        "com.apple.Spotlight",
        "com.apple.loginwindow",
        "com.apple.SecurityAgent",
        "com.apple.WindowManager",           // Stage Manager UI surfaces
        "com.apple.screencaptureui",
        "com.apple.wallpaper.agent",
        "com.apple.dock.extra",
        "com.apple.CoreLocationAgent",
        "com.apple.TextInputMenuAgent",
        "com.apple.TextInputSwitcher",
        "com.apple.universalaccess.MagnifierWindow",
        "com.apple.PowerChime",
        "com.apple.UserNotificationCenter",
        "com.apple.talagent",                // "Desktop" / Dashboard agent
        "com.apple.dt.Xcode.PlaygroundStub-macosx"
    ]

    /// Owner names used only when a process has no bundle identifier at all
    /// (raw executables such as `WindowServer`).
    static let excludedProcessNames: Set<String> = [
        "Window Server",
        "WindowServer",
        "Wallpaper",
        "universalaccessd"
    ]

    /// Accessibility subroles accepted as user-switchable windows.
    ///
    /// `AXStandardWindow` is the ordinary document/browser window. Dialogs are
    /// included only when titled, because untitled `AXDialog` elements are
    /// overwhelmingly transient sheets and autocompletion popovers.
    static let standardSubroles: Set<String> = [
        kAXStandardWindowSubrole as String
    ]

    static let conditionalSubroles: Set<String> = [
        kAXDialogSubrole as String,
        kAXSystemDialogSubrole as String
    ]

    /// Windows smaller than this in either dimension are decorations, drag
    /// proxies, shadow helpers or off-screen 1×1 placeholders.
    static let minimumSide: CGFloat = 48

    /// Windows at or below this alpha are invisible helper surfaces.
    static let minimumAlpha: CGFloat = 0.05

    /// Minimum size for a window that Accessibility never described.
    static let minimumCGOnlySide: CGFloat = 120

    let ownPID: pid_t

    init(ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.ownPID = ownPID
    }

    /// Whether a running application is worth asking the Accessibility API about.
    func allowsApplication(_ app: NSRunningApplication) -> Bool {
        guard app.processIdentifier != ownPID else { return false }
        guard !app.isTerminated else { return false }
        // `.prohibited` processes are daemons and never own user windows.
        guard app.activationPolicy != .prohibited else { return false }
        if let bundleID = app.bundleIdentifier {
            guard !Self.excludedBundleIdentifiers.contains(bundleID) else { return false }
        } else if let name = app.localizedName {
            guard !Self.excludedProcessNames.contains(name) else { return false }
        }
        return true
    }

    /// Whether a `CGWindowListCopyWindowInfo` entry describes a real window.
    ///
    /// - Parameters:
    ///   - layer: `kCGWindowLayer`. Normal app windows are layer 0; the menu
    ///     bar, Dock, Spotlight and desktop icons all live on other layers.
    ///   - alpha: `kCGWindowAlpha`.
    ///   - bounds: `kCGWindowBounds`.
    func allowsCGWindow(layer: Int, alpha: CGFloat, bounds: CGRect) -> Bool {
        guard layer == 0 else { return false }
        guard alpha > Self.minimumAlpha else { return false }
        guard bounds.width >= Self.minimumSide, bounds.height >= Self.minimumSide else { return false }
        return true
    }

    /// Whether a window found *only* through `CGWindowList` should be listed.
    ///
    /// Deliberately stricter than `allowsCGWindow`. Without an Accessibility
    /// subrole there is no way to tell a document window from the menu-bar
    /// strips, drag proxies and status surfaces that processes publish at layer
    /// zero — a live system shows dozens of 1680x24 and 54x54 entries. A real
    /// window is comfortably larger than either.
    func allowsCGOnlyWindow(layer: Int, alpha: CGFloat, bounds: CGRect) -> Bool {
        guard allowsCGWindow(layer: layer, alpha: alpha, bounds: bounds) else { return false }
        return bounds.width >= Self.minimumCGOnlySide && bounds.height >= Self.minimumCGOnlySide
    }

    /// Whether an Accessibility window element should be listed.
    ///
    /// Minimised windows report a zero or stale frame, so the size rule is
    /// skipped for them — that is exactly the case the old on-screen-only
    /// enumeration dropped entirely.
    func allowsAXWindow(subrole: String?, title: String, isMinimized: Bool, frame: CGRect?) -> Bool {
        if let subrole {
            if Self.standardSubroles.contains(subrole) {
                // fall through to geometry checks
            } else if Self.conditionalSubroles.contains(subrole) {
                guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            } else {
                // AXUnknown, AXFloatingWindow, AXSheet, AXDrawer, popovers…
                return false
            }
        } else {
            // No subrole at all: accept only if it is titled, which excludes the
            // untitled utility surfaces that Java and Electron apps expose.
            guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        }

        if isMinimized { return true }

        guard let frame else { return true }
        guard frame.width >= Self.minimumSide, frame.height >= Self.minimumSide else { return false }
        return true
    }
}
