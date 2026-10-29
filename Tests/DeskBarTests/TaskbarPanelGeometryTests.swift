import AppKit
import Testing
@testable import DeskBar

@MainActor
struct TaskbarPanelGeometryTests {
    @Test(arguments: DeskBarLayoutMode.allCases)
    func carrierRecoversFromAWindowResizeWithoutClippingItsContent(mode: DeskBarLayoutMode) async throws {
        let screen = try #require(NSScreen.screens.first)
        let suite = "com.deskbar.tests.panel-geometry.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = TaskbarSettings(defaults: defaults)
        settings.layoutMode = mode
        let panel = TaskbarPanel(
            permissionsManager: PermissionsManager(),
            settings: settings,
            screen: screen
        )
        let content = NSView()
        panel.setContentSubview(content)
        defer { panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(panel.level == .statusBar)

        var smallerFrame = panel.frame
        smallerFrame.size.width -= 44
        panel.setFrame(smallerFrame, display: false)
        try await Task.sleep(for: .milliseconds(50))

        #expect(panel.frame.width == screen.frame.width)
        #expect(panel.contentView?.frame.width == panel.contentLayoutRect.width)
        let contentFrame = content.convert(content.bounds, to: panel.contentView)
        #expect(contentFrame.minX >= 0)
        #expect(contentFrame.maxX <= panel.contentLayoutRect.width)
    }
}
