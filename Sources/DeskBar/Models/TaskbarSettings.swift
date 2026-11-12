import AppKit
import Combine

enum DockMode: String, CaseIterable {
    case independent
    case autoHide
    case hidden
}

enum WindowGroupingMode: String, CaseIterable {
    case never
    case automatic
    case always
}

enum DeskBarLayoutMode: String, CaseIterable {
    case fullWidth
    case fullWidthGlass
    case compact
    case compactGlass
}

enum SystemResourceWidgetLocation: String, CaseIterable {
    case taskbar
    case menuBar
}

enum AppsLauncherShortcut: String, CaseIterable {
    case commandTap
    case controlOptionReturn
    case controlOptionSpace
    case optionSpace
}

class TaskbarSettings: ObservableObject {
    static let defaultTaskbarHeight: CGFloat = 40
    static let defaultTitleFontSize: CGFloat = 12
    static let defaultMaxTaskWidth: CGFloat = 200
    static let defaultThumbnailSize: CGFloat = 200

    private let defaults: UserDefaults

    /// Icon size and taskbar height depend on each other: the bar is never
    /// shorter than its icons need. Each slider keeps the value the user chose
    /// for it, and the other one follows only as far as needed. Larger icons
    /// make the bar taller, and smaller ones give the chosen height back; a
    /// lower bar shrinks the icons, and a taller one gives the chosen size back.
    private var preferredTaskbarHeight: CGFloat
    private var preferredIconSize: CGFloat
    /// Set while one of the two values is being adjusted to fit the other, so
    /// the adjustment is not taken as the user's choice. Assigning a
    /// @Published property runs its didSet even from inside another didSet.
    private var isFittingIconsAndHeight = false
    static let preferredIconSizeKey = "preferredIconSize"

    @Published var taskbarHeight: CGFloat {
        didSet {
            guard !isFittingIconsAndHeight else {
                return
            }

            preferredTaskbarHeight = taskbarHeight
            defaults.set(taskbarHeight, forKey: "taskbarHeight")
            fitIconsAndHeight {
                let fittedIconSize = min(preferredIconSize, IconMetrics.largestIconSize(forTaskbarHeight: taskbarHeight))
                if fittedIconSize != iconSize {
                    iconSize = fittedIconSize
                }
                // Below the smallest usable height, settle on it.
                let minimum = IconMetrics.minimumTaskbarHeight(forIconSize: iconSize)
                if taskbarHeight < minimum {
                    taskbarHeight = minimum
                }
            }
        }
    }

    private func fitIconsAndHeight(_ body: () -> Void) {
        isFittingIconsAndHeight = true
        body()
        isFittingIconsAndHeight = false
    }

    @Published var titleFontSize: CGFloat {
        didSet { defaults.set(titleFontSize, forKey: "titleFontSize") }
    }

    @Published var maxTaskWidth: CGFloat {
        didSet { defaults.set(maxTaskWidth, forKey: "maxTaskWidth") }
    }

    @Published var iconSize: CGFloat {
        didSet {
            // Views without a TaskbarSettings read the size in effect from here.
            defaults.set(iconSize, forKey: IconMetrics.iconSizeKey)
            if !isFittingIconsAndHeight {
                preferredIconSize = iconSize
                defaults.set(iconSize, forKey: Self.preferredIconSizeKey)
                fitIconsAndHeight {
                    let fittedHeight = max(preferredTaskbarHeight, IconMetrics.minimumTaskbarHeight(forIconSize: iconSize))
                    if fittedHeight != taskbarHeight {
                        taskbarHeight = fittedHeight
                    }
                }
            }
            if iconSize != oldValue {
                NotificationCenter.default.post(name: IconMetrics.didChange, object: self)
            }
        }
    }

    @Published var itemSpacing: CGFloat {
        didSet {
            defaults.set(itemSpacing, forKey: IconMetrics.itemSpacingKey)
            if itemSpacing != oldValue {
                NotificationCenter.default.post(name: IconMetrics.didChange, object: self)
            }
        }
    }

    /// With titles hidden, shrink each task button to its icon instead of
    /// keeping the titled width. Off by default.
    @Published var compactIconOnlyButtons: Bool {
        didSet { defaults.set(compactIconOnlyButtons, forKey: "compactIconOnlyButtons") }
    }

    @Published var showTitles: Bool {
        didSet { defaults.set(showTitles, forKey: "showTitles") }
    }

    @Published var groupingMode: WindowGroupingMode {
        didSet { defaults.set(groupingMode.rawValue, forKey: "groupingMode") }
    }

