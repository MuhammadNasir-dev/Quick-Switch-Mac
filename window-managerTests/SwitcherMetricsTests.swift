import Combine
import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import QuickSwitch

@Suite("Panel geometry")
struct SwitcherMetricsTests {
    @Test("List height grows with the item count until the cap")
    func listHeightGrowsThenCaps() {
        func height(_ count: Int) -> CGFloat {
            SwitcherMetrics.panelHeight(
                layout: .list, itemCount: count, maximumVisibleRows: 9, showsFooter: true
            )
        }
        #expect(height(3) < height(9))
        #expect(height(9) == height(50), "Beyond the cap the list scrolls instead of growing")
    }

    @Test("The grid packs a full row of cards before growing")
    func gridPacksByRow() {
        func height(_ count: Int, _ layout: SwitcherLayout) -> CGFloat {
            SwitcherMetrics.panelHeight(
                layout: layout, itemCount: count, maximumVisibleRows: 9, showsFooter: true
            )
        }
        let columns = SwitcherLayout.grid.columnCount
        #expect(height(1, .grid) == height(columns, .grid))
        #expect(height(columns, .grid) < height(columns + 1, .grid))
        // Ten items need ten list rows but only two grid rows.
        #expect(height(10, .list) > height(10, .grid))
    }

    @Test("List height accounts for inter-row spacing")
    func listHeightIncludesSpacing() {
        // Regression: the height ignored `LazyVStack(spacing:)`, so the frame
        // was short by one point per gap and clipped the final row.
        let layout = SwitcherLayout.list
        let height = SwitcherMetrics.contentHeight(
            layout: layout, itemCount: 5, maximumVisibleRows: 9
        )
        let expected = 5 * layout.itemHeight
            + 4 * layout.itemSpacing
            + SwitcherMetrics.contentPadding * 2
        #expect(height == expected)
    }

    @Test("Grouped height makes room for its application headers")
    func groupedHeightIncludesHeaders() {
        let plain = SwitcherMetrics.contentHeight(
            layout: .grouped, itemCount: 6, groupCount: 0, maximumVisibleRows: 9
        )
        let grouped = SwitcherMetrics.contentHeight(
            layout: .grouped, itemCount: 6, groupCount: 3, maximumVisibleRows: 9
        )
        #expect(grouped - plain == 3 * SwitcherLayout.grouped.groupHeaderHeight)
    }

    @Test("Only the grouped layout reserves header space")
    func headersOnlyAffectGrouped() {
        for layout in [SwitcherLayout.list, .grid] {
            let without = SwitcherMetrics.contentHeight(
                layout: layout, itemCount: 6, groupCount: 0, maximumVisibleRows: 9
            )
            let with = SwitcherMetrics.contentHeight(
                layout: layout, itemCount: 6, groupCount: 4, maximumVisibleRows: 9
            )
            #expect(without == with)
        }
    }

    @Test("The grid is wider than the list")
    func gridIsWider() {
        #expect(SwitcherMetrics.panelWidth(layout: .grid) > SwitcherMetrics.panelWidth(layout: .list))
    }

    @Test("An empty list still has a visible body")
    func emptyStateHasHeight() {
        for layout in SwitcherLayout.allCases {
            let height = SwitcherMetrics.panelHeight(
                layout: layout, itemCount: 0, maximumVisibleRows: 9, showsFooter: true
            )
            #expect(height > SwitcherMetrics.headerHeight)
        }
    }

    @Test("Hiding the hints removes exactly the footer")
    func footerToggle() {
        let withFooter = SwitcherMetrics.panelHeight(
            layout: .list, itemCount: 5, maximumVisibleRows: 9, showsFooter: true
        )
        let without = SwitcherMetrics.panelHeight(
            layout: .list, itemCount: 5, maximumVisibleRows: 9, showsFooter: false
        )
        #expect(withFooter - without == SwitcherMetrics.footerHeight)
    }

