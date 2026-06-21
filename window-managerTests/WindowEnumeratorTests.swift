import AppKit
import Testing
@testable import window_manager

/// Integration-flavoured checks against the live window server.
///
/// These run against whatever is actually open on the machine, so they assert
/// invariants rather than exact contents. They are the only tests that can
/// catch a regression in the CoreGraphics/Accessibility correlation, which is
/// the part of the system that unit tests cannot reach.
@Suite("Window enumeration", .serialized)
struct WindowEnumeratorTests {
    @Test("The private window-number lookup still resolves")
    func privateAPIAvailable() {
        // If this ever fails on a new macOS release, the enumerator silently
        // falls back to geometry correlation — this test is the early warning.
        #expect(AXPrivateAPI.isWindowIDLookupAvailable)
    }

    @Test("Enumeration never traps and never returns duplicates")
    func snapshotIsWellFormed() {
        guard AXIsProcessTrusted() else { return }
        let windows = WindowEnumerator().snapshot()
        let ids = windows.map(\.id)
        #expect(Set(ids).count == ids.count, "Each window must appear exactly once")
        #expect(windows.allSatisfy { $0.id != 0 })
        #expect(windows.allSatisfy { $0.pid > 0 })
        #expect(windows.allSatisfy { !$0.displayTitle.isEmpty })
    }

    @Test("Excluded system processes never appear")
    func excludesSystemUI() {
        guard AXIsProcessTrusted() else { return }
        let windows = WindowEnumerator().snapshot()
        let bundleIDs = Set(windows.compactMap(\.bundleIdentifier))
        #expect(bundleIDs.isDisjoint(with: WindowFilter.excludedBundleIdentifiers))
        #expect(!windows.contains { $0.pid == ProcessInfo.processInfo.processIdentifier })
    }

    @Test("A full scan stays inside the refresh budget", .timeLimit(.minutes(1)))
    func snapshotIsFastEnough() {
        guard AXIsProcessTrusted() else { return }
        let enumerator = WindowEnumerator()
        _ = enumerator.snapshot() // warm the Accessibility connections

        let (_, seconds) = measure { enumerator.snapshot() }
        // The panel reads a warm cache, so this is the *background* refresh
        // budget, not the open-time budget. Two seconds would indicate the
        // per-process timeout or the concurrent fan-out has regressed.
        #expect(seconds < 2.0, "Enumeration took \(seconds)s")
    }
}
