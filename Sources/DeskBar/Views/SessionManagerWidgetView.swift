import AppKit
import Combine

final class SessionManagerWidgetView: NSView {
    private static let separatorWidth: CGFloat = 1
    private static let separatorHeight: CGFloat = 24
    private static let iconWidth: CGFloat = 28
    private static let metricWidth: CGFloat = 44
    private static let widgetHeight: CGFloat = 32
    private static let stackSpacing: CGFloat = 8
    private static let leadingInset: CGFloat = 4

    private let settings: TaskbarSettings
    private let service: SMPluginService
    private let displayID: CGDirectDisplayID
    private let stackView = NSStackView()
    private let separatorView = NSView()
    private let iconButton = SMWidgetIconButton()
    private let activeControl = SMWidgetMetricControl(title: "ACT", color: .systemGreen)
    private let thinkingControl = SMWidgetMetricControl(title: "THK", color: .systemBlue)
    private let inactiveControl = SMWidgetMetricControl(title: "IDL", color: .secondaryLabelColor)
    private var widthConstraint: NSLayoutConstraint?
    private var cancellables = Set<AnyCancellable>()

    var preferredWidthDidChange: (() -> Void)?

    init(
        settings: TaskbarSettings,
        service: SMPluginService,
        displayID: CGDirectDisplayID
    ) {
        self.settings = settings
        self.service = service
        self.displayID = displayID
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        configureSubviews()
        configureActions()
        bindState()
        update(with: service.watchSummary)
        updateVisibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        isHidden ? .zero : NSSize(width: contentWidth(), height: Self.widgetHeight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        service.openOrActivateWatch()
    }

    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(makeMenu(), with: event, for: self)
    }

    func preferredContentWidth() -> CGFloat {
        isHidden ? 0 : contentWidth()
    }

    private func configureSubviews() {
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = Self.stackSpacing
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: Self.leadingInset, bottom: 0, right: 0)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        separatorView.wantsLayer = true
        separatorView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        separatorView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(separatorView)
        stackView.addArrangedSubview(iconButton)
        stackView.addArrangedSubview(activeControl)
        stackView.addArrangedSubview(thinkingControl)
        stackView.addArrangedSubview(inactiveControl)

