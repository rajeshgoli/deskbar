import AppKit
import Foundation
import Testing
@testable import DeskBar

struct IconMetricsTests {
    /// Each test gets its own defaults suite; nothing global is changed, so
    /// these tests can run alongside the view tests that read `IconMetrics`.
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "IconMetricsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }

    @Test
    func defaultsKeepTheExistingLook() {
        withDefaults { defaults in
            let settings = TaskbarSettings(defaults: defaults)

            #expect(settings.iconSize == 24)
            #expect(settings.itemSpacing == 8)
            #expect(settings.compactIconOnlyButtons == false)
            #expect(settings.taskbarHeight == 40)
            #expect(IconMetrics.storedIconSize(in: defaults) == 24)
            #expect(IconMetrics.storedItemSpacing(in: defaults) == 8)
        }

        #expect(IconMetrics.launcherIconSize(forIconSize: 24) == 28)
        #expect(IconMetrics.launcherButtonWidth(forIconSize: 24) == 36)
        #expect(IconMetrics.groupHeaderWidth(forIconSize: 24) == 40)
        #expect(IconMetrics.rowHeight(forIconSize: 24) == 32)
        #expect(TaskButtonView.minimumTaskWidth(forIconSize: 24) == TaskButtonView.minimumTaskWidth)
        #expect(TaskButtonView.minimumAdaptiveTaskWidth(forIconSize: 24) == TaskButtonView.minimumAdaptiveTaskWidth)
    }

    @Test
    func settingsPersistAndDriveTheMetrics() {
        withDefaults { defaults in
            let settings = TaskbarSettings(defaults: defaults)
            settings.iconSize = 36
            settings.itemSpacing = 2
            settings.compactIconOnlyButtons = true

            #expect(IconMetrics.storedIconSize(in: defaults) == 36)
            #expect(IconMetrics.storedItemSpacing(in: defaults) == 2)

            let reloaded = TaskbarSettings(defaults: defaults)
            #expect(reloaded.iconSize == 36)
            #expect(reloaded.itemSpacing == 2)
            #expect(reloaded.compactIconOnlyButtons)
        }

        #expect(IconMetrics.launcherIconSize(forIconSize: 36) == 40)
        #expect(IconMetrics.iconOnlyTaskWidth(forIconSize: 36) == 48)
        #expect(IconMetrics.rowHeight(forIconSize: 36) == 44)
    }

    @Test
    func outOfRangeValuesAreClamped() {
        withDefaults { defaults in
            defaults.set(500.0, forKey: IconMetrics.iconSizeKey)
            defaults.set(-4.0, forKey: IconMetrics.itemSpacingKey)

            #expect(IconMetrics.storedIconSize(in: defaults) == IconMetrics.iconSizeRange.upperBound)
            #expect(IconMetrics.storedItemSpacing(in: defaults) == IconMetrics.itemSpacingRange.lowerBound)
            #expect(TaskbarSettings(defaults: defaults).iconSize == IconMetrics.iconSizeRange.upperBound)
        }
    }

    @Test
    func largerIconsRaiseTheTaskbarAndSmallerOnesGiveTheChosenHeightBack() {
        withDefaults { defaults in
            let settings = TaskbarSettings(defaults: defaults)
            #expect(settings.taskbarHeight == 40)

            settings.iconSize = 64
            #expect(settings.taskbarHeight == 72)

            settings.iconSize = 24
            #expect(settings.taskbarHeight == 40)
            #expect(TaskbarSettings(defaults: defaults).taskbarHeight == 40)
        }
    }

    @Test
    func aLowerTaskbarShrinksTheIconsAndATallerOneGivesTheChosenSizeBack() {
        withDefaults { defaults in
            let settings = TaskbarSettings(defaults: defaults)
            settings.iconSize = 64

            settings.taskbarHeight = 48
            #expect(settings.taskbarHeight == 48)
            #expect(settings.iconSize == 40)
            #expect(IconMetrics.storedIconSize(in: defaults) == 40)

            settings.taskbarHeight = 96
            #expect(settings.iconSize == 64)

            settings.taskbarHeight = 60
            #expect(settings.iconSize == 52)

            let reloaded = TaskbarSettings(defaults: defaults)
            #expect(reloaded.taskbarHeight == 60)
            #expect(reloaded.iconSize == 52)
            reloaded.taskbarHeight = 96
            #expect(reloaded.iconSize == 64)
        }
    }

