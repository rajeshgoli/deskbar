import AppKit
import Combine

final class AppsLauncherButtonView: NSView {
    private let settings: TaskbarSettings
    private let openSettingsHandler: (() -> Void)?
    private let iconView = NSImageView()
    private var trackingAreaRef: NSTrackingArea?
    private var cancellables = Set<AnyCancellable>()
    private var isHovered = false {
        didSet {
            updateBackgroundColor()
        }
    }

    init(settings: TaskbarSettings, openSettingsHandler: (() -> Void)? = nil) {
        self.settings = settings
        self.openSettingsHandler = openSettingsHandler
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8

        configureSubviews()
        bindSettings()
        refreshTarget()
        updateBackgroundColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 36, height: 32)
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

        addSubview(iconView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 36),
            heightAnchor.constraint(equalToConstant: 32),

            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func bindSettings() {
        let refresh: () -> Void = { [weak self] in self?.refreshTarget() }
        settings.$launcherButtonAction
            .receive(on: RunLoop.main)
            .sink { _ in refresh() }
            .store(in: &cancellables)
        settings.$launcherCustomAppBundleID
            .receive(on: RunLoop.main)
            .sink { _ in refresh() }
            .store(in: &cancellables)
        settings.$launcherCustomAppPath
            .receive(on: RunLoop.main)
            .sink { _ in refresh() }
            .store(in: &cancellables)
        settings.$launcherCustomCommand
            .receive(on: RunLoop.main)
            .sink { _ in refresh() }
            .store(in: &cancellables)
    }

    private func refreshTarget() {
        let target = AppsLauncher.resolve(settings: settings)
        iconView.image = target.icon
        toolTip = target.tooltip
    }

    private func openAppsLauncher() {
        AppsLauncher.open(settings: settings)
    }

    private func showContextMenu(with event: NSEvent) {
        let target = AppsLauncher.resolve(settings: settings)
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open \(target.name)", action: #selector(openAppsFromMenu(_:)), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        if openSettingsHandler != nil {
            let configureItem = NSMenuItem(
                title: "Configure Launcher Button…",
                action: #selector(openLauncherSettings(_:)),
                keyEquivalent: ""
            )
            configureItem.target = self
            menu.addItem(configureItem)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc
    private func openAppsFromMenu(_ sender: Any?) {
        openAppsLauncher()
    }

    @objc
    private func openLauncherSettings(_ sender: Any?) {
        openSettingsHandler?()
    }

    private func updateBackgroundColor() {
        layer?.backgroundColor = (
            isHovered
                ? NSColor.white.withAlphaComponent(0.1)
                : NSColor.clear
        ).cgColor
    }
}
