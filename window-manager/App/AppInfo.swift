import AppKit
import Foundation

/// Read-only bundle metadata, resolved once.
///
/// Everything here comes from `Info.plist` rather than being hard-coded, so the
/// version shown in About is by construction the version that shipped — the
/// usual failure mode being a literal in the UI that nobody remembers to bump.
enum AppInfo {
    static let name: String = string("CFBundleName") ?? "QuickSwitch"

    /// Marketing version, e.g. `1.0`.
    static let version: String = string("CFBundleShortVersionString") ?? "1.0"

    /// Build number, e.g. `1`.
    static let build: String = string("CFBundleVersion") ?? "1"

    /// `1.0 (1)`, or just `1.0` when the build number adds nothing.
    static var displayVersion: String {
        build == version ? version : "\(version) (\(build))"
    }

    static let copyright: String = string("NSHumanReadableCopyright")
        ?? "© \(Calendar.current.component(.year, from: Date())) QuickSwitchMac"

    static let website = URL(string: "https://quickswitchmac.com") ?? URL(fileURLWithPath: "/")

    /// The icon actually installed in the bundle, so UI never drifts from it.
    @MainActor
    static var icon: NSImage { NSApp.applicationIconImage }

    private static func string(_ key: String) -> String? {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        return value?.isEmpty == false ? value : nil
    }
}
