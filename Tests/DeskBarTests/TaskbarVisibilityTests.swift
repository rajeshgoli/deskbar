import AppKit
import Testing
@testable import DeskBar

@MainActor
struct TaskbarVisibilityTests {
    @Test
    func onlyIntentionalDownwardVerticalScrollsHideTheBar() {
        #expect(hides(deltaX: 0, deltaY: -10))
        #expect(!hides(deltaX: 0, deltaY: 10))
        #expect(!hides(deltaX: 10, deltaY: -1))
        #expect(!hides(deltaX: 0, deltaY: -10, isMomentum: true))
        #expect(!hides(deltaX: 0, deltaY: 0))
    }

    @Test(arguments: [false, true])
    func selectedDirectionDoesNotReverseWithNaturalScrolling(inverted: Bool) {
        let downDelta: CGFloat = inverted ? 10 : -10
        #expect(hides(deltaX: 0, deltaY: downDelta, inverted: inverted))
        #expect(!hides(deltaX: 0, deltaY: -downDelta, inverted: inverted))
        #expect(hides(deltaX: 0, deltaY: -downDelta, inverted: inverted, direction: .up))
        #expect(!hides(deltaX: 0, deltaY: downDelta, inverted: inverted, direction: .up))
        #expect(!hides(deltaX: 0, deltaY: downDelta, inverted: inverted, direction: .disabled))
    }

    @Test
    func refreshesDoNotUndoManualDismissalAndShowRestoresIt() throws {
        let panel = try makePanel()
        defer { panel.orderOut(nil) }
        let visibility = TaskbarVisibilityController(panel: panel, settings: try makeSettings())
        visibility.setAvailable(true)
        #expect(panel.isVisible)
        visibility.hide()
        visibility.setAvailable(true)
        #expect(visibility.isManuallyHidden)
        #expect(!panel.isVisible)
        visibility.show()
        #expect(!visibility.isManuallyHidden)
        #expect(panel.isVisible)
    }

    @Test
    func fullScreenSuppressionTakesPriorityOverManualShow() throws {
        let panel = try makePanel()
        defer { panel.orderOut(nil) }
        let visibility = TaskbarVisibilityController(panel: panel, settings: try makeSettings())
        visibility.setAvailable(true)
        visibility.hide()
        visibility.setAvailable(false)
        visibility.show()
        #expect(!visibility.isManuallyHidden)
        #expect(!panel.isVisible)
        visibility.setAvailable(true)
        #expect(panel.isVisible)
    }

    @Test
    func disablingScrollHidingRestoresADismissedPanel() async throws {
        let panel = try makePanel()
        defer { panel.orderOut(nil) }
        let settings = try makeSettings()
        settings.taskbarHideScrollDirection = .down
        let visibility = TaskbarVisibilityController(panel: panel, settings: settings)
        visibility.setAvailable(true)
        visibility.hide()
        settings.taskbarHideScrollDirection = .disabled
        try await Task.sleep(for: .milliseconds(50))
        #expect(panel.isVisible)
        #expect(!visibility.isManuallyHidden)
    }

    @Test
    func hidingOnePanelDoesNotDismissAnother() throws {
        let first = try makePanel()
        let second = try makePanel()
        defer { first.orderOut(nil); second.orderOut(nil) }
        let firstVisibility = TaskbarVisibilityController(panel: first, settings: try makeSettings())
        let secondVisibility = TaskbarVisibilityController(panel: second, settings: try makeSettings())
        firstVisibility.setAvailable(true)
        secondVisibility.setAvailable(true)
        firstVisibility.hide()
        #expect(!first.isVisible)
        #expect(second.isVisible)
        #expect(!secondVisibility.isManuallyHidden)
    }

    @Test
    func pointerAlreadyOnTheEdgeMustLeaveBeforeRevealing() throws {
        let view = TaskbarRevealView()
        var reveals = 0
        view.reveal = { reveals += 1 }
        let event = try #require(NSEvent.enterExitEvent(
            with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        ))
        view.arm(pointerIsInside: true)
        view.mouseEntered(with: event)
        #expect(reveals == 0)
        view.mouseExited(with: event)
        view.mouseEntered(with: event)
        #expect(reveals == 1)
        view.arm(pointerIsInside: false)
        view.mouseEntered(with: event)
        #expect(reveals == 2)
        #expect(view.accessibilityPerformPress())
        #expect(reveals == 3)
    }

    private func makePanel() throws -> TaskbarPanel {
        let screen = try #require(NSScreen.screens.first)
        return TaskbarPanel(permissionsManager: PermissionsManager(),
                            settings: try makeSettings(), screen: screen)
    }

    private func makeSettings() throws -> TaskbarSettings {
        let suite = "com.deskbar.tests.visibility.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        return TaskbarSettings(defaults: defaults)
    }

    private func hides(
        deltaX: CGFloat, deltaY: CGFloat, isMomentum: Bool = false,
        inverted: Bool = false, direction: TaskbarHideScrollDirection = .down
    ) -> Bool {
        TaskbarVisibilityController.isHideScroll(
            deltaX: deltaX, deltaY: deltaY, isMomentum: isMomentum,
            isDirectionInverted: inverted, direction: direction
        )
    }
}
