import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

/// Builds a snapshot of every switchable window on the system.
///
/// ## Why two APIs
///
/// Neither window API is sufficient alone:
///
/// * `CGWindowListCopyWindowInfo` is fast and gives z-order, alpha and
///   on-screen state, but it **omits minimised windows**, its `kCGWindowName`
///   requires Screen Recording permission, and its entries cannot be focused.
/// * The Accessibility API gives titles without Screen Recording, includes
///   minimised and other-Space windows, and yields the `AXUIElement` that
///   activation actually needs — but it has no z-order and is slow.
///
/// So Accessibility is the source of truth for *which windows exist* and
/// `CGWindowList` decorates them with ordering and visibility. The old code
/// used `CGWindowList(.optionOnScreenOnly)` alone, which is why minimised
/// windows, other-Space windows and (without Screen Recording) all titles were
/// missing.
///
/// ## Why it is not on the main thread
///
/// Every Accessibility read is synchronous IPC to the target process. A single
/// hung app used to block the main thread for the six-second default timeout.
/// Enumeration therefore runs off-main, fans out across applications with
/// `concurrentPerform`, and caps each process at `Self.messagingTimeout`.
nonisolated struct WindowEnumerator: Sendable {
    /// Per-process Accessibility timeout. Generous enough for a busy Electron
    /// app, short enough that a wedged process costs one frame, not six seconds.
    static let messagingTimeout: Float = 0.35

    let filter: WindowFilter

    init(filter: WindowFilter = WindowFilter()) {
        self.filter = filter
    }

    /// Metadata harvested from `CGWindowListCopyWindowInfo`, keyed by window ID.
    private struct CGWindowMetadata {
        var zOrder: Int
        var ownerName: String
        var isOnScreen: Bool
        var isOnActiveSpace: Bool
        var bounds: CGRect
        var alpha: CGFloat
        var layer: Int
        var pid: pid_t
    }

    /// One pass over the system.
    struct Snapshot: Sendable {
        /// Windows Accessibility described this time round.
        var windows: [AppWindow]
        /// Every layer-0 window CoreGraphics can see, whether or not
        /// Accessibility mentioned it. Lets the index tell "this window closed"
        /// apart from "Accessibility stopped reporting it".
        var liveWindowIDs: Set<CGWindowID>
        /// Windows composited on the Space currently being looked at.
        var onScreenWindowIDs: Set<CGWindowID>
    }

    /// Produces the current window list, unordered beyond z-order.
    ///
    /// Safe to call from any thread; must not be called on the main thread in
    /// production paths.
    nonisolated func snapshot() -> Snapshot {
        let cgWindows = copyCGWindowMetadata()
        let applications = switchableApplications()
        let harvested = harvestWindows(from: applications, cgWindows: cgWindows)

        // Only layer-0 windows of switchable processes count as "alive"; a
        // window ID belonging to the Dock must never keep an entry breathing.
        let switchablePIDs = Set(applications.map(\.processIdentifier))
        var live: Set<CGWindowID> = []
        var onScreen: Set<CGWindowID> = []
        for (id, metadata) in cgWindows where metadata.layer == 0 && switchablePIDs.contains(metadata.pid) {
            live.insert(id)
            if metadata.isOnActiveSpace { onScreen.insert(id) }
        }

        return Snapshot(windows: harvested, liveWindowIDs: live, onScreenWindowIDs: onScreen)
    }

    // MARK: - CGWindowList

    /// Reads *all* windows (including off-screen ones) plus a second on-screen
    /// pass used to determine which Space each window is on.
    ///
    /// `.optionOnScreenOnly` returns exactly the windows composited on the
    /// active Space, which makes it a public-API answer to "is this window on
    /// the Space I am looking at?" — no private `CGSSpace` calls required.
    private nonisolated func copyCGWindowMetadata() -> [CGWindowID: CGWindowMetadata] {
        var result: [CGWindowID: CGWindowMetadata] = [:]

        let allOptions = CGWindowListOption([.optionAll, .excludeDesktopElements])
        guard let all = CGWindowListCopyWindowInfo(allOptions, kCGNullWindowID) as? [[String: Any]] else {
            Log.windows.error("CGWindowListCopyWindowInfo returned nil")
            return result
        }

        let onScreenOptions = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        let onScreenIDs: Set<CGWindowID> = {
            guard let list = CGWindowListCopyWindowInfo(onScreenOptions, kCGNullWindowID) as? [[String: Any]] else {
                return []
            }
            return Set(list.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
        }()

        result.reserveCapacity(all.count)
        for (index, info) in all.enumerated() {
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let alpha = info[kCGWindowAlpha as String] as? CGFloat ?? 1
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? onScreenIDs.contains(windowID)

            var bounds = CGRect.zero
            if let dictionary = info[kCGWindowBounds as String] as? [String: Any],
               let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary) {
                bounds = rect
            }

            result[windowID] = CGWindowMetadata(
                // The array is returned front-to-back, so the index *is* the
                // z-order. It is the cheapest recency proxy available for
                // windows the app has never seen focused.
                zOrder: index,
                ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
                isOnScreen: isOnScreen,
                isOnActiveSpace: onScreenIDs.contains(windowID),
                bounds: bounds,
                alpha: alpha,
                layer: layer,
                pid: pid
            )
        }
        return result
    }

    // MARK: - Applications

    private nonisolated func switchableApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter(filter.allowsApplication)
    }

    // MARK: - Accessibility fan-out

    private nonisolated func harvestWindows(
        from applications: [NSRunningApplication],
        cgWindows: [CGWindowID: CGWindowMetadata]
    ) -> [AppWindow] {
        guard !applications.isEmpty else { return [] }

        // `concurrentPerform` bounds total latency by the slowest single app
        // rather than the sum of all of them. Results are collected under a
        // lock because the closure runs on arbitrary worker threads.
        let collector = Collector()

        DispatchQueue.concurrentPerform(iterations: applications.count) { index in
            let app = applications[index]
            let windows = windowsForApplication(app, cgWindows: cgWindows)
            guard !windows.isEmpty else { return }
            collector.append(windows)
        }

        var windows = collector.drain()
        // Deterministic base order; `WindowStore` applies recency on top.
        windows.sort { lhs, rhs in
            if lhs.zOrder != rhs.zOrder { return lhs.zOrder < rhs.zOrder }
            if lhs.appName != rhs.appName { return lhs.appName < rhs.appName }
            return lhs.id < rhs.id
        }
        return windows
    }

    private nonisolated func windowsForApplication(
        _ app: NSRunningApplication,
        cgWindows: [CGWindowID: CGWindowMetadata]
    ) -> [AppWindow] {
        let pid = app.processIdentifier
        guard pid > 0 else { return [] }

        let appElement = AXUIElementCreateApplication(pid)
        AX.setMessagingTimeout(appElement, seconds: Self.messagingTimeout)

        let axWindows = AX.elements(appElement, kAXWindowsAttribute as String)
        guard !axWindows.isEmpty else { return [] }

        let appName = app.localizedName ?? "Unknown"
        let bundleID = app.bundleIdentifier
        let bundleURL = app.bundleURL

        // Resolving the focused window once per app is far cheaper than asking
        // each window whether it is main.
        let focusedElement: AXUIElement? = AX.value(
            appElement,
            kAXFocusedWindowAttribute as String,
            as: AXUIElement.self
        )

        var result: [AppWindow] = []
        result.reserveCapacity(axWindows.count)

        for axWindow in axWindows {
            let subrole = AX.string(axWindow, kAXSubroleAttribute as String)
            let title = AX.string(axWindow, kAXTitleAttribute as String) ?? ""
            let isMinimized = AX.bool(axWindow, kAXMinimizedAttribute as String) ?? false
            let axFrame = AX.frame(axWindow)

            let windowID = AXPrivateAPI.windowID(of: axWindow)
                ?? correlateWindowID(frame: axFrame, pid: pid, cgWindows: cgWindows)

            guard let windowID else {
                // Without a window number there is no way to de-duplicate or
                // track recency; skipping is better than emitting a ghost row.
                Log.windows.debug("Skipping unidentifiable window in \(appName, privacy: .public)")
                continue
            }

            let metadata = cgWindows[windowID]

            // Identity is resolved *before* filtering so the size rule can fall
            // back to the CoreGraphics bounds.
            //
            // A window on another Space is not composited, and Accessibility
            // frequently reports a zero or stale frame for it. Filtering on the
            // Accessibility frame alone therefore threw away every window on
            // Desktop 2 for failing a minimum-size check it could never pass —
            // CoreGraphics knows the real bounds all along.
            let frame = (axFrame?.isEmpty == false) ? axFrame : metadata?.bounds

            guard filter.allowsAXWindow(
                subrole: subrole,
                title: title,
                isMinimized: isMinimized,
                frame: frame
            ) else { continue }

            // Structural rejection using CoreGraphics facts the AX API cannot
            // provide: menu-bar-layer surfaces and fully transparent helpers.
            if let metadata, !isMinimized {
                guard filter.allowsCGWindow(
                    layer: metadata.layer,
                    alpha: metadata.alpha,
                    bounds: metadata.bounds.isEmpty ? (frame ?? .zero) : metadata.bounds
                ) else { continue }
            }

            let isFullScreen = AX.bool(axWindow, AXAttribute.fullScreen) ?? false
            let isFocused = focusedElement.map { CFEqual($0, axWindow) } ?? false

            result.append(
                AppWindow(
                    id: windowID,
                    axElement: AXElementRef(axWindow),
                    pid: pid,
                    bundleIdentifier: bundleID,
                    appName: appName,
                    title: title,
                    isMinimized: isMinimized,
                    isFullScreen: isFullScreen,
                    // A minimised window is on no Space; treat it as reachable.
                    isOnActiveSpace: isMinimized ? true : (metadata?.isOnActiveSpace ?? false),
                    isAppFocusedWindow: isFocused,
                    frame: frame ?? .zero,
                    zOrder: metadata?.zOrder ?? Int.max,
                    bundleURL: bundleURL
                )
            )
        }

        return result
    }

    /// Fallback correlation when `_AXUIElementGetWindow` is unavailable.
    ///
    /// Matches on owning process plus frame, with a small tolerance for the
    /// rounding differences between AX and CoreGraphics coordinates.
    private nonisolated func correlateWindowID(
        frame: CGRect?,
        pid: pid_t,
        cgWindows: [CGWindowID: CGWindowMetadata]
    ) -> CGWindowID? {
        guard let frame, !frame.isEmpty else { return nil }
        let tolerance: CGFloat = 2
        for (windowID, metadata) in cgWindows where metadata.pid == pid {
            if abs(metadata.bounds.origin.x - frame.origin.x) <= tolerance,
               abs(metadata.bounds.origin.y - frame.origin.y) <= tolerance,
               abs(metadata.bounds.width - frame.width) <= tolerance,
               abs(metadata.bounds.height - frame.height) <= tolerance {
                return windowID
            }
        }
        return nil
    }
}

/// Minimal lock-protected accumulator for `concurrentPerform` results.
private nonisolated final class Collector: @unchecked Sendable {
    private var storage: [AppWindow] = []
    private let lock = NSLock()

    func append(_ windows: [AppWindow]) {
        lock.lock()
        storage.append(contentsOf: windows)
        lock.unlock()
    }

    func drain() -> [AppWindow] {
        lock.lock()
        defer {
            storage = []
            lock.unlock()
        }
        return storage
    }
}