    @Test("The anchor height is never exceeded by real content")
    func maximumBoundsRealHeights() {
        for layout in SwitcherLayout.allCases {
            let maximum = SwitcherMetrics.maximumPanelHeight(
                layout: layout, maximumVisibleRows: 9, showsFooter: true
            )
            let actual = SwitcherMetrics.panelHeight(
                layout: layout, itemCount: 500, groupCount: 500, maximumVisibleRows: 9, showsFooter: true
            )
            #expect(actual <= maximum, "\(layout) content must fit the anchored height")
        }
    }
}

@Suite("Layout")
struct SwitcherLayoutTests {
    @Test("Column count drives vertical navigation")
    func columnCounts() {
        #expect(SwitcherLayout.list.columnCount == 1)
        #expect(SwitcherLayout.grouped.columnCount == 1)
        #expect(SwitcherLayout.grid.columnCount > 1)
    }

    @Test("Only the grouped layout draws application headers")
    func headerFlags() {
        #expect(SwitcherLayout.grouped.showsGroupHeaders)
        #expect(!SwitcherLayout.list.showsGroupHeaders)
        #expect(!SwitcherLayout.grid.showsGroupHeaders)
        #expect(SwitcherLayout.list.groupHeaderHeight == 0)
        #expect(SwitcherLayout.grouped.groupHeaderHeight > 0)
    }

    @Test("⌘L cycles through every layout and returns to the start")
    func layoutCycles() {
        var seen: [SwitcherLayout] = []
        var current = SwitcherLayout.list
        for _ in SwitcherLayout.allCases {
            seen.append(current)
            current = current.next
        }
        #expect(current == .list, "Cycling must wrap")
        #expect(Set(seen).count == SwitcherLayout.allCases.count, "Every layout must be reachable")
    }

    @Test("Row count rounds up for ragged final rows")
    func rowCounts() {
        #expect(SwitcherLayout.grid.rowCount(forItemCount: 0) == 0)
        #expect(SwitcherLayout.grid.rowCount(forItemCount: 1) == 1)
        let columns = SwitcherLayout.grid.columnCount
        #expect(SwitcherLayout.grid.rowCount(forItemCount: columns) == 1)
        #expect(SwitcherLayout.grid.rowCount(forItemCount: columns + 1) == 2)
        #expect(SwitcherLayout.list.rowCount(forItemCount: 7) == 7)
        #expect(SwitcherLayout.grouped.rowCount(forItemCount: 7) == 7)
    }

    @Test("Both layouts round-trip through their persisted raw value")
    func roundTrip() {
        for layout in SwitcherLayout.allCases {
            #expect(SwitcherLayout(rawValue: layout.rawValue) == layout)
        }
    }

    @Test("The grid shows fewer, taller rows than the configured list count")
    func visibleRowLimits() {
        #expect(SwitcherLayout.list.visibleRowLimit(forConfiguredRows: 9) == 9)
        #expect(SwitcherLayout.grouped.visibleRowLimit(forConfiguredRows: 9) == 9)
        #expect(SwitcherLayout.grid.visibleRowLimit(forConfiguredRows: 9) < 9)
        #expect(SwitcherLayout.grid.visibleRowLimit(forConfiguredRows: 4) >= 1)
    }
}

@Suite("Key decoding")
struct KeyCodeTests {
    @Test("Digit keys map to 1…9 and nothing else")
    func digitMapping() {
        #expect(KeyCode.digit(for: 18) == 1)
        #expect(KeyCode.digit(for: 25) == 9)
        #expect(KeyCode.digit(for: 29) == nil, "0 has no row to address")
        #expect(KeyCode.digit(for: KeyCode.tab) == nil)
    }

    @Test("Each modifier maps to its own event flag and symbol")
    func modifierFlags() {
        #expect(SwitcherModifier.command.flag == .maskCommand)
        #expect(SwitcherModifier.option.flag == .maskAlternate)
        #expect(SwitcherModifier.control.flag == .maskControl)
        #expect(Set(SwitcherModifier.allCases.map(\.symbol)).count == SwitcherModifier.allCases.count)
    }

    @Test("Every modifier round-trips through its persisted raw value")
    func modifierRoundTrip() {
        for modifier in SwitcherModifier.allCases {
            #expect(SwitcherModifier(rawValue: modifier.rawValue) == modifier)
        }
    }
}

