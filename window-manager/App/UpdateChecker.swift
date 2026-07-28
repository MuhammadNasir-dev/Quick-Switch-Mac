import AppKit
import Combine
import Foundation
import os

/// Checks quickswitchmac.com for a newer release, once a day.
///
/// ## Why this exists twice over
///
/// QuickSwitch is distributed directly rather than through the App Store, and
/// without a Developer ID certificate it cannot be notarized — so it cannot
/// auto-update either, because every replacement binary would trip Gatekeeper
/// again. Telling the user a new version exists, and sending them to the
/// download, is the most that can be done honestly.
///
/// The same request also answers "how many people use this?". Each running copy
/// fetches one static file per day, so the web server's ordinary access logs
/// give a daily active count with no analytics service, no dependency, and
/// nothing stored on the user's machine beyond the date of the last check.
///
/// ## What is sent
///
/// A plain `GET` carrying the app version and the macOS version as query
/// parameters, so releases can be broken down by version. There is **no install
/// identifier**, no account, no persistent token — and emphatically nothing
/// derived from the user's windows. An app holding Accessibility permission has
/// to be able to say that plainly and have it be true.
@MainActor
final class UpdateChecker: ObservableObject {
    /// `nonisolated` so the manifest can be parsed and asserted on without a
    /// main-actor hop; nothing here touches shared state.
    nonisolated struct Release: Equatable {
        let version: AppVersion
        let downloadURL: URL
        let notes: String?
    }

    nonisolated enum State: Equatable {
        case idle
        case checking
        case upToDate(checkedAt: Date)
        case updateAvailable(Release)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// Where the release manifest lives. A static file — no backend required.
    nonisolated static let manifestURL = URL(string: "https://quickswitchmac.com/appcast.json")
        ?? URL(fileURLWithPath: "/")

    private static let lastCheckKey = "updates.lastCheck"
    /// Once a day. Frequent enough to notice a release, rare enough that the
    /// resulting log line is a meaningful "active today" signal rather than noise.
    private static let interval: TimeInterval = 24 * 60 * 60

    private let defaults: UserDefaults
    private let session: URLSession
    private let currentVersion: AppVersion
    private var checkTask: Task<Void, Never>?

    /// - Parameter currentVersion: `nil` reads the bundle. A default
    ///   *expression* cannot be used because default arguments are evaluated in
    ///   a `nonisolated` context, and `AppInfo.version` is main-actor isolated.
    init(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        currentVersion: String? = nil
    ) {
        self.defaults = defaults
        self.session = session
        self.currentVersion = AppVersion(currentVersion ?? AppInfo.version)
    }

    deinit {
        checkTask?.cancel()
    }

    var lastCheck: Date? {
        let stamp = defaults.double(forKey: Self.lastCheckKey)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// Runs a check if one is due. Called at launch and when Settings opens.
    func checkIfDue(enabled: Bool) {
        guard enabled else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.interval { return }
        check()
    }

    /// Checks now, regardless of when the last one ran.
    func check() {
        checkTask?.cancel()
        state = .checking
        checkTask = Task { [weak self] in
            await self?.performCheck()
        }
    }

    func openDownloadPage() {
        if case .updateAvailable(let release) = state {
            NSWorkspace.shared.open(release.downloadURL)
        } else {
            NSWorkspace.shared.open(AppInfo.website)
        }
    }

    // MARK: - Private

    private func performCheck() async {
        var components = URLComponents(url: Self.manifestURL, resolvingAgainstBaseURL: false)
        let os = ProcessInfo.processInfo.operatingSystemVersion
        components?.queryItems = [
            URLQueryItem(name: "v", value: currentVersion.original),
            URLQueryItem(name: "os", value: "\(os.majorVersion).\(os.minorVersion)")
        ]
        guard let url = components?.url else {
            state = .failed("Could not build the update URL.")
            return
        }

        var request = URLRequest(url: url)
        // Short: a stalled check must never be something the user notices.
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: request)
            if Task.isCancelled { return }

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                state = .failed("The update server replied with \(code).")
                return
            }

            let release = try Self.parse(data)
            defaults.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)

            if release.version > currentVersion {
                Log.ui.notice("Update available: \(release.version.original, privacy: .public)")
                state = .updateAvailable(release)
            } else {
                state = .upToDate(checkedAt: Date())
            }
        } catch is CancellationError {
            return
        } catch {
            // Being offline is normal and not worth alarming anybody about; the
            // message is only shown if the user explicitly asked to check.
            state = .failed(error.localizedDescription)
        }
    }

    /// Parses the manifest.
    ///
    /// Deliberately hand-rolled rather than `Codable`: the file is three fields
    /// hosted separately from the app, and a future field added to it must never
    /// make an older build fail to parse and stop checking for updates.
    nonisolated static func parse(_ data: Data) throws -> Release {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let versionString = object["version"] as? String,
              let urlString = object["url"] as? String,
              let url = URL(string: urlString) else {
            throw UpdateError.malformedManifest
        }
        return Release(
            version: AppVersion(versionString),
            downloadURL: url,
            notes: object["notes"] as? String
        )
    }

    nonisolated enum UpdateError: LocalizedError {
        case malformedManifest

        var errorDescription: String? {
            switch self {
            case .malformedManifest: "The update manifest could not be read."
            }
        }
    }
}
