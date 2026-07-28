import AppKit

/// The branded header at the top of the status-item menu.
///
/// A plain `NSMenuItem` can only show a title and an image, which reads as a
/// list of commands rather than as an application. Hosting a custom view gives
/// the menu an identity — the real app icon, the product name, a live status
/// line — plus a gear button on the trailing edge for Settings.
///
/// Laid out with explicit frames rather than Auto Layout: menu item views are
/// measured once per open at a fixed height, so constraints would buy nothing
/// and cost a layout pass every time the menu appears.
final class MenuHeaderView: NSView {
    nonisolated static let preferredWidth: CGFloat = 268
    nonisolated static let preferredHeight: CGFloat = 58

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "QuickSwitch")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let onOpenSettings: () -> Void
    private var hoverArea: NSTrackingArea?
    private var isHoveringGear = false {
        didSet {
            guard oldValue != isHoveringGear else { return }
            needsDisplay = true
        }
    }

    fileprivate nonisolated enum Metrics {
        static let horizontalInset: CGFloat = 14
        static let iconSize: CGFloat = 32
        static let textLeading: CGFloat = 54
        static let buttonSize = NSSize(width: 26, height: 26)
    }

    init(onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        super.init(frame: NSRect(x: 0, y: 0, width: Self.preferredWidth, height: Self.preferredHeight))
        // The menu is as wide as its widest item, which may be a long warning
        // row. Without this the header keeps its intrinsic width and the gear
        // floats in the middle instead of sitting on the trailing edge.
        autoresizingMask = [.width]
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MenuHeaderView is created in code only")
    }

    private func setUp() {
        // `applicationIconImage` is the icon actually installed in the bundle,
        // so the menu reflects whatever ships rather than a hard-coded asset.
        // 32pt matches a native icon representation exactly, so a 1x display
        // draws the 32px rep and a 2x display the 64px one — no resampling.
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        addSubview(subtitleLabel)

    }

    /// The gear is **drawn**, not an `NSButton`.
    ///
    /// A button inside a menu item view is unreliable: menu windows are
    /// layer-backed and vibrant, and a borderless `NSButton` renders its bezel
    /// differently there than anywhere else — `.accessoryBarAction` in
    /// particular paints an accent-coloured fill over the template glyph, so
    /// the gear reads as a solid blue block that only resolves into an icon
    /// while pressed. Drawing the symbol directly sidesteps every one of those
    /// behaviours and makes the contrast explicit at both appearances.
    private func gearImage(tint: NSColor) -> NSImage? {
        // Built inside `draw(_:)` so a dynamic `NSColor` resolves against the
        // menu's current appearance rather than whatever was active at init.
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        return NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")?
            .withSymbolConfiguration(configuration)
    }

    /// Hit target for the gear, deliberately larger than the glyph.
    ///
    /// Exposed as a pure function of the view's size so the trailing-edge
    /// anchoring can be asserted directly, rather than inferred from rendered
    /// pixels — which would make the test hostage to font metrics.
    nonisolated static func gearRect(in size: NSSize) -> NSRect {
        NSRect(
            x: size.width - Metrics.horizontalInset - Metrics.buttonSize.width,
            y: (size.height - Metrics.buttonSize.height) / 2,
            width: Metrics.buttonSize.width,
            height: Metrics.buttonSize.height
        )
    }

    private var gearRect: NSRect { Self.gearRect(in: bounds.size) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isHoveringGear {
            // A faint plate is the only resting affordance that the gear is
            // clickable, and it guarantees contrast whatever is behind it.
            let plate = NSBezierPath(roundedRect: gearRect.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            NSColor.labelColor.withAlphaComponent(0.1).setFill()
            plate.fill()
        }

        let tint: NSColor = isHoveringGear ? .labelColor : .secondaryLabelColor
        guard let image = gearImage(tint: tint) else { return }
        let target = NSRect(
            x: gearRect.midX - image.size.width / 2,
            y: gearRect.midY - image.size.height / 2,
            width: image.size.width,
            height: image.size.height
        )
        image.draw(in: target.integral)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        let height = bounds.height
        iconView.frame = NSRect(
            x: Metrics.horizontalInset,
            y: (height - Metrics.iconSize) / 2,
            width: Metrics.iconSize,
            height: Metrics.iconSize
        )

        // Text stops short of the gear so a long status line truncates rather
        // than running underneath it.
        let textWidth = max(0, gearRect.minX - Metrics.textLeading - 8)
        titleLabel.frame = NSRect(x: Metrics.textLeading, y: height - 32, width: textWidth, height: 17)
        subtitleLabel.frame = NSRect(x: Metrics.textLeading, y: height - 48, width: textWidth, height: 15)
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        isHoveringGear = gearRect.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        isHoveringGear = false
    }

    override func mouseUp(with event: NSEvent) {
        guard gearRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        openSettings()
    }

    // MARK: - Accessibility

    // The view stands in for the gear, so VoiceOver announces a button rather
    // than an inert graphic. Keyboard users reach Settings through the ⌘,
    // menu item, which remains the primary route.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Settings" }
    override func accessibilityPerformPress() -> Bool {
        openSettings()
        return true
    }

    // MARK: - Content

    /// Updates the status line beneath the product name.
    func update(subtitle: String, isWarning: Bool) {
        subtitleLabel.stringValue = subtitle
        subtitleLabel.textColor = isWarning ? .systemOrange : .secondaryLabelColor
    }

    private func openSettings() {
        // Dismiss the menu first; leaving it tracking while a window comes
        // forward leaves the menu stuck open over the new window.
        enclosingMenuItem?.menu?.cancelTracking()
        onOpenSettings()
    }
}

/// A small-caps section label, used to group the menu without adding noise.
enum MenuSectionHeader {
    static func item(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .kern: 0.4
            ]
        )
        return item
    }
}