@MainActor
@Suite("Preferences defaults")
struct PreferencesTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)") ?? .standard
    }

    @Test("A fresh install summons with Option + Tab")
    func defaultsToOptionTab() {
        let preferences = Preferences(defaults: freshDefaults())
        #expect(preferences.modifier == .option)
        #expect(preferences.modifier.flag == .maskAlternate)
        #expect(preferences.modifier.symbol == "⌥")
    }

    @Test("Option is offered first in the picker")
    func optionListedFirst() {
        #expect(SwitcherModifier.allCases.first == .option)
    }

    @Test("Choosing a modifier persists it")
    func modifierPersists() {
        let defaults = freshDefaults()
        Preferences(defaults: defaults).modifier = .command
        #expect(Preferences(defaults: defaults).modifier == .command)
    }

    @Test("Row count is clamped to a sane range on load")
    func rowCountClamped() {
        let defaults = freshDefaults()
        defaults.set(999, forKey: "switcher.maximumVisibleRows")
        #expect(Preferences(defaults: defaults).maximumVisibleRows == 16)
        defaults.set(1, forKey: "switcher.maximumVisibleRows")
        #expect(Preferences(defaults: defaults).maximumVisibleRows == 4)
    }
}

@Suite("Event tap failure handling")
struct HotKeyFailureTests {
    @Test("Failure reasons are distinguishable")
    func failureCases() {
        #expect(HotKeyMonitor.Failure.trustRevoked != HotKeyMonitor.Failure.repeatedTimeouts)
    }

    @MainActor
    @Test("Starting without Accessibility trust is refused, not attempted")
    func startRequiresTrust() {
        // The test host is not a trusted process, so this exercises the guard
        // that keeps a useless tap out of the system input path.
        guard !AXIsProcessTrusted() else { return }
        let monitor = HotKeyMonitor(modifier: .option)
        #expect(monitor.start() == false)
        #expect(monitor.isRunning == false)
    }

    @MainActor
    @Test("Stopping an unstarted monitor is safe and idempotent")
    func stopIsIdempotent() {
        let monitor = HotKeyMonitor(modifier: .option)
        monitor.stop()
        monitor.stop()
        #expect(monitor.isRunning == false)
    }

    @MainActor
    @Test("Visibility and hold-mode flags can always be cleared")
    func flagsAlwaysClearable() {
        // The lockout scenario: these flags decide whether the tap swallows
        // every keystroke, so clearing them must never depend on the tap being
        // healthy, or on any prior state.
        let monitor = HotKeyMonitor(modifier: .option)
        monitor.setSwitcherVisible(true)
        monitor.setHoldModeActive(true)
        monitor.setSwitcherVisible(false)
        monitor.setHoldModeActive(false)
        monitor.stop()
        #expect(monitor.isRunning == false)
    }
}

@MainActor
@Suite("Published state settling")
struct PublishedSettlingTests {
    /// Reproduces the shape of the menu-bar icon bug: `@Published` fires from
    /// `willSet`, so a subscriber that reads the property back sees the value
    /// that is being *replaced*. Anything reading state back must therefore hop
    /// a run-loop turn first.
    @Test("A sink reading the property back sees the previous value")
    func willSetDeliversStaleState() async {
        final class Model: ObservableObject {
            @Published var flag = false
        }
        let model = Model()
        var observedByReadBack: [Bool] = []
        var observedByValue: [Bool] = []

        let token = model.$flag.dropFirst().sink { value in
            observedByValue.append(value)
            observedByReadBack.append(model.flag)
        }
        defer { token.cancel() }

        model.flag = true

        #expect(observedByValue == [true], "The emitted value is correct…")
        #expect(observedByReadBack == [false], "…but reading the property back is not")
    }

    @Test("Deferring to the next run-loop turn observes the settled value")
    func runLoopHopSeesSettledState() async throws {
        final class Model: ObservableObject {
            @Published var flag = false
        }
        let model = Model()
        var observed: [Bool] = []

        let token = model.$flag
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { _ in observed.append(model.flag) }
        defer { token.cancel() }

        model.flag = true
        // Let the deferred delivery run.
        try await Task.sleep(for: .milliseconds(50))

        #expect(observed == [true], "After the hop the property holds its new value")
    }
}
