import ApplicationServices
import CoreGraphics
import Foundation
@testable import window_manager

/// Builders for `AppWindow` values in tests.
///
/// `AXUIElement` cannot be constructed in a unit test without a live
/// application, so fixtures borrow the *system-wide* element. It is a valid,
/// non-null `AXUIElement` that is never activated by these tests, which keeps
/// the model type honest (no optional element, no test-only initialiser) while
/// staying entirely offline.
enum WindowFixtures {
    static func make(
        id: CGWindowID,
        app: String,
        title: String,
        pid: pid_t = 1_000,
        isMinimized: Bool = false,
        isFullScreen: Bool = false,
        isOnActiveSpace: Bool = true,
        isAppFocusedWindow: Bool = false,
        zOrder: Int = 0
    ) -> AppWindow {
        AppWindow(
            id: id,
            axElement: AXElementRef(AXUIElementCreateSystemWide()),
            pid: pid,
            bundleIdentifier: "test.\(app.lowercased())",
            appName: app,
            title: title,
            isMinimized: isMinimized,
            isFullScreen: isFullScreen,
            isOnActiveSpace: isOnActiveSpace,
            isAppFocusedWindow: isAppFocusedWindow,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            zOrder: zOrder,
            bundleURL: nil
        )
    }

    /// The list from the brief: several windows per application.
    static func browserAndEditor() -> [AppWindow] {
        [
            make(id: 1, app: "Safari", title: "ChatGPT — OpenAI", pid: 10, zOrder: 0),
            make(id: 2, app: "Safari", title: "GitHub", pid: 10, zOrder: 1),
            make(id: 3, app: "Safari", title: "Gmail", pid: 10, zOrder: 2),
            make(id: 4, app: "VS Code", title: "Browser.swift", pid: 20, zOrder: 3),
            make(id: 5, app: "VS Code", title: "AppDelegate.swift", pid: 20, zOrder: 4),
            make(id: 6, app: "Terminal", title: "npm run dev", pid: 30, zOrder: 5),
            make(id: 7, app: "Finder", title: "Downloads", pid: 40, zOrder: 6)
        ]
    }
}
