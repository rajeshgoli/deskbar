import AppKit
import CoreGraphics
import Testing
@testable import DeskBar

@Test
func smAgentMenuIncludesCopySessionIDCommand() {
    let annotation = SMAgentWindowAnnotation(
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
        tmuxSession: "session-123",
        terminalWindowID: 42,
        terminalTTY: "/dev/ttys001",
        terminalFrame: nil,
        isSelectedTerminalTab: true
    )

    let menu = SMPluginAgentMenuFactory.makeMenu(
        annotation: annotation,
        target: nil,
        action: Selector(("performMenuCommand:"))
    )

    let copyItem = menu.items.first { $0.title == "Copy SM ID" }
    let command = copyItem?.representedObject as? SMPluginAgentMenuCommand

    #expect(command?.action == .copySessionID)
    #expect(command?.annotation.sessionID == "session-123")
}

@Test
func smAgentMenuHidesTerminalOnlyActionsWithoutTerminalBacking() {
    let annotation = SMAgentWindowAnnotation(
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
        tmuxSession: "session-123",
        terminalWindowID: 0,
        terminalTTY: "",
        terminalFrame: nil,
        isSelectedTerminalTab: false
    )

    let menu = SMPluginAgentMenuFactory.makeMenu(
        annotation: annotation,
        target: nil,
        action: Selector(("performMenuCommand:"))
    )
    let titles = menu.items.map(\.title)

    #expect(titles.contains("Rename"))
    #expect(titles.contains("Retire"))
    #expect(titles.contains("Node: macbook"))
    #expect(!titles.contains("New Terminal Like This"))
    #expect(!titles.contains("Retire and Close"))
}

@Test
func smPluginParsesLocalTmuxAttachTarget() {
    let command = "tmux -L session-manager attach -t codex-fork-1a701804"

    #expect(SMPluginService.tmuxAttachTarget(in: command) == "codex-fork-1a701804")
}

@Test
func smPluginParsesSSHWrappedTmuxAttachTarget() {
    let command = "ssh -tt -o ControlMaster=auto -o ControlPersist=600 -o ConnectTimeout=5 -S /Users/rajesh/.ssh/sm-macbook-%r@%h:%p rajesh@macbook.local /bin/sh -lc 'tmux -L session-manager attach -t claude-29d86946'"

    #expect(SMPluginService.tmuxAttachTarget(in: command) == "claude-29d86946")
}