        let widthConstraint = widthAnchor.constraint(equalToConstant: contentWidth())
        self.widthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            separatorView.widthAnchor.constraint(equalToConstant: Self.separatorWidth),
            separatorView.heightAnchor.constraint(equalToConstant: Self.separatorHeight),
            iconButton.widthAnchor.constraint(equalToConstant: Self.iconWidth),
            iconButton.heightAnchor.constraint(equalToConstant: Self.iconWidth),
            activeControl.widthAnchor.constraint(equalToConstant: Self.metricWidth),
            thinkingControl.widthAnchor.constraint(equalToConstant: Self.metricWidth),
            inactiveControl.widthAnchor.constraint(equalToConstant: Self.metricWidth),
            activeControl.heightAnchor.constraint(equalToConstant: Self.widgetHeight),
            thinkingControl.heightAnchor.constraint(equalToConstant: Self.widgetHeight),
            inactiveControl.heightAnchor.constraint(equalToConstant: Self.widgetHeight),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthConstraint,
            heightAnchor.constraint(equalToConstant: Self.widgetHeight)
        ])
    }

    private func configureActions() {
        iconButton.target = self
        iconButton.action = #selector(showMenuFromIcon(_:))

        [activeControl, thinkingControl, inactiveControl].forEach { control in
            control.target = self
            control.action = #selector(openWatch(_:))
        }
    }

    private func bindState() {
        service.$watchSummary
            .receive(on: RunLoop.main)
            .sink { [weak self] summary in
                self?.update(with: summary)
            }
            .store(in: &cancellables)

        settings.$enableSessionManagerPlugin
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateVisibility()
            }
            .store(in: &cancellables)

        settings.$showSessionManagerWidget
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateVisibility()
            }
            .store(in: &cancellables)

        settings.$sessionManagerWidgetPinnedDisplayID
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateVisibility()
            }
            .store(in: &cancellables)
    }

    private func update(with summary: SMWatchSummary) {
        let activeColor: NSColor = summary.workingCount > 0 ? .systemGreen :
            (summary.waitingCount > 0 ? .systemOrange : .secondaryLabelColor)

        activeControl.update(
            value: summary.activeCount,
            color: activeColor,
            detail: "Active SM agents: \(summary.workingCount) working, \(summary.waitingCount) waiting."
        )
        thinkingControl.update(
            value: summary.thinkingCount,
            color: summary.thinkingCount > 0 ? .systemBlue : .secondaryLabelColor,
            detail: "Thinking SM agents: \(summary.thinkingCount)."
        )
        inactiveControl.update(
            value: summary.inactiveCount,
            color: .secondaryLabelColor,
            detail: "Inactive SM agents: \(summary.idleCount) idle, \(summary.stoppedCount) stopped."
        )
        iconButton.activityColor = summary.aggregateState.color

        let tooltip = "SM agents: \(summary.workingCount) working, \(summary.thinkingCount) thinking, \(summary.waitingCount) waiting, \(summary.idleCount) idle."
        toolTip = tooltip
        iconButton.toolTip = "Session Manager actions"
        activeControl.toolTip = tooltip
        thinkingControl.toolTip = tooltip
        inactiveControl.toolTip = tooltip
    }

    private func updateVisibility() {
        let shouldShow = settings.enableSessionManagerPlugin &&
            settings.showSessionManagerWidget &&
            displayMatchesPin
        isHidden = !shouldShow
        widthConstraint?.constant = contentWidth()
        invalidateIntrinsicContentSize()
        preferredWidthDidChange?()
    }

    private var displayMatchesPin: Bool {
        guard let pinnedDisplayID = settings.sessionManagerWidgetPinnedDisplayID else {
            return true
        }

        return pinnedDisplayID == displayID
    }

    private func contentWidth() -> CGFloat {
        let widths = [
            Self.separatorWidth,
            Self.iconWidth,
            Self.metricWidth,
            Self.metricWidth,
            Self.metricWidth
        ]
        let spacing = CGFloat(max(widths.count - 1, 0)) * Self.stackSpacing
        return Self.leadingInset + widths.reduce(0, +) + spacing
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let openItem = NSMenuItem(title: "Open SM Watch", action: #selector(openWatch(_:)), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let newItem = NSMenuItem(title: "New SM Watch Window", action: #selector(openNewWatchWindow(_:)), keyEquivalent: "")
        newItem.target = self
        menu.addItem(newItem)

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshSMPlugin(_:)), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let pinItem = NSMenuItem(
            title: "Pin to \(displayName)",
            action: #selector(pinWidgetToThisDisplay(_:)),
            keyEquivalent: ""
        )
        pinItem.target = self
        pinItem.isEnabled = settings.sessionManagerWidgetPinnedDisplayID != displayID
        menu.addItem(pinItem)

        let allDisplaysItem = NSMenuItem(
            title: "Show on All Displays",
            action: #selector(showWidgetOnAllDisplays(_:)),
            keyEquivalent: ""
        )
        allDisplaysItem.target = self
        allDisplaysItem.isEnabled = settings.sessionManagerWidgetPinnedDisplayID != nil
        menu.addItem(allDisplaysItem)

        menu.addItem(.separator())

        let hideItem = NSMenuItem(title: "Hide SM Widget", action: #selector(hideWidget(_:)), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)

        return menu
    }

    private var displayName: String {
        ScreenGeometry.screen(for: displayID)?.localizedName ?? "This Display"
    }

    @objc
    private func showMenuFromIcon(_ sender: NSButton) {
        let menu = makeMenu()
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: sender.bounds.maxY + 2),
            in: sender
        )
    }

    @objc
    private func openWatch(_ sender: Any?) {
        service.openOrActivateWatch()
    }

    @objc
    private func openNewWatchWindow(_ sender: Any?) {
        service.openNewWatchWindow()
    }

    @objc
    private func refreshSMPlugin(_ sender: Any?) {
        service.refresh(forceTerminalMapping: true)
    }

    @objc
    private func pinWidgetToThisDisplay(_ sender: Any?) {
        settings.sessionManagerWidgetPinnedDisplayID = displayID
    }

    @objc
    private func showWidgetOnAllDisplays(_ sender: Any?) {
        settings.sessionManagerWidgetPinnedDisplayID = nil
    }

    @objc
    private func hideWidget(_ sender: Any?) {
        settings.showSessionManagerWidget = false
    }
}

private final class SMWidgetIconButton: NSButton {
    var activityColor: NSColor = .secondaryLabelColor {
        didSet {
            updateLayerStyle()
        }
    }

    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false {
        didSet {
            updateLayerStyle()
        }
    }

    init() {
        super.init(frame: .zero)

        title = "sm"
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        font = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 5
        updateLayerStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingAreaRef = NSTrackingArea(
            rect: bounds,
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

    private func updateLayerStyle() {
        let alpha = isHovered ? 0.28 : 0.16
        layer?.backgroundColor = activityColor.withAlphaComponent(alpha).cgColor
        layer?.borderColor = activityColor.withAlphaComponent(isHovered ? 0.75 : 0.45).cgColor
        layer?.borderWidth = 1
        contentTintColor = activityColor
    }
}

private final class SMWidgetMetricControl: NSControl {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private var color: NSColor

    init(title: String, color: NSColor) {
        self.color = color
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        titleLabel.stringValue = title
        configureSubviews()
        update(value: 0, color: color, detail: "")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    override func rightMouseDown(with event: NSEvent) {
        nextResponder?.rightMouseDown(with: event)
    }

    func update(value: Int, color: NSColor, detail: String) {
        valueLabel.stringValue = "\(value)"
        self.color = color
        toolTip = detail
        updateColors()
    }

    private func configureSubviews() {
        titleLabel.font = NSFont.monospacedSystemFont(ofSize: 8, weight: .bold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        valueLabel.alignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 1),

            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: -1),
            valueLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -1)
        ])
    }

    private func updateColors() {
        valueLabel.textColor = color
        layer?.shadowColor = color.cgColor
        layer?.shadowOpacity = color == NSColor.secondaryLabelColor ? 0 : 0.18
        layer?.shadowRadius = 3
        layer?.shadowOffset = .zero
    }
}
