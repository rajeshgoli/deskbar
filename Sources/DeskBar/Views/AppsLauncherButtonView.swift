import AppKit

final class AppsLauncherButtonView: NSView {
    private let iconView = NSImageView()
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false {
        didSet {
            updateBackgroundColor()
        }
    }

    init() {
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        toolTip = "Apps"

        configureSubviews()
        updateBackgroundColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private lazy var iconMetricsBinding = IconMetricsBinding(view: self)

    override var intrinsicContentSize: NSSize {
        NSSize(width: IconMetrics.launcherButtonWidth, height: IconMetrics.rowHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingAreaRef = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingAreaRef)
        self.trackingAreaRef = trackingAreaRef
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !event.modifierFlags.contains(.control) else {
            showContextMenu(with: event)
            return
        }

        IconClickFeedback.show(on: iconView)
        openAppsLauncher()
    }

    override func rightMouseDown(with event: NSEvent) {
        showContextMenu(with: event)
    }

    private func configureSubviews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.wantsLayer = true
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = launcherIcon()

        addSubview(iconView)

        NSLayoutConstraint.activate([
            iconMetricsBinding.bind(widthAnchor.constraint(equalToConstant: 36)) { IconMetrics.launcherButtonWidth },
            iconMetricsBinding.bind(heightAnchor.constraint(equalToConstant: 32)) { IconMetrics.rowHeight },

            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconMetricsBinding.bind(iconView.widthAnchor.constraint(equalToConstant: 28)) { IconMetrics.launcherIconSize },
            iconMetricsBinding.bind(iconView.heightAnchor.constraint(equalToConstant: 28)) { IconMetrics.launcherIconSize }
        ])
    }

    private func openAppsLauncher() {
        AppsLauncher.open()
    }

    private func launcherIcon() -> NSImage? {
        AppsLauncher.icon()
    }

    private func showContextMenu(with event: NSEvent) {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Apps", action: #selector(openAppsFromMenu(_:)), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc
    private func openAppsFromMenu(_ sender: Any?) {
        openAppsLauncher()
    }

    private func updateBackgroundColor() {
        layer?.backgroundColor = (
            isHovered
                ? NSColor.white.withAlphaComponent(0.1)
                : NSColor.clear
        ).cgColor
    }
}
