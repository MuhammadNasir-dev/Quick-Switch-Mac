import AppKit
import SwiftUI

/// Shared presentation vocabulary for a window in every layout.
///
/// Keeping the badge, highlight and icon treatment in one place is what stops
/// the list, grouped and grid modes from drifting into three different-looking
/// products.
enum WindowPresentation {
    /// Trailing status badge, or `nil` for an ordinary on-screen window.
    struct Badge {
        let text: String
        let symbol: String
        let tint: Color
    }

    static func badge(for window: AppWindow) -> Badge? {
        if window.isMinimized {
            return Badge(text: "Minimised", symbol: "arrow.down.right.and.arrow.up.left", tint: .orange)
        }
        if window.isFullScreen {
            return Badge(text: "Full Screen", symbol: "arrow.up.left.and.arrow.down.right", tint: .blue)
        }
        if !window.isOnActiveSpace {
            return Badge(text: "Other Space", symbol: "rectangle.on.rectangle", tint: .purple)
        }
        return nil
    }

    /// Renders the title with fuzzy-match hits emphasised, so it is visible
    /// *why* a row matched the query.
    static func highlighted(_ text: String, indices: [Int]) -> Text {
        guard !indices.isEmpty else { return Text(text) }
        let matched = Set(indices)
        var result = Text("")
        for (offset, character) in text.enumerated() {
            let piece = Text(String(character))
            result = result + (matched.contains(offset)
                ? piece.foregroundColor(.accentColor).fontWeight(.semibold)
                : piece)
        }
        return result
    }
}

/// The pin control shown on each row and card.
///
/// A `Button` rather than a bare `Image` with a tap gesture: the panel never
/// becomes key, so the star has to work purely from mouse tracking, and a button
/// gets the hit-testing, pressed state and VoiceOver role for free. `.plain`
/// keeps it from drawing a bezel over the row.
///
/// It is visible whenever the window is pinned, and appears in outline form on
/// the highlighted row — showing an empty star on all forty rows at once would
/// be visual noise, and the highlighted row is the one ⌘D would act on anyway.
struct FavouriteButton: View {
    let isFavourite: Bool
    let isSelected: Bool
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        if isFavourite || isSelected {
            Button(action: action) {
                Image(systemName: isFavourite ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(isFavourite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tertiary))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isFavourite ? "Unpin this app" : "Pin this app to the top")
            .accessibilityLabel(isFavourite ? "Unpin app" : "Pin app")
        }
    }
}

/// A window as a dense, left-to-right list row.
///
/// Used by both `.list` and `.grouped`; in the latter the application name is
/// suppressed (the section header already carries it) and the row is indented
/// under that header.
struct WindowRowView: View {
    let row: SwitcherViewModel.Row
    let icon: NSImage
    let isSelected: Bool
    /// 1-based position, rendered as the ⌘N hint for the first nine items.
    let ordinal: Int
    var showsAppName: Bool = true
    var isIndented: Bool = false
    var onToggleFavourite: () -> Void = {}

    private var window: AppWindow { row.window }

