import AppKit
import Combine
import CoreGraphics
import Foundation

/// Presentation state for the switcher panel.
///
/// Holds no AppKit window references and performs no Accessibility calls: it
/// consumes an `AppWindow` snapshot from `WindowIndex`, applies filtering and
/// selection, and reports the chosen window back. That makes every behaviour
/// here — ordering, fuzzy filtering, wrap-around, selection preservation —
/// unit-testable without a running window server.
@MainActor
final class SwitcherViewModel: ObservableObject {
    /// Rows currently displayed, after filtering.
    @Published private(set) var rows: [Row] = []
    /// Index into `rows`.
    @Published private(set) var selectedIndex: Int = 0
    /// The live search query.
    @Published private(set) var query: String = ""
    /// `true` once the user has typed, which pins the panel open.
    @Published private(set) var isPinned: Bool = false
    @Published private(set) var isAccessibilityTrusted: Bool = true
    /// Increments on every `beginSession`, letting the view reset per-session
    /// display state (such as the scroll position) without inspecting the rows.
    @Published private(set) var sessionToken: Int = 0

    struct Row: Identifiable, Equatable {
        let window: AppWindow
        /// Character offsets in `window.displayTitle` that matched the query.
        let highlightedTitleIndices: [Int]
        /// `true` when this row starts a new application run, so the grouped
        /// layout draws a header above it.
        ///
        /// Computed once here rather than by comparing against the previous row
        /// during rendering: `LazyVStack` builds rows out of order and in
        /// isolation, so a view has no reliable access to its predecessor.
        let startsGroup: Bool
        /// Number of windows in this row's application run, shown in the header.
        let groupSize: Int
        var id: CGWindowID { window.id }
    }

    /// Number of application headers the grouped layout will draw.
    /// Used by the controller to size the panel before the content is laid out.
    var groupCount: Int { rows.count { $0.startsGroup } }

    let iconProvider: IconProvider
    private let preferences: Preferences
    private var allWindows: [AppWindow] = []
    private var cancellables = Set<AnyCancellable>()

    /// Resolves the process that was frontmost when the session opened.
    /// Injected so ordering can be tested without a running window server.
    private let frontmostPID: () -> pid_t?

    /// Display the switcher is being shown on. Injected for the same reason as
    /// `frontmostPID`: so ordering and filtering are testable offline.
    private let activeDisplayID: () -> CGDirectDisplayID?
    private var sessionDisplayID: CGDirectDisplayID?

    /// Captured at `beginSession` rather than read live: once the switcher
    /// activates a window the frontmost app changes, and the list must not
    /// reshuffle underneath the user mid-session.
    private var sessionFrontmostPID: pid_t?

    /// Window order frozen for the duration of a session.
    ///
    /// `WindowIndex` re-sorts by most-recent-use on every refresh, and
    /// refreshes fire while the panel is open — a title change in any
    /// application, the periodic revalidation, or the refresh scheduled when
    /// the panel opens. Without freezing, rows shuffle *underneath the user
    /// mid-keystroke*: the highlight stays on its window but that window's
    /// position jumps, which reads as the selection leaping back to the top
    /// after a few presses.
    ///
    /// New windows are appended, closed ones drop out, and titles still update
    /// live — only the ordering is pinned, and only until the panel closes.
    private var sessionOrder: [CGWindowID]?

