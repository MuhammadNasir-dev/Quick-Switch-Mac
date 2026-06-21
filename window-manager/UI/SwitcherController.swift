import AppKit
import Combine
import SwiftUI

/// Orchestrates the switcher: turns `SwitcherCommand`s into view-model updates
/// and panel visibility, and hands the final choice to `WindowActivator`.
///
/// This is the piece the original `SwitcherPanel` conflated with the window
/// itself: it owned the view model, the hosting view, the AX activation logic
/// and the key handling all at once. Separating orchestration from the
/// `NSPanel` is what makes the panel reusable and the behaviour testable.
@MainActor
final class SwitcherController {
    private let panel: SwitcherPanel
    private let viewModel: SwitcherViewModel
    private let preferences: Preferences
    private let windowIndex: WindowIndex
    private let activator: WindowActivator
    private let authorizer: AccessibilityAuthorizer
    private let hotKeyMonitor: HotKeyMonitor

    private var hostingView: NSHostingView<SwitcherView>?
    private var cancellables = Set<AnyCancellable>()
    private var localMouseMonitor: Any?

    /// `true` between `show()` and `dismiss()`.
    private(set) var isVisible = false

    init(
        preferences: Preferences,
        windowIndex: WindowIndex,
        authorizer: AccessibilityAuthorizer,
        hotKeyMonitor: HotKeyMonitor,
        iconProvider: IconProvider,
        activator: WindowActivator? = nil
    ) {
        let activator = activator ?? WindowActivator()
        self.preferences = preferences
        self.windowIndex = windowIndex
        self.authorizer = authorizer
        self.hotKeyMonitor = hotKeyMonitor
        self.activator = activator
        self.panel = SwitcherPanel()
        self.viewModel = SwitcherViewModel(preferences: preferences, iconProvider: iconProvider)

        viewModel.bind(to: windowIndex, authorizer: authorizer)
        buildContentView()
        observeState()

        activator.onActivated = { [weak self] window in
            self?.windowIndex.recordFocus(windowID: window.id)
        }
    }

    deinit {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
    }

    // MARK: - Setup

    /// Builds and warms the hosting view at launch.
    ///
    /// The first `NSHostingView` render of a SwiftUI hierarchy costs tens of
    /// milliseconds (view graph construction, font loading, material setup).
    /// Paying it during app launch instead of on the first hotkey press is the
    /// single biggest contributor to hitting the open-time budget.
    private func buildContentView() {
        let view = SwitcherView(
            viewModel: viewModel,
            preferences: preferences,
            onActivate: { [weak self] window in self?.activate(window) },
            onHover: { [weak self] index in self?.viewModel.select(at: index) },
            onRequestPermissions: { [weak self] in
                self?.dismiss()
                self?.authorizer.openSystemSettings()
            }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.autoresizingMask = [.width, .height]
        if let contentView = panel.contentView {
            hosting.frame = contentView.bounds
        }
        panel.contentView = hosting
        hostingView = hosting

        // Force one layout pass off-screen so the view graph is resident.
        panel.setFrame(
            NSRect(x: -10_000, y: -10_000, width: SwitcherLayout.list.panelWidth, height: 300),
            display: false
        )
        panel.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        panel.orderOut(nil)
    }

    private func observeState() {
        // Keep the panel height in step with the number of matches.
        viewModel.$rows
            .map { rows in [rows.count, rows.count { $0.startsGroup }] }
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, self.isVisible else { return }
                self.panel.updateSize(self.currentPanelSize())
            }
            .store(in: &cancellables)

        // Switching layout changes both dimensions of the panel.
        preferences.$layout
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.isVisible else { return }
                self.panel.updateSize(self.currentPanelSize())
            }
            .store(in: &cancellables)

        // A pinned panel no longer confirms on modifier release.
        viewModel.$isPinned
            .sink { [weak self] pinned in
                guard let self else { return }
                self.hotKeyMonitor.setHoldModeActive(
                    !pinned && self.preferences.confirmOnModifierRelease
                )
            }
            .store(in: &cancellables)

        preferences.$modifier
            .sink { [weak self] modifier in
                self?.hotKeyMonitor.setModifier(modifier)
            }
            .store(in: &cancellables)

        // Losing Accessibility trust mid-session must close the panel, because
        // nothing in it can be acted on any more.
        authorizer.$status
            .sink { [weak self] status in
                if status == .notTrusted { self?.dismiss() }
            }
            .store(in: &cancellables)

