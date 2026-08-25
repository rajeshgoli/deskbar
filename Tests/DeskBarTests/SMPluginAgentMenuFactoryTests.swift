import AppKit
import CoreGraphics
import Testing
@testable import DeskBar

@Test
func smPluginMatchesDirectSMWatchCommand() {
    #expect(SMPluginService.commandLooksLikeSMWatch("sm watch"))
    #expect(SMPluginService.commandLooksLikeSMWatch("/opt/homebrew/bin/sm --api-url http://127.0.0.1:8420 watch"))
}

@Test
func smPluginMatchesLegacyPythonSMWatchEntrypoint() {
    let command = "python /Users/rajesh/projects/session-manager/src/cli/main.py watch --repo deskbar"

    #expect(SMPluginService.commandLooksLikeSMWatch(command))
}

@Test
func smPluginRejectsOtherWatchCommands() {
    #expect(!SMPluginService.commandLooksLikeSMWatch("watch ls"))
    #expect(!SMPluginService.commandLooksLikeSMWatch("sm status"))
    #expect(!SMPluginService.commandLooksLikeSMWatch("node /Users/rajesh/projects/session-manager/web/watch.js watch"))
}

@Test
func smPluginParsesProcessTableIntoCommandLinesByTTY() {
    let output = """
    ttys000 -zsh
    ttys000 tmux -L session-manager attach-session -t claude-29d86946
    /dev/ttys001 login -pf rajesh
    ?? /usr/sbin/some-daemon
    ttys002 ssh studio sm watch codex-9f8e7d6c
    """

    let map = SMPluginService.parseProcessCommandLinesByTTY(output)

    // TTY keys are normalized to /dev/<name> paths.
    #expect(map["/dev/ttys000"] == [
        "-zsh",
        "tmux -L session-manager attach-session -t claude-29d86946"
    ])
    #expect(map["/dev/ttys001"] == ["login -pf rajesh"])
    #expect(map["/dev/ttys002"] == ["ssh studio sm watch codex-9f8e7d6c"])
    // Rows without a controlling terminal (??) are dropped.
    #expect(map["??"] == nil)
    #expect(map.count == 3)
}

@Test
func smPluginParsesTmuxAttachTargetFromScannedCommandLines() {
    let output = "ttys004 tmux -L session-manager attach-session -t claude-29d86946\n"

    let map = SMPluginService.parseProcessCommandLinesByTTY(output)

    let command = try! #require(map["/dev/ttys004"]?.first)
    #expect(SMPluginService.tmuxAttachTarget(in: command) == "claude-29d86946")
}

@Test
func smPluginMatchesOnlyNakedSMWatchTerminal() {
    let commands = [
        "login -pf rajesh",
        "-zsh",
        "/opt/homebrew/Cellar/python@3.14/3.14.5/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python /Users/rajesh/projects/session-manager/venv/bin/sm watch"
    ]

    #expect(SMPluginService.commandsLookLikeNakedSMWatch(commands))
}

@Test
func smPluginRejectsSMWatchTerminalAttachedToAgent() {
    let commands = [
        "login -pf rajesh",
        "-zsh",
        "/opt/homebrew/Cellar/python@3.14/3.14.5/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python /Users/rajesh/projects/session-manager/venv/bin/sm watch --restore",
        "tmux -L session-manager attach-session -t sm-rust-codex-fork-2117c91f-a8944850589c"
    ]

    #expect(!SMPluginService.commandsLookLikeNakedSMWatch(commands))
}

@Test
func smPluginDropsMissingAgentAfterCompletedTerminalMapping() {
    let now = Date()
    let annotation = smTestAnnotation(sessionID: "eng-t17")

    let result = SMPluginService.mergedAgentAnnotations(
        liveSessionIDs: ["eng-t17"],
        freshAnnotations: [],
        previousAnnotations: [annotation],
        lastObservedAtBySessionID: ["eng-t17": now.addingTimeInterval(-5)],
        now: now,
        retainsMissingAnnotations: false
    )

    #expect(result.annotations.isEmpty)
    #expect(result.lastObservedAtBySessionID.isEmpty)
}