    /// - Parameter frontmostPID: `nil` uses `NSWorkspace`. A default *expression*
    ///   cannot be used here because it would be evaluated outside the main actor.
    init(
        preferences: Preferences,
        iconProvider: IconProvider,
        frontmostPID: (() -> pid_t?)? = nil,
        activeDisplayID: (() -> CGDirectDisplayID?)? = nil
    ) {
        self.preferences = preferences
        self.iconProvider = iconProvider
        self.frontmostPID = frontmostPID ?? { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        self.activeDisplayID = activeDisplayID ?? {
            // The screen under the pointer is the one the panel appears on.
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            return screen?.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID
        }
    }

    /// Binds to the shared window index.
    func bind(to index: WindowIndex, authorizer: AccessibilityAuthorizer) {
        index.$windows
            .sink { [weak self] windows in
                self?.ingest(windows)
            }
            .store(in: &cancellables)

        authorizer.$status
            .map { $0 == .trusted }
            .assign(to: \.isAccessibilityTrusted, on: self)
            .store(in: &cancellables)

        // Preferences that change the *contents* or *order* of the list re-run
        // the pipeline against the cached snapshot — no re-enumeration needed.
        // `layout` is in here because the grouped layout clusters rows by
        // application, which changes the row order and therefore the indices
        // that arrow keys and ⌘N address.
        Publishers.MergeMany(
            preferences.$includeMinimized.map { _ in }.eraseToAnyPublisher(),
            preferences.$includeOtherSpaces.map { _ in }.eraseToAnyPublisher(),
            preferences.$showActiveAppWindowsFirst.map { _ in }.eraseToAnyPublisher(),
            preferences.$includeOtherDisplays.map { _ in }.eraseToAnyPublisher(),
            preferences.$layout.map { _ in }.eraseToAnyPublisher()
        )
        .dropFirst(5) // the five replayed current values at subscription time
        // `rebuildRows` reads these preferences back, and `@Published` emits
        // from `willSet` — without the hop the rebuild would use the values
        // that were just replaced.
        .receive(on: RunLoop.main)
        .sink { [weak self] in
            self?.rebuildRows(preservingSelection: true)
        }
        .store(in: &cancellables)
    }

    var selectedWindow: AppWindow? {
        guard rows.indices.contains(selectedIndex) else { return nil }
        return rows[selectedIndex].window
    }

    var isEmpty: Bool { rows.isEmpty }

    // MARK: - Session lifecycle

    /// Resets state for a freshly summoned panel.
    ///
    /// - Parameter reverse: `true` when summoned with Shift held, which starts
    ///   the selection at the end of the list.
    func beginSession(reverse: Bool) {
        query = ""
        isPinned = false
        sessionFrontmostPID = frontmostPID()
        sessionDisplayID = activeDisplayID()
        // Clear first so the fresh ordering is computed from live recency,
        // then pin whatever that produced for the rest of the session.
        sessionOrder = nil
        rebuildRows(preservingSelection: false)
        sessionOrder = rows.map(\.id)
        sessionToken &+= 1

        guard !rows.isEmpty else {
            selectedIndex = 0
            return
        }
        // Index 0 is the window the user is looking at, so a forward invocation
        // starts on index 1 — press once, land on the previous window.
        selectedIndex = reverse ? rows.count - 1 : min(1, rows.count - 1)
    }

    func endSession() {
        query = ""
        isPinned = false
        sessionFrontmostPID = nil
        sessionDisplayID = nil
        sessionOrder = nil
    }

    /// Keeps the panel open until Return or Escape, leaving the selection alone.
    ///
    /// Pinning happens when the user opens the switcher without a held modifier
    /// (from the menu bar), when they start typing, and — importantly — the
    /// moment they use the arrow keys. Reaching the arrows means letting go of
    /// the summoning modifier, which would otherwise fire "confirm on release"
    /// and switch away before the arrow key ever arrived.
    func pin() {
        isPinned = true
    }

    // MARK: - Commands

    /// Steps the selection one item at a time, wrapping at both ends.
    func move(by delta: Int) {
        guard !rows.isEmpty else { return }
        let count = rows.count
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    /// Moves by a visual row: one item in the list, one row of cards in the grid.
    ///
    /// Wrapping is deliberately *linear* rather than column-preserving — moving
    /// down from the last grid row lands on the first item, not on a phantom
    /// slot past the end of a ragged final row.
    func moveVertical(by rowDelta: Int) {
        guard !rows.isEmpty else { return }
        move(by: rowDelta * preferences.layout.columnCount)
    }

    func moveToEdge(first: Bool) {
        guard !rows.isEmpty else { return }
        selectedIndex = first ? 0 : rows.count - 1
    }

    func select(at index: Int) {
        guard rows.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// Selects the 1-based row addressed by ⌘1…⌘9.
    @discardableResult
    func selectOrdinal(_ ordinal: Int) -> Bool {
        let index = ordinal - 1
        guard rows.indices.contains(index) else { return false }
        selectedIndex = index
        return true
    }

    func insertText(_ text: String) {
        query.append(text)
        isPinned = true
        rebuildRows(preservingSelection: false)
        selectedIndex = 0
    }

    func deleteBackward() {
        guard !query.isEmpty else { return }
        query.removeLast()
        rebuildRows(preservingSelection: false)
        selectedIndex = 0
    }

    func clearQuery() {
        guard !query.isEmpty else { return }
        query = ""
        rebuildRows(preservingSelection: false)
        selectedIndex = 0
    }

    // MARK: - Data pipeline

    /// Accepts a new snapshot from `WindowIndex`.
    ///
    /// Internal rather than private: this is the model's only data entry point,
    /// so tests drive the whole filtering and selection pipeline through it
    /// without needing a live window server or a test-only code path.
    func ingest(_ windows: [AppWindow]) {
        allWindows = windows
        rebuildRows(preservingSelection: true)
    }

    /// Applies preference filters, then the fuzzy query, then re-anchors the
    /// selection on the same window it was on before.
    ///
    /// Preserving selection matters because the index refreshes asynchronously
    /// while the panel is open: without it, an unrelated app opening a window
    /// would move the highlight out from under the user mid-keystroke.
    private func rebuildRows(preservingSelection: Bool) {
        let previouslySelected = preservingSelection ? selectedWindow?.id : nil

        var candidates = allWindows
        if !preferences.includeMinimized {
            candidates.removeAll { $0.isMinimized }
        }
        if !preferences.includeOtherSpaces {
            candidates.removeAll { !$0.isOnActiveSpace && !$0.isMinimized }
        }
        if !preferences.includeOtherDisplays, let display = sessionDisplayID {
            // A minimised window sits on no display, so it is never excluded by
            // a display filter — the same reasoning as the Space filter.
            candidates.removeAll { window in
                guard !window.isMinimized, let windowDisplay = window.displayID else { return false }
                return windowDisplay != display
            }
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)

        var ordered: [(window: AppWindow, highlights: [Int])]

        if trimmedQuery.isEmpty {
            // Every window of the app you are currently in, first — then the
            // rest in most-recently-used order. Applied only to the unfiltered
            // list: once you are searching, relevance beats grouping.
            if let sessionOrder {
                // A session is in progress: hold the order the panel opened
                // with. Windows opened since are appended in arrival order.
                candidates = Self.applying(order: sessionOrder, to: candidates)
            } else if preferences.showActiveAppWindowsFirst, let frontPID = sessionFrontmostPID {
                candidates = candidates.filter { $0.pid == frontPID }
                    + candidates.filter { $0.pid != frontPID }
            }
            ordered = candidates.map { ($0, []) }
        } else {
            // Preserve the MRU order as the tie-breaker by scoring in place and
            // using a stable sort on (score, original position).
            let scored = candidates.enumerated().compactMap { position, window -> (window: AppWindow, highlights: [Int], score: Int, position: Int)? in
                guard let match = FuzzyMatcher.score(query: trimmedQuery, window: window) else { return nil }
                let titleIndices = FuzzyMatcher.match(query: trimmedQuery, candidate: window.displayTitle)?
                    .matchedIndices ?? []
                return (window, titleIndices, match.score, position)
            }
            ordered = scored
                .sorted { lhs, rhs in
                    lhs.score == rhs.score ? lhs.position < rhs.position : lhs.score > rhs.score
                }
                .map { ($0.window, $0.highlights) }
        }

        // The grouped layout needs each application's windows to be contiguous.
        // Runs are ordered by where the app *first* appears, so the ordering
        // computed above (MRU, active-app-first, or relevance) still decides
        // which application leads.
        if preferences.layout.showsGroupHeaders {
            ordered = Self.clusteringByApplication(ordered)
        }

        rows = Self.makeRows(from: ordered)

        if let previouslySelected, let index = rows.firstIndex(where: { $0.id == previouslySelected }) {
            selectedIndex = index
        } else {
            selectedIndex = min(selectedIndex, max(rows.count - 1, 0))
        }
    }

    /// Reorders `windows` to match a previously captured sequence.
    ///
    /// Windows absent from `order` (opened since the session began) keep their
    /// incoming relative order and go last. The explicit offset tie-break makes
    /// this deterministic — `sorted(by:)` is not a stable sort in Swift.
    private static func applying(order: [CGWindowID], to windows: [AppWindow]) -> [AppWindow] {
        var rank: [CGWindowID: Int] = [:]
        rank.reserveCapacity(order.count)
        for (index, id) in order.enumerated() { rank[id] = index }

        return windows.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = rank[lhs.element.id] ?? Int.max
                let rhsRank = rank[rhs.element.id] ?? Int.max
                return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
            }
            .map(\.element)
    }

    /// Makes each application's windows contiguous without disturbing which
    /// application comes first.
    ///
    /// A plain `sorted(by: pid)` would destroy the incoming order; this keeps
    /// the first appearance of each process as that group's rank, so an
    /// MRU-ordered input yields MRU-ordered groups.
    private static func clusteringByApplication(
        _ items: [(window: AppWindow, highlights: [Int])]
    ) -> [(window: AppWindow, highlights: [Int])] {
        var order: [pid_t] = []
        var groups: [pid_t: [(window: AppWindow, highlights: [Int])]] = [:]
        for item in items {
            if groups[item.window.pid] == nil { order.append(item.window.pid) }
            groups[item.window.pid, default: []].append(item)
        }
        return order.flatMap { groups[$0] ?? [] }
    }

    /// Annotates each row with its group boundary and run length.
    private static func makeRows(
        from items: [(window: AppWindow, highlights: [Int])]
    ) -> [Row] {
        var runLengths: [pid_t: Int] = [:]
        for item in items {
            runLengths[item.window.pid, default: 0] += 1
        }

        var result: [Row] = []
        result.reserveCapacity(items.count)
        var previousPID: pid_t?
        for item in items {
            let starts = item.window.pid != previousPID
            result.append(
                Row(
                    window: item.window,
                    highlightedTitleIndices: item.highlights,
                    startsGroup: starts,
                    groupSize: runLengths[item.window.pid] ?? 1
                )
            )
            previousPID = item.window.pid
        }
        return result
    }
}