    @Test
    func theLowestTaskbarStillHoldsTheDefaultIcons() {
        withDefaults { defaults in
            let settings = TaskbarSettings(defaults: defaults)
            settings.iconSize = 48

            settings.taskbarHeight = 32
            #expect(settings.taskbarHeight == 32)
            #expect(settings.taskbarHeight == IconMetrics.smallestTaskbarHeight)
            #expect(settings.iconSize == 24)
        }
    }

    @Test
    func heightsBelowTheDefaultSavedBeforeIconSizesExistAreKept() {
        // The height slider has always started at 32 pt.
        withDefaults { defaults in
            defaults.set(32.0, forKey: "taskbarHeight")

            let settings = TaskbarSettings(defaults: defaults)
            #expect(settings.taskbarHeight == 32)
            #expect(settings.iconSize == 24)
        }
    }

    @Test
    func largestIconSizeIsTheInverseOfTheMinimumHeight() {
        for size in stride(from: IconMetrics.iconSizeRange.lowerBound, through: IconMetrics.iconSizeRange.upperBound, by: 1) {
            let height = IconMetrics.minimumTaskbarHeight(forIconSize: size)
            #expect(IconMetrics.largestIconSize(forTaskbarHeight: height) >= size)
            #expect(IconMetrics.minimumTaskbarHeight(forIconSize: IconMetrics.largestIconSize(forTaskbarHeight: height)) <= height)
        }
        #expect(IconMetrics.largestIconSize(forTaskbarHeight: 20) == 24)
        #expect(IconMetrics.largestIconSize(forTaskbarHeight: 200) == IconMetrics.iconSizeRange.upperBound)
    }

    @Test
    func storedHeightTooSmallForStoredIconsIsRaisedOnLoad() {
        withDefaults { defaults in
            defaults.set(64.0, forKey: IconMetrics.iconSizeKey)
            defaults.set(48.0, forKey: "taskbarHeight")

            #expect(TaskbarSettings(defaults: defaults).taskbarHeight == 72)
            // Fitting to the icons does not overwrite the stored preference.
            #expect(defaults.object(forKey: "taskbarHeight") as? CGFloat == 48)
        }
    }

    @Test
    func resetRestoresDefaultHeightEvenFromLargeIcons() {
        withDefaults { defaults in
            let settings = TaskbarSettings(defaults: defaults)
            settings.iconSize = 64
            settings.resetAppearanceSlidersToDefaults()

            #expect(settings.iconSize == 24)
            #expect(settings.taskbarHeight == 40)
        }
    }

    @Test
    func largerIconsWidenTheNarrowestButtonsSoTheIconFits() {
        #expect(TaskButtonView.minimumAdaptiveTaskWidth(forIconSize: 48) == 56)
        #expect(TaskButtonView.minimumTaskWidth(forIconSize: 48) == 80)
        for size in stride(from: IconMetrics.iconSizeRange.lowerBound, through: IconMetrics.iconSizeRange.upperBound, by: 1) {
            #expect(TaskButtonView.minimumAdaptiveTaskWidth(forIconSize: size) >= size + 8)
        }
    }

    @Test
    func changingASizeNotifiesViewsOnlyWhenItChanges() {
        withDefaults { defaults in
            let settings = TaskbarSettings(defaults: defaults)
            var notifications = 0
            let observer = NotificationCenter.default.addObserver(
                forName: IconMetrics.didChange,
                object: settings,
                queue: nil
            ) { _ in notifications += 1 }
            defer { NotificationCenter.default.removeObserver(observer) }

            settings.iconSize = 30
            settings.itemSpacing = 4
            #expect(notifications == 2)

            settings.iconSize = 30
            settings.itemSpacing = 4
            #expect(notifications == 2)
        }
    }
}