@Test
func smPluginRetainsMissingAgentAfterIncompleteTerminalMapping() {
    let now = Date()
    let annotation = smTestAnnotation(sessionID: "eng-t17")

    let result = SMPluginService.mergedAgentAnnotations(
        liveSessionIDs: ["eng-t17"],
        freshAnnotations: [],
        previousAnnotations: [annotation],
        lastObservedAtBySessionID: ["eng-t17": now.addingTimeInterval(-5)],
        now: now,
        retainsMissingAnnotations: true
    )

    #expect(result.annotations.map(\.sessionID) == ["eng-t17"])
    #expect(result.lastObservedAtBySessionID["eng-t17"] == now.addingTimeInterval(-5))
}

@Test
func smAgentMenuIncludesCopySessionIDCommand() {
    let annotation = smTestAnnotation(sessionID: "session-123")

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

@Test
func smPluginParsesStudioSSHAttachSessionID() {
    #expect(SMPluginService.sshAttachSessionID(in: "ssh studio sm attach claude-1a2b3c4d") == "claude-1a2b3c4d")
    #expect(SMPluginService.sshAttachSessionID(in: "ssh rajesh@studio.local sm watch codex-9f8e7d6c") == "codex-9f8e7d6c")
    #expect(
        SMPluginService.sshAttachSessionID(
            in: "ssh -tt -o ConnectTimeout=5 studio-ssh.rajeshgo.li sm --api-url http://127.0.0.1:8420 attach claude-42"
        ) == "claude-42"
    )
}

@Test
func smPluginRejectsNonStudioOrNakedSSHAttach() {
    // Unknown host must not match.
    #expect(SMPluginService.sshAttachSessionID(in: "ssh someserver sm attach claude-1a2b3c4d") == nil)
    // Naked `sm watch` with no session id yields nothing to map.
    #expect(SMPluginService.sshAttachSessionID(in: "ssh studio sm watch") == nil)
    // Local tmux attach is handled by tmuxAttachTarget, not this detector.
    #expect(SMPluginService.sshAttachSessionID(in: "tmux -L session-manager attach -t claude-29d86946") == nil)
}

@Test
func smPluginMapsStudioSSHAttachTabToAnnotation() {
    let session = SMSessionSnapshot(
        id: "claude-studio-1",
        friendlyName: "Studio Agent",
        workingDirectory: "/home/rajesh/proj",
        node: "studio",
        provider: "claude",
        status: "running",
        activityState: .working,
        currentTask: nil,
        agentStatusText: nil,
        lastToolName: nil,
        lastActionSummary: nil,
        tokensUsed: nil,
        tmuxSession: "claude-studio-1",
        tmuxSocketName: nil
    )
    let terminalTab = SMTerminalTabSnapshot(
        windowID: 7,
        tty: "/dev/ttys004",
        frame: nil,
        isSelected: true
    )

    let annotations = SMPluginService.makeAgentTabAnnotations(
        sessions: [session],
        tmuxClients: [],
        sshAttachSessionIDByTTY: ["/dev/ttys004": "claude-studio-1"],
        terminalTabs: [terminalTab]
    )

    #expect(annotations.count == 1)
    #expect(annotations.first?.sessionID == "claude-studio-1")
    #expect(annotations.first?.terminalWindowID == 7)
    #expect(annotations.first?.terminalTTY == "/dev/ttys004")
    #expect(annotations.first?.isLocalTerminalBacked == true)
}

private func smTestAnnotation(sessionID: String) -> SMAgentWindowAnnotation {
    SMAgentWindowAnnotation(
        sessionID: sessionID,
        friendlyName: "Session \(sessionID)",
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
        tmuxSession: sessionID,
        terminalWindowID: 42,
        terminalTTY: "/dev/ttys001",
        terminalFrame: nil,
        isSelectedTerminalTab: true
    )
}
