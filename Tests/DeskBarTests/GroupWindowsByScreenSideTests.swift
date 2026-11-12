import Foundation
import Testing

@testable import DeskBar

struct GroupWindowsByScreenSideTests {
    @Test
    func defaultsOnAndPersists() {
        let suiteName = "GroupWindowsByScreenSideTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = TaskbarSettings(defaults: defaults)
        #expect(settings.groupWindowsByScreenSide)

        settings.groupWindowsByScreenSide = false
        #expect(TaskbarSettings(defaults: defaults).groupWindowsByScreenSide == false)
    }

    @Test
    func halfScreenWindowsGoToTheirSideOnlyWhileGroupingBySide() {
        let displayBounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let halves = [
            CGRect(x: 0, y: 30, width: 960, height: 1010),
            CGRect(x: 960, y: 30, width: 960, height: 1010)
        ]
        func zone(for frame: CGRect, groupingBySide: Bool) -> TaskbarWindowZone {
            TaskbarContentView.taskbarZone(groupingByScreenSide: groupingBySide) {
                ScreenGeometry.taskbarZone(for: frame, onDisplay: displayBounds, topInset: 30, taskbarHeight: 40)
            }
        }

        #expect(halves.map { zone(for: $0, groupingBySide: true) } == [.left, .right])
        #expect(halves.map { zone(for: $0, groupingBySide: false) } == [.neutral, .neutral])
    }
}
