import Foundation
import Testing

@testable import DeskBar

struct ResourceWidgetScaleTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "ResourceWidgetScaleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }

    @Test
    func defaultKeepsTheNormalSizeAndTheChoiceSurvivesARestart() {
        withDefaults { defaults in
            let settings = TaskbarSettings(defaults: defaults)
            #expect(settings.resourceWidgetScale == 1)

            settings.resourceWidgetScale = 1.5
            #expect(TaskbarSettings(defaults: defaults).resourceWidgetScale == 1.5)
        }
    }

    @Test
    func storedValuesOutsideTheRangeAreClamped() {
        withDefaults { defaults in
            defaults.set(5.0, forKey: "resourceWidgetScale")
            #expect(TaskbarSettings(defaults: defaults).resourceWidgetScale == TaskbarSettings.resourceWidgetScaleRange.upperBound)
            defaults.set(0.2, forKey: "resourceWidgetScale")
            #expect(TaskbarSettings(defaults: defaults).resourceWidgetScale == TaskbarSettings.resourceWidgetScaleRange.lowerBound)
        }
    }

    @Test
    func theWidgetOnlyGrowsAsFarAsTheTaskbarHeightAllows() {
        // The default 40 pt bar keeps the 32 pt widget whatever is chosen.
        #expect(TaskbarSettings.effectiveResourceWidgetScale(scale: 2, taskbarHeight: 40) == 1)
        // A 72 pt bar has room for a 64 pt widget.
        #expect(TaskbarSettings.effectiveResourceWidgetScale(scale: 2, taskbarHeight: 72) == 2)
        #expect(TaskbarSettings.effectiveResourceWidgetScale(scale: 1.5, taskbarHeight: 72) == 1.5)
        #expect(TaskbarSettings.effectiveResourceWidgetScale(scale: 2, taskbarHeight: 56) == 1.5)
        // Bars shorter than the widget never make it smaller than normal.
        #expect(TaskbarSettings.effectiveResourceWidgetScale(scale: 1, taskbarHeight: 32) == 1)
    }
}

struct ResourceWidgetBarWidthTests {
    @Test
    func defaultKeepsFullBarsAndTheChoiceSurvivesARestart() {
        let suiteName = "ResourceWidgetBarWidthTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = TaskbarSettings(defaults: defaults)
        #expect(settings.resourceWidgetBarWidth == 1)
        settings.resourceWidgetBarWidth = 0.5
        #expect(TaskbarSettings(defaults: defaults).resourceWidgetBarWidth == 0.5)

        defaults.set(3.0, forKey: "resourceWidgetBarWidth")
        #expect(TaskbarSettings(defaults: defaults).resourceWidgetBarWidth == 1)
    }

    @Test
    func fullBarsKeepTheExistingWidths() {
        for metric in [SystemResourceMetric.memory, .cpu, .gpu, .network] {
            #expect(metric.controlWidth(barWidth: 1) == metric.controlWidth)
            #expect(metric.trackWidth(barWidth: 1) == metric.trackWidth)
        }
    }

    @Test
    func narrowerBarsGiveTheirRoomBackToTheWidget() {
        #expect(SystemResourceMetric.cpu.trackWidth(barWidth: 0.5) == 27)
        #expect(SystemResourceMetric.cpu.controlWidth(barWidth: 0.5) == CGFloat(98))
        #expect(SystemResourceMetric.memory.controlWidth(barWidth: 0.5) == CGFloat(132))
        // Without bars the gap before the value goes too.
        #expect(SystemResourceMetric.cpu.trackWidth(barWidth: 0) == 0)
        #expect(SystemResourceMetric.cpu.controlWidth(barWidth: 0) == CGFloat(63))
    }

    @Test
    func theNetworkStatusDotKeepsItsSize() {
        #expect(SystemResourceMetric.network.trackWidth(barWidth: 0) == 8)
        #expect(SystemResourceMetric.network.controlWidth(barWidth: 0) == 130)
    }
}
