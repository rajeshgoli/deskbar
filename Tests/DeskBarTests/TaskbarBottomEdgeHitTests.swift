import AppKit
import Testing
@testable import DeskBar

@MainActor
struct TaskbarBottomEdgeHitTests {
    @Test(arguments: [40.0, 60.0])
    func bottomPaddingActivatesTheWindow(height: Double) throws {
        var activatedWindowID: String?
        let (zones, taskZone, button) = makeTaskZone(height: height) {
            activatedWindowID = $0.id
        }
        let point = NSPoint(x: zones.frame.minX + taskZone.frame.minX + 50, y: zones.frame.minY)
        let hit = try #require(zones.hitTest(point))
        #expect(hit === button)

        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
        hit.mouseUp(with: event)
        #expect(activatedWindowID == "123-456")
    }

    @Test
    func gapsAndNonTaskZonesStayUnclaimed() {
        let (zones, taskZone, button) = makeTaskZone()
        let y = zones.frame.minY
        #expect(zones.hitTest(NSPoint(x: zones.frame.minX + 10, y: y)) !== button)
        #expect(zones.hitTest(NSPoint(x: zones.frame.minX + taskZone.frame.minX + 120, y: y)) !== button)
        #expect(zones.hitTest(NSPoint(x: zones.frame.maxX - 1, y: y)) !== button)
        #expect(zones.hitTest(NSPoint(x: zones.frame.minX + taskZone.frame.minX + 50, y: y - 1)) == nil)
    }

    @Test
    func hiddenTasksStayUnclaimed() {
        let (zones, taskZone, button) = makeTaskZone()
        let point = NSPoint(x: zones.frame.minX + taskZone.frame.minX + 50, y: zones.frame.minY)
        button.isHidden = true
        #expect(zones.hitTest(point) !== button)
        button.isHidden = false
        taskZone.isHidden = true
        #expect(zones.hitTest(point) !== button)
    }

    @Test
    func clippedTasksDoNotStealAdjacentZoneClicks() {
        let (zones, taskZone, button) = makeTaskZone()
        taskZone.frame.size.width = 60
        let point = NSPoint(x: zones.frame.minX + taskZone.frame.minX + 80, y: zones.frame.minY)
        #expect(zones.hitTest(point) !== button)
    }

    @Test
    func topPaddingAndNormalSubviewHitsAreUnchanged() {
        let (zones, taskZone, button) = makeTaskZone()
        let x = zones.frame.minX + taskZone.frame.minX + 50
        #expect(zones.hitTest(NSPoint(x: x, y: zones.frame.maxY - 1)) !== button)
        let control = NSButton(frame: NSRect(x: 40, y: 10, width: 20, height: 12))
        button.addSubview(control)
        let point = NSPoint(x: x, y: zones.frame.minY + taskZone.frame.minY + 16)
        #expect(zones.hitTest(point) === control)
        #expect(zones.hitTest(NSPoint(x: x, y: zones.frame.minY)) === button)
    }

    private func makeTaskZone(
        height: Double = 40,
        activate: @escaping (WindowInfo) -> Void = { _ in }
    ) -> (TaskbarZonesStackView, NSView, TaskButtonView) {
        let zones = TaskbarZonesStackView(frame: NSRect(x: 40, y: 70, width: 500, height: height))
        let taskZone = NSView(frame: NSRect(x: 20, y: (height - 32) / 2, width: 300, height: 32))
        zones.addSubview(taskZone)
        zones.taskZoneView = taskZone

        let defaults = UserDefaults(suiteName: "com.deskbar.tests.bottom-edge.\(UUID().uuidString)")!
        let button = TaskButtonView(
            windowInfo: WindowInfo(pid: 123, cgWindowID: 456, appName: "Example", title: "Window", icon: nil, bundleIdentifier: nil),
            isActive: false,
            hasBadge: false,
            isAccessibilityAvailable: false,
            runtimeState: AppRuntimeState(),
            showsActivityOverlay: false,
            settings: TaskbarSettings(defaults: defaults),
            blacklistManager: BlacklistManager(),
            activationHandler: activate
        )
        button.frame = NSRect(x: 0, y: 0, width: 100, height: 32)
        taskZone.addSubview(button)
        return (zones, taskZone, button)
    }
}