        // Clicking anywhere outside the panel cancels, matching every other
        // transient macOS overlay.
        localMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible else { return }
                self.dismiss()
            }
        }
    }

    // MARK: - Commands

    func handle(_ command: SwitcherCommand) {
        switch command {
        case .invoke(let reverse):
            if isVisible {
                viewModel.move(by: reverse ? -1 : 1)
            } else {
                show(reverse: reverse)
            }

        // Explicit navigation pins the panel.
        //
        // Reaching the arrow keys means taking your hand off the summoning
        // modifier, and releasing it would otherwise fire "confirm on release"
        // and switch away before the arrow key ever arrived — which made arrow
        // navigation effectively unusable in hold mode. Note that Tab *with*
        // the modifier decodes as `.invoke`, not `.move`, so holding the
        // modifier and tabbing still behaves exactly like Command-Tab.
        case .move(let delta):
            guard isVisible else { return }
            viewModel.pin()
            viewModel.move(by: delta)

        case .moveVertical(let rows):
            guard isVisible else { return }
            viewModel.pin()
            viewModel.moveVertical(by: rows)

        case .moveToEdge(let first):
            guard isVisible else { return }
            viewModel.pin()
            viewModel.moveToEdge(first: first)

        case .selectIndex(let ordinal):
            guard isVisible else { return }
            if viewModel.selectOrdinal(ordinal) {
                confirm()
            }

        case .confirm:
            guard isVisible else { return }
            confirm()

        case .toggleLayout:
            guard isVisible else { return }
            viewModel.pin()
            preferences.layout = preferences.layout.next

        case .cancel:
            dismiss()

        case .insertText(let text):
            guard isVisible else { return }
            viewModel.insertText(text)

        case .deleteBackward:
            guard isVisible else { return }
            viewModel.deleteBackward()

        case .clearQuery:
            guard isVisible else { return }
            viewModel.clearQuery()

        case .modifierReleased:
            guard isVisible, !viewModel.isPinned, preferences.confirmOnModifierRelease else { return }
            confirm()
        }
    }

    /// Opens the switcher, e.g. from the status-item menu. Always pinned, since
    /// there is no held modifier to release.
    func showPinned() {
        show(reverse: false)
        viewModel.pin()
        // Opened without a held modifier, so start on the first entry rather
        // than the "previous window" position that Tab-invocation uses.
        viewModel.moveToEdge(first: true)
    }

    // MARK: - Presentation

    private func show(reverse: Bool) {
        guard authorizer.isTrusted else {
            authorizer.requestTrust()
            return
        }

        // Render from the warm cache immediately, then reconcile in the
        // background. The user sees the list on the same run-loop turn as the
        // keystroke; the async refresh lands a frame or two later if anything
        // changed.
        viewModel.beginSession(reverse: reverse)

        panel.beginSession(
            size: currentPanelSize(),
            maximumHeight: SwitcherMetrics.maximumPanelHeight(
                layout: preferences.layout,
                maximumVisibleRows: preferences.maximumVisibleRows,
                showsFooter: preferences.showShortcutHints
            )
        )
        panel.orderFrontRegardless()
        isVisible = true
        hotKeyMonitor.setSwitcherVisible(true)
        hotKeyMonitor.setHoldModeActive(preferences.confirmOnModifierRelease)

        windowIndex.scheduleRefresh()
    }

    func dismiss() {
        guard isVisible else { return }
        isVisible = false
        hotKeyMonitor.setSwitcherVisible(false)
        hotKeyMonitor.setHoldModeActive(false)
        panel.orderOut(nil)
        panel.endSession()
        viewModel.endSession()
    }

    private func confirm() {
        guard let window = viewModel.selectedWindow else {
            dismiss()
            return
        }
        activate(window)
    }

    private func activate(_ window: AppWindow) {
        // Hide first: the panel is non-activating, but ordering it out before
        // the target app comes forward avoids a frame where both are visible.
        dismiss()
        activator.activate(window)
    }

    private func currentPanelSize() -> CGSize {
        let layout = preferences.layout
        return CGSize(
            width: SwitcherMetrics.panelWidth(layout: layout),
            height: SwitcherMetrics.panelHeight(
                layout: layout,
                itemCount: viewModel.isAccessibilityTrusted ? viewModel.rows.count : 0,
                groupCount: viewModel.isAccessibilityTrusted ? viewModel.groupCount : 0,
                maximumVisibleRows: preferences.maximumVisibleRows,
                showsFooter: preferences.showShortcutHints
            )
        )
    }
}
