import CoreGraphics
import Foundation
import Testing
@testable import window_manager

@MainActor
@Suite("Switcher view model")
struct SwitcherViewModelTests {
    /// Each test gets an isolated defaults suite so preferences never leak
    /// between tests or into the developer's real settings.
    private func makeModel(
        windows: [AppWindow] = WindowFixtures.browserAndEditor(),
        frontmostPID: pid_t? = nil,
        configure: (Preferences) -> Void = { _ in }
    ) -> SwitcherViewModel {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)") ?? .standard
        let preferences = Preferences(defaults: defaults)
        // Grouping is on by default; most tests want plain MRU order, so it is
        // opt-in here via an explicit `frontmostPID`.
        preferences.showActiveAppWindowsFirst = frontmostPID != nil
        configure(preferences)
        let model = SwitcherViewModel(
            preferences: preferences,
            iconProvider: IconProvider(),
            frontmostPID: { frontmostPID }
        )
        model.ingest(windows)
        return model
    }

    // MARK: - Every window is its own row

    @Test("Windows are listed individually, not grouped by application")
    func listsEveryWindow() {
        let model = makeModel()
        model.beginSession(reverse: false)
        #expect(model.rows.count == 7)

        let safariRows = model.rows.filter { $0.window.appName == "Safari" }
        #expect(safariRows.count == 3)
        #expect(Set(safariRows.map(\.window.title)) == ["ChatGPT — OpenAI", "GitHub", "Gmail"])
    }

    @Test("Each row carries the identity the brief requires")
    func rowsCarryIdentity() throws {
        let model = makeModel()
        model.beginSession(reverse: false)
        let window = try #require(model.rows.first?.window)
        #expect(window.id != 0)
        #expect(window.pid != 0)
        #expect(!window.appName.isEmpty)
        #expect(!window.displayTitle.isEmpty)
    }

    // MARK: - Selection

    @Test("Opening forward selects the previous window, like Command-Tab")
    func forwardStartsOnSecondRow() {
        let model = makeModel()
        model.beginSession(reverse: false)
        #expect(model.selectedIndex == 1)
    }

    @Test("Opening with Shift selects the last window")
    func reverseStartsAtEnd() {
        let model = makeModel()
        model.beginSession(reverse: true)
        #expect(model.selectedIndex == 6)
    }

    @Test("A single window selects itself rather than wrapping to nothing")
    func singleWindow() {
        let model = makeModel(windows: [WindowFixtures.make(id: 1, app: "Finder", title: "Downloads")])
        model.beginSession(reverse: false)
        #expect(model.selectedIndex == 0)
    }

    @Test("An empty list leaves no selection and no crash")
    func emptyList() {
        let model = makeModel(windows: [])
        model.beginSession(reverse: false)
        #expect(model.rows.isEmpty)
        #expect(model.selectedWindow == nil)
        model.move(by: 1)
        model.move(by: -1)
        #expect(model.selectedIndex == 0)
    }

    @Test("Selection wraps in both directions")
    func selectionWraps() {
        let model = makeModel()
        model.beginSession(reverse: false)
        model.moveToEdge(first: true)
        #expect(model.selectedIndex == 0)
        model.move(by: -1)
        #expect(model.selectedIndex == 6)
        model.move(by: 1)
        #expect(model.selectedIndex == 0)
        // Deltas larger than the list must still land in range.
        model.move(by: 20)
        #expect(model.rows.indices.contains(model.selectedIndex))
        model.move(by: -20)
        #expect(model.rows.indices.contains(model.selectedIndex))
    }

    @Test("Command-N addresses rows by their 1-based position")
    func ordinalSelection() {
        let model = makeModel()
        model.beginSession(reverse: false)
        #expect(model.selectOrdinal(3))
        #expect(model.selectedIndex == 2)
        #expect(!model.selectOrdinal(99))
        #expect(model.selectedIndex == 2, "An out-of-range ordinal must not move the selection")
    }

    // MARK: - Search

    @Test("Typing filters instantly and pins the panel")
    func typingFilters() {
        let model = makeModel()
        model.beginSession(reverse: false)
        #expect(!model.isPinned)

        model.insertText("git")
        #expect(model.isPinned)
        #expect(model.rows.count < 7, "Typing must narrow the list")
        // "git" is a subsequence of "AppDeleGate.swIfT" too, so the assertion
        // is about *ranking*: the exact match has to come first.
        #expect(model.rows.first?.window.title == "GitHub")
        #expect(model.selectedIndex == 0, "Filtering resets the highlight to the best match")
    }

    @Test("Search covers the application name as well as the title")
    func searchMatchesAppName() {
        let model = makeModel()
        model.beginSession(reverse: false)
        model.insertText("safari")
        #expect(model.rows.count == 3)
        #expect(model.rows.allSatisfy { $0.window.appName == "Safari" })
    }

    @Test("Search is fuzzy, not a substring test")
    func searchIsFuzzy() {
        let model = makeModel()
        model.beginSession(reverse: false)
        model.insertText("apdl")
        #expect(model.rows.contains { $0.window.title == "AppDelegate.swift" })
    }

    @Test("Backspace restores the previous results")
    func backspaceRestores() {
        let model = makeModel()
        model.beginSession(reverse: false)
        model.insertText("g")
        model.insertText("i")
        model.insertText("t")
        let narrowed = model.rows.count
        model.deleteBackward()
        #expect(model.rows.count >= narrowed)
        model.clearQuery()
        #expect(model.query.isEmpty)
        #expect(model.rows.count == 7)
    }

    @Test("A query with no matches yields an empty, safe state")
    func noMatches() {
        let model = makeModel()
        model.beginSession(reverse: false)
        model.insertText("zzzzzz")
        #expect(model.rows.isEmpty)
        #expect(model.selectedWindow == nil)
    }

    @Test("Matched indices are returned for highlighting")
    func highlightIndices() throws {
        let model = makeModel()
        model.beginSession(reverse: false)
        model.insertText("git")
        let row = try #require(model.rows.first)
        #expect(!row.highlightedTitleIndices.isEmpty)
    }

    // MARK: - Live updates

    @Test("A background refresh keeps the highlight on the same window")
    func selectionSurvivesRefresh() throws {
        let model = makeModel()
        model.beginSession(reverse: false)
        model.select(at: 4)
        let selected = try #require(model.selectedWindow)

        // Simulate another app opening a window ahead of the selection.
        var updated = WindowFixtures.browserAndEditor()
        updated.insert(WindowFixtures.make(id: 99, app: "Mail", title: "Inbox", pid: 50), at: 0)
        model.ingest(updated)

        #expect(model.selectedWindow?.id == selected.id)
    }

    @Test("Losing the selected window clamps rather than going out of bounds")
    func selectionClampsWhenWindowCloses() {
        let model = makeModel()
        model.beginSession(reverse: false)
        model.moveToEdge(first: false)
        model.ingest(Array(WindowFixtures.browserAndEditor().prefix(2)))
        #expect(model.rows.indices.contains(model.selectedIndex))
    }

    // MARK: - Preferences

    @Test("Minimised windows can be excluded")
    func excludeMinimized() {
        var windows = WindowFixtures.browserAndEditor()
        windows.append(WindowFixtures.make(id: 8, app: "Notes", title: "Ideas", pid: 60, isMinimized: true))

        let model = makeModel(windows: windows) { $0.includeMinimized = false }
        model.beginSession(reverse: false)
        #expect(!model.rows.contains { $0.window.isMinimized })

        let inclusive = makeModel(windows: windows) { $0.includeMinimized = true }
        inclusive.beginSession(reverse: false)
        #expect(inclusive.rows.contains { $0.window.isMinimized })
    }

    @Test("Other-Space windows can be excluded without dropping minimised ones")
    func excludeOtherSpaces() {
        var windows = WindowFixtures.browserAndEditor()
        windows.append(WindowFixtures.make(id: 8, app: "Notes", title: "Ideas", pid: 60, isOnActiveSpace: false))
        windows.append(
            WindowFixtures.make(id: 9, app: "Notes", title: "Archive", pid: 60, isMinimized: true, isOnActiveSpace: false)
        )

        let model = makeModel(windows: windows) { $0.includeOtherSpaces = false }
        model.beginSession(reverse: false)
        #expect(!model.rows.contains { $0.window.id == 8 })
        #expect(model.rows.contains { $0.window.id == 9 }, "Minimised windows belong to no Space")
    }
}

