import AppKit
import Combine

/// Shows the system resource widget as a menu bar status item when
/// `systemResourceWidgetLocation == .menuBar`, so it costs no taskbar space.
@MainActor
final class SystemResourceStatusItemController: NSObject, NSMenuDelegate {
    private let settings: TaskbarSettings
    private let monitor: SystemResourceMonitor
    private var statusItem: NSStatusItem?
    private var statusView: SystemResourceStatusView?
    private var cancellables = Set<AnyCancellable>()

    init(settings: TaskbarSettings, monitor: SystemResourceMonitor) {
        self.settings = settings
        self.monitor = monitor
        super.init()
        bindState()
        updateStatusItem()
    }

    private func bindState() {
        let settingsChanges: [AnyPublisher<Void, Never>] = [
            settings.$showSystemResourceWidget.map { _ in () }.eraseToAnyPublisher(),
            settings.$systemResourceWidgetLocation.map { _ in () }.eraseToAnyPublisher(),
            settings.$showSystemResourceMemoryMetric.map { _ in () }.eraseToAnyPublisher(),
            settings.$showSystemResourceCPUMetric.map { _ in () }.eraseToAnyPublisher(),
            settings.$showSystemResourceGPUMetric.map { _ in () }.eraseToAnyPublisher(),
            settings.$showSystemResourceNetworkMetric.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(settingsChanges)
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        monitor.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.render(snapshot)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard settings.showsSystemResourceWidgetInMenuBar else {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
            statusView = nil
            return
        }

        if statusItem == nil {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.autosaveName = "DeskBarSystemResources"
            let menu = NSMenu()
            menu.delegate = self
            statusItem.menu = menu

            let statusView = SystemResourceStatusView()
            if let button = statusItem.button {
                statusView.frame = button.bounds
                statusView.autoresizingMask = [.width, .height]
                button.addSubview(statusView)
            }
            self.statusItem = statusItem
            self.statusView = statusView
        }

        statusView?.metrics = enabledMetrics
        render(monitor.snapshot)
    }

    private var enabledMetrics: [SystemResourceMetric] {
        var metrics: [SystemResourceMetric] = []
        if settings.showSystemResourceMemoryMetric {
            metrics.append(.memory)
        }
        if settings.showSystemResourceCPUMetric {
            metrics.append(.cpu)
        }
        if settings.showSystemResourceGPUMetric {
            metrics.append(.gpu)
        }
        if settings.showSystemResourceNetworkMetric {
            metrics.append(.network)
        }
        return metrics
    }

    private func render(_ snapshot: SystemResourceSnapshot) {
        guard let statusItem, let statusView else {
            return
        }

        statusView.snapshot = snapshot
        let width = statusView.preferredWidth
        if statusItem.length != width {
            statusItem.length = width
        }

        let summary = detailLines(for: snapshot).joined(separator: "\n")
        statusItem.button?.toolTip = summary
        statusItem.button?.setAccessibilityLabel(summary)
    }

    private func detailLines(for snapshot: SystemResourceSnapshot) -> [String] {
        enabledMetrics.map { metric in
            switch metric {
            case .memory:
                return SystemResourceFormatting.memoryTooltip(for: snapshot)
            case .cpu:
                return "CPU: \(SystemResourceFormatting.percentString(snapshot.cpuPercent))"
            case .gpu:
                return "GPU: \(SystemResourceFormatting.percentString(snapshot.gpuPercent))"
            case .network:
                return SystemResourceFormatting.networkTooltip(for: snapshot.network)
            }
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        for line in detailLines(for: monitor.snapshot) {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        for metric in enabledMetrics {
            let item = NSMenuItem(
                title: "Open Activity Monitor \(metric.activityMonitorTitle)",
                action: #selector(openActivityMonitor(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = metric.activityMonitorPane
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let taskbarItem = NSMenuItem(title: "Move to Taskbar", action: #selector(moveToTaskbar(_:)), keyEquivalent: "")
        taskbarItem.target = self
        menu.addItem(taskbarItem)

        let hideItem = NSMenuItem(title: "Hide System Resource Widget", action: #selector(hideWidget(_:)), keyEquivalent: "")
        hideItem.target = self
        menu.addItem(hideItem)
    }

    @objc
    private func openActivityMonitor(_ sender: NSMenuItem) {
        guard let pane = sender.representedObject as? ActivityMonitorPane else {
            return
        }

        ActivityMonitorLauncher.open(pane)
    }

    @objc
    private func moveToTaskbar(_ sender: Any?) {
        settings.systemResourceWidgetLocation = .taskbar
    }

    @objc
    private func hideWidget(_ sender: Any?) {
        settings.showSystemResourceWidget = false
    }
}

/// Two-line readout sized for the menu bar: label over value for each percentage metric, and
/// upload over download beside a health dot for network.
final class SystemResourceStatusView: NSView {
    private static let horizontalPadding: CGFloat = 4
    private static let columnSpacing: CGFloat = 7
    private static let dotSize: CGFloat = 6
    private static let dotSpacing: CGFloat = 3
    private static let labelFont = NSFont.systemFont(ofSize: 8, weight: .semibold)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    private static let rateFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)

    var metrics: [SystemResourceMetric] = [] {
        didSet {
            guard metrics != oldValue else {
                return
            }
            needsDisplay = true
        }
    }

    var snapshot: SystemResourceSnapshot = .empty {
        didSet {
            guard snapshot != oldValue else {
                return
            }
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    // Clicks belong to the status bar button underneath, which opens the menu.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    var preferredWidth: CGFloat {
        guard !metrics.isEmpty else {
            return 0
        }

        let columns = metrics.map(Self.columnWidth(for:))
        return Self.horizontalPadding * 2 +
            columns.reduce(0, +) +
            CGFloat(columns.count - 1) * Self.columnSpacing
    }

    override func draw(_ dirtyRect: NSRect) {
        var x = Self.horizontalPadding
        for metric in metrics {
            let width = Self.columnWidth(for: metric)
            let column = NSRect(x: x, y: 0, width: width, height: bounds.height)
            if metric == .network {
                drawNetworkColumn(in: column)
            } else {
                drawPercentColumn(metric, in: column)
            }
            x += width + Self.columnSpacing
        }
    }

    private func drawPercentColumn(_ metric: SystemResourceMetric, in rect: NSRect) {
        let value: String
        let severity: SystemResourceMetricSeverity
        switch metric {
        case .memory:
            value = snapshot.memoryUsedBytes.map {
                SystemResourceFormatting.memoryAmountString($0, includesUnit: true)
            } ?? SystemResourceFormatting.percentString(snapshot.memoryUsedPercent)
            severity = SystemResourceFormatting.severity(
                percent: snapshot.memoryUsedPercent,
                pressureLevel: snapshot.memoryPressureLevel
            )
        case .cpu:
            value = SystemResourceFormatting.percentString(snapshot.cpuPercent)
            severity = SystemResourceFormatting.severity(percent: snapshot.cpuPercent)
        case .gpu:
            value = SystemResourceFormatting.percentString(snapshot.gpuPercent)
            severity = SystemResourceFormatting.severity(percent: snapshot.gpuPercent)
        case .network:
            return
        }

        let label = NSAttributedString(string: metric.menuBarLabel, attributes: [
            .font: Self.labelFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        let valueText = NSAttributedString(string: value, attributes: [
            .font: Self.valueFont,
            .foregroundColor: Self.textColor(for: severity)
        ])
        drawStacked(top: label, bottom: valueText, in: rect)
    }

    private func drawNetworkColumn(in rect: NSRect) {
        let network = snapshot.network
        let dotRect = NSRect(
            x: rect.minX,
            y: rect.midY - Self.dotSize / 2,
            width: Self.dotSize,
            height: Self.dotSize
        )
        Self.dotColor(for: SystemResourceFormatting.severity(for: network)).setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.rateFont,
            .foregroundColor: NSColor.labelColor
        ]
        let upload = NSAttributedString(
            string: "↑" + SystemResourceFormatting.rateString(network.uploadBytesPerSecond),
            attributes: attributes
        )
        let download = NSAttributedString(
            string: "↓" + SystemResourceFormatting.rateString(network.downloadBytesPerSecond),
            attributes: attributes
        )
        let textInset = Self.dotSize + Self.dotSpacing
        let textRect = NSRect(x: rect.minX + textInset, y: rect.minY, width: rect.width - textInset, height: rect.height)
        drawStacked(top: upload, bottom: download, in: textRect, alignment: .left)
    }

    private func drawStacked(
        top: NSAttributedString,
        bottom: NSAttributedString,
        in rect: NSRect,
        alignment: NSTextAlignment = .center
    ) {
        let topSize = top.size()
        let bottomSize = bottom.size()
        let lineGap: CGFloat = -1
        let totalHeight = topSize.height + lineGap + bottomSize.height
        var y = rect.midY - totalHeight / 2

        for (text, size) in [(top, topSize), (bottom, bottomSize)] {
            let x = alignment == .center ? rect.midX - size.width / 2 : rect.minX
            text.draw(at: NSPoint(x: x, y: y))
            y += size.height + lineGap
        }
    }

    private static func columnWidth(for metric: SystemResourceMetric) -> CGFloat {
        switch metric {
        case .network:
            let rateWidth = NSAttributedString(string: "↓888M", attributes: [.font: rateFont]).size().width
            return ceil(dotSize + dotSpacing + rateWidth)
        case .memory, .cpu, .gpu:
            let template = metric == .memory ? "888G" : "100%"
            let valueWidth = NSAttributedString(string: template, attributes: [.font: valueFont]).size().width
            let labelWidth = NSAttributedString(string: metric.menuBarLabel, attributes: [.font: labelFont]).size().width
            return ceil(max(valueWidth, labelWidth))
        }
    }

    private static func textColor(for severity: SystemResourceMetricSeverity) -> NSColor {
        switch severity {
        case .warning:
            return .systemOrange
        case .critical:
            return .systemRed
        case .normal, .unknown:
            return .labelColor
        }
    }

    private static func dotColor(for severity: SystemResourceMetricSeverity) -> NSColor {
        switch severity {
        case .normal:
            return .systemGreen
        case .warning:
            return .systemOrange
        case .critical:
            return .systemRed
        case .unknown:
            return .tertiaryLabelColor
        }
    }
}

private extension SystemResourceMetric {
    var menuBarLabel: String {
        switch self {
        case .memory:
            return "MEM"
        case .cpu:
            return "CPU"
        case .gpu:
            return "GPU"
        case .network:
            return "NET"
        }
    }

    var activityMonitorTitle: String {
        switch self {
        case .memory:
            return "Memory"
        case .cpu:
            return "CPU History"
        case .gpu:
            return "GPU History"
        case .network:
            return "Network"
        }
    }

    var activityMonitorPane: ActivityMonitorPane {
        switch self {
        case .memory:
            return .memory
        case .cpu:
            return .cpu
        case .gpu:
            return .gpu
        case .network:
            return .network
        }
    }
}
