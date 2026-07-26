import AppKit
import Combine
import SwiftUI

/// The switcher panel's content.
///
/// Two presentations share one data pipeline and one visual vocabulary: a dense
/// list and an icon-forward grid. Colours come entirely from the semantic
/// palette (`.primary`, `.secondary`, `Color.accentColor`) over a system
/// material, so the panel is legible in both appearances and honours Increase
/// Contrast, Reduce Transparency and the user's accent colour — none of which
/// the original hard-coded `Color.black.opacity(0.82)` with white text did.
struct SwitcherView: View {
    @ObservedObject var viewModel: SwitcherViewModel
    @ObservedObject var preferences: Preferences

    var onActivate: (AppWindow) -> Void
    var onHover: (Int) -> Void
    var onRequestPermissions: () -> Void

    private var layout: SwitcherLayout { preferences.layout }

    /// Index of the row currently pinned to the top of the scroll area.
    ///
    /// The scroll position is tracked explicitly rather than delegating to
    /// `scrollTo`'s built-in heuristics. Anchoring to `.center` drags the list
    /// under a stationary highlight; passing no anchor leaves the behaviour up
    /// to SwiftUI, which cannot compute a minimal scroll for rows a `LazyVStack`
    /// has not realised yet. Knowing the first visible row makes it exact: only
    /// scroll when the selection crosses an edge, and by exactly one row.
    @State private var firstVisibleIndex = 0

    /// How many items fit without scrolling, in the current layout.
    private var visibleItemCount: Int {
        let rows = layout.visibleRowLimit(forConfiguredRows: preferences.maximumVisibleRows)
        return max(1, rows * layout.columnCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            separator

            if !viewModel.isAccessibilityTrusted {
                permissionsBanner
            } else if viewModel.isEmpty {
                emptyState
            } else {
                content
            }

            if preferences.showShortcutHints {
                separator
                footer
            }
        }
        .frame(width: SwitcherMetrics.panelWidth(layout: layout))
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: SwitcherMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SwitcherMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("QuickSwitch")
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
    }

    // MARK: - Header

    /// A *rendered* search field, not an `NSTextField`.
    ///
    /// The panel is deliberately non-activating: giving it a real first
    /// responder would require activating our process, which deactivates the app
    /// the user is switching away from and breaks hold-to-preview. The event tap
    /// already owns the keyboard while the panel is visible, so it feeds
    /// characters straight into the view model and this view draws the result.
    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(viewModel.query.isEmpty ? .tertiary : .secondary)

            ZStack(alignment: .leading) {
                if viewModel.query.isEmpty {
                    Text("Search windows by app or title")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 1) {
                    Text(viewModel.query)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    if viewModel.isPinned {
                        Caret()
                    }
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Image(systemName: layout.symbolName)
                    .font(.system(size: 9, weight: .semibold))
                Text("\(viewModel.rows.count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .padding(.horizontal, 16)
        .frame(height: SwitcherMetrics.headerHeight)
        .accessibilityLabel("Search windows")
        .accessibilityValue(viewModel.query)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                switch layout {
                case .list, .grouped: listBody
                case .grid: gridBody
                }
            }
            .frame(
                height: SwitcherMetrics.contentHeight(
                    layout: layout,
                    itemCount: viewModel.rows.count,
                    groupCount: viewModel.groupCount,
                    maximumVisibleRows: preferences.maximumVisibleRows
                )
            )
            .onChange(of: viewModel.selectedIndex) { _, newValue in
                scroll(proxy, to: newValue)
            }
            .onChange(of: preferences.layout) { _, _ in
                // Column count changed, so the previous anchor is meaningless.
                firstVisibleIndex = 0
                scroll(proxy, to: viewModel.selectedIndex, animated: false)
            }
            .onChange(of: viewModel.sessionToken) { _, _ in
                firstVisibleIndex = 0
                scroll(proxy, to: viewModel.selectedIndex, animated: false)
            }
            .onChange(of: viewModel.query) { _, _ in
                // Filtering rebuilds the list from the top.
                firstVisibleIndex = 0
                scroll(proxy, to: viewModel.selectedIndex, animated: false)
            }
        }
    }

