import AppKit
import ApplicationServices
import Combine

final class RunningAppTrayView: NSStackView {
    private static let iconWidth: CGFloat = 24
    private static let iconSpacing: CGFloat = 4
    private static let overflowButtonWidth: CGFloat = 24
    private static let dividerWidth: CGFloat = 1

    private let windowManager: WindowManager
    private let pinnedAppManager: PinnedAppManager
    private let settings: TaskbarSettings
    private let displayID: CGDirectDisplayID
    private let dividerView = NSView()
    private let iconsStackView = NSStackView()
    private let overflowButton = NSButton()
    private let collapsedSystemResourceWidgetView: CollapsedSystemResourceWidgetView
    private let accessibilityService = AccessibilityService()
    private var cancellables = Set<AnyCancellable>()
    private var lastContentSignature: ContentSignature?
    private var applicationIconViews: [TrayIconView] = []
    private var currentApplications: [TrayApplicationInfo] = []
    private var overflowedApplications: [TrayApplicationInfo] = []
    private var visibleApplicationCapacity: Int?

    var preferredWidthDidChange: (() -> Void)?

    init(
        windowManager: WindowManager,
        pinnedAppManager: PinnedAppManager,
        settings: TaskbarSettings,
        systemResourceMonitor: SystemResourceMonitor,
        displayID: CGDirectDisplayID
    ) {
        self.windowManager = windowManager
        self.pinnedAppManager = pinnedAppManager
        self.settings = settings
        self.displayID = displayID
        self.collapsedSystemResourceWidgetView = CollapsedSystemResourceWidgetView(
            settings: settings,
            monitor: systemResourceMonitor,
            displayID: displayID
        )
        super.init(frame: .zero)

        orientation = .horizontal
        alignment = .centerY
        distribution = .fill
        spacing = 8
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        translatesAutoresizingMaskIntoConstraints = false

        configureDividerView()
        configureIconsStackView()
        configureOverflowButton()
        bindState()
        rebuildIcons()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureDividerView() {
        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        dividerView.translatesAutoresizingMaskIntoConstraints = false

        addArrangedSubview(dividerView)
        NSLayoutConstraint.activate([
            dividerView.widthAnchor.constraint(equalToConstant: 1),
            dividerView.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func configureIconsStackView() {
        iconsStackView.orientation = .horizontal
        iconsStackView.alignment = .centerY
        iconsStackView.distribution = .fill
        iconsStackView.spacing = 4
        iconsStackView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        addArrangedSubview(iconsStackView)
        heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
    }

    private func bindState() {
        windowManager.$windows
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildIcons()
            }
            .store(in: &cancellables)

        windowManager.$trayApps
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildIcons()
            }
            .store(in: &cancellables)

        pinnedAppManager.$pinnedApps
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildIcons()
            }
            .store(in: &cancellables)

        settings.$showSystemResourceWidget
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildIcons()
            }
            .store(in: &cancellables)

        settings.$systemResourceWidgetPinnedDisplayID
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildIcons()
            }
            .store(in: &cancellables)

