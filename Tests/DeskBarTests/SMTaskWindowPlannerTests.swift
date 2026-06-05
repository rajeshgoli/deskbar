import AppKit
import CoreGraphics
import Testing
@testable import DeskBar

@Test
func smTaskPlannerDropsAgentAnnotationWithoutCurrentTerminalWindow() {
    let baseWindows = [
        WindowInfo(
            pid: 11,
            cgWindowID: 101,
            appName: "Notes",
            title: "Notes",
            icon: nil,
            bundleIdentifier: "com.apple.Notes"
        )
    ]
    let annotation = agentAnnotation(
        terminalWindowID: 42,
        terminalFrame: CGRect(x: 100, y: 100, width: 800, height: 500)
    )

    let result = SMTaskWindowPlanner.scopedWindows(
        baseWindows: baseWindows,
        annotations: [annotation],
        terminalTabCountByWindowID: [42: 1],
        showAgentTitles: true,
        frameProvider: { _ in nil }
    )

    #expect(result == baseWindows)
}

@Test
func smTaskPlannerReplacesSingleAgentTerminalWindowWithVirtualAgentWindow() {
    let terminalWindow = window(
        cgWindowID: 42,
        title: "Terminal"
    )
    let annotation = agentAnnotation(terminalWindowID: 42)

    let result = SMTaskWindowPlanner.scopedWindows(
        baseWindows: [terminalWindow],
        annotations: [annotation],
        terminalTabCountByWindowID: [42: 1],
        showAgentTitles: true,
        frameProvider: { _ in nil }
    )

    #expect(result.count == 1)
    #expect(result.first?.provisionalID == "sm-agent:session-123")
    #expect(result.first?.title == "Session 123")
    #expect(result.first?.bundleIdentifier == SMPluginService.terminalBundleIdentifier)
}

@Test
func smTaskPlannerKeepsTerminalWindowWhenItHasNonAgentTabs() {
    let terminalWindow = window(
        cgWindowID: 42,
        title: "Terminal"
    )
    let annotation = agentAnnotation(terminalWindowID: 42)

    let result = SMTaskWindowPlanner.scopedWindows(
        baseWindows: [terminalWindow],
        annotations: [annotation],
        terminalTabCountByWindowID: [42: 2],
        showAgentTitles: true,
        frameProvider: { _ in nil }
    )

    #expect(result.count == 2)
    #expect(result.map(\.id).contains(terminalWindow.id))
    #expect(result.map(\.provisionalID).contains("sm-agent:session-123"))
}

private func window(
    cgWindowID: CGWindowID,
    title: String
) -> WindowInfo {
    WindowInfo(
        pid: 22,
        cgWindowID: cgWindowID,
        appName: "Terminal",
        title: title,
        icon: nil,
        bundleIdentifier: SMPluginService.terminalBundleIdentifier
    )
}

private func agentAnnotation(
    terminalWindowID: CGWindowID,
    terminalFrame: CGRect? = nil
) -> SMAgentWindowAnnotation {
    SMAgentWindowAnnotation(
        sessionID: "session-123",
        friendlyName: "Session 123",
        workingDirectory: "/tmp",
        node: "macbook",
        provider: "codex",
        sessionStatus: "running",
        activityState: .working,
        currentTask: nil,
        agentStatusText: nil,
        lastToolName: nil,
        lastActionSummary: nil,
        tokensUsed: nil,
        tmuxSession: "codex-fork-session-123",
        terminalWindowID: terminalWindowID,
        terminalTTY: "/dev/ttys001",
        terminalFrame: terminalFrame,
        isSelectedTerminalTab: true
    )
}