    private var listBody: some View {
        LazyVStack(spacing: layout.itemSpacing) {
            ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                if layout.showsGroupHeaders, row.startsGroup {
                    GroupHeaderView(
                        appName: row.window.appName,
                        icon: viewModel.iconProvider.icon(for: row.window),
                        count: row.groupSize
                    )
                }
                WindowRowView(
                    row: row,
                    icon: viewModel.iconProvider.icon(for: row.window),
                    isSelected: index == viewModel.selectedIndex,
                    ordinal: index + 1,
                    // The header already names the app, so the row doesn't
                    // repeat it — that is the whole point of grouping.
                    showsAppName: !layout.showsGroupHeaders,
                    isIndented: layout.showsGroupHeaders
                )
                .id(row.id)
                .onTapGesture { onActivate(row.window) }
                .onHover { if $0 { onHover(index) } }
            }
        }
        .padding(.horizontal, SwitcherMetrics.contentPadding)
        .padding(.vertical, SwitcherMetrics.contentPadding)
    }

    private var gridBody: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: layout.itemSpacing),
                count: layout.columnCount
            ),
            spacing: layout.itemSpacing
        ) {
            ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                WindowCardView(
                    row: row,
                    icon: viewModel.iconProvider.icon(for: row.window),
                    isSelected: index == viewModel.selectedIndex,
                    ordinal: index + 1
                )
                .id(row.id)
                .onTapGesture { onActivate(row.window) }
                .onHover { if $0 { onHover(index) } }
            }
        }
        .padding(.horizontal, SwitcherMetrics.contentPadding)
        .padding(.vertical, SwitcherMetrics.contentPadding)
    }

    /// Keeps the selection visible, scrolling only when it crosses an edge.
    ///
    /// The scroll target is always the row that should sit at the *top* of the
    /// viewport, anchored to `.top` — a fully determined position, so the list
    /// cannot drift. While the selection is already on screen nothing moves at
    /// all, which is what makes arrowing through a list feel steady.
    private func scroll(_ proxy: ScrollViewProxy, to index: Int, animated: Bool = true) {
        let rows = viewModel.rows
        guard rows.indices.contains(index) else { return }

        let visible = visibleItemCount
        guard rows.count > visible else {
            // Everything fits; there is nothing to scroll.
            if firstVisibleIndex != 0 { firstVisibleIndex = 0 }
            return
        }

        var first = firstVisibleIndex
        if index < first {
            first = index
        } else if index >= first + visible {
            first = index - visible + 1
        } else {
            return // already visible
        }
        first = min(max(0, first), rows.count - visible)
        guard first != firstVisibleIndex else { return }

        firstVisibleIndex = first
        // Align to a row boundary in the grid so cards never sit half-scrolled.
        let aligned = first - (first % max(1, layout.columnCount))
        let target = rows[min(aligned, rows.count - 1)].id

        if animated {
            withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(target, anchor: .top) }
        } else {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: viewModel.query.isEmpty ? "macwindow" : "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(viewModel.query.isEmpty ? "No open windows" : "No matches for “\(viewModel.query)”")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if !viewModel.query.isEmpty {
                Text("Press ⌫ to edit your search")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: SwitcherMetrics.emptyStateHeight)
    }

    private var permissionsBanner: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 26))
                .foregroundStyle(.orange)
            Text("Accessibility access is required")
                .font(.system(size: 13, weight: .semibold))
            Text("QuickSwitch cannot list or focus other apps' windows without it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("Open System Settings", action: onRequestPermissions)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .frame(height: SwitcherMetrics.emptyStateHeight)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            ShortcutHint(keys: ["\(preferences.modifier.symbol)⇥"], label: "next")
            ShortcutHint(keys: layout == .grid ? ["↑", "↓", "←", "→"] : ["↑", "↓"], label: "navigate")
            ShortcutHint(keys: ["⏎"], label: "switch")
            ShortcutHint(keys: ["⌘1–9"], label: "jump")
            Spacer(minLength: 8)
            ShortcutHint(keys: ["esc"], label: "cancel")
        }
        .padding(.horizontal, 16)
        .frame(height: SwitcherMetrics.footerHeight)
        .accessibilityHidden(true)
    }
}

/// Blinking insertion point for the rendered search field.
private struct Caret: View {
    @State private var isVisible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(width: 1.5, height: 17)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    isVisible = false
                }
            }
    }
}

struct ShortcutHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { KeyCapView(text: $0) }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.leading, 1)
        }
    }
}
