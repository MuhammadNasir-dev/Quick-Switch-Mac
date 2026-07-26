import AppKit
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

@MainActor
@Suite("Launch at login")
struct LaunchAtLoginTests {
    @Test("State reflects the system, with no local mirror to drift")
    func stateComesFromTheSystem() {
        // Constructing the service reads `SMAppService` directly. The test host
        // is not a registered login item, so any state except `.enabled` is
        // valid here — what matters is that it resolves without trapping.
        let service = LaunchAtLoginService()
        #expect(service.state != .enabled || service.isEnabled)
    }

    @Test("Refreshing is idempotent")
    func refreshIsIdempotent() {
        let service = LaunchAtLoginService()
        let first = service.state
        service.refresh()
        #expect(service.state == first)
    }

    @Test("Approval and unavailable states both read as 'on' or explained")
    func stateSemantics() {
        #expect(LaunchAtLoginService.State.enabled.isOn)
        #expect(LaunchAtLoginService.State.requiresApproval.isOn,
                "Registered-but-unapproved must show the switch as on")
        #expect(!LaunchAtLoginService.State.disabled.isOn)
        #expect(!LaunchAtLoginService.State.unavailable(reason: "x").isOn)
    }

    @Test("Only actionable states carry an explanation")
    func explanations() {
        let service = LaunchAtLoginService()
        // A service in a plain enabled/disabled state needs no help text.
        if service.state == .enabled || service.state == .disabled {
            #expect(service.explanation == nil)
        } else {
            #expect(service.explanation != nil, "Non-obvious states must explain themselves")
        }
    }
}

@MainActor
@Suite("Bundle metadata and icon geometry")
struct AppInfoTests {
    @Test("Version strings come from the bundle, never hard-coded")
    func versionFromBundle() {
        // The test bundle carries its own Info.plist, so this asserts the
        // plumbing resolves rather than any particular value.
        #expect(!AppInfo.version.isEmpty)
        #expect(!AppInfo.build.isEmpty)
        #expect(!AppInfo.name.isEmpty)
        #expect(!AppInfo.copyright.isEmpty)
    }

    @Test("Display version collapses a redundant build number")
    func displayVersionFormatting() {
        // `1.0 (1)` when they differ, plain `1.0` when they are the same.
        let combined = AppInfo.displayVersion
        if AppInfo.build == AppInfo.version {
            #expect(combined == AppInfo.version)
        } else {
            #expect(combined == "\(AppInfo.version) (\(AppInfo.build))")
        }
    }

    @Test("The website URL is well-formed without force-unwrapping")
    func websiteURL() {
        #expect(AppInfo.website.host() == "quickswitchmac.com")
        #expect(AppInfo.website.scheme == "https")
    }

    @Test("Menu-bar icon heights stay on whole pixels at 1x")
    func statusIconAvoidsHalfPixels() {
        // The blur on non-Retina displays came from SF Symbols' default 15pt
        // height inside a 22pt bar: (22 - 15) / 2 = 3.5pt, half a pixel at 1x.
        // An even height keeps the centring inset integral at every scale.
        let thickness = NSStatusBar.system.thickness
        let height = StatusItemController.roundedToEven(min(18, thickness - 4))

        #expect(height.truncatingRemainder(dividingBy: 2) == 0, "Height must be even")
        let inset = (thickness - height) / 2
        #expect(inset == inset.rounded(), "Centring inset must land on a whole point")
        #expect(height <= thickness - 2, "Icon must not fill the bar edge to edge")
    }

    @Test("Even-rounding never yields a zero or odd size")
    func evenRounding() {
        for raw in stride(from: 0.0, through: 40.0, by: 0.5) {
            let value = StatusItemController.roundedToEven(CGFloat(raw))
            #expect(value >= 2)
            #expect(value.truncatingRemainder(dividingBy: 2) == 0)
        }
    }
}

