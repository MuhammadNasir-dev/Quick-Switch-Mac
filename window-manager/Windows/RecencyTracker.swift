import AppKit
import CoreGraphics
import Foundation

/// Most-recently-used ordering for windows.
///
/// The system Command-Tab is useful because the first two entries are "where I
/// am" and "where I just was". Reproducing that requires remembering focus
/// history; z-order alone cannot, because minimised and other-Space windows
/// have no z-order at all.
///
/// Ranks are a monotonically increasing counter rather than timestamps: no
/// clock skew, no equal-timestamp ties, and comparisons are integer compares on
/// the panel's hot path.
@MainActor
final class RecencyTracker {
    private var ranks: [CGWindowID: UInt64] = [:]
    private var counter: UInt64 = 0

    /// Caps memory when long-lived sessions churn through thousands of windows.
    private let maximumEntries = 2_048

    /// Records that a window became focused.
    func touch(windowID: CGWindowID) {
        counter &+= 1
        ranks[windowID] = counter
        if ranks.count > maximumEntries {
            prune()
        }
    }

    /// Higher means more recently focused; `nil` when never seen.
    func rank(of windowID: CGWindowID) -> UInt64? {
        ranks[windowID]
    }

    /// Drops entries for windows that no longer exist.
    func reconcile(existing windowIDs: Set<CGWindowID>) {
        guard ranks.count > windowIDs.count else { return }
        ranks = ranks.filter { windowIDs.contains($0.key) }
    }

    /// Orders a snapshot the way the switcher presents it.
    ///
    /// 1. Windows with focus history, most recent first.
    /// 2. Everything else by z-order (front-most first), then app name.
    ///
    /// The currently focused window sorts to index 0, which is what makes
    /// "press once → previous window" work.
    func ordered(_ windows: [AppWindow]) -> [AppWindow] {
        windows.sorted { lhs, rhs in
            switch (ranks[lhs.id], ranks[rhs.id]) {
            case let (lhsRank?, rhsRank?):
                return lhsRank > rhsRank
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                if lhs.zOrder != rhs.zOrder { return lhs.zOrder < rhs.zOrder }
                if lhs.appName != rhs.appName {
                    return lhs.appName.localizedStandardCompare(rhs.appName) == .orderedAscending
                }
                return lhs.id < rhs.id
            }
        }
    }

    /// Seeds history from a fresh snapshot so the very first invocation of the
    /// switcher already behaves like a real MRU list.
    func seedIfNeeded(from windows: [AppWindow]) {
        guard ranks.isEmpty else { return }
        // Apply in reverse so the front-most window ends up with the highest rank.
        for window in windows.sorted(by: { $0.zOrder > $1.zOrder }) where window.zOrder != Int.max {
            touch(windowID: window.id)
        }
        if let focused = windows.first(where: \.isAppFocusedWindow),
           NSWorkspace.shared.frontmostApplication?.processIdentifier == focused.pid {
            touch(windowID: focused.id)
        }
    }

    private func prune() {
        let survivors = ranks
            .sorted { $0.value > $1.value }
            .prefix(maximumEntries / 2)
        ranks = Dictionary(uniqueKeysWithValues: survivors.map { ($0.key, $0.value) })
    }
}
