import Foundation
import Testing
@testable import DeskBar

struct TaskbarSettingsTests {
    @Test
    func showOnAllMonitorsDefaultsToTrue() {
        let suiteName = "TaskbarSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = TaskbarSettings(defaults: defaults)

        #expect(settings.showOnAllMonitors)
        #expect(settings.groupingMode == .never)
        #expect(settings.flashAttentionIndicators)
        #expect(settings.showProgressIndicators)
        #expect(settings.enableActivityMode)
        #expect(settings.showSystemResourceWidget)
        #expect(settings.showSystemResourceMemoryMetric)
        #expect(settings.showSystemResourceCPUMetric)
        #expect(settings.showSystemResourceGPUMetric)
        #expect(settings.systemResourceWidgetCollapsed == false)
        #expect(settings.systemResourceWidgetPinnedDisplayID == nil)
        #expect(settings.showSessionManagerWidget)
        #expect(settings.sessionManagerWidgetPinnedDisplayID == nil)
        #expect(settings.layoutMode == .fullWidth)
        #expect(settings.enableWindowSwitcher == false)
        #expect(settings.disableSwitcherInFullScreen == false)
        #expect(settings.enableBareCommandLauncher == false)
        #expect(settings.appsLauncherShortcut == .controlOptionReturn)
        #expect(settings.animateSessionManagerActivity == false)
        #expect(settings.showNowPlayingTitles)
        #expect(settings.launcherButtonAction == .systemApps)
        #expect(settings.launcherCustomAppBundleID == nil)
        #expect(settings.launcherCustomAppPath == nil)
        #expect(settings.launcherCustomCommand == "")
    }

    @Test
    func migratesLegacyGroupByAppSetting() {
        let suiteName = "TaskbarSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "groupByApp")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = TaskbarSettings(defaults: defaults)

        #expect(settings.groupingMode == .always)
    }

    @Test
    func persistsLayoutAndShortcutSettings() {
        let suiteName = "TaskbarSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        var settings = TaskbarSettings(defaults: defaults)
        settings.layoutMode = .fullWidthGlass
        settings.enableWindowSwitcher = false
        settings.disableSwitcherInFullScreen = true
        settings.enableBareCommandLauncher = false
        settings.appsLauncherShortcut = .optionSpace
        settings.showSystemResourceWidget = false
        settings.showSystemResourceMemoryMetric = false
        settings.showSystemResourceCPUMetric = false
        settings.showSystemResourceGPUMetric = true
        settings.systemResourceWidgetCollapsed = true
        settings.systemResourceWidgetPinnedDisplayID = 12345
        settings.showSessionManagerWidget = false
        settings.sessionManagerWidgetPinnedDisplayID = 67890

        settings = TaskbarSettings(defaults: defaults)

        #expect(settings.layoutMode == .fullWidthGlass)
        #expect(settings.enableWindowSwitcher == false)
        #expect(settings.disableSwitcherInFullScreen)
        #expect(settings.enableBareCommandLauncher == false)
        #expect(settings.appsLauncherShortcut == .optionSpace)
        #expect(settings.showSystemResourceWidget == false)
        #expect(settings.showSystemResourceMemoryMetric == false)
        #expect(settings.showSystemResourceCPUMetric == false)
        #expect(settings.showSystemResourceGPUMetric)
        #expect(settings.systemResourceWidgetCollapsed)
        #expect(settings.systemResourceWidgetPinnedDisplayID == 12345)
        #expect(settings.showSessionManagerWidget == false)
        #expect(settings.sessionManagerWidgetPinnedDisplayID == 67890)

        settings.systemResourceWidgetPinnedDisplayID = nil
        settings.sessionManagerWidgetPinnedDisplayID = nil
        settings = TaskbarSettings(defaults: defaults)

        #expect(settings.systemResourceWidgetPinnedDisplayID == nil)
        #expect(settings.sessionManagerWidgetPinnedDisplayID == nil)
    }

    @Test
    func persistsNowPlayingAndLauncherButtonSettings() {
        let suiteName = "TaskbarSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        var settings = TaskbarSettings(defaults: defaults)
        settings.showNowPlayingTitles = false
        settings.launcherButtonAction = .customApp
        settings.launcherCustomAppBundleID = "com.apple.Finder"
        settings.launcherCustomAppPath = "/System/Library/CoreServices/Finder.app"
        settings.launcherCustomCommand = "open https://example.com"

        settings = TaskbarSettings(defaults: defaults)

        #expect(settings.showNowPlayingTitles == false)
        #expect(settings.launcherButtonAction == .customApp)
        #expect(settings.launcherCustomAppBundleID == "com.apple.Finder")
        #expect(settings.launcherCustomAppPath == "/System/Library/CoreServices/Finder.app")
        #expect(settings.launcherCustomCommand == "open https://example.com")

        settings.launcherButtonAction = .hidden
        settings.launcherCustomAppBundleID = nil
        settings.launcherCustomAppPath = nil
        settings.launcherCustomCommand = ""
        settings.showNowPlayingTitles = true

        settings = TaskbarSettings(defaults: defaults)

        #expect(settings.showNowPlayingTitles)
        #expect(settings.launcherButtonAction == .hidden)
        #expect(settings.launcherCustomAppBundleID == nil)
        #expect(settings.launcherCustomAppPath == nil)
        #expect(settings.launcherCustomCommand == "")
    }

    @Test
    func resetAppearanceSlidersRestoresDefaults() {
        let suiteName = "TaskbarSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        var settings = TaskbarSettings(defaults: defaults)
        settings.taskbarHeight = 60
        settings.titleFontSize = 18
        settings.maxTaskWidth = 400
        settings.thumbnailSize = 400

        settings.resetAppearanceSlidersToDefaults()

        #expect(settings.taskbarHeight == TaskbarSettings.defaultTaskbarHeight)
        #expect(settings.titleFontSize == TaskbarSettings.defaultTitleFontSize)
        #expect(settings.maxTaskWidth == TaskbarSettings.defaultMaxTaskWidth)
        #expect(settings.thumbnailSize == TaskbarSettings.defaultThumbnailSize)

        settings = TaskbarSettings(defaults: defaults)

        #expect(settings.taskbarHeight == TaskbarSettings.defaultTaskbarHeight)
        #expect(settings.titleFontSize == TaskbarSettings.defaultTitleFontSize)
        #expect(settings.maxTaskWidth == TaskbarSettings.defaultMaxTaskWidth)
        #expect(settings.thumbnailSize == TaskbarSettings.defaultThumbnailSize)
    }
}
