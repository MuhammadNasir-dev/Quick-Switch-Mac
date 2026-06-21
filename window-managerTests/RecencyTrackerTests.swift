import CoreGraphics
import Testing
@testable import window_manager

@MainActor
@Suite("Recency ordering")
struct RecencyTrackerTests {
    @Test("Without history, ordering falls back to z-order")
    func fallsBackToZOrder() {
        let tracker = RecencyTracker()
        let windows = [
            WindowFixtures.make(id: 1, app: "A", title: "A", zOrder: 2),
            WindowFixtures.make(id: 2, app: "B", title: "B", zOrder: 0),
            WindowFixtures.make(id: 3, app: "C", title: "C", zOrder: 1)
        ]
        #expect(tracker.ordered(windows).map(\.id) == [2, 3, 1])
    }

    @Test("Focused windows sort ahead of never-focused ones, most recent first")
    func recencyWins() {
        let tracker = RecencyTracker()
        let windows = [
            WindowFixtures.make(id: 1, app: "A", title: "A", zOrder: 0),
            WindowFixtures.make(id: 2, app: "B", title: "B", zOrder: 1),
            WindowFixtures.make(id: 3, app: "C", title: "C", zOrder: 2)
        ]
        tracker.touch(windowID: 3)
        tracker.touch(windowID: 2)
        // 2 was focused most recently, then 3; 1 has no history.
        #expect(tracker.ordered(windows).map(\.id) == [2, 3, 1])
    }

    @Test("Re-focusing moves a window back to the front")
    func refocusPromotes() {
        let tracker = RecencyTracker()
        let windows = (1...3).map {
            WindowFixtures.make(id: CGWindowID($0), app: "A\($0)", title: "T\($0)", zOrder: $0)
        }
        tracker.touch(windowID: 1)
        tracker.touch(windowID: 2)
        tracker.touch(windowID: 3)
        #expect(tracker.ordered(windows).map(\.id) == [3, 2, 1])
        tracker.touch(windowID: 1)
        #expect(tracker.ordered(windows).map(\.id) == [1, 3, 2])
    }

    @Test("Off-screen windows sort last when nothing has been focused")
    func offScreenSortsLast() {
        let tracker = RecencyTracker()
        let windows = [
            WindowFixtures.make(id: 1, app: "Minimised", title: "M", zOrder: Int.max),
            WindowFixtures.make(id: 2, app: "Visible", title: "V", zOrder: 0)
        ]
        #expect(tracker.ordered(windows).map(\.id) == [2, 1])
    }

    @Test("Ordering is deterministic when z-order ties")
    func stableTieBreak() {
        let tracker = RecencyTracker()
        let windows = [
            WindowFixtures.make(id: 9, app: "Zebra", title: "Z", zOrder: Int.max),
            WindowFixtures.make(id: 8, app: "Apple", title: "A", zOrder: Int.max)
        ]
        #expect(tracker.ordered(windows).map(\.id) == [8, 9])
        // Same input, same output — no reliance on dictionary iteration order.
        #expect(tracker.ordered(windows).map(\.id) == tracker.ordered(windows).map(\.id))
    }

    @Test("Closed windows are dropped from the history")
    func reconcileDropsDeadWindows() {
        let tracker = RecencyTracker()
        tracker.touch(windowID: 1)
        tracker.touch(windowID: 2)
        #expect(tracker.rank(of: 1) != nil)
        tracker.reconcile(existing: [2])
        #expect(tracker.rank(of: 1) == nil)
        #expect(tracker.rank(of: 2) != nil)
    }

    @Test("Seeding runs once and gives the front-most window the highest rank")
    func seedingOrdersByZOrder() throws {
        let tracker = RecencyTracker()
        let windows = [
            WindowFixtures.make(id: 1, app: "Front", title: "F", zOrder: 0),
            WindowFixtures.make(id: 2, app: "Middle", title: "M", zOrder: 1),
            WindowFixtures.make(id: 3, app: "Back", title: "B", zOrder: 2)
        ]
        tracker.seedIfNeeded(from: windows)
        let front = try #require(tracker.rank(of: 1))
        let back = try #require(tracker.rank(of: 3))
        #expect(front > back)

        // A second seed must not disturb history the user has since created.
        tracker.touch(windowID: 3)
        let afterTouch = try #require(tracker.rank(of: 3))
        tracker.seedIfNeeded(from: windows)
        #expect(tracker.rank(of: 3) == afterTouch)
    }
}
