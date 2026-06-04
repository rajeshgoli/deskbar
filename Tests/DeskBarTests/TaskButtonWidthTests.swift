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

    @MainActor
    @Test
    func adaptiveWidthCapHidesInlinePluginActionButton() {
        let suiteName = "TaskButtonWidthTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = TaskbarSettings(defaults: defaults)
        let menuConfiguration = TaskButtonPluginMenuConfiguration(
            buttonTitle: "sm",
            tintColor: .systemGreen,
            showsActionButton: true,
            menuProvider: { NSMenu() }
        )
        let button = TaskButtonView(
            windowInfo: WindowInfo(
                pid: 123,
                cgWindowID: 456,
                appName: "Session Manager",
                title: "Active session",
                icon: nil,
                bundleIdentifier: "com.example.session"
            ),
            isActive: false,
            hasBadge: false,
            isAccessibilityAvailable: false,
            runtimeState: AppRuntimeState(),
            showsActivityOverlay: false,
            settings: settings,
            blacklistManager: BlacklistManager(),
            pluginMenuConfiguration: menuConfiguration,
            activationHandler: { _ in }
        )
        let pluginActionButton = findPluginActionButton(in: button)

        #expect(pluginActionButton?.isHidden == false)

        button.setWidthMode(usesAdaptiveWidth: true, widthCap: 40)

        #expect(pluginActionButton?.isHidden == true)
    }

    @MainActor
    @Test
    func compactPluginMenuCommandsAnchorToVisibleTaskButton() {
        let suiteName = "TaskButtonWidthTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = TaskbarSettings(defaults: defaults)
        let annotation = makeAgentAnnotation()
        let menuConfiguration = TaskButtonPluginMenuConfiguration(
            buttonTitle: "sm",
            tintColor: .systemGreen,
            showsActionButton: true,
            menuProvider: {
                SMPluginAgentMenuFactory.makeMenu(
                    annotation: annotation,
                    target: nil,
                    action: Selector(("performMenuCommand:"))
                )
            }
        )
        let button = TaskButtonView(
            windowInfo: WindowInfo(
                pid: 123,
                cgWindowID: 456,
                appName: "Session Manager",
                title: "Active session",
                icon: nil,
                bundleIdentifier: "com.example.session"
            ),
            isActive: false,
            hasBadge: false,
            isAccessibilityAvailable: false,
            runtimeState: AppRuntimeState(),
            showsActivityOverlay: false,
            settings: settings,
            blacklistManager: BlacklistManager(),
            pluginMenuConfiguration: menuConfiguration,
            activationHandler: { _ in }
        )

        button.setWidthMode(usesAdaptiveWidth: true, widthCap: 40)

        let menu = button.makeContextMenu()
        let renameCommand = menu.items
            .first { $0.title == "Rename" }?
            .representedObject as? SMPluginAgentMenuCommand
        #expect(renameCommand?.presentationView === button)
    }

    @MainActor
    private func findPluginActionButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton,
           button.toolTip == "Session Manager actions" {
            return button
        }

        for subview in view.subviews {
            if let button = findPluginActionButton(in: subview) {
                return button
            }
        }

        return nil
    }

    private func makeAgentAnnotation() -> SMAgentWindowAnnotation {
        SMAgentWindowAnnotation(
            sessionID: "session-123",
            friendlyName: "Session 123",
            workingDirectory: "/tmp",
            provider: "codex",
            sessionStatus: "running",
            activityState: .working,
            currentTask: nil,
            agentStatusText: nil,
            lastToolName: nil,
            lastActionSummary: nil,
            tokensUsed: nil,
            tmuxSession: "session-123",
            terminalWindowID: 42,
            terminalTTY: "/dev/ttys001",
            terminalFrame: nil,
            isSelectedTerminalTab: true
        )
    }
}