    @Published var dragReorder: Bool {
        didSet { defaults.set(dragReorder, forKey: "dragReorder") }
    }

    @Published var middleClickCloses: Bool {
        didSet { defaults.set(middleClickCloses, forKey: "middleClickCloses") }
    }

    @Published var thumbnailSize: CGFloat {
        didSet { defaults.set(thumbnailSize, forKey: "thumbnailSize") }
    }

    @Published var hoverDelay: TimeInterval {
        didSet { defaults.set(hoverDelay, forKey: "hoverDelay") }
    }

    /// App-level tray icons only; window buttons and minimized-window items remain available.
    @Published private(set) var hiddenTrayApps: [String: String] {
        didSet { defaults.set(hiddenTrayApps, forKey: "hiddenTrayApps") }
    }

    @Published var enableTrayIconHiding: Bool {
        didSet { defaults.set(enableTrayIconHiding, forKey: "enableTrayIconHiding") }
    }

    @Published var dockMode: DockMode {
        didSet { defaults.set(dockMode.rawValue, forKey: "dockMode") }
    }

    @Published var showOverFullScreenApps: Bool {
        didSet { defaults.set(showOverFullScreenApps, forKey: "showOverFullScreenApps") }
    }

    @Published var flashAttentionIndicators: Bool {
        didSet { defaults.set(flashAttentionIndicators, forKey: "flashAttentionIndicators") }
    }

    @Published var showProgressIndicators: Bool {
        didSet { defaults.set(showProgressIndicators, forKey: "showProgressIndicators") }
    }

    @Published var enableActivityMode: Bool {
        didSet { defaults.set(enableActivityMode, forKey: "enableActivityMode") }
    }

    @Published var showSystemResourceWidget: Bool {
        didSet { defaults.set(showSystemResourceWidget, forKey: "showSystemResourceWidget") }
    }

    @Published var showSystemResourceMemoryMetric: Bool {
        didSet { defaults.set(showSystemResourceMemoryMetric, forKey: "showSystemResourceMemoryMetric") }
    }

    @Published var showSystemResourceCPUMetric: Bool {
        didSet { defaults.set(showSystemResourceCPUMetric, forKey: "showSystemResourceCPUMetric") }
    }

    @Published var showSystemResourceGPUMetric: Bool {
        didSet { defaults.set(showSystemResourceGPUMetric, forKey: "showSystemResourceGPUMetric") }
    }

    @Published var showSystemResourceNetworkMetric: Bool {
        didSet { defaults.set(showSystemResourceNetworkMetric, forKey: "showSystemResourceNetworkMetric") }
    }

    @Published var systemResourceWidgetLocation: SystemResourceWidgetLocation {
        didSet { defaults.set(systemResourceWidgetLocation.rawValue, forKey: "systemResourceWidgetLocation") }
    }

    @Published var systemResourceWidgetCollapsed: Bool {
        didSet { defaults.set(systemResourceWidgetCollapsed, forKey: "systemResourceWidgetCollapsed") }
    }

    @Published var systemResourceWidgetPinnedDisplayID: CGDirectDisplayID? {
        didSet {
            if let systemResourceWidgetPinnedDisplayID {
                defaults.set(Int(systemResourceWidgetPinnedDisplayID), forKey: "systemResourceWidgetPinnedDisplayID")
            } else {
                defaults.removeObject(forKey: "systemResourceWidgetPinnedDisplayID")
            }
        }
    }

    @Published var showSessionManagerWidget: Bool {
        didSet { defaults.set(showSessionManagerWidget, forKey: "showSessionManagerWidget") }
    }

    @Published var sessionManagerWidgetPinnedDisplayID: CGDirectDisplayID? {
        didSet {
            if let sessionManagerWidgetPinnedDisplayID {
                defaults.set(Int(sessionManagerWidgetPinnedDisplayID), forKey: "sessionManagerWidgetPinnedDisplayID")
            } else {
                defaults.removeObject(forKey: "sessionManagerWidgetPinnedDisplayID")
            }
        }
    }

    @Published var startAtLogin: Bool {
        didSet { defaults.set(startAtLogin, forKey: "startAtLogin") }
    }

    @Published var showOnAllMonitors: Bool {
        didSet { defaults.set(showOnAllMonitors, forKey: "showOnAllMonitors") }
    }

    @Published var layoutMode: DeskBarLayoutMode {
        didSet { defaults.set(layoutMode.rawValue, forKey: "layoutMode") }
    }

    @Published var enableWindowSwitcher: Bool {
        didSet { defaults.set(enableWindowSwitcher, forKey: "enableWindowSwitcher") }
    }

