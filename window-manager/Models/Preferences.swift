import Combine
import Foundation
import SwiftUI

/// User-visible settings, persisted in `UserDefaults`.
///
/// Injected as an `ObservableObject` rather than reached through a global, so
/// tests can construct an instance backed by an ephemeral suite.
@MainActor
final class Preferences: ObservableObject {
    private enum Key {
        static let modifier = "switcher.modifier"
        static let includeMinimized = "switcher.includeMinimized"
        static let includeOtherSpaces = "switcher.includeOtherSpaces"
        static let showShortcutHints = "switcher.showShortcutHints"
        static let confirmOnModifierRelease = "switcher.confirmOnModifierRelease"
        static let maximumVisibleRows = "switcher.maximumVisibleRows"
        static let layout = "switcher.layout"
        static let activeAppFirst = "switcher.activeAppFirst"
    }

    private let defaults: UserDefaults

    /// Modifier combined with Tab to summon the switcher.
    ///
    /// Defaults to Option, not Command: Option-Tab is unclaimed, so the
    /// switcher works immediately and the system app switcher stays available
    /// as a fallback while the user is still granting permissions or deciding
    /// whether they like this one. Choosing Command in Settings takes over
    /// Command-Tab and replaces the system switcher outright.
    @Published var modifier: SwitcherModifier {
        didSet { defaults.set(modifier.rawValue, forKey: Key.modifier) }
    }

    @Published var includeMinimized: Bool {
        didSet { defaults.set(includeMinimized, forKey: Key.includeMinimized) }
    }

    @Published var includeOtherSpaces: Bool {
        didSet { defaults.set(includeOtherSpaces, forKey: Key.includeOtherSpaces) }
    }

    @Published var showShortcutHints: Bool {
        didSet { defaults.set(showShortcutHints, forKey: Key.showShortcutHints) }
    }

    /// When enabled, letting go of the modifier activates the highlighted
    /// window — the familiar Command-Tab feel. Disable for a click-to-dismiss
    /// panel that stays open until Return or Escape.
    @Published var confirmOnModifierRelease: Bool {
        didSet { defaults.set(confirmOnModifierRelease, forKey: Key.confirmOnModifierRelease) }
    }

    @Published var maximumVisibleRows: Int {
        didSet { defaults.set(maximumVisibleRows, forKey: Key.maximumVisibleRows) }
    }

    /// List or grid presentation.
    @Published var layout: SwitcherLayout {
        didSet { defaults.set(layout.rawValue, forKey: Key.layout) }
    }

    /// Sorts every window of the currently active application to the top.
    ///
    /// Useful when you mostly switch *within* an app (editor tabs, browser
    /// windows). Turn it off for strict most-recently-used order, where the
    /// second entry is whatever you were on immediately before.
    @Published var showActiveAppWindowsFirst: Bool {
        didSet { defaults.set(showActiveAppWindowsFirst, forKey: Key.activeAppFirst) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.modifier: SwitcherModifier.option.rawValue,
            Key.includeMinimized: true,
            Key.includeOtherSpaces: true,
            Key.showShortcutHints: true,
            Key.confirmOnModifierRelease: true,
            Key.maximumVisibleRows: 9,
            Key.layout: SwitcherLayout.list.rawValue,
            Key.activeAppFirst: true
        ])

        let rawModifier = defaults.string(forKey: Key.modifier) ?? SwitcherModifier.option.rawValue
        modifier = SwitcherModifier(rawValue: rawModifier) ?? .option
        includeMinimized = defaults.bool(forKey: Key.includeMinimized)
        includeOtherSpaces = defaults.bool(forKey: Key.includeOtherSpaces)
        showShortcutHints = defaults.bool(forKey: Key.showShortcutHints)
        confirmOnModifierRelease = defaults.bool(forKey: Key.confirmOnModifierRelease)
        maximumVisibleRows = min(max(defaults.integer(forKey: Key.maximumVisibleRows), 4), 16)
        layout = SwitcherLayout(rawValue: defaults.string(forKey: Key.layout) ?? "") ?? .list
        showActiveAppWindowsFirst = defaults.bool(forKey: Key.activeAppFirst)
    }
}