    var body: some View {
        HStack(spacing: 12) {
            // A thin accent bar reads as "selected" even at a glance and even
            // for users who cannot distinguish the tinted background.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.accentColor)
                .frame(width: 3, height: 22)
                .opacity(isSelected ? 1 : 0)

            AppIconView(icon: icon, size: showsAppName ? 30 : 22, isDimmed: window.isMinimized)

            VStack(alignment: .leading, spacing: 2) {
                WindowPresentation.highlighted(window.displayTitle, indices: row.highlightedTitleIndices)
                    .font(.system(size: 13.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if showsAppName {
                    Text(window.appName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            FavouriteButton(
                isFavourite: row.isFavourite,
                isSelected: isSelected,
                size: 11,
                action: onToggleFavourite
            )

            if let badge = WindowPresentation.badge(for: window) {
                BadgeView(badge: badge, compact: false)
            }

            if ordinal <= 9 {
                KeyCapView(text: "⌘\(ordinal)")
                    .opacity(isSelected ? 1 : 0.45)
            }
        }
        .padding(.leading, isIndented ? 18 : 6)
        .padding(.trailing, 10)
        .frame(height: SwitcherLayout.list.itemHeight)
        .background(SelectionBackground(isSelected: isSelected))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.appName), \(window.displayTitle)")
        .accessibilityValue(
            [row.isFavourite ? "Favourite" : nil, WindowPresentation.badge(for: window)?.text]
                .compactMap { $0 }.joined(separator: ", ")
        )
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Application header above a run of that app's windows in `.grouped`.
struct GroupHeaderView: View {
    let appName: String
    let icon: NSImage
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 15, height: 15)

            Text(appName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("\(count)")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.07)))

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)
        }
        .padding(.horizontal, 8)
        .frame(height: SwitcherLayout.grouped.groupHeaderHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(appName), \(count) windows")
        .accessibilityAddTraits(.isHeader)
    }
}

/// A window as a grid card.
///
/// Modelled on the system Command-Tab switcher — a large, centred application
/// icon is what the eye actually recognises — with the window title beneath,
/// since unlike the system switcher this addresses individual windows.
struct WindowCardView: View {
    let row: SwitcherViewModel.Row
    let icon: NSImage
    let isSelected: Bool
    let ordinal: Int
    var onToggleFavourite: () -> Void = {}

    private var window: AppWindow { row.window }

    var body: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .topTrailing) {
                AppIconView(icon: icon, size: 46, isDimmed: window.isMinimized)
                    .frame(maxWidth: .infinity)

                if let badge = WindowPresentation.badge(for: window) {
                    Image(systemName: badge.symbol)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Circle().fill(badge.tint))
                        .offset(x: -6, y: -2)
                }
            }
            .frame(height: 48)
            .overlay(alignment: .topLeading) {
                FavouriteButton(
                    isFavourite: row.isFavourite,
                    isSelected: isSelected,
                    size: 10,
                    action: onToggleFavourite
                )
                .padding(.leading, 4)
            }

            VStack(spacing: 1) {
                WindowPresentation.highlighted(window.displayTitle, indices: row.highlightedTitleIndices)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)

                Text(window.appName)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.top, 9)
        .padding(.bottom, 6)
        .frame(height: SwitcherLayout.grid.itemHeight)
        .frame(maxWidth: .infinity)
        .background(SelectionBackground(isSelected: isSelected))
        // Opposite corner from the pin, which owns the top-leading slot.
        .overlay(alignment: .topTrailing) {
            if ordinal <= 9, isSelected {
                KeyCapView(text: "⌘\(ordinal)")
                    .padding(5)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.appName), \(window.displayTitle)")
        .accessibilityValue(
            [row.isFavourite ? "Favourite" : nil, WindowPresentation.badge(for: window)?.text]
                .compactMap { $0 }.joined(separator: ", ")
        )
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Shared components

/// Selection treatment used by every layout.
private struct SelectionBackground: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: SwitcherMetrics.itemCornerRadius, style: .continuous)
            .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(Color.clear))
            .overlay(
                RoundedRectangle(cornerRadius: SwitcherMetrics.itemCornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(isSelected ? 0.5 : 0), lineWidth: 1)
            )
    }
}

/// Application icon with a subtle shadow, dimmed for minimised windows.
private struct AppIconView: View {
    let icon: NSImage
    let size: CGFloat
    let isDimmed: Bool

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
            .opacity(isDimmed ? 0.55 : 1)
            .accessibilityHidden(true)
    }
}

private struct BadgeView: View {
    let badge: WindowPresentation.Badge
    let compact: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: badge.symbol)
                .font(.system(size: compact ? 7 : 8, weight: .semibold))
            if !compact {
                Text(badge.text)
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .foregroundStyle(badge.tint)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, compact ? 2 : 3)
        .background(Capsule().fill(badge.tint.opacity(0.15)))
        .overlay(Capsule().strokeBorder(badge.tint.opacity(0.25), lineWidth: 0.5))
    }
}

/// A key-cap styled shortcut chip.
struct KeyCapView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
    }
}