    @Published var enableBareCommandLauncher: Bool {
        didSet { defaults.set(enableBareCommandLauncher, forKey: "enableBareCommandLauncher") }
    }

    @Published var appsLauncherShortcut: AppsLauncherShortcut {
        didSet { defaults.set(appsLauncherShortcut.rawValue, forKey: "appsLauncherShortcut") }
    }

    @Published var enableSessionManagerPlugin: Bool {
        didSet { defaults.set(enableSessionManagerPlugin, forKey: "enableSessionManagerPlugin") }
    }

    @Published var showSessionManagerAgentTitles: Bool {
        didSet { defaults.set(showSessionManagerAgentTitles, forKey: "showSessionManagerAgentTitles") }
    }

    @Published var showSessionManagerActivityIndicators: Bool {
        didSet { defaults.set(showSessionManagerActivityIndicators, forKey: "showSessionManagerActivityIndicators") }
    }

    @Published var animateSessionManagerActivity: Bool {
        didSet { defaults.set(animateSessionManagerActivity, forKey: "animateSessionManagerActivity") }
    }

    @Published var enableSessionManagerTerminalActions: Bool {
        didSet { defaults.set(enableSessionManagerTerminalActions, forKey: "enableSessionManagerTerminalActions") }
    }

    @Published var showSessionManagerActionButton: Bool {
        didSet { defaults.set(showSessionManagerActionButton, forKey: "showSessionManagerActionButton") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferredTaskbarHeight = defaults.object(forKey: "taskbarHeight") as? CGFloat ?? Self.defaultTaskbarHeight
        preferredIconSize = IconMetrics.clamp(
            defaults.object(forKey: Self.preferredIconSizeKey) as? CGFloat ?? IconMetrics.storedIconSize(in: defaults),
            to: IconMetrics.iconSizeRange
        )
        taskbarHeight = max(
            preferredTaskbarHeight,
            IconMetrics.minimumTaskbarHeight(forIconSize: IconMetrics.storedIconSize(in: defaults))
        )
        titleFontSize = defaults.object(forKey: "titleFontSize") as? CGFloat ?? Self.defaultTitleFontSize
        maxTaskWidth = defaults.object(forKey: "maxTaskWidth") as? CGFloat ?? Self.defaultMaxTaskWidth
        showTitles = defaults.object(forKey: "showTitles") as? Bool ?? true
        compactIconOnlyButtons = defaults.object(forKey: "compactIconOnlyButtons") as? Bool ?? false
        iconSize = IconMetrics.storedIconSize(in: defaults)
        itemSpacing = IconMetrics.clamp(
            defaults.object(forKey: IconMetrics.itemSpacingKey) as? CGFloat ?? IconMetrics.defaultItemSpacing,
            to: IconMetrics.itemSpacingRange
        )
        if let rawValue = defaults.string(forKey: "groupingMode"),
           let groupingMode = WindowGroupingMode(rawValue: rawValue) {
            self.groupingMode = groupingMode
        } else if defaults.object(forKey: "groupByApp") != nil {
            self.groupingMode = (defaults.object(forKey: "groupByApp") as? Bool ?? false) ? .always : .never
        } else {
            groupingMode = .never
        }
        dragReorder = defaults.object(forKey: "dragReorder") as? Bool ?? true
        middleClickCloses = defaults.object(forKey: "middleClickCloses") as? Bool ?? true
        thumbnailSize = defaults.object(forKey: "thumbnailSize") as? CGFloat ?? Self.defaultThumbnailSize
        hoverDelay = defaults.object(forKey: "hoverDelay") as? TimeInterval ?? 0.4
        hiddenTrayApps = defaults.dictionary(forKey: "hiddenTrayApps") as? [String: String] ?? [:]
        enableTrayIconHiding = defaults.object(forKey: "enableTrayIconHiding") as? Bool ?? true
        dockMode = DockMode(rawValue: defaults.string(forKey: "dockMode") ?? "") ?? .independent
        showOverFullScreenApps = defaults.object(forKey: "showOverFullScreenApps") as? Bool ?? false
        flashAttentionIndicators = defaults.object(forKey: "flashAttentionIndicators") as? Bool ?? true
        showProgressIndicators = defaults.object(forKey: "showProgressIndicators") as? Bool ?? true
        enableActivityMode = defaults.object(forKey: "enableActivityMode") as? Bool ?? true
        showSystemResourceWidget = defaults.object(forKey: "showSystemResourceWidget") as? Bool ?? true
        showSystemResourceMemoryMetric = defaults.object(forKey: "showSystemResourceMemoryMetric") as? Bool ?? true
        showSystemResourceCPUMetric = defaults.object(forKey: "showSystemResourceCPUMetric") as? Bool ?? true
        showSystemResourceGPUMetric = defaults.object(forKey: "showSystemResourceGPUMetric") as? Bool ?? true
        showSystemResourceNetworkMetric = defaults.object(forKey: "showSystemResourceNetworkMetric") as? Bool ?? true
        systemResourceWidgetLocation = SystemResourceWidgetLocation(
            rawValue: defaults.string(forKey: "systemResourceWidgetLocation") ?? ""
        ) ?? .taskbar
        systemResourceWidgetCollapsed = defaults.object(forKey: "systemResourceWidgetCollapsed") as? Bool ?? false
        if let pinnedDisplayID = defaults.object(forKey: "systemResourceWidgetPinnedDisplayID") as? NSNumber {
            systemResourceWidgetPinnedDisplayID = CGDirectDisplayID(pinnedDisplayID.uint32Value)
        } else {
            systemResourceWidgetPinnedDisplayID = nil
        }
        showSessionManagerWidget = defaults.object(forKey: "showSessionManagerWidget") as? Bool ?? true
        if let pinnedDisplayID = defaults.object(forKey: "sessionManagerWidgetPinnedDisplayID") as? NSNumber {
            sessionManagerWidgetPinnedDisplayID = CGDirectDisplayID(pinnedDisplayID.uint32Value)
        } else {
            sessionManagerWidgetPinnedDisplayID = nil
        }
        startAtLogin = defaults.object(forKey: "startAtLogin") as? Bool ?? false
        showOnAllMonitors = defaults.object(forKey: "showOnAllMonitors") as? Bool ?? true
        layoutMode = DeskBarLayoutMode(rawValue: defaults.string(forKey: "layoutMode") ?? "") ?? .fullWidth
        enableWindowSwitcher = defaults.object(forKey: "enableWindowSwitcher") as? Bool ?? false
        enableBareCommandLauncher = defaults.object(forKey: "enableBareCommandLauncher") as? Bool ?? false
        appsLauncherShortcut = AppsLauncherShortcut(rawValue: defaults.string(forKey: "appsLauncherShortcut") ?? "") ?? .controlOptionReturn
        enableSessionManagerPlugin = defaults.object(forKey: "enableSessionManagerPlugin") as? Bool ?? true
        showSessionManagerAgentTitles = defaults.object(forKey: "showSessionManagerAgentTitles") as? Bool ?? true
        showSessionManagerActivityIndicators = defaults.object(forKey: "showSessionManagerActivityIndicators") as? Bool ?? true
        animateSessionManagerActivity = defaults.object(forKey: "animateSessionManagerActivity") as? Bool ?? false
        enableSessionManagerTerminalActions = defaults.object(forKey: "enableSessionManagerTerminalActions") as? Bool ?? true
        showSessionManagerActionButton = defaults.object(forKey: "showSessionManagerActionButton") as? Bool ?? true
    }

    func hideTrayApp(bundleIdentifier: String, name: String) {
        guard !bundleIdentifier.isEmpty else { return }
        hiddenTrayApps[bundleIdentifier] = name
    }

    func showTrayApp(bundleIdentifier: String) {
        hiddenTrayApps.removeValue(forKey: bundleIdentifier)
    }

    func showAllTrayApps() {
        hiddenTrayApps.removeAll()
    }

    var hasEnabledSystemResourceMetric: Bool {
        showSystemResourceMemoryMetric ||
            showSystemResourceCPUMetric ||
            showSystemResourceGPUMetric ||
            showSystemResourceNetworkMetric
    }

    var showsSystemResourceWidgetInTaskbar: Bool {
        showSystemResourceWidget && systemResourceWidgetLocation == .taskbar
    }

    var showsSystemResourceWidgetInMenuBar: Bool {
        showSystemResourceWidget && systemResourceWidgetLocation == .menuBar && hasEnabledSystemResourceMetric
    }

    func resetAppearanceSlidersToDefaults() {
        // Icons first: the height may not go below what the icons need.
        iconSize = IconMetrics.defaultIconSize
        itemSpacing = IconMetrics.defaultItemSpacing
        taskbarHeight = Self.defaultTaskbarHeight
        titleFontSize = Self.defaultTitleFontSize
        maxTaskWidth = Self.defaultMaxTaskWidth
        thumbnailSize = Self.defaultThumbnailSize
    }
}
