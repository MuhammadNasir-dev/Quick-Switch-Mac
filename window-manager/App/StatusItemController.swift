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
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let services: AppServices
    private let onOpenOnboarding: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(services: AppServices, onOpenOnboarding: @escaping () -> Void) {
        self.services = services
        self.onOpenOnboarding = onOpenOnboarding
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
        rebuildMenu()

        Publishers.CombineLatest(services.authorizer.$status, services.authorizer.$isSecureInputActive)
            .sink { [weak self] _, _ in
                self?.configureButton()
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        services.preferences.$layout
            .dropFirst()
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let trusted = services.authorizer.isTrusted
        let symbol = trusted ? "macwindow.on.rectangle" : "exclamationmark.triangle"
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "Window Switcher"
        )
        button.image?.isTemplate = true
        button.toolTip = trusted ? "Window Switcher" : "Window Switcher — Accessibility access required"
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if !services.authorizer.isTrusted {
            let warning = NSMenuItem(
                title: "Accessibility access required",
                action: #selector(openOnboarding),
                keyEquivalent: ""
            )
            warning.target = self
            menu.addItem(warning)
            menu.addItem(.separator())
        } else if services.authorizer.isSecureInputActive {
            let warning = NSMenuItem(
                title: "Secure input is active — hotkey paused",
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

        let count = NSMenuItem(
            title: "\(services.windowIndex.windows.count) windows tracked",
            action: nil,
            keyEquivalent: ""
        )
        count.isEnabled = false
        menu.addItem(count)

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

        let quit = NSMenuItem(title: "Quit Window Switcher", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Refresh the window count each time the menu opens rather than
        // subscribing to every index update.
        menu.delegate = MenuRefresher.shared
        statusItem.menu = menu
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

    /// Opens the SwiftUI `Settings` scene.
    ///
    /// Two things have to be right, and the previous implementation got both
    /// wrong, so the menu item silently did nothing:
    ///
    /// 1. The action must be *sent through the responder chain*
    ///    (`sendAction(_:to:nil)`). SwiftUI installs the handler on an internal
    ///    responder, not on `NSApplication`, so `NSApp.responds(to:)` is false
    ///    and `NSApp.perform(_:)` never reaches it.
    /// 2. The app is an `.accessory`, which cannot show an ordinary window that
    ///    the user can interact with. It has to become `.regular` first —
    ///    `AppDelegate` drops it back to `.accessory` when the window closes.
    @objc private func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // The selector was renamed in macOS 14; try the modern one, then fall
        // back. `sendAction` returns false when nothing handled it.
        let selectors = [Selector(("showSettingsWindow:")), Selector(("showPreferencesWindow:"))]
        for selector in selectors where NSApp.sendAction(selector, to: nil, from: nil) {
            return
        }

        // Neither responded: surface the setup window rather than appearing to
        // do nothing, and undo the policy change.
        Log.ui.error("Could not open the Settings scene")
        NSApp.setActivationPolicy(.accessory)
        onOpenOnboarding()
    }

    @objc private func openOnboarding() {
        onOpenOnboarding()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Shared no-op delegate placeholder; the menu is rebuilt on state changes, so
/// nothing dynamic is needed per-open beyond what AppKit already does.
private final class MenuRefresher: NSObject, NSMenuDelegate {
    @MainActor static let shared = MenuRefresher()
}
