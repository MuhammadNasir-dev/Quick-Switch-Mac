import AppKit
import Combine
import os

/// Menu-bar presence for a background (`LSUIElement`) app.
///
/// The original app had no Dock icon, no menu bar item and no window: once
/// launched there was no way to quit it, change anything, or discover that it
/// was running at all. HIG requires a background agent to provide a visible
/// affordance, and it is also the natural place to surface the two states that
/// otherwise look like the app is broken — missing Accessibility trust, and
/// secure keyboard entry suppressing the hotkey.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let services: AppServices
    private let onOpenSettings: () -> Void
    private let onOpenOnboarding: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private weak var windowCountItem: NSMenuItem?

    init(
        services: AppServices,
        onOpenSettings: @escaping () -> Void,
        onOpenOnboarding: @escaping () -> Void
    ) {
        self.services = services
        self.onOpenSettings = onOpenSettings
        self.onOpenOnboarding = onOpenOnboarding
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        refresh()
        observeState()
    }

    private func observeState() {
        Publishers.MergeMany(
            services.authorizer.$status.map { _ in }.eraseToAnyPublisher(),
            services.authorizer.$isSecureInputActive.map { _ in }.eraseToAnyPublisher(),
            services.$inputFailure.map { _ in }.eraseToAnyPublisher(),
            services.preferences.$layout.map { _ in }.eraseToAnyPublisher()
        )
        // `@Published` publishes from `willSet`, so at delivery time the
        // properties still hold their *previous* values. `refresh()` reads the
        // current state back out of the services, and reading it one
        // notification too early is exactly why the icon stayed on the warning
        // triangle after access was granted: the last emission was handled
        // while `status` was still `.notTrusted`, and nothing emitted again.
        //
        // Hopping to the next run-loop turn lets every transition settle first,
        // and coalesces the burst of changes that a grant produces — status,
        // then the input failure being cleared — into a single rebuild.
        //
        // The window index is deliberately *not* a trigger: it changes
        // constantly, and the only thing that depends on it is the count, which
        // `menuWillOpen` freshens at the moment it becomes visible.
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.refresh() }
        .store(in: &cancellables)
    }

    /// Re-reads every input and rebuilds the icon and menu from scratch.
    private func refresh() {
        configureButton()
        rebuildMenu()
    }

    /// Overall health, driving both the icon and the warning row in the menu.
    private enum Health {
        case ready
        case needsAccessibility
        case inputFailed(HotKeyMonitor.Failure)
        case secureInput

        var symbolName: String {
            switch self {
            case .ready: "macwindow.on.rectangle"
            case .needsAccessibility, .inputFailed: "exclamationmark.triangle"
            case .secureInput: "keyboard.badge.ellipsis"
            }
        }

        var tooltip: String {
            switch self {
            case .ready: "QuickSwitch"
            case .needsAccessibility: "QuickSwitch — Accessibility access required"
            case .inputFailed(.trustRevoked): "QuickSwitch — Accessibility access was revoked"
            case .inputFailed(.repeatedTimeouts): "QuickSwitch — shortcut disabled by the system"
            case .secureInput: "QuickSwitch — secure input is active, shortcut paused"
            }
        }
    }

    /// Ordered by severity: what stops the app working outright comes first.
    private var health: Health {
        guard services.authorizer.isTrusted else { return .needsAccessibility }
        if let failure = services.inputFailure { return .inputFailed(failure) }
        if services.authorizer.isSecureInputActive { return .secureInput }
        return .ready
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let health = self.health
        button.image = NSImage(
            systemSymbolName: health.symbolName,
            accessibilityDescription: "QuickSwitch"
        )
        button.image?.isTemplate = true
        button.toolTip = health.tooltip
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Derived from the same `Health` the icon uses, so the two can never
        // disagree about whether anything is wrong.
        switch health {
        case .ready:
            break

        case .needsAccessibility:
            let warning = NSMenuItem(
                title: "Accessibility access required",
                action: #selector(openOnboarding),
                keyEquivalent: ""
            )
            warning.target = self
            menu.addItem(warning)
            menu.addItem(.separator())

        case .inputFailed(let failure):
            let title = switch failure {
            case .trustRevoked: "Accessibility access was revoked"
            case .repeatedTimeouts: "Shortcut disabled — the system kept dropping it"
            }
            let warning = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)

            let retry = NSMenuItem(title: "Re-enable Shortcut", action: #selector(retryInput), keyEquivalent: "")
            retry.target = self
            menu.addItem(retry)
            menu.addItem(.separator())

        case .secureInput:
            let warning = NSMenuItem(
                title: "Secure input is active — shortcut paused",
                action: nil,
                keyEquivalent: ""
            )
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        let show = NSMenuItem(title: "Show Switcher", action: #selector(showSwitcher), keyEquivalent: "")
        show.target = self
        show.isEnabled = services.authorizer.isTrusted
        menu.addItem(show)

        let count = NSMenuItem(title: windowCountTitle, action: nil, keyEquivalent: "")
        count.isEnabled = false
        menu.addItem(count)
        windowCountItem = count

        menu.addItem(.separator())

        let layoutItem = NSMenuItem(title: "Layout", action: nil, keyEquivalent: "")
        let layoutMenu = NSMenu()
        for layout in SwitcherLayout.allCases {
            let item = NSMenuItem(title: layout.displayName, action: #selector(selectLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = layout.rawValue
            item.state = services.preferences.layout == layout ? .on : .off
            layoutMenu.addItem(item)
        }
        layoutItem.submenu = layoutMenu
        menu.addItem(layoutItem)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let help = NSMenuItem(title: "Setup Guide…", action: #selector(openOnboarding), keyEquivalent: "")
        help.target = self
        menu.addItem(help)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit QuickSwitch", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.delegate = self
        statusItem.menu = menu
    }

    /// Freshens the live window count at the moment the menu is shown, which is
    /// cheaper and more accurate than rebuilding on every index update.
    func menuWillOpen(_ menu: NSMenu) {
        windowCountItem?.title = windowCountTitle
    }

    private var windowCountTitle: String {
        let count = services.windowIndex.windows.count
        return count == 1 ? "1 window tracked" : "\(count) windows tracked"
    }

    @objc private func retryInput() {
        services.restartInput()
    }

    @objc private func showSwitcher() {
        services.switcher.showPinned()
    }

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let layout = SwitcherLayout(rawValue: raw) else { return }
        services.preferences.layout = layout
        rebuildMenu()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func openOnboarding() {
        onOpenOnboarding()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
