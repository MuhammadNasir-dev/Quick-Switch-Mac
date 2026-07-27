import AppKit
import Combine
import CoreGraphics
import Foundation
import os

/// The always-warm, MRU-ordered cache of every switchable window.
///
/// This is the change that makes the sub-50 ms target reachable. Opening the
/// panel reads `windows` — an array that is already correct — and schedules an
/// asynchronous refresh; it never blocks on Accessibility IPC. The old code
/// performed a full synchronous enumeration inside the hotkey handler.
///
/// Concurrency model:
/// * State (`windows`, recency, coalescing) is `@MainActor`-isolated.
/// * Enumeration is pure and runs on a detached task.
/// * Only one enumeration is ever in flight; overlapping requests set a
///   "dirty" bit that re-runs once, which prevents the notification storms that
///   apps like Xcode and Chrome produce during window teardown from spawning
///   dozens of concurrent scans.
@MainActor
final class WindowIndex: ObservableObject {
    /// MRU-ordered snapshot. Index 0 is the current window.
    @Published private(set) var windows: [AppWindow] = []
    /// Timestamp of the last successful enumeration.
    @Published private(set) var lastRefresh: Date?

    private let enumerator: WindowEnumerator
    private let recency: RecencyTracker
    private let observation: WindowObservationCenter

    private var isEnumerating = false
    private var needsAnotherPass = false
    private var coalesceWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false

    /// Notification bursts are coalesced over this window. Long enough to
    /// collapse a Chrome tab-drag storm, short enough to be invisible.
    private let coalescingInterval: TimeInterval = 0.12

    /// - Note: `recency` and `observation` default to `nil` rather than to
    ///   freshly constructed values because default argument expressions are
    ///   evaluated in a `nonisolated` context, which cannot call a `@MainActor`
    ///   initialiser. Tests inject their own instances.
    init(
        enumerator: WindowEnumerator = WindowEnumerator(),
        recency: RecencyTracker? = nil,
        observation: WindowObservationCenter? = nil
    ) {
        self.enumerator = enumerator
        self.recency = recency ?? RecencyTracker()
        self.observation = observation ?? WindowObservationCenter()
    }

    deinit {
        coalesceWorkItem?.cancel()
    }

    // MARK: - Lifecycle

    /// Begins observing and performs the initial enumeration.
    ///
    /// Requires Accessibility trust; call again after trust is granted.
    func start() {
        guard !isStarted else { return }
        isStarted = true

        observation.changes
            .sink { [weak self] change in
                guard let self else { return }
                switch change {
                case .focus(let pid):
                    self.recordFocus(pid: pid)
                    self.scheduleRefresh()
                case .structural, .metadata:
                    self.scheduleRefresh()
                }
            }
            .store(in: &cancellables)

        observation.start()
        Task { await refresh() }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        observation.stop()
        cancellables.removeAll()
        coalesceWorkItem?.cancel()
        coalesceWorkItem = nil
        windows = []
    }

    // MARK: - Refresh

    /// Coalesced, non-blocking refresh request.
    func scheduleRefresh() {
        coalesceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { await self.refresh() }
        }
        coalesceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + coalescingInterval, execute: item)
    }

    /// Performs one enumeration, serialised against any in-flight pass.
    func refresh() async {
        guard !isEnumerating else {
            needsAnotherPass = true
            return
        }
        isEnumerating = true
        defer { isEnumerating = false }

        repeat {
            needsAnotherPass = false
            let enumerator = self.enumerator
            let snapshot = await Task.detached(priority: .userInitiated) {
                enumerator.snapshot()
            }.value

            apply(snapshot)
        } while needsAnotherPass
    }

    private func apply(_ snapshot: WindowEnumerator.Snapshot) {
        let merged = retaining(snapshot)
        recency.seedIfNeeded(from: merged)
        recency.reconcile(existing: Set(merged.map(\.id)))
        let ordered = recency.ordered(merged)

        // Publishing an identical array would invalidate every SwiftUI row for
        // nothing; `AppWindow: Equatable` makes this comparison cheap.
        if ordered != windows {
            windows = ordered
        }
        lastRefresh = Date()
        observation.syncWindowObservations(with: ordered)
    }

    /// Carries forward windows that are still open but that Accessibility
    /// omitted from this pass.
    ///
    /// `kAXWindowsAttribute` under-reports an application's windows that sit on
    /// a Space other than the active one, so a plain replace-the-list refresh
    /// makes everything on Desktop 2 vanish while the user is on Desktop 1 —
    /// and reappear when they switch. CoreGraphics still lists those windows,
    /// so a window absent from Accessibility but present in `liveWindowIDs` is
    /// kept exactly as it was last described, `AXUIElement` and title included.
    ///
    /// This is deliberately *retention*, not invention: only windows previously
    /// described by Accessibility survive. Synthesising entries from the
    /// CoreGraphics list instead produces duplicates, because a single window
    /// routinely owns several layer-0 surfaces that no public API distinguishes
    /// from real windows.
    private func retaining(_ snapshot: WindowEnumerator.Snapshot) -> [AppWindow] {
        let reported = Set(snapshot.windows.map(\.id))
        let carriedOver = windows.filter { window in
            !reported.contains(window.id) && snapshot.liveWindowIDs.contains(window.id)
        }
        guard !carriedOver.isEmpty else { return snapshot.windows }

        Log.windows.debug("Carrying over \(carriedOver.count, privacy: .public) window(s) Accessibility did not report")
        return snapshot.windows + carriedOver.map {
            $0.onActiveSpace(snapshot.onScreenWindowIDs.contains($0.id))
        }
    }

    // MARK: - Recency

    /// Marks the focused window of `pid` as most recent.
    ///
    /// Reads only two Accessibility attributes, so it is safe on the main
    /// thread even during rapid app switching.
    func recordFocus(pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        AX.setMessagingTimeout(appElement, seconds: 0.1)
        guard let focused: AXUIElement = AX.value(appElement, kAXFocusedWindowAttribute as String),
              let windowID = AXPrivateAPI.windowID(of: focused) else { return }
        recency.touch(windowID: windowID)
    }

    /// Marks a specific window as most recent — used immediately after the
    /// switcher activates it, so the ordering is correct even before the
    /// system's focus notification arrives.
    func recordFocus(windowID: CGWindowID) {
        recency.touch(windowID: windowID)
        if let index = windows.firstIndex(where: { $0.id == windowID }), index != 0 {
            var reordered = windows
            let window = reordered.remove(at: index)
            reordered.insert(window, at: 0)
            windows = reordered
        }
    }
}