// MARK: - Layout-aware navigation

@MainActor
@Suite("Grid navigation")
struct SwitcherGridNavigationTests {
    private func makeGridModel(windowCount: Int) -> SwitcherViewModel {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)") ?? .standard
        let preferences = Preferences(defaults: defaults)
        preferences.layout = .grid
        preferences.showActiveAppWindowsFirst = false
        let model = SwitcherViewModel(
            preferences: preferences,
            iconProvider: IconProvider(),
            frontmostPID: { nil }
        )
        model.ingest((0..<windowCount).map {
            WindowFixtures.make(id: CGWindowID($0 + 1), app: "App\($0)", title: "Window \($0)", zOrder: $0)
        })
        model.beginSession(reverse: false)
        return model
    }

    @Test("Left and right step one card at a time")
    func horizontalStepsByOne() {
        let model = makeGridModel(windowCount: 12)
        model.moveToEdge(first: true)
        model.move(by: 1)
        #expect(model.selectedIndex == 1)
        model.move(by: -1)
        #expect(model.selectedIndex == 0)
    }

    @Test("Up and down move a whole row of cards")
    func verticalMovesByRow() {
        let columns = SwitcherLayout.grid.columnCount
        let model = makeGridModel(windowCount: columns * 3)
        model.moveToEdge(first: true)
        model.moveVertical(by: 1)
        #expect(model.selectedIndex == columns)
        model.moveVertical(by: 1)
        #expect(model.selectedIndex == columns * 2)
        model.moveVertical(by: -1)
        #expect(model.selectedIndex == columns)
    }

    @Test("Vertical movement wraps without escaping a ragged final row")
    func verticalWrapsInBounds() {
        // A full row of cards plus a partial one.
        let model = makeGridModel(windowCount: SwitcherLayout.grid.columnCount + 2)
        model.moveToEdge(first: false)
        for _ in 0..<8 {
            model.moveVertical(by: 1)
            #expect(model.rows.indices.contains(model.selectedIndex))
        }
        for _ in 0..<8 {
            model.moveVertical(by: -1)
            #expect(model.rows.indices.contains(model.selectedIndex))
        }
    }

    @Test("In the list, vertical movement is a single step")
    func listVerticalIsOneStep() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)") ?? .standard
        let preferences = Preferences(defaults: defaults)
        preferences.layout = .list
        preferences.showActiveAppWindowsFirst = false
        let model = SwitcherViewModel(
            preferences: preferences,
            iconProvider: IconProvider(),
            frontmostPID: { nil }
        )
        model.ingest(WindowFixtures.browserAndEditor())
        model.beginSession(reverse: false)
        model.moveToEdge(first: true)
        model.moveVertical(by: 1)
        #expect(model.selectedIndex == 1)
    }
}

