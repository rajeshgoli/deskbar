import AppKit
import Testing
@testable import DeskBar

struct TaskButtonWidthTests {
    @Test
    func shortTitlesCanUseContentWidthInAdaptiveMode() {
        let font = NSFont.systemFont(ofSize: TaskbarSettings.defaultTitleFontSize)
        let width = TaskButtonView.preferredWidth(
            title: "AirDrop",
            font: font,
            maxWidth: 200,
            showsTitles: true,
            showsPluginActionButton: false,
            isAgentWindow: false
        )

        #expect(width < 140)
        #expect(width > TaskButtonView.minimumTaskWidth)
    }

    @Test
    func longTitlesStillClampToConfiguredMaxWidthInAdaptiveMode() {
        let font = NSFont.systemFont(ofSize: TaskbarSettings.defaultTitleFontSize)
        let width = TaskButtonView.preferredWidth(
            title: "Set up new Mac Studio with dev tools",
            font: font,
            maxWidth: 200,
            showsTitles: true,
            showsPluginActionButton: false,
            isAgentWindow: false
        )

        #expect(width == 200)
    }

    @Test
    func hiddenTitlesUseMinimumIconWidthInAdaptiveMode() {
        let font = NSFont.systemFont(ofSize: TaskbarSettings.defaultTitleFontSize)
        let width = TaskButtonView.preferredWidth(
            title: "Desktop",
            font: font,
            maxWidth: 200,
            showsTitles: false,
            showsPluginActionButton: false,
            isAgentWindow: false
        )

        #expect(width == TaskButtonView.minimumTaskWidth)
    }

    @Test
    func adaptiveEmergencyMinimumsAllowIconOnlyCompression() {
        #expect(TaskButtonView.minimumAdaptiveTaskWidth == 32)
        #expect(TaskButtonView.minimumAdaptivePluginActionTaskWidth == 32)
    }
}
