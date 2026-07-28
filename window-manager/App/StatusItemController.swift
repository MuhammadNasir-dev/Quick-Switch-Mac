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
    private let onOpenAbout: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private weak var windowCountItem: NSMenuItem?
    private weak var headerViewRef: MenuHeaderView?

    init(
        services: AppServices,
        onOpenSettings: @escaping () -> Void,
        onOpenOnboarding: @escaping () -> Void,
        onOpenAbout: @escaping () -> Void
    ) {
        self.services = services
        self.onOpenSettings = onOpenSettings
        self.onOpenOnboarding = onOpenOnboarding
        self.onOpenAbout = onOpenAbout
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
            services.preferences.$layout.map { _ in }.eraseToAnyPublisher(),
            services.updates.$state.map { _ in }.eraseToAnyPublisher()
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
    private enum Health: Equatable {
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

        /// Status line under the product name in the menu header.
        var menuSubtitle: String {
            switch self {
            case .ready: "Ready"
            case .needsAccessibility: "Accessibility access required"
            case .inputFailed(.trustRevoked): "Accessibility access was revoked"
            case .inputFailed(.repeatedTimeouts): "Shortcut disabled by the system"
            case .secureInput: "Secure input active — shortcut paused"
            }
        }

        /// The row offering a way out of this state, if there is one.
        typealias Remedy = (title: String, symbol: String, selector: Selector?)

        var remedy: Remedy? {
            // A statement rather than a switch expression: the latter infers a
            // single result type from the first case, which cannot reconcile
            // `nil` with the tuple.
            switch self {
            case .ready:
                return nil
            case .needsAccessibility:
                return ("Grant Accessibility Access…", "lock.shield", #selector(StatusItemController.openOnboarding))
            case .inputFailed:
                return ("Re-enable Shortcut", "arrow.clockwise", #selector(StatusItemController.retryInput))
            case .secureInput:
                // Nothing this app can do; another process holds secure input.
                return ("Waiting for the other app to release it", "keyboard.badge.ellipsis", nil)
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
        button.image = Self.statusBarImage(health.symbolName)
        button.toolTip = health.tooltip
        button.setAccessibilityLabel("QuickSwitch")
    }

    /// Builds the menu-bar image so that it lands on whole pixels.
    ///
    /// The status bar centres the button image vertically, so the inset is
    /// `(barThickness - imageHeight) / 2`. SF Symbols default to a **15pt-tall**
    /// image and the bar is 22pt, which makes that inset 3.5pt — half a point.
    ///
    /// On a Retina display half a point is exactly one device pixel and looks
    /// perfect. On a 1x display (a 1080p external monitor) it is *half a pixel*,
    /// so the compositor resamples the entire glyph and it renders soft.
    /// Forcing an **even** height keeps the inset integral at both scale
    /// factors; the width is rounded to even as well, preserving the symbol's
    /// aspect ratio, so horizontal centring is exact too.
    private static func statusBarImage(_ name: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: "QuickSwitch") else {
            return nil
        }

        let barThickness = NSStatusBar.system.thickness
        // Leave a little breathing room in the bar, then snap down to even.
        let targetHeight = roundedToEven(min(18, barThickness - 4))
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        let targetWidth = roundedToEven(targetHeight * aspect)

        image.size = NSSize(width: targetWidth, height: targetHeight)
        // Template rendering lets macOS invert it for dark menu bars and for
        // the highlighted state.
        image.isTemplate = true
        return image
    }

    /// Rounds to the nearest even number of points, never below 2.
    static func roundedToEven(_ value: CGFloat) -> CGFloat {
        max(2, (value / 2).rounded() * 2)
    }

    private var windowCountTitle: String {
        let count = services.windowIndex.windows.count
        return count == 1 ? "1 window tracked" : "\(count) windows tracked"
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let health = self.health

        // 1. Branded header: app icon, product name, live status, gear button.
        let header = NSMenuItem()
        let headerView = MenuHeaderView(onOpenSettings: { [weak self] in self?.onOpenSettings() })
        headerView.update(subtitle: health.menuSubtitle, isWarning: health != .ready)
        header.view = headerView
        menu.addItem(header)
        headerViewRef = headerView

        menu.addItem(.separator())

        // 2. Whatever is stopping the app working, with the action that fixes it.
        if let remedy = health.remedy {
            let warning = NSMenuItem(title: remedy.title, action: remedy.selector, keyEquivalent: "")
            warning.image = Self.symbol(remedy.symbol, tint: .systemOrange)
            warning.target = remedy.selector == nil ? nil : self
            warning.isEnabled = remedy.selector != nil
            menu.addItem(warning)
            menu.addItem(.separator())
        }

        // 3. The primary action.
        let show = NSMenuItem(title: "Open Switcher", action: #selector(showSwitcher), keyEquivalent: "")
        show.image = Self.symbol("rectangle.stack")
        show.target = self
        show.isEnabled = services.authorizer.isTrusted
        show.attributedTitle = Self.titleWithShortcut(
            "Open Switcher",
            shortcut: "\(services.preferences.modifier.symbol)⇥"
        )
        menu.addItem(show)

        let count = NSMenuItem(title: windowCountTitle, action: nil, keyEquivalent: "")
        count.image = Self.symbol("macwindow")
        count.isEnabled = false
        menu.addItem(count)
        windowCountItem = count

        // 4. Layouts, inline with icons and a tick on the active one, so the
        //    current choice is visible without opening a submenu.
        menu.addItem(.separator())
        menu.addItem(MenuSectionHeader.item("Layout"))
        for layout in SwitcherLayout.allCases {
            let item = NSMenuItem(
                title: layout.displayName,
                action: #selector(selectLayout(_:)),
                keyEquivalent: ""
            )
            item.image = Self.symbol(layout.symbolName)
            item.target = self
            item.representedObject = layout.rawValue
            item.state = services.preferences.layout == layout ? .on : .off
            menu.addItem(item)
        }

        // 5. Everything else.
        menu.addItem(.separator())

        let launch = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launch.image = Self.symbol("power")
        launch.target = self
        launch.state = services.launchAtLogin.isEnabled ? .on : .off
        if case .unavailable = services.launchAtLogin.state {
            launch.isEnabled = false
        }
        if let explanation = services.launchAtLogin.explanation {
            launch.toolTip = explanation
        }
        menu.addItem(launch)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.image = Self.symbol("gearshape")
        settings.target = self
        menu.addItem(settings)

        let help = NSMenuItem(title: "Setup Guide…", action: #selector(openOnboarding), keyEquivalent: "")
        help.image = Self.symbol("questionmark.circle")
        help.target = self
        menu.addItem(help)

        if case .updateAvailable(let release) = services.updates.state {
            let update = NSMenuItem(
                title: "Update to \(release.version.original)…",
                action: #selector(downloadUpdate),
                keyEquivalent: ""
            )
            update.image = Self.symbol("arrow.down.circle", tint: .controlAccentColor)
            update.target = self
            menu.addItem(update)
        }

        let about = NSMenuItem(title: "About \(AppInfo.name)", action: #selector(openAbout), keyEquivalent: "")
        about.image = Self.symbol("info.circle")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit QuickSwitch", action: #selector(quit), keyEquivalent: "q")
        quit.image = Self.symbol("xmark.circle")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    /// A consistently sized, template-rendered SF Symbol for a menu row.
    ///
    /// Menu images are not resized by AppKit, so an unconstrained symbol makes
    /// rows different heights. Template rendering lets the system tint them for
    /// the highlighted row and for both appearances.
    private static func symbol(_ name: String, tint: NSColor? = nil) -> NSImage? {
        var configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        if let tint {
            // A palette configuration keeps the colour inside the symbol
            // renderer, so it still adapts to appearance changes — unlike
            // drawing a tinted copy into a bitmap.
            configuration = configuration.applying(.init(paletteColors: [tint]))
        }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        // Template rendering lets AppKit invert the symbol on the highlighted
        // row; a palette-coloured warning keeps its own colour deliberately.
        image.isTemplate = tint == nil
        return image
    }

    /// Renders "Title    ⌥⇥" with the shortcut dimmed and trailing.
    ///
    /// `keyEquivalent` cannot express a modifier-plus-Tab binding that the app
    /// handles through an event tap rather than through the responder chain, so
    /// the hint is drawn rather than declared.
    private static func titleWithShortcut(_ title: String, shortcut: String) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: title,
            attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.labelColor]
        )
        result.append(NSAttributedString(
            string: "   \(shortcut)",
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
        ))
        return result
    }

    /// Reinstalls the event tap after it was abandoned. User-initiated by
    /// design — see `AppServices.restartInput()`.
    @objc func retryInput() {
        services.restartInput()
        rebuildMenu()
    }

    @objc private func showSwitcher() {
        services.switcher.showPinned()
    }

    @objc private func toggleLaunchAtLogin() {
        services.launchAtLogin.toggle()
        // `requiresApproval` cannot be resolved from here — send the user to
        // the one place that can.
        if services.launchAtLogin.state == .requiresApproval {
            services.launchAtLogin.openLoginItemsSettings()
        }
        rebuildMenu()
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

    @objc private func downloadUpdate() {
        services.updates.openDownloadPage()
    }

    @objc private func openAbout() {
        onOpenAbout()
    }

    @objc func openOnboarding() {
        onOpenOnboarding()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
