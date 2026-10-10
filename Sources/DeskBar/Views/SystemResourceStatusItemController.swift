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
            statusView.heightDidChange = { [weak self] in
                guard let self else {
                    return
                }
                self.render(self.monitor.snapshot)
            }
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

/// Single-line menu bar readout: "MEM 33G  CPU 8%  GPU 11%  ● ↓24K ↑25K", each label beside
/// its value and the dot showing network health.
final class SystemResourceStatusView: NSView {
    /// Fonts and spacing scaled to the menu bar's height: 22pt on older macOS, 30pt or more on
    /// macOS 26 and notched displays, where fixed small fonts look cramped.
    private struct Layout {
        let horizontalPadding: CGFloat
        let columnSpacing: CGFloat
        let dotSize: CGFloat
        let dotSpacing: CGFloat
        let labelSpacing: CGFloat
        let labelFont: NSFont
        let valueFont: NSFont

        init(barHeight: CGFloat) {
            let height = max(barHeight, 22)
            horizontalPadding = round(height * 0.2)
            columnSpacing = round(height * 0.34)
            dotSize = round(height * 0.24)
            dotSpacing = round(height * 0.14)
            labelSpacing = round(height * 0.12)
            labelFont = NSFont.systemFont(ofSize: max(8, round(height * 0.32 * 2) / 2), weight: .bold)
            valueFont = NSFont.monospacedDigitSystemFont(ofSize: max(11, round(height * 0.45 * 2) / 2), weight: .semibold)
        }
    }

    private static let fallbackBarHeight: CGFloat = 24

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

    override func setFrameSize(_ newSize: NSSize) {
        let heightChanged = newSize.height != frame.height
        super.setFrameSize(newSize)
        if heightChanged {
            needsDisplay = true
            heightDidChange?()
        }
    }

    /// Called when the status bar resizes the view, so the item length can follow the new fonts.
    var heightDidChange: (() -> Void)?

    private var layout: Layout {
        Layout(barHeight: bounds.height > 0 ? bounds.height : Self.fallbackBarHeight)
    }

    // Clicks belong to the status bar button underneath, which opens the menu.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    var preferredWidth: CGFloat {
        guard !metrics.isEmpty else {
            return 0
        }

        let layout = layout
        let columns = metrics.map { Self.columnWidth(for: $0, layout: layout) }
        return layout.horizontalPadding * 2 +
            columns.reduce(0, +) +
            CGFloat(columns.count - 1) * layout.columnSpacing
    }

    override func draw(_ dirtyRect: NSRect) {
        let layout = layout
        var x = layout.horizontalPadding
        for metric in metrics {
            let width = Self.columnWidth(for: metric, layout: layout)
            let column = NSRect(x: x, y: 0, width: width, height: bounds.height)
            if metric == .network {
                drawNetworkColumn(in: column, layout: layout)
            } else {
                drawPercentColumn(metric, in: column, layout: layout)
            }
            x += width + layout.columnSpacing
        }
    }

    private func drawPercentColumn(_ metric: SystemResourceMetric, in rect: NSRect, layout: Layout) {
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
            .font: layout.labelFont,
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.7)
        ])
        let valueText = NSAttributedString(string: value, attributes: [
            .font: layout.valueFont,
            .foregroundColor: valueColor(for: severity, metric: metric)
        ])
        drawInline(label: label, value: valueText, in: rect, layout: layout)
    }

    /// Draws label then value on a shared baseline, vertically centred on the value's cap height.
    /// The value is left-aligned in a slot sized for its widest form, so the item never jitters.
    private func drawInline(label: NSAttributedString, value: NSAttributedString, in rect: NSRect, layout: Layout) {
        let baseline = round(rect.midY + layout.valueFont.capHeight / 2)
        label.draw(at: NSPoint(x: rect.minX, y: baseline - layout.labelFont.ascender))
        let valueX = rect.minX + ceil(label.size().width) + layout.labelSpacing
        value.draw(at: NSPoint(x: valueX, y: baseline - layout.valueFont.ascender))
    }

    private func drawNetworkColumn(in rect: NSRect, layout: Layout) {
        let network = snapshot.network
        let dotRect = NSRect(
            x: rect.minX,
            y: rect.midY - layout.dotSize / 2,
            width: layout.dotSize,
            height: layout.dotSize
        )
        valueColor(for: SystemResourceFormatting.severity(for: network), metric: .network).setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        let arrowAttributes: [NSAttributedString.Key: Any] = [
            .font: layout.labelFont,
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.7)
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: layout.valueFont,
            .foregroundColor: valueColor(for: SystemResourceFormatting.severity(for: network), metric: .network)
        ]
        let rates = [
            ("↓", network.downloadBytesPerSecond),
            ("↑", network.uploadBytesPerSecond)
        ]
        var x = rect.minX + layout.dotSize + layout.dotSpacing
        for (arrow, rate) in rates {
            let slot = NSRect(x: x, y: rect.minY, width: Self.rateSlotWidth(layout: layout), height: rect.height)
            drawInline(
                label: NSAttributedString(string: arrow, attributes: arrowAttributes),
                value: NSAttributedString(string: SystemResourceFormatting.rateString(rate), attributes: valueAttributes),
                in: slot,
                layout: layout
            )
            x = slot.maxX + layout.labelSpacing * 2
        }
    }

    /// Width of one "↓888M" slot; rate strings never exceed four characters.
    private static func rateSlotWidth(layout: Layout) -> CGFloat {
        let arrowWidth = NSAttributedString(string: "↓", attributes: [.font: layout.labelFont]).size().width
        let valueWidth = NSAttributedString(string: "888M", attributes: [.font: layout.valueFont]).size().width
        return ceil(arrowWidth) + layout.labelSpacing + ceil(valueWidth)
    }

    private static func columnWidth(for metric: SystemResourceMetric, layout: Layout) -> CGFloat {
        switch metric {
        case .network:
            return layout.dotSize + layout.dotSpacing + rateSlotWidth(layout: layout) * 2 + layout.labelSpacing * 2
        case .memory, .cpu, .gpu:
            let template = metric == .memory ? "888G" : "100%"
            let valueWidth = NSAttributedString(string: template, attributes: [.font: layout.valueFont]).size().width
            let labelWidth = NSAttributedString(string: metric.menuBarLabel, attributes: [.font: layout.labelFont]).size().width
            return ceil(labelWidth) + layout.labelSpacing + ceil(valueWidth)
        }
    }

    /// Matches the taskbar widget's bar colours: green for memory and network, accent for CPU and
    /// GPU, yellow then red as usage climbs. Text needs more contrast than a bar, so a dark menu
    /// bar uses cyan instead of the accent, and a light one uses orange instead of yellow.
    private func valueColor(for severity: SystemResourceMetricSeverity, metric: SystemResourceMetric) -> NSColor {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch severity {
        case .normal:
            guard metric == .cpu || metric == .gpu else {
                return .systemGreen
            }
            return isDark ? .systemCyan : .controlAccentColor
        case .warning:
            return isDark ? .systemYellow : .systemOrange
        case .critical:
            return .systemRed
        case .unknown:
            return .secondaryLabelColor
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