        settings.$systemResourceWidgetCollapsed
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildIcons()
            }
            .store(in: &cancellables)

        settings.$showSystemResourceMemoryMetric
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildIcons()
            }
            .store(in: &cancellables)

        settings.$showSystemResourceCPUMetric
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildIcons()
            }
            .store(in: &cancellables)

        settings.$showSystemResourceGPUMetric
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildIcons()
            }
            .store(in: &cancellables)
    }

    func refresh() {
        lastContentSignature = nil
        rebuildIcons()
    }

    func preferredContentWidth() -> CGFloat {
        plannedContentWidth(visibleApplicationCapacity: visibleApplicationCapacity)
    }

    func plannedContentWidth(visibleApplicationCapacity: Int?) -> CGFloat {
        let itemCount = plannedIconItemCount(visibleApplicationCapacity: visibleApplicationCapacity)
        guard itemCount > 0 else {
            return 0
        }

        let iconWidth = CGFloat(itemCount) * Self.iconWidth + CGFloat(itemCount - 1) * Self.iconSpacing
        return ceil(Self.dividerWidth + spacing + iconWidth)
    }

    func minimumOverflowContentWidth() -> CGFloat {
        guard !currentApplications.isEmpty else {
            return plannedContentWidth(visibleApplicationCapacity: nil)
        }

        return plannedContentWidth(visibleApplicationCapacity: 0)
    }

    func visibleApplicationCapacity(fitting availableWidth: CGFloat) -> Int? {
        guard !currentApplications.isEmpty else {
            return nil
        }

        if plannedContentWidth(visibleApplicationCapacity: nil) <= availableWidth + 0.5 {
            return nil
        }

        for capacity in stride(from: currentApplications.count - 1, through: 0, by: -1) {
            if plannedContentWidth(visibleApplicationCapacity: capacity) <= availableWidth + 0.5 {
                return capacity
            }
        }

        return 0
    }

    @discardableResult
    func setVisibleApplicationCapacity(_ capacity: Int?, notifiesPreferredWidthChange: Bool = true) -> Bool {
        let normalizedCapacity = normalizedVisibleApplicationCapacity(capacity)
        guard visibleApplicationCapacity != normalizedCapacity else {
            return false
        }

        visibleApplicationCapacity = normalizedCapacity
        updateOverflowVisibility()
        invalidateIntrinsicContentSize()
        needsLayout = true
        if notifiesPreferredWidthChange {
            preferredWidthDidChange?()
        }
        return true
    }

    private func rebuildIcons() {
        let applications = localTrayApps
        let showsCollapsedWidget = shouldShowCollapsedSystemResourceWidget
        let signature = ContentSignature(
            applications: applications.map {
                ContentSignature.Application(
                    pid: $0.pid,
                    bundleIdentifier: $0.bundleIdentifier,
                    localizedName: $0.name,
                    hasRunningApplication: $0.runningApplication != nil,
                    iconSignature: ImageMetadataSignature($0.icon)
                )
            },
            showsCollapsedSystemResourceWidget: showsCollapsedWidget
        )
        guard signature != lastContentSignature else {
            return
        }

        lastContentSignature = signature
        currentApplications = applications
        applicationIconViews.removeAll()

        iconsStackView.arrangedSubviews.forEach { view in
            iconsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for application in applications {
            let iconView = TrayIconView(
                application: application,
                pinnedAppManager: pinnedAppManager
            )
            applicationIconViews.append(iconView)
            iconsStackView.addArrangedSubview(iconView)
        }

        iconsStackView.addArrangedSubview(overflowButton)

        if showsCollapsedWidget {
            iconsStackView.insertArrangedSubview(collapsedSystemResourceWidgetView, at: 0)
        }

        visibleApplicationCapacity = normalizedVisibleApplicationCapacity(visibleApplicationCapacity)
        updateOverflowVisibility()
        preferredWidthDidChange?()
    }

    private func configureOverflowButton() {
        overflowButton.translatesAutoresizingMaskIntoConstraints = false
        overflowButton.isBordered = false
        overflowButton.bezelStyle = .regularSquare
        overflowButton.setButtonType(.momentaryChange)
        overflowButton.title = ">>"
        overflowButton.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        overflowButton.contentTintColor = .secondaryLabelColor
        overflowButton.toolTip = "More tray apps"
        overflowButton.target = self
        overflowButton.action = #selector(showOverflowMenu(_:))
        overflowButton.isHidden = true

        NSLayoutConstraint.activate([
            overflowButton.widthAnchor.constraint(equalToConstant: Self.overflowButtonWidth),
            overflowButton.heightAnchor.constraint(equalToConstant: Self.iconWidth)
        ])
    }

    private func plannedIconItemCount(visibleApplicationCapacity: Int?) -> Int {
        let appCount = currentApplications.count
        let visibleAppCount = normalizedVisibleApplicationCapacity(visibleApplicationCapacity) ?? appCount
        let hiddenAppCount = max(0, appCount - visibleAppCount)

        var itemCount = 0
        if shouldShowCollapsedSystemResourceWidget {
            itemCount += 1
        }
        itemCount += visibleAppCount
        if hiddenAppCount > 0 {
            itemCount += 1
        }
        return itemCount
    }

    private func normalizedVisibleApplicationCapacity(_ capacity: Int?) -> Int? {
        guard let capacity else {
            return nil
        }

        let appCount = currentApplications.count
        guard appCount > 0 else {
            return nil
        }

        let clampedCapacity = min(max(capacity, 0), appCount)
        return clampedCapacity >= appCount ? nil : clampedCapacity
    }

    private func updateOverflowVisibility() {
        let visibleAppCount = visibleApplicationCapacity ?? applicationIconViews.count
        for (index, iconView) in applicationIconViews.enumerated() {
            iconView.isHidden = index >= visibleAppCount
        }

        overflowedApplications = Array(currentApplications.dropFirst(visibleAppCount))
        overflowButton.isHidden = overflowedApplications.isEmpty
        dividerView.isHidden = plannedIconItemCount(visibleApplicationCapacity: visibleApplicationCapacity) == 0
    }

    @objc
    private func showOverflowMenu(_ sender: NSButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for application in overflowedApplications {
            let item = NSMenuItem(
                title: application.name,
                action: #selector(activateOverflowApplication(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = application
            item.image = application.icon?.scaled(to: NSSize(width: 16, height: 16))
            menu.addItem(item)
        }

        if overflowedApplications.isEmpty {
            let item = NSMenuItem(title: "No hidden tray apps", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: sender.bounds.height + 2),
            in: sender
        )
    }

    @objc
    private func activateOverflowApplication(_ sender: NSMenuItem) {
        guard let application = sender.representedObject as? TrayApplicationInfo else {
            return
        }

        switch TrayActivationPlanner.action(
            bundleIdentifier: application.bundleIdentifier,
            hasAnyWindows: hasAnyApplicationWindows(for: application)
        ) {
        case .activateApplication:
            activateOrReopenApplication(application, shouldReopen: false)
        case .reopenApplication:
            activateOrReopenApplication(application, shouldReopen: true)
        case .openFinderWindow:
            LauncherApplicationActivator.openFinderWindow()
        }
    }

    private func activateOrReopenApplication(_ application: TrayApplicationInfo, shouldReopen: Bool) {
        guard let bundleIdentifier = application.bundleIdentifier else {
            application.runningApplication?.unhide()
            application.runningApplication?.activate(options: .activateAllWindows)
            return
        }

        if let runningApplication = application.runningApplication {
            LauncherApplicationActivator.activate(
                runningApplication,
                bundleIdentifier: bundleIdentifier,
                applicationURL: application.bundleURL,
                shouldReopen: shouldReopen
            )
        } else if shouldReopen {
            LauncherApplicationActivator.reopen(
                bundleIdentifier: bundleIdentifier,
                applicationURL: application.bundleURL
            )
        } else {
            LauncherApplicationActivator.launch(
                bundleIdentifier: bundleIdentifier,
                applicationURL: application.bundleURL
            )
        }
    }

    private func hasAnyApplicationWindows(for application: TrayApplicationInfo) -> Bool? {
        guard let runningApplication = application.runningApplication else {
            return nil
        }

        if AXIsProcessTrusted() {
            let windows = accessibilityService.enumerateWindows(for: runningApplication)
            if !windows.isEmpty {
                return true
            }
        }

        return LauncherApplicationActivator.hasCGWindows(for: runningApplication)
    }

    private var localTrayApps: [TrayApplicationInfo] {
        guard let screen = ScreenGeometry.screen(for: displayID) else {
            return []
        }

        return windowManager.trayApplications(on: screen)
    }

    private var shouldShowCollapsedSystemResourceWidget: Bool {
        guard
            settings.showSystemResourceWidget,
            settings.systemResourceWidgetCollapsed,
            [
                settings.showSystemResourceMemoryMetric,
                settings.showSystemResourceCPUMetric,
                settings.showSystemResourceGPUMetric
            ].contains(true)
        else {
            return false
        }

        guard let pinnedDisplayID = settings.systemResourceWidgetPinnedDisplayID else {
            return true
        }

        return pinnedDisplayID == displayID
    }

}

private struct ContentSignature: Equatable {
    struct Application: Equatable {
        let pid: pid_t
        let bundleIdentifier: String?
        let localizedName: String?
        let hasRunningApplication: Bool
        let iconSignature: ImageMetadataSignature
    }

    let applications: [Application]
    let showsCollapsedSystemResourceWidget: Bool
}