// MARK: - Active-app grouping

@MainActor
@Suite("Active app grouping")
struct ActiveAppGroupingTests {
    private func model(frontmost: pid_t?, enabled: Bool) -> SwitcherViewModel {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)") ?? .standard
        let preferences = Preferences(defaults: defaults)
        preferences.showActiveAppWindowsFirst = enabled
        let model = SwitcherViewModel(
            preferences: preferences,
            iconProvider: IconProvider(),
            frontmostPID: { frontmost }
        )
        // Terminal (pid 30) is deliberately in the middle of the MRU order.
        model.ingest(WindowFixtures.browserAndEditor())
        model.beginSession(reverse: false)
        return model
    }

    @Test("Every window of the active app is hoisted to the top")
    func activeAppWindowsComeFirst() {
        let model = self.model(frontmost: 20, enabled: true) // VS Code
        #expect(model.rows.prefix(2).allSatisfy { $0.window.appName == "VS Code" })
        #expect(model.rows.count == 7, "Grouping reorders, it never drops windows")
    }

    @Test("Relative order is preserved inside and outside the active app")
    func groupingIsStable() {
        let model = self.model(frontmost: 10, enabled: true) // Safari
        let safariTitles = model.rows.prefix(3).map(\.window.title)
        #expect(safariTitles == ["ChatGPT — OpenAI", "GitHub", "Gmail"])
        let rest = model.rows.dropFirst(3).map(\.window.appName)
        #expect(rest == ["VS Code", "VS Code", "Terminal", "Finder"])
    }

    @Test("Disabling the option restores strict most-recently-used order")
    func disabledKeepsMRUOrder() {
        let model = self.model(frontmost: 20, enabled: false)
        #expect(model.rows.first?.window.appName == "Safari")
    }

    @Test("An unknown frontmost app changes nothing")
    func unknownFrontmostIsHarmless() {
        let model = self.model(frontmost: nil, enabled: true)
        #expect(model.rows.count == 7)
        #expect(model.rows.first?.window.appName == "Safari")
    }
}

// MARK: - Pinning

