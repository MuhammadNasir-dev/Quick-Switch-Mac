import AppKit
import Combine
import Foundation

/// Applications the user has pinned to the top of the switcher.
///
/// Favourites are keyed by **bundle identifier**, not by window. A window's
/// `CGWindowID` is reassigned every time the window is closed and reopened, and
/// its title changes as the user works, so neither survives a restart — a
/// favourite anchored to either would silently evaporate. The bundle identifier
/// is stable for the life of the installed app.
///
/// That also matches how the feature is used: "always show me Xcode and Slack
/// first", not "always show me this one particular untitled document".
@MainActor
final class FavouritesStore: ObservableObject {
    private static let key = "switcher.favouriteBundleIdentifiers"

    /// Bundle identifiers, in the order they were added.
    @Published private(set) var bundleIdentifiers: [String]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bundleIdentifiers = defaults.stringArray(forKey: Self.key) ?? []
    }

    var isEmpty: Bool { bundleIdentifiers.isEmpty }

    func contains(_ window: AppWindow) -> Bool {
        guard let bundleID = window.bundleIdentifier else { return false }
        return bundleIdentifiers.contains(bundleID)
    }

    /// Adds or removes the window's application. Returns the new state, so the
    /// caller can report what happened without re-querying.
    @discardableResult
    func toggle(_ window: AppWindow) -> Bool {
        // Processes without a bundle identifier — raw executables — cannot be
        // favourited, because there is nothing durable to remember them by.
        guard let bundleID = window.bundleIdentifier else { return false }

        if let index = bundleIdentifiers.firstIndex(of: bundleID) {
            bundleIdentifiers.remove(at: index)
            persist()
            return false
        }
        bundleIdentifiers.append(bundleID)
        persist()
        return true
    }

    func remove(_ bundleIdentifier: String) {
        guard let index = bundleIdentifiers.firstIndex(of: bundleIdentifier) else { return }
        bundleIdentifiers.remove(at: index)
        persist()
    }

    func removeAll() {
        guard !bundleIdentifiers.isEmpty else { return }
        bundleIdentifiers.removeAll()
        persist()
    }

    /// Moves every favourited window to the front, preserving the relative
    /// order of both groups.
    ///
    /// A stable partition rather than a sort: the incoming order already
    /// encodes most-recent-use (and the active-app grouping), and that ranking
    /// should still decide the order *within* the favourites.
    func prioritising(_ windows: [AppWindow]) -> [AppWindow] {
        guard !bundleIdentifiers.isEmpty else { return windows }
        let favourites = Set(bundleIdentifiers)
        var pinned: [AppWindow] = []
        var rest: [AppWindow] = []
        for window in windows {
            if let bundleID = window.bundleIdentifier, favourites.contains(bundleID) {
                pinned.append(window)
            } else {
                rest.append(window)
            }
        }
        return pinned + rest
    }

    /// Best-effort human-readable name for a stored identifier.
    ///
    /// Favourites outlive the apps being running, so Settings has to name them
    /// from the identifier alone. Launch Services knows the name of anything
    /// installed; the identifier's last component is the fallback for an app
    /// that has since been deleted.
    static func displayName(for bundleIdentifier: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
           let bundle = Bundle(url: url),
           let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) {
            return name
        }
        return bundleIdentifier.components(separatedBy: ".").last ?? bundleIdentifier
    }

    private func persist() {
        defaults.set(bundleIdentifiers, forKey: Self.key)
    }
}
