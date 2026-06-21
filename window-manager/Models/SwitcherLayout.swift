import CoreGraphics
import Foundation

/// How the switcher presents its windows.
///
/// The three modes are genuinely different tools rather than a cosmetic choice:
///
/// * `.list` is dense and reads left-to-right — best for many windows with
///   long, similar titles (twenty editor tabs).
/// * `.grouped` is the same list with an application header above each run of
///   that app's windows — best for "which app was that in?".
/// * `.grid` trades density for large icons, echoing the system app switcher —
///   best for recognising apps at a glance.
///
/// Navigation adapts: Up/Down moves one row in the lists and a whole row of
/// cards in the grid.
nonisolated enum SwitcherLayout: String, CaseIterable, Sendable {
    case list
    case grouped
    case grid

    var displayName: String {
        switch self {
        case .list: "List"
        case .grouped: "Grouped"
        case .grid: "Grid"
        }
    }

    var symbolName: String {
        switch self {
        case .list: "list.bullet"
        case .grouped: "list.bullet.indent"
        case .grid: "square.grid.3x2"
        }
    }

    var summary: String {
        switch self {
        case .list:
            "A flat list, one window per line — densest, and the fastest to scan when titles differ."
        case .grouped:
            "Each application heads a section listing its own windows."
        case .grid:
            "Large icons like the system switcher, five across."
        }
    }

    /// `true` when the layout draws an application header above each run of
    /// windows belonging to the same process.
    var showsGroupHeaders: Bool { self == .grouped }

    /// Number of items per visual row; drives vertical arrow navigation.
    var columnCount: Int {
        switch self {
        case .list, .grouped: 1
        case .grid: 5
        }
    }

    /// Panel width. The grid needs room for five readable cards.
    var panelWidth: CGFloat {
        switch self {
        case .list, .grouped: 640
        case .grid: 760
        }
    }

    /// Height of one item.
    var itemHeight: CGFloat {
        switch self {
        case .list, .grouped: 52
        case .grid: 104
        }
    }

    /// Vertical gap between items in the same column.
    var itemSpacing: CGFloat {
        switch self {
        case .list, .grouped: 1
        case .grid: 6
        }
    }

    /// Height of an application header row in `.grouped`.
    var groupHeaderHeight: CGFloat { showsGroupHeaders ? 28 : 0 }

    /// How many visual rows fit before the content starts scrolling.
    ///
    /// `maximumVisibleRows` is expressed in list rows, so the grid scales it
    /// down — nine rows of cards would be taller than most screens.
    func visibleRowLimit(forConfiguredRows rows: Int) -> Int {
        switch self {
        case .list, .grouped: max(1, rows)
        case .grid: max(1, Int((Double(rows) / 3.0).rounded(.up)))
        }
    }

    /// The next layout in declaration order, wrapping — drives ⌘L.
    var next: SwitcherLayout {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return .list }
        return all[(index + 1) % all.count]
    }

    /// Number of visual rows needed for `itemCount` items.
    func rowCount(forItemCount itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        return Int((Double(itemCount) / Double(columnCount)).rounded(.up))
    }
}