@MainActor
@Suite("Panel pinning")
struct PinningTests {
    private func makeModel() -> SwitcherViewModel {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)") ?? .standard
        let preferences = Preferences(defaults: defaults)
        preferences.showActiveAppWindowsFirst = false
        let model = SwitcherViewModel(
            preferences: preferences,
            iconProvider: IconProvider(),
            frontmostPID: { nil }
        )
        model.ingest(WindowFixtures.browserAndEditor())
        model.beginSession(reverse: false)
        return model
    }

    @Test("Pinning leaves the selection where it is")
    func pinPreservesSelection() {
        // Regression: `pin()` used to reset the highlight to row 0, so pinning
        // on arrow-key navigation would have thrown away the user's position.
        let model = makeModel()
        model.select(at: 4)
        model.pin()
        #expect(model.isPinned)
        #expect(model.selectedIndex == 4)
    }

    @Test("A new session starts unpinned")
    func sessionResetsPinning() {
        let model = makeModel()
        model.pin()
        model.beginSession(reverse: false)
        #expect(!model.isPinned)
    }
}

// MARK: - Grouped layout

@MainActor
@Suite("Grouped layout")
struct GroupedLayoutTests {
    private func makeModel(
        layout: SwitcherLayout,
        windows: [AppWindow] = WindowFixtures.browserAndEditor()
    ) -> SwitcherViewModel {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)") ?? .standard
        let preferences = Preferences(defaults: defaults)
        preferences.layout = layout
        preferences.showActiveAppWindowsFirst = false
        let model = SwitcherViewModel(
            preferences: preferences,
            iconProvider: IconProvider(),
            frontmostPID: { nil }
        )
        model.ingest(windows)
        model.beginSession(reverse: false)
        return model
    }

    @Test("Windows of the same app become contiguous")
    func clustersByApplication() {
        // Interleave two apps so a stable sort is genuinely required.
        let interleaved = [
            WindowFixtures.make(id: 1, app: "Safari", title: "One", pid: 10, zOrder: 0),
            WindowFixtures.make(id: 2, app: "Notes", title: "Two", pid: 20, zOrder: 1),
            WindowFixtures.make(id: 3, app: "Safari", title: "Three", pid: 10, zOrder: 2),
            WindowFixtures.make(id: 4, app: "Notes", title: "Four", pid: 20, zOrder: 3)
        ]
        let model = makeModel(layout: .grouped, windows: interleaved)
        #expect(model.rows.map(\.window.pid) == [10, 10, 20, 20])
        #expect(model.rows.count == 4, "Grouping reorders, it never drops windows")
    }

    @Test("The leading application is whichever came first before grouping")
    func leadingGroupFollowsInputOrder() {
        let model = makeModel(layout: .grouped)
        #expect(model.rows.first?.window.appName == "Safari")
    }

    @Test("Exactly one row per application starts a group")
    func groupBoundaries() {
        let model = makeModel(layout: .grouped)
        let starts = model.rows.filter(\.startsGroup)
        #expect(starts.count == 4, "Safari, VS Code, Terminal, Finder")
        #expect(model.groupCount == 4)
        #expect(starts.map(\.window.appName) == ["Safari", "VS Code", "Terminal", "Finder"])
    }

    @Test("Group size counts every window of that application")
    func groupSizes() throws {
        let model = makeModel(layout: .grouped)
        let safari = try #require(model.rows.first { $0.window.appName == "Safari" })
        let finder = try #require(model.rows.first { $0.window.appName == "Finder" })
        #expect(safari.groupSize == 3)
        #expect(finder.groupSize == 1)
    }

    @Test("Flat layouts do not cluster")
    func flatLayoutsKeepOrder() {
        let interleaved = [
            WindowFixtures.make(id: 1, app: "Safari", title: "One", pid: 10, zOrder: 0),
            WindowFixtures.make(id: 2, app: "Notes", title: "Two", pid: 20, zOrder: 1),
            WindowFixtures.make(id: 3, app: "Safari", title: "Three", pid: 10, zOrder: 2)
        ]
        for layout in [SwitcherLayout.list, .grid] {
            let model = makeModel(layout: layout, windows: interleaved)
            #expect(model.rows.map(\.window.pid) == [10, 20, 10])
        }
    }

    @Test("Navigation still addresses a flat index across groups")
    func navigationIsFlat() {
        let model = makeModel(layout: .grouped)
        model.moveToEdge(first: true)
        for expected in 1..<model.rows.count {
            model.moveVertical(by: 1)
            #expect(model.selectedIndex == expected, "Grouped rows advance one at a time")
        }
    }

    @Test("⌘N addresses visible rows, ignoring headers")
    func ordinalsSkipHeaders() {
        let model = makeModel(layout: .grouped)
        #expect(model.selectOrdinal(4))
        #expect(model.rows[3].window.appName == "VS Code")
    }
}

