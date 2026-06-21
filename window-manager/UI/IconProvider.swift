import AppKit
import Foundation
import UniformTypeIdentifiers

/// Caches application icons keyed by bundle identity.
///
/// `NSRunningApplication.icon` decodes and composites an `NSImage` on every
/// access. The old enumerator called it once per *window*, so a Safari session
/// with twenty tabs-as-windows paid twenty decodes per keypress. Icons are
/// per-application and change rarely, so a small keyed cache removes the cost
/// entirely.
@MainActor
final class IconProvider {
    private var cache: [String: NSImage] = [:]
    private let size = NSSize(width: 32, height: 32)
    private var terminationObserver: NSObjectProtocol?

    init() {
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                else { return }
                self.cache.removeValue(forKey: Self.key(bundleID: app.bundleIdentifier, pid: app.processIdentifier))
            }
        }
    }

    deinit {
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
        }
    }

    /// Returns the icon for a window's owning application.
    func icon(for window: AppWindow) -> NSImage {
        let key = Self.key(bundleID: window.bundleIdentifier, pid: window.pid)
        if let cached = cache[key] { return cached }

        let image = resolveIcon(for: window)
        image.size = size
        cache[key] = image
        return image
    }

    func removeAll() {
        cache.removeAll()
    }

    private func resolveIcon(for window: AppWindow) -> NSImage {
        if let bundleURL = window.bundleURL {
            let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
            return icon
        }
        if let running = NSRunningApplication(processIdentifier: window.pid), let icon = running.icon {
            return icon
        }
        // `NSImage(named:)` for a system symbol never fails, but the API is
        // optional; fall back to an empty image rather than force-unwrapping.
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private static func key(bundleID: String?, pid: pid_t) -> String {
        bundleID ?? "pid:\(pid)"
    }
}
