import CoreGraphics
import Foundation

/// Geometry shared by the SwiftUI content and the `NSPanel` that hosts it.
///
/// The panel is sized arithmetically rather than by measuring SwiftUI's
/// `fittingSize`, which keeps `show()` free of a layout pass — a meaningful
/// slice of the sub-50 ms open-time budget — and lets the panel be positioned
/// before its content has ever been laid out.
///
/// The arithmetic must therefore match what the views actually draw, *including
/// inter-item spacing*. Getting that wrong clips the final row, which is
/// exactly the bug an earlier version shipped: the list used `spacing: 1` while
/// the height calculation assumed zero.
nonisolated enum SwitcherMetrics {
    static let headerHeight: CGFloat = 56
    static let footerHeight: CGFloat = 34
    static let contentPadding: CGFloat = 8
    static let emptyStateHeight: CGFloat = 132
    static let cornerRadius: CGFloat = 16
    static let itemCornerRadius: CGFloat = 10

    static func panelWidth(layout: SwitcherLayout) -> CGFloat {
        layout.panelWidth
    }

    /// Height of the scrolling area.
    ///
    /// - Parameter groupCount: number of application headers drawn, which is
    ///   zero in every layout except `.grouped`.
    static func contentHeight(
        layout: SwitcherLayout,
        itemCount: Int,
        groupCount: Int = 0,
        maximumVisibleRows: Int
    ) -> CGFloat {
        guard itemCount > 0 else { return emptyStateHeight }

        let rows = layout.rowCount(forItemCount: itemCount)
        let limit = layout.visibleRowLimit(forConfiguredRows: maximumVisibleRows)
        let visibleRows = min(rows, limit)

        let itemsHeight = CGFloat(visibleRows) * layout.itemHeight
        let spacing = layout.itemSpacing * CGFloat(max(visibleRows - 1, 0))

        // At most one header can precede each visible row, so this both bounds
        // the height and keeps it monotonic in `groupCount`.
        let headers = layout.showsGroupHeaders ? min(groupCount, visibleRows) : 0
        let headersHeight = CGFloat(headers) * layout.groupHeaderHeight

        return itemsHeight + spacing + headersHeight + contentPadding * 2
    }

    /// Total panel height.
    static func panelHeight(
        layout: SwitcherLayout,
        itemCount: Int,
        groupCount: Int = 0,
        maximumVisibleRows: Int,
        showsFooter: Bool
    ) -> CGFloat {
        headerHeight
            + contentHeight(
                layout: layout,
                itemCount: itemCount,
                groupCount: groupCount,
                maximumVisibleRows: maximumVisibleRows
            )
            + (showsFooter ? footerHeight : 0)
    }

    /// How the list should scroll when the selection moves.
    ///
    /// Stateless by design. An earlier version tracked which row it believed
    /// was at the top of the viewport and skipped scrolling whenever the
    /// selection looked visible — but that belief is only ever an assumption.
    /// A mouse wheel moves the list without saying so, and SwiftUI resets the
    /// offset by itself when the row set changes, which it now does routinely
    /// as windows on other Spaces are picked up. Once the belief drifted, every
    /// later move decided "already visible" and the highlight stayed off screen.
    ///
    /// Deriving the answer from the move alone cannot drift.
    enum ScrollTarget: Equatable {
        /// Pin the selection to the top edge.
        case top
        /// Pin the selection to the bottom edge.
        case bottom
        /// Scroll the least amount needed; a no-op if it is already on screen.
        case minimal
    }

    static func scrollTarget(
        from previousSelection: Int,
        to selection: Int,
        totalItems: Int,
        visibleItemCount: Int
    ) -> ScrollTarget {
        // The ends are anchored explicitly so the first and last rows are never
        // left half-cut behind the container's padding.
        if selection <= 0 { return .top }
        if selection >= totalItems - 1 { return .bottom }

        // A move larger than a page is a wrap or a jump. `minimal` cannot be
        // trusted there: in a `LazyVStack` the destination row has not been
        // realised, so SwiftUI has no geometry to compute a minimal scroll from
        // and may not move at all.
        if abs(selection - previousSelection) > max(1, visibleItemCount) {
            return selection < previousSelection ? .top : .bottom
        }
        return .minimal
    }

    /// The tallest the panel can grow to for a given configuration, used to
    /// anchor its top edge before the content is known.
    static func maximumPanelHeight(
        layout: SwitcherLayout,
        maximumVisibleRows: Int,
        showsFooter: Bool
    ) -> CGFloat {
        let limit = layout.visibleRowLimit(forConfiguredRows: maximumVisibleRows)
        return panelHeight(
            layout: layout,
            itemCount: limit * layout.columnCount,
            // Worst case: every visible row carries its own header.
            groupCount: limit,
            maximumVisibleRows: maximumVisibleRows,
            showsFooter: showsFooter
        )
    }
}