// MARK: - Session stability

@MainActor
@Suite("Session ordering stability")
struct SessionOrderTests {
    private func makeModel(
        windows: [AppWindow] = WindowFixtures.browserAndEditor()
    ) -> SwitcherViewModel {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)") ?? .standard
        let preferences = Preferences(defaults: defaults)
        preferences.showActiveAppWindowsFirst = false
        let model = SwitcherViewModel(
            preferences: preferences,
            iconProvider: IconProvider(),
            frontmostPID: { nil }
        )
        model.ingest(windows)
        return model
    }

    @Test("A background reorder does not move rows while the panel is open")
    func orderIsFrozenDuringSession() {
        // Regression: `WindowIndex` re-sorts by recency on every refresh, and
        // refreshes fire while the panel is open. Rows used to shuffle
        // mid-navigation, which read as the selection jumping to the top.
        let model = makeModel()
        model.beginSession(reverse: false)
        let opening = model.rows.map(\.window.id)

        // The index delivers the same windows in a completely different order.
        model.ingest(WindowFixtures.browserAndEditor().reversed())

        #expect(model.rows.map(\.window.id) == opening)
    }

    @Test("The highlight stays on the same row index across a reorder")
    func selectionIndexIsStable() {
        let model = makeModel()
        model.beginSession(reverse: false)
        model.select(at: 4)
        let selectedID = model.selectedWindow?.id

        model.ingest(WindowFixtures.browserAndEditor().reversed())

        #expect(model.selectedIndex == 4)
        #expect(model.selectedWindow?.id == selectedID)
    }

    @Test("Repeated advancing walks the whole list exactly once")
    func advancingVisitsEveryRowInOrder() {
        // Mirrors holding the modifier and tapping Tab, with the window index
        // pushing a reordered snapshot between every press.
        let model = makeModel()
        model.beginSession(reverse: false)
        let expected = model.rows.map(\.window.id)

        var visited: [CGWindowID] = [model.selectedWindow?.id].compactMap { $0 }
        for _ in 1..<expected.count {
            model.ingest(WindowFixtures.browserAndEditor().shuffled())
            model.move(by: 1)
            if let id = model.selectedWindow?.id { visited.append(id) }
        }

        #expect(visited.count == expected.count)
        #expect(Set(visited).count == expected.count, "Every window must be visited exactly once")
        // Starting at index 1 and wrapping, the walk is the opening order
        // rotated by one.
        #expect(visited == Array(expected[1...]) + [expected[0]])
    }

    @Test("Newly opened windows are appended, never inserted mid-list")
    func newWindowsAppend() {
        let model = makeModel()
        model.beginSession(reverse: false)
        let opening = model.rows.map(\.window.id)

        var updated = WindowFixtures.browserAndEditor()
        updated.insert(WindowFixtures.make(id: 99, app: "Mail", title: "Inbox", pid: 50), at: 0)
        model.ingest(updated)

        #expect(model.rows.map(\.window.id) == opening + [99])
    }

    @Test("A closed window drops out without disturbing the rest")
    func closedWindowsDropOut() {
        let model = makeModel()
        model.beginSession(reverse: false)
        let opening = model.rows.map(\.window.id)

        model.ingest(WindowFixtures.browserAndEditor().filter { $0.id != 3 })

        #expect(model.rows.map(\.window.id) == opening.filter { $0 != 3 })
    }

    @Test("The next session picks up the current order again")
    func orderRefreshesOnReopen() {
        let model = makeModel()
        model.beginSession(reverse: false)
        model.endSession()

        let reordered = Array(WindowFixtures.browserAndEditor().reversed())
        model.ingest(reordered)
        model.beginSession(reverse: false)

        #expect(model.rows.map(\.window.id) == reordered.map(\.id))
    }

    @Test("Searching still ranks by relevance, not by the frozen order")
    func searchOverridesFrozenOrder() {
        let model = makeModel()
        model.beginSession(reverse: false)
        model.insertText("git")
        #expect(model.rows.first?.window.title == "GitHub")

        // Clearing the query restores the session order rather than re-sorting.
        model.clearQuery()
        #expect(model.rows.first?.window.title == "ChatGPT — OpenAI")
    }

    @Test("Each session bumps the token so the view can reset its scroll")
    func sessionTokenAdvances() {
        let model = makeModel()
        let before = model.sessionToken
        model.beginSession(reverse: false)
        #expect(model.sessionToken != before)
    }
}