@MainActor
@Suite("Menu header rendering")
struct MenuHeaderViewTests {
    private func render(width: CGFloat = MenuHeaderView.preferredWidth) -> (NSBitmapImageRep, MenuHeaderView)? {
        let view = MenuHeaderView(onOpenSettings: {})
        view.frame = NSRect(x: 0, y: 0, width: width, height: MenuHeaderView.preferredHeight)
        view.update(subtitle: "Ready", isWarning: false)
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return (rep, view)
    }

    /// Counts pixels with meaningful alpha inside a rect, in view coordinates.
    private func coverage(_ rep: NSBitmapImageRep, in rect: NSRect, viewHeight: CGFloat) -> Double {
        let scaleX = Double(rep.pixelsWide) / Double(rep.size.width)
        let scaleY = Double(rep.pixelsHigh) / Double(rep.size.height)
        var opaque = 0
        var total = 0
        for x in Int(rect.minX * scaleX)..<Int(rect.maxX * scaleX) {
            for y in Int(rect.minY * scaleY)..<Int(rect.maxY * scaleY) {
                // Bitmap rows run top-down; view coordinates run bottom-up.
                let flipped = Int(viewHeight * scaleY) - 1 - y
                guard x >= 0, x < rep.pixelsWide, flipped >= 0, flipped < rep.pixelsHigh else { continue }
                total += 1
                if let colour = rep.colorAt(x: x, y: flipped), colour.alphaComponent > 0.05 {
                    opaque += 1
                }
            }
        }
        return total == 0 ? 0 : Double(opaque) / Double(total)
    }

    @Test("The settings gear draws visible pixels")
    func gearIsVisible() throws {
        // Regression: the gear was an NSButton with an `.accessoryBarAction`
        // bezel, which inside a vibrant menu painted an accent-coloured fill
        // over the template glyph — the icon was invisible until pressed.
        let (rep, view) = try #require(render())
        let trailing = NSRect(
            x: view.bounds.width - 44,
            y: 0,
            width: 44,
            height: view.bounds.height
        )
        let filled = coverage(rep, in: trailing, viewHeight: view.bounds.height)
        #expect(filled > 0.01, "The gear must render something; coverage was \(filled)")
        #expect(filled < 0.85, "A glyph, not a filled block; coverage was \(filled)")
    }

    @Test("The gear is anchored to the trailing edge at any width")
    func gearFollowsWidth() {
        // Asserted arithmetically rather than by sampling pixels: the header
        // also draws text, and a pixel probe would be measuring font metrics
        // as much as layout.
        let height = MenuHeaderView.preferredHeight
        for width in [MenuHeaderView.preferredWidth, 320, 380, 460] as [CGFloat] {
            let rect = MenuHeaderView.gearRect(in: NSSize(width: width, height: height))
            let trailingGap = width - rect.maxX
            #expect(trailingGap == 14, "Gear must keep a constant trailing inset at width \(width)")
            #expect(rect.midY == height / 2, "Gear must stay vertically centred")
            #expect(rect.minX > 0)
        }
    }

    @Test("A wider menu moves the gear rather than stranding it")
    func gearIsNotStranded() {
        let height = MenuHeaderView.preferredHeight
        let narrow = MenuHeaderView.gearRect(in: NSSize(width: 268, height: height))
        let wide = MenuHeaderView.gearRect(in: NSSize(width: 380, height: height))
        #expect(wide.minX - narrow.minX == 112, "Gear must shift by the full width increase")
    }

    @Test("The gear exposes itself as a button to assistive technology")
    func gearIsAccessible() {
        let view = MenuHeaderView(onOpenSettings: {})
        #expect(view.isAccessibilityElement())
        #expect(view.accessibilityRole() == .button)
        #expect(view.accessibilityLabel() == "Settings")
    }

    @Test("Pressing through accessibility invokes the callback")
    func accessibilityPressWorks() {
        var opened = false
        let view = MenuHeaderView(onOpenSettings: { opened = true })
        #expect(view.accessibilityPerformPress())
        #expect(opened)
    }
}
