import AppKit
import ApplicationServices
import CoreGraphics

/// One switchable window.
///
/// Deliberately a value type holding no `NSImage`: icons are resolved lazily by
/// `IconProvider` at render time and shared per application, so a 200-window
/// snapshot costs no image memory and can be diffed cheaply.
nonisolated struct AppWindow: Identifiable, Hashable, @unchecked Sendable {
    /// `CGWindowID` (the window "number"). Unique for the lifetime of the window.
    let id: CGWindowID
    /// Accessibility handle used for activation.
    ///
    /// `nil` for windows discovered only through `CGWindowList`. The
    /// Accessibility API does not reliably report an application's windows that
    /// live on another Space, so a window the user can plainly see on Desktop 2
    /// is often absent from `kAXWindowsAttribute` while Desktop 1 is active.
    /// Those windows are still listed — activation resolves the element after
    /// bringing the owning app forward, which is the point at which macOS does
    /// expose it.
    let axElement: AXElementRef?

    /// Display the window is on, used by the "other displays" filter.
    let displayID: CGDirectDisplayID?
    let pid: pid_t
    let bundleIdentifier: String?
    /// Localised application name, e.g. "Safari".
    let appName: String
    /// The window's own title, e.g. "ChatGPT — OpenAI". May be empty.
    let title: String
    let isMinimized: Bool
    let isFullScreen: Bool
    /// `false` when the window lives on a Space that is not currently visible.
    let isOnActiveSpace: Bool
    /// `true` when the window is the application's focused (main) window.
    let isAppFocusedWindow: Bool
    /// Frame in Accessibility coordinates (top-left origin, y grows downward).
    let frame: CGRect
    /// Front-to-back index from `CGWindowListCopyWindowInfo`; `Int.max` when the
    /// window is not on screen (minimised or on another Space).
    let zOrder: Int
    /// URL of the owning application bundle, used as the icon cache key.
    let bundleURL: URL?

    /// The title to render, falling back to the app name for untitled windows
    /// (blank documents, some tool windows) so a row is never empty.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }

    /// Stable identity across refreshes, used to preserve selection while the
    /// list updates underneath the user.
    var identityKey: String { "\(pid)#\(id)" }

    static func == (lhs: AppWindow, rhs: AppWindow) -> Bool {
        lhs.id == rhs.id
            && lhs.pid == rhs.pid
            && lhs.title == rhs.title
            && lhs.isMinimized == rhs.isMinimized
            && lhs.isFullScreen == rhs.isFullScreen
            && lhs.isOnActiveSpace == rhs.isOnActiveSpace
            && lhs.zOrder == rhs.zOrder
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(pid)
    }
}

extension AppWindow {
    /// Short status string shown on the trailing edge of a row.
    var statusLabel: String? {
        if isMinimized { return "Minimised" }
        if isFullScreen { return "Full Screen" }
        if !isOnActiveSpace { return "Other Space" }
        return nil
    }
}
