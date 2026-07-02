import AppKit
import CoreGraphics
import Darwin
import Foundation

enum SMAgentActivityState: String, Codable, Equatable {
    case working
    case thinking
    case idle
    case waitingPermission = "waiting_permission"
    case waitingInput = "waiting_input"
    case stopped

    init(rawValue: String) {
        switch rawValue {
        case Self.working.rawValue:
            self = .working
        case Self.thinking.rawValue:
            self = .thinking
        case Self.waitingPermission.rawValue:
            self = .waitingPermission
        case Self.waitingInput.rawValue:
            self = .waitingInput
        case Self.stopped.rawValue:
            self = .stopped
        default:
            self = .idle
        }
    }

    var badgeLabel: String {
        switch self {
        case .working:
            return "work"
        case .thinking:
            return "think"
        case .idle:
            return "idle"
        case .waitingPermission:
            return "perm"
        case .waitingInput:
            return "input"
        case .stopped:
            return "stop"
        }
    }

    var displayName: String {
        switch self {
        case .working:
            return "Working"
        case .thinking:
            return "Thinking"
        case .idle:
            return "Idle"
        case .waitingPermission:
            return "Waiting for permission"
        case .waitingInput:
            return "Waiting for input"
        case .stopped:
            return "Stopped"
        }
    }

    var color: NSColor {
        switch self {
        case .working:
            return .systemGreen
        case .thinking:
            return .systemBlue
        case .idle:
            return .secondaryLabelColor
        case .waitingPermission:
            return .systemOrange
        case .waitingInput:
            return .systemPurple
        case .stopped:
            return .systemRed
        }
    }
}

struct SMAgentWindowAnnotation: Equatable {
    let sessionID: String
    let friendlyName: String
    let workingDirectory: String
    let node: String?
    let provider: String
    let sessionStatus: String
    let activityState: SMAgentActivityState
    let currentTask: String?
    let agentStatusText: String?
    let lastToolName: String?
    let lastActionSummary: String?
    let tokensUsed: Int?
    let tmuxSession: String
    let terminalWindowID: CGWindowID
    let terminalTTY: String
    let terminalFrame: CGRect?
    let isSelectedTerminalTab: Bool

    var isLocalTerminalBacked: Bool {
        terminalWindowID != 0 && !terminalTTY.isEmpty
    }
}

struct SMWatchSummary: Equatable {
    let workingCount: Int
    let thinkingCount: Int
    let waitingPermissionCount: Int
    let waitingInputCount: Int
    let idleCount: Int
    let stoppedCount: Int
    let totalCount: Int

    static let empty = SMWatchSummary(
        workingCount: 0,
        thinkingCount: 0,
        waitingPermissionCount: 0,
        waitingInputCount: 0,
        idleCount: 0,
        stoppedCount: 0,
        totalCount: 0
    )

    init(sessions: [SMSessionSnapshot]) {
        var workingCount = 0
        var thinkingCount = 0
        var waitingPermissionCount = 0
        var waitingInputCount = 0
        var idleCount = 0
        var stoppedCount = 0

        for session in sessions {
            switch session.activityState {
            case .working:
                workingCount += 1
            case .thinking:
                thinkingCount += 1
            case .waitingPermission:
                waitingPermissionCount += 1
            case .waitingInput:
                waitingInputCount += 1
            case .idle:
                idleCount += 1
            case .stopped:
                stoppedCount += 1
            }
        }

        self.workingCount = workingCount
        self.thinkingCount = thinkingCount
        self.waitingPermissionCount = waitingPermissionCount
        self.waitingInputCount = waitingInputCount
        self.idleCount = idleCount
        self.stoppedCount = stoppedCount
        totalCount = sessions.count
    }

    private init(
        workingCount: Int,
        thinkingCount: Int,
        waitingPermissionCount: Int,
        waitingInputCount: Int,
        idleCount: Int,
        stoppedCount: Int,
        totalCount: Int
    ) {
        self.workingCount = workingCount
        self.thinkingCount = thinkingCount
        self.waitingPermissionCount = waitingPermissionCount
        self.waitingInputCount = waitingInputCount
        self.idleCount = idleCount
        self.stoppedCount = stoppedCount
        self.totalCount = totalCount
    }

    var waitingCount: Int {
        waitingPermissionCount + waitingInputCount
    }

    var activeCount: Int {
        workingCount + waitingCount
    }

    var inactiveCount: Int {
        idleCount + stoppedCount
    }

    var aggregateState: SMAgentActivityState {
        if workingCount > 0 {
            return .working
        }
        if thinkingCount > 0 {
            return .thinking
        }
        if waitingPermissionCount > 0 {
            return .waitingPermission
        }
        if waitingInputCount > 0 {
            return .waitingInput
        }
        if stoppedCount > 0, totalCount == stoppedCount {
            return .stopped
        }
        return .idle
    }
}

struct SMWatchWindowAnnotation: Equatable {
    let terminalWindowID: CGWindowID
    let terminalTTY: String
    let terminalFrame: CGRect?
    let isSelectedTerminalTab: Bool
    let summary: SMWatchSummary

    var aggregateState: SMAgentActivityState {
        summary.aggregateState
    }
}

struct SMSessionSnapshot: Equatable {
    let id: String
    let friendlyName: String?
    let workingDirectory: String
    let node: String?
    let provider: String
    let status: String
    let activityState: SMAgentActivityState
    let currentTask: String?
    let agentStatusText: String?
    let lastToolName: String?
    let lastActionSummary: String?
    let tokensUsed: Int?
    let tmuxSession: String
    let tmuxSocketName: String?

    var displayName: String {
        let trimmedName = friendlyName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty {
            return trimmedName
        }

        return id
    }
}

struct SMTmuxClientSnapshot: Equatable {
    let tty: String
    let tmuxSession: String
}

struct SMTerminalTabSnapshot: Equatable {
    let windowID: CGWindowID
    let tty: String
    let frame: CGRect?
    let isSelected: Bool
}

private struct SMAgentTabFetchSnapshot {
    let annotations: [SMAgentWindowAnnotation]
    let watchWindows: [SMWatchWindowAnnotation]
    let watchSummary: SMWatchSummary
    let liveSessionIDs: Set<String>
    let terminalTabCountByWindowID: [CGWindowID: Int]
    let sessionMappingIdentities: Set<SMSessionMappingIdentity>
}

private struct SMSessionMappingIdentity: Hashable {
    let id: String
    let tmuxSession: String
    let tmuxSocketName: String?
}

private enum SMPluginRefreshResult {
    case mapped(SMPluginRefreshPayload<SMAgentTabFetchSnapshot>)
    case sessions(SMPluginRefreshPayload<[SMSessionSnapshot]>)
    case sessionsWithoutTerminal(SMPluginRefreshPayload<[SMSessionSnapshot]>)
    case clear
    case failed
}

private struct SMPluginRefreshPayload<Value> {
    let value: Value
    let tmuxClientEventVersion: Int?
}

enum SMPluginAgentMenuAction {
    case copySessionID
    case rename
    case openTerminalLikeThis
    case retire
    case retireAndClose
}

final class SMPluginAgentMenuCommand: NSObject {
    let action: SMPluginAgentMenuAction
    let annotation: SMAgentWindowAnnotation
    weak var presentationView: NSView?

    init(action: SMPluginAgentMenuAction, annotation: SMAgentWindowAnnotation) {
        self.action = action
        self.annotation = annotation
    }
}

enum SMPluginAgentMenuFactory {
    static func makeMenu(
        annotation: SMAgentWindowAnnotation,
        target: AnyObject?,
        action: Selector
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(metadataItem(annotation.friendlyName))
        menu.addItem(metadataItem("\(annotation.activityState.displayName) - \(annotation.provider) - \(annotation.sessionStatus)"))
        if let node = trimmed(annotation.node), node != "primary" {
            menu.addItem(metadataItem("Node: \(node)"))
        }
        if let agentStatusText = trimmed(annotation.agentStatusText) {
            menu.addItem(metadataItem(agentStatusText))
        } else if let currentTask = trimmed(annotation.currentTask) {
            menu.addItem(metadataItem(currentTask))
        }
        if let lastActionSummary = trimmed(annotation.lastActionSummary) {
            menu.addItem(metadataItem("Last: \(lastActionSummary)"))
        } else if let lastToolName = trimmed(annotation.lastToolName) {
            menu.addItem(metadataItem("Tool: \(lastToolName)"))
        }
        if let tokensUsed = annotation.tokensUsed, tokensUsed > 0 {
            menu.addItem(metadataItem("Tokens: \(tokensUsed)"))
        }
        menu.addItem(metadataItem("Dir: \(abbreviatedPath(annotation.workingDirectory))"))
        menu.addItem(.separator())
        menu.addItem(item("Copy SM ID", .copySessionID, annotation, target, action))
        menu.addItem(item("Rename", .rename, annotation, target, action))
        if annotation.isLocalTerminalBacked {
            menu.addItem(item("New Terminal Like This", .openTerminalLikeThis, annotation, target, action))
        }
        menu.addItem(.separator())
        menu.addItem(item("Retire", .retire, annotation, target, action))
        if annotation.isLocalTerminalBacked {
            menu.addItem(item("Retire and Close", .retireAndClose, annotation, target, action))
        }
        return menu
    }

    private static func metadataItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func item(
        _ title: String,
        _ menuAction: SMPluginAgentMenuAction,
        _ annotation: SMAgentWindowAnnotation,
        _ target: AnyObject?,
        _ action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = SMPluginAgentMenuCommand(action: menuAction, annotation: annotation)
        return item
    }

    private static func trimmed(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedValue, !trimmedValue.isEmpty else {
            return nil
        }

        return trimmedValue
    }

    private static func abbreviatedPath(_ path: String) -> String {
        let homeDirectory = NSHomeDirectory()
        guard path == homeDirectory || path.hasPrefix("\(homeDirectory)/") else {
            return path
        }

        return "~" + path.dropFirst(homeDirectory.count)
    }
}

@MainActor
final class SMPluginService: ObservableObject {
    nonisolated static let terminalBundleIdentifier = "com.apple.Terminal"
    private nonisolated static let commandTimeout: TimeInterval = 2.0
    private nonisolated static let refreshStaleTimeout: TimeInterval = 20.0
    private nonisolated static let terminalMappingRefreshInterval: TimeInterval = 300.0
    private nonisolated static let retireTimeout: TimeInterval = 30.0
    private nonisolated static let staleAnnotationRetention: TimeInterval = 60.0
    private nonisolated static let diagnosticLogURL = URL(fileURLWithPath: "/tmp/deskbar-sm-plugin.log")
    private nonisolated static let diagnosticRepeatInterval: TimeInterval = 60.0
    private nonisolated static let maxDiagnosticThrottleKeys = 128
    private nonisolated static let diagnosticLogLock = NSLock()
    private nonisolated(unsafe) static var diagnosticLastWriteByMessage: [String: Date] = [:]

    @Published private(set) var windowAnnotations: [CGWindowID: SMAgentWindowAnnotation] = [:]
    @Published private(set) var agentTabs: [SMAgentWindowAnnotation] = []
    @Published private(set) var watchSummary: SMWatchSummary = .empty
    @Published private(set) var watchWindows: [SMWatchWindowAnnotation] = []
    @Published private(set) var terminalTabCountByWindowID: [CGWindowID: Int] = [:]

    private let pollInterval: TimeInterval
    private var pollLoopTask: Task<Void, Never>?
    private var eventStreamTask: Task<Void, Never>?
    private var eventDrivenRefreshTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshStartedAt: Date?
    private var refreshGeneration = 0
    private var isEnabled: Bool
    private var lastTerminalMappingRefreshAt: Date?
    private var lastMappedSessionIdentities: Set<SMSessionMappingIdentity> = []
    private var lastTmuxClientEventVersion: Int?
    private var lastObservedAgentTabAtBySessionID: [String: Date] = [:]
    private var renamePopover: NSPopover?

    init(pollInterval: TimeInterval = 2.0, isEnabled: Bool = true) {
        self.pollInterval = pollInterval
        self.isEnabled = isEnabled
        guard isEnabled else {
            return
        }

        startPolling()
        startEventStream()
    }

    deinit {
        pollLoopTask?.cancel()
        eventStreamTask?.cancel()
        eventDrivenRefreshTask?.cancel()
        refreshTask?.cancel()
    }

    func setEnabled(_ isEnabled: Bool) {
        guard self.isEnabled != isEnabled else {
            return
        }

        self.isEnabled = isEnabled
        if isEnabled {
            startPolling()
            startEventStream()
        } else {
            pollLoopTask?.cancel()
            pollLoopTask = nil
            eventStreamTask?.cancel()
            eventStreamTask = nil
            eventDrivenRefreshTask?.cancel()
            eventDrivenRefreshTask = nil
            refreshTask?.cancel()
            refreshTask = nil
            refreshStartedAt = nil
            refreshGeneration += 1
            lastTerminalMappingRefreshAt = nil
            lastMappedSessionIdentities = []
            lastTmuxClientEventVersion = nil
            windowAnnotations = [:]
            agentTabs = []
            watchSummary = .empty
            watchWindows = []
            terminalTabCountByWindowID = [:]
            lastObservedAgentTabAtBySessionID = [:]
        }
    }

    private func startEventStream() {
        eventStreamTask?.cancel()
        eventStreamTask = Task(priority: .utility) { [weak self] in
            await Self.consumeEventStream { eventType in
                guard eventType == "tmux_client_event" else {
                    return
                }

                await MainActor.run {
                    self?.scheduleEventDrivenRefresh()
                }
            }
        }
    }

    private func scheduleEventDrivenRefresh() {
        eventDrivenRefreshTask?.cancel()
        eventDrivenRefreshTask = Task { @MainActor [weak self] in
            let retryDelays: [UInt64] = [
                0,
                750_000_000,
                1_500_000_000
            ]

            for delay in retryDelays {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard !Task.isCancelled else {
                    return
                }
                self?.refresh(forceTerminalMapping: true)
            }
        }
    }

    private func startPolling() {
        pollLoopTask?.cancel()
        pollLoopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refresh()

                let nanoseconds = UInt64(max(self?.pollInterval ?? 0, 0.1) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
    }

    func refresh(forceTerminalMapping: Bool = false) {
        guard isEnabled else {
            windowAnnotations = [:]
            agentTabs = []
            watchSummary = .empty
            watchWindows = []
            terminalTabCountByWindowID = [:]
            return
        }

        if let refreshTask {
            let refreshAge = refreshStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            guard forceTerminalMapping || refreshAge > Self.refreshStaleTimeout else {
                return
            }

            if forceTerminalMapping {
                Self.writeDiagnostic("tmux client event; starting terminal mapping refresh")
            } else {
                Self.writeDiagnostic("refresh stale after \(String(format: "%.1f", refreshAge))s; starting replacement poll")
            }
            refreshTask.cancel()
            self.refreshTask = nil
            refreshStartedAt = nil
            refreshGeneration += 1
        }

        refreshGeneration += 1
        let generation = refreshGeneration
        refreshStartedAt = Date()
        let now = Date()
        let mappedSessionIdentities = lastMappedSessionIdentities
        let tmuxClientEventVersion = lastTmuxClientEventVersion
        let intervalRequiresTerminalMapping = lastTerminalMappingRefreshAt
            .map { now.timeIntervalSince($0) >= Self.terminalMappingRefreshInterval } ?? true
        let shouldRefreshTerminalMapping = forceTerminalMapping || intervalRequiresTerminalMapping
        refreshTask = Task { [weak self] in
            let result = await Self.fetchRefreshResult(
                lastMappedSessionIdentities: mappedSessionIdentities,
                lastTmuxClientEventVersion: tmuxClientEventVersion,
                shouldRefreshTerminalMapping: shouldRefreshTerminalMapping
            )

            await MainActor.run {
                guard let self else {
                    return
                }

                guard generation == self.refreshGeneration else {
                    return
                }

                defer {
                    self.refreshTask = nil
                    self.refreshStartedAt = nil
                }

                guard !Task.isCancelled, self.isEnabled else {
                    return
                }

                switch result {
                case .mapped(let payload):
                    if let eventVersion = payload.tmuxClientEventVersion {
                        self.lastTmuxClientEventVersion = eventVersion
                    }
                    self.lastTerminalMappingRefreshAt = Date()
                    self.lastMappedSessionIdentities = payload.value.sessionMappingIdentities
                    self.applyAgentTabFetchSnapshot(payload.value)
                case .sessions(let payload):
                    if let eventVersion = payload.tmuxClientEventVersion {
                        self.lastTmuxClientEventVersion = eventVersion
                    }
                    self.applySessionSnapshot(payload.value)
                case .sessionsWithoutTerminal(let payload):
                    if let eventVersion = payload.tmuxClientEventVersion {
                        self.lastTmuxClientEventVersion = eventVersion
                    }
                    self.lastTerminalMappingRefreshAt = nil
                    self.lastMappedSessionIdentities = []
                    self.applyTerminalUnavailableSessionSnapshot(payload.value)
                case .clear:
                    self.lastTerminalMappingRefreshAt = nil
                    self.lastMappedSessionIdentities = []
                    self.lastTmuxClientEventVersion = nil
                    self.lastObservedAgentTabAtBySessionID = [:]
                    self.windowAnnotations = [:]
                    self.agentTabs = []
                    self.watchSummary = .empty
                    self.watchWindows = []
                    self.terminalTabCountByWindowID = [:]
                case .failed:
                    Self.writeDiagnostic("fetch failed; keeping agentTabs=\(self.agentTabs.count)")
                }
            }
        }
    }

    private nonisolated static func fetchRefreshResult(
        lastMappedSessionIdentities: Set<SMSessionMappingIdentity>,
        lastTmuxClientEventVersion: Int?,
        shouldRefreshTerminalMapping: Bool
    ) async -> SMPluginRefreshResult {
        async let sessionsTask = fetchSessions()
        async let eventStateTask = fetchEventState()

        guard let sessions = await sessionsTask else {
            return .failed
        }
        let eventState = await eventStateTask
        let eventVersion = eventState?.tmuxClientEventVersion

        guard !sessions.isEmpty else {
            return .clear
        }

        let sessionMappingIdentities = mappingIdentities(for: sessions)
        let eventRequiresTerminalMapping = eventVersion.map { version in
            guard let lastTmuxClientEventVersion else {
                return false
            }

            return version != lastTmuxClientEventVersion
        } ?? false
        let needsTerminalMapping = shouldRefreshTerminalMapping ||
            eventRequiresTerminalMapping ||
            sessionMappingIdentities != lastMappedSessionIdentities
        guard needsTerminalMapping else {
            return .sessions(SMPluginRefreshPayload(
                value: sessions,
                tmuxClientEventVersion: eventVersion
            ))
        }

        let terminalIsRunning = await MainActor.run {
            isTerminalRunning
        }
        guard terminalIsRunning else {
            return .sessionsWithoutTerminal(SMPluginRefreshPayload(
                value: sessions,
                tmuxClientEventVersion: eventVersion
            ))
        }

        guard let snapshot = await fetchAgentTabAnnotations(for: sessions) else {
            return .failed
        }

        if eventRequiresTerminalMapping, let eventVersion {
            writeDiagnostic("tmux event state changed to \(eventVersion); refreshed terminal mapping")
        }

        return .mapped(SMPluginRefreshPayload(
            value: snapshot,
            tmuxClientEventVersion: eventVersion
        ))
    }

    private func applyAgentTabFetchSnapshot(_ snapshot: SMAgentTabFetchSnapshot) {
        let now = Date()
        let liveSessionIDs = snapshot.liveSessionIDs
        if watchSummary != snapshot.watchSummary {
            watchSummary = snapshot.watchSummary
        }
        if watchWindows != snapshot.watchWindows {
            watchWindows = snapshot.watchWindows
        }
        if terminalTabCountByWindowID != snapshot.terminalTabCountByWindowID {
            terminalTabCountByWindowID = snapshot.terminalTabCountByWindowID
        }
        let freshAnnotationsBySessionID = Dictionary(
            preservingFirstValues: snapshot.annotations.map { ($0.sessionID, $0) }
        )
        let previousAnnotationsBySessionID = Dictionary(
            preservingFirstValues: agentTabs.map { ($0.sessionID, $0) }
        )

        var mergedAnnotationsBySessionID: [String: SMAgentWindowAnnotation] = [:]
        for sessionID in liveSessionIDs {
            if let freshAnnotation = freshAnnotationsBySessionID[sessionID] {
                mergedAnnotationsBySessionID[sessionID] = freshAnnotation
                lastObservedAgentTabAtBySessionID[sessionID] = now
                continue
            }

            guard
                let previousAnnotation = previousAnnotationsBySessionID[sessionID]
            else {
                continue
            }

            let lastObservedAt = lastObservedAgentTabAtBySessionID[sessionID] ?? now
            guard now.timeIntervalSince(lastObservedAt) <= Self.staleAnnotationRetention else {
                continue
            }

            mergedAnnotationsBySessionID[sessionID] = previousAnnotation
            lastObservedAgentTabAtBySessionID[sessionID] = lastObservedAt
        }

        lastObservedAgentTabAtBySessionID = lastObservedAgentTabAtBySessionID.filter { sessionID, lastObservedAt in
            liveSessionIDs.contains(sessionID) &&
                now.timeIntervalSince(lastObservedAt) <= Self.staleAnnotationRetention
        }

        let mergedAnnotations = Self.sortedAnnotations(Array(mergedAnnotationsBySessionID.values))
        if agentTabs != mergedAnnotations {
            agentTabs = mergedAnnotations
        }

        let selectedWindowAnnotations = Self.selectedWindowAnnotations(from: mergedAnnotations)
        if windowAnnotations != selectedWindowAnnotations {
            windowAnnotations = selectedWindowAnnotations
        }
    }

    private func applySessionSnapshot(_ sessions: [SMSessionSnapshot]) {
        guard !sessions.isEmpty else {
            lastObservedAgentTabAtBySessionID = [:]
            windowAnnotations = [:]
            agentTabs = []
            watchSummary = .empty
            watchWindows = []
            terminalTabCountByWindowID = [:]
            return
        }

        let summary = SMWatchSummary(sessions: sessions)
        if watchSummary != summary {
            watchSummary = summary
        }

        let liveSessionIDs = Set(sessions.map(\.id))
        let sessionsByID = Dictionary(preservingFirstValues: sessions.map { ($0.id, $0) })
        let updatedAnnotations = agentTabs.compactMap { annotation -> SMAgentWindowAnnotation? in
            guard let session = sessionsByID[annotation.sessionID] else {
                return nil
            }

            return Self.annotation(annotation, updatedWith: session)
        }

        lastObservedAgentTabAtBySessionID = lastObservedAgentTabAtBySessionID.filter { sessionID, _ in
            liveSessionIDs.contains(sessionID)
        }

        let sortedAnnotations = Self.sortedAnnotations(updatedAnnotations)
        if agentTabs != sortedAnnotations {
            agentTabs = sortedAnnotations
        }

        let selectedWindowAnnotations = Self.selectedWindowAnnotations(from: sortedAnnotations)
        if windowAnnotations != selectedWindowAnnotations {
            windowAnnotations = selectedWindowAnnotations
        }
    }

    private func applyTerminalUnavailableSessionSnapshot(_ sessions: [SMSessionSnapshot]) {
        let summary = SMWatchSummary(sessions: sessions)
        if watchSummary != summary {
            watchSummary = summary
        }

        lastObservedAgentTabAtBySessionID = [:]
        if windowAnnotations != [:] {
            windowAnnotations = [:]
        }
        if agentTabs != [] {
            agentTabs = []
        }
        if watchWindows != [] {
            watchWindows = []
        }
        if terminalTabCountByWindowID != [:] {
            terminalTabCountByWindowID = [:]
        }
    }

    func openOrActivateWatch() {
        Task.detached(priority: .userInitiated) {
            let watchWindows = await Self.fetchSMWatchWindowAnnotations(summary: .empty)
            let target = watchWindows.first(where: \.isSelectedTerminalTab) ?? watchWindows.first
            if let target {
                Self.activateTerminalTab(
                    windowID: target.terminalWindowID,
                    tty: target.terminalTTY
                )
            } else {
                Self.openSMWatchTerminal()
            }
        }
    }

    func openNewWatchWindow() {
        Task.detached(priority: .userInitiated) {
            Self.openSMWatchTerminal()
        }
    }

    func activate(annotation: SMAgentWindowAnnotation) {
        Task.detached(priority: .userInitiated) {
            guard annotation.isLocalTerminalBacked else {
                return
            }

            Self.activateTerminalTab(
                windowID: annotation.terminalWindowID,
                tty: annotation.terminalTTY
            )
        }
    }

    func openTerminalLike(annotation: SMAgentWindowAnnotation, inWorkingDirectory: Bool) {
        Task.detached(priority: .userInitiated) {
            guard annotation.isLocalTerminalBacked else {
                return
            }

            Self.openTerminalLike(
                frame: annotation.terminalFrame,
                workingDirectory: annotation.workingDirectory,
                inWorkingDirectory: inWorkingDirectory
            )
        }
    }

    func rename(annotation: SMAgentWindowAnnotation, presentationView: NSView?) {
        renamePopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = SMPluginRenameViewController.preferredSize
        popover.contentViewController = SMPluginRenameViewController(
            annotation: annotation,
            onRename: { [weak self, weak popover] newName in
                popover?.close()
                self?.renamePopover = nil
                self?.submitRename(
                    annotation: annotation,
                    newName: newName
                )
            },
            onCancel: { [weak self, weak popover] in
                popover?.close()
                self?.renamePopover = nil
            }
        )

        renamePopover = popover
        NSApp.activate(ignoringOtherApps: true)

        let hostView = renamePopoverHostView(preferredView: presentationView)
        guard let hostView else {
            renamePopover = nil
            Self.presentRenameFailureAlert(message: "DeskBar could not find a window to present rename.")
            return
        }

        popover.show(
            relativeTo: hostView.bounds,
            of: hostView,
            preferredEdge: .maxY
        )
    }

    private func submitRename(annotation: SMAgentWindowAnnotation, newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, trimmedName != annotation.friendlyName else {
            return
        }

        Task.detached(priority: .userInitiated) {
            let result = await Self.renameAgentViaAPI(
                sessionID: annotation.sessionID,
                newName: trimmedName
            )

            await MainActor.run { [weak self] in
                guard result.success else {
                    Self.presentRenameFailureAlert(message: result.errorMessage)
                    return
                }

                self?.refresh()
            }
        }
    }

    private func renamePopoverHostView(preferredView: NSView?) -> NSView? {
        if let preferredView, preferredView.window != nil {
            return preferredView
        }

        if let contentView = NSApp.mainWindow?.contentView, contentView.window != nil {
            return contentView
        }

        return NSApp.windows
            .lazy
            .compactMap(\.contentView)
            .first { $0.window != nil }
    }

    func retire(annotation: SMAgentWindowAnnotation, closeTerminal: Bool) {
        Task.detached(priority: .userInitiated) {
            let didRetire = await Self.retireAgent(sessionID: annotation.sessionID)
            guard didRetire else {
                return
            }

            guard closeTerminal else {
                return
            }

            guard annotation.isLocalTerminalBacked else {
                return
            }

            try? await Task.sleep(nanoseconds: 1_000_000_000)
            Self.closeTerminalTab(
                windowID: annotation.terminalWindowID,
                tty: annotation.terminalTTY
            )
        }
    }

    nonisolated static func makeAgentTabAnnotations(
        sessions: [SMSessionSnapshot],
        tmuxClients: [SMTmuxClientSnapshot],
        terminalTabs: [SMTerminalTabSnapshot]
    ) -> [SMAgentWindowAnnotation] {
        var sessionsByTmuxName: [String: SMSessionSnapshot] = [:]
        sessions.forEach { sessionsByTmuxName[$0.tmuxSession] = $0 }

        var tmuxSessionByTTY: [String: String] = [:]
        tmuxClients.forEach { tmuxSessionByTTY[$0.tty] = $0.tmuxSession }

        var annotationsBySessionID: [String: SMAgentWindowAnnotation] = [:]
        for terminalTab in terminalTabs {
            guard
                let tmuxSession = tmuxSessionByTTY[terminalTab.tty],
                let session = sessionsByTmuxName[tmuxSession]
            else {
                continue
            }

            let annotation = SMAgentWindowAnnotation(
                sessionID: session.id,
                friendlyName: session.displayName,
                workingDirectory: session.workingDirectory,
                node: session.node,
                provider: session.provider,
                sessionStatus: session.status,
                activityState: session.activityState,
                currentTask: session.currentTask,
                agentStatusText: session.agentStatusText,
                lastToolName: session.lastToolName,
                lastActionSummary: session.lastActionSummary,
                tokensUsed: session.tokensUsed,
                tmuxSession: session.tmuxSession,
                terminalWindowID: terminalTab.windowID,
                terminalTTY: terminalTab.tty,
                terminalFrame: terminalTab.frame,
                isSelectedTerminalTab: terminalTab.isSelected
            )

            if annotationsBySessionID[session.id]?.isSelectedTerminalTab != true {
                annotationsBySessionID[session.id] = annotation
            }
        }
        return sortedAnnotations(Array(annotationsBySessionID.values))
    }

    private nonisolated static func annotation(
        _ annotation: SMAgentWindowAnnotation,
        updatedWith session: SMSessionSnapshot
    ) -> SMAgentWindowAnnotation {
        SMAgentWindowAnnotation(
            sessionID: session.id,
            friendlyName: session.displayName,
            workingDirectory: session.workingDirectory,
            node: session.node,
            provider: session.provider,
            sessionStatus: session.status,
            activityState: session.activityState,
            currentTask: session.currentTask,
            agentStatusText: session.agentStatusText,
            lastToolName: session.lastToolName,
            lastActionSummary: session.lastActionSummary,
            tokensUsed: session.tokensUsed,
            tmuxSession: session.tmuxSession,
            terminalWindowID: annotation.terminalWindowID,
            terminalTTY: annotation.terminalTTY,
            terminalFrame: annotation.terminalFrame,
            isSelectedTerminalTab: annotation.isSelectedTerminalTab
        )
    }

    private nonisolated static func mappingIdentities(for sessions: [SMSessionSnapshot]) -> Set<SMSessionMappingIdentity> {
        Set(sessions.map {
            SMSessionMappingIdentity(
                id: $0.id,
                tmuxSession: $0.tmuxSession,
                tmuxSocketName: $0.tmuxSocketName
            )
        })
    }

    private nonisolated static func sortedAnnotations(
        _ annotations: [SMAgentWindowAnnotation]
    ) -> [SMAgentWindowAnnotation] {
        annotations.sorted {
            if $0.isLocalTerminalBacked != $1.isLocalTerminalBacked {
                return $0.isLocalTerminalBacked
            }

            if $0.terminalWindowID != $1.terminalWindowID {
                return $0.terminalWindowID < $1.terminalWindowID
            }

            return $0.sessionID < $1.sessionID
        }
    }

    private static var isTerminalRunning: Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: terminalBundleIdentifier
        ).isEmpty
    }

    private nonisolated static func consumeEventStream(
        onEvent: @escaping (String) async -> Void
    ) async {
        while !Task.isCancelled {
            guard let eventsURL = SMClientConfiguration.apiURL(path: "/events") else {
                return
            }

            var request = URLRequest(url: eventsURL)
            request.timeoutInterval = 65
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    writeDiagnostic("event stream returned HTTP \(httpResponse.statusCode)")
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    continue
                }

                var currentEventType: String?
                for try await line in bytes.lines {
                    if Task.isCancelled {
                        return
                    }

                    if line.hasPrefix("event:") {
                        currentEventType = String(line.dropFirst("event:".count))
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        continue
                    }

                    if line.isEmpty {
                        if let currentEventType, !currentEventType.isEmpty {
                            await onEvent(currentEventType)
                        }
                        currentEventType = nil
                    }
                }
            } catch {
                if Task.isCancelled {
                    return
                }
                writeDiagnostic("event stream failed; reconnecting")
            }

            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    private nonisolated static func fetchAgentTabAnnotations() async -> SMAgentTabFetchSnapshot? {
        guard let sessions = await fetchSessions() else {
            writeDiagnostic("sessions fetch failed")
            return nil
        }

        return await fetchAgentTabAnnotations(for: sessions)
    }

    private nonisolated static func fetchAgentTabAnnotations(
        for sessions: [SMSessionSnapshot]
    ) async -> SMAgentTabFetchSnapshot? {
        guard !sessions.isEmpty else {
            return SMAgentTabFetchSnapshot(
                annotations: [],
                watchWindows: [],
                watchSummary: .empty,
                liveSessionIDs: [],
                terminalTabCountByWindowID: [:],
                sessionMappingIdentities: []
            )
        }

        return await Task.detached(priority: .utility) {
            let watchSummary = SMWatchSummary(sessions: sessions)
            let sessionMappingIdentities = mappingIdentities(for: sessions)
            guard let terminalTabs = fetchTerminalTabs() else {
                writeDiagnostic("terminal tabs fetch failed for sessions=\(sessions.count)")
                return nil
            }

            guard !terminalTabs.isEmpty else {
                writeDiagnostic("terminal tabs empty for live sessions=\(sessions.count); clearing local annotations")
                return SMAgentTabFetchSnapshot(
                    annotations: [],
                    watchWindows: [],
                    watchSummary: watchSummary,
                    liveSessionIDs: [],
                    terminalTabCountByWindowID: [:],
                    sessionMappingIdentities: []
                )
            }
            let terminalTabCountByWindowID = terminalTabCountByWindowID(from: terminalTabs)
            let watchWindows = makeSMWatchWindowAnnotations(
                terminalTabs: terminalTabs,
                summary: watchSummary
            )

            let tmuxSessionNames = Set(sessions.map(\.tmuxSession))
            let listedClients = fetchTmuxClients(for: sessions)
            var clientsByTTY = Dictionary(
                preservingFirstValues: (listedClients ?? []).map { ($0.tty, $0) }
            )
            let terminalTabClients = fetchTmuxClientsFromTerminalTabs(
                terminalTabs,
                matching: tmuxSessionNames,
                shouldWriteEmptyDiagnostic: clientsByTTY.isEmpty
            )
            for client in terminalTabClients {
                clientsByTTY[client.tty] = client
            }
            let clients = clientsByTTY.values.sorted { $0.tty < $1.tty }

            guard !clients.isEmpty else {
                let reason = listedClients == nil ? "fetch failed" : "empty"
                writeDiagnostic("tmux clients \(reason) for live sessions=\(sessions.count); updating SM watch summary")
                return SMAgentTabFetchSnapshot(
                    annotations: [],
                    watchWindows: watchWindows,
                    watchSummary: watchSummary,
                    liveSessionIDs: Set(sessions.map(\.id)),
                    terminalTabCountByWindowID: terminalTabCountByWindowID,
                    sessionMappingIdentities: sessionMappingIdentities
                )
            }

            let annotations = makeAgentTabAnnotations(
                sessions: sessions,
                tmuxClients: clients,
                terminalTabs: terminalTabs
            )
            return SMAgentTabFetchSnapshot(
                annotations: annotations,
                watchWindows: watchWindows,
                watchSummary: watchSummary,
                liveSessionIDs: Set(sessions.map(\.id)),
                terminalTabCountByWindowID: terminalTabCountByWindowID,
                sessionMappingIdentities: sessionMappingIdentities
            )
        }.value
    }

    private nonisolated static func terminalTabCountByWindowID(
        from terminalTabs: [SMTerminalTabSnapshot]
    ) -> [CGWindowID: Int] {
        var tabCountByWindowID: [CGWindowID: Int] = [:]
        for terminalTab in terminalTabs {
            tabCountByWindowID[terminalTab.windowID, default: 0] += 1
        }

        return tabCountByWindowID
    }

    private nonisolated static func fetchSessions() async -> [SMSessionSnapshot]? {
        guard let sessionsURL = SMClientConfiguration.apiURL(path: "/sessions") else {
            return nil
        }

        var request = URLRequest(url: sessionsURL)
        request.timeoutInterval = 0.75

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(SMSessionsResponse.self, from: data)
            return response.sessions.compactMap { session in
                guard !session.tmuxSession.isEmpty else {
                    return nil
                }

                return SMSessionSnapshot(
                    id: session.id,
                    friendlyName: session.friendlyName,
                    workingDirectory: session.workingDirectory,
                    node: session.node,
                    provider: session.provider ?? "sm",
                    status: session.status,
                    activityState: SMAgentActivityState(rawValue: session.activityState),
                    currentTask: session.currentTask,
                    agentStatusText: session.agentStatusText,
                    lastToolName: session.lastToolName,
                    lastActionSummary: session.lastActionSummary,
                    tokensUsed: session.tokensUsed,
                    tmuxSession: session.tmuxSession,
                    tmuxSocketName: session.tmuxSocketName
                )
            }
        } catch {
            return nil
        }
    }

    private nonisolated static func fetchEventState() async -> SMEventStateResponse? {
        guard let eventStateURL = SMClientConfiguration.apiURL(path: "/events/state") else {
            return nil
        }

        var request = URLRequest(url: eventStateURL)
        request.timeoutInterval = 0.75

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(SMEventStateResponse.self, from: data)
        } catch {
            return nil
        }
    }

    private nonisolated static func fetchTmuxClients(for sessions: [SMSessionSnapshot]) -> [SMTmuxClientSnapshot]? {
        let tmuxSessionNames = Set(sessions.map(\.tmuxSession))
        let socketNames = Set(sessions.map(\.tmuxSocketName))
        var clients: [SMTmuxClientSnapshot] = []
        var hadCommandFailure = false
        for socketName in socketNames {
            guard let socketClients = fetchTmuxClients(socketName: socketName) else {
                hadCommandFailure = true
                continue
            }

            clients.append(contentsOf: socketClients)
        }

        let matchingClients = clients.filter { tmuxSessionNames.contains($0.tmuxSession) }
        if !matchingClients.isEmpty {
            return matchingClients
        }

        let processClients = fetchTmuxClientsFromProcessTable(matching: tmuxSessionNames)
        if !processClients.isEmpty {
            writeDiagnostic("using process-table tmux clients=\(processClients.count) after list-clients=\(clients.count)")
            return processClients
        }

        return hadCommandFailure ? nil : []
    }

    private nonisolated static func fetchTmuxClients(socketName: String?) -> [SMTmuxClientSnapshot]? {
        guard let tmuxExecutablePath = tmuxExecutablePath() else {
            return nil
        }

        var arguments: [String] = []
        if let socketName, !socketName.isEmpty {
            arguments.append(contentsOf: ["-L", socketName])
        }
        arguments.append(contentsOf: ["list-clients", "-F", "#{client_tty}\t#{client_session}"])

        guard let output = runCommand(tmuxExecutablePath, arguments: arguments) else {
            return nil
        }

        return output
            .split(separator: "\n")
            .compactMap { line in
                let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard columns.count >= 2 else {
                    return nil
                }

                let tty = String(columns[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let tmuxSession = String(columns[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tty.isEmpty, !tmuxSession.isEmpty else {
                    return nil
                }

                return SMTmuxClientSnapshot(tty: tty, tmuxSession: tmuxSession)
            }
    }

    private nonisolated static func tmuxExecutablePath() -> String? {
        let candidatePaths = [
            "/opt/homebrew/bin/tmux",
            "/usr/local/bin/tmux",
            "/usr/bin/tmux",
            "/bin/tmux"
        ]

        return candidatePaths.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private nonisolated static func fetchTmuxClientsFromProcessTable(
        matching tmuxSessionNames: Set<String>
    ) -> [SMTmuxClientSnapshot] {
        guard
            !tmuxSessionNames.isEmpty,
            let output = runCommand("/bin/ps", arguments: ["-axo", "tty=,command="])
        else {
            return []
        }

        var clientsByTTY: [String: SMTmuxClientSnapshot] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(
                maxSplits: 1,
                omittingEmptySubsequences: true,
                whereSeparator: { $0.isWhitespace }
            )
            guard parts.count == 2 else {
                continue
            }

            let tty = String(parts[0])
            guard tty != "??" else {
                continue
            }

            let command = String(parts[1])
            guard let tmuxSession = tmuxAttachTarget(in: command),
                  tmuxSessionNames.contains(tmuxSession)
            else {
                continue
            }

            let ttyPath = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
            clientsByTTY[ttyPath] = SMTmuxClientSnapshot(
                tty: ttyPath,
                tmuxSession: tmuxSession
            )
        }

        return clientsByTTY.values.sorted { $0.tty < $1.tty }
    }

    private nonisolated static func fetchTmuxClientsFromTerminalTabs(
        _ terminalTabs: [SMTerminalTabSnapshot],
        matching tmuxSessionNames: Set<String>,
        shouldWriteEmptyDiagnostic: Bool = true
    ) -> [SMTmuxClientSnapshot] {
        guard !tmuxSessionNames.isEmpty else {
            return []
        }

        var clientsByTTY: [String: SMTmuxClientSnapshot] = [:]
        var psFailureCount = 0
        var commandLineCount = 0
        var tmuxLineCount = 0
        for terminalTab in terminalTabs {
            let ttyName = terminalTab.tty.replacingOccurrences(of: "/dev/", with: "")
            guard !ttyName.isEmpty else {
                continue
            }

            guard let output = runCommand(
                    "/bin/ps",
                    arguments: ["-t", ttyName, "-o", "command="],
                    timeout: 2.0
                  )
            else {
                psFailureCount += 1
                continue
            }

            for commandLine in output.split(separator: "\n") {
                commandLineCount += 1
                if commandLine.contains("tmux") {
                    tmuxLineCount += 1
                }
                guard let tmuxSession = tmuxAttachTarget(in: String(commandLine)),
                      tmuxSessionNames.contains(tmuxSession)
                else {
                    continue
                }

                clientsByTTY[terminalTab.tty] = SMTmuxClientSnapshot(
                    tty: terminalTab.tty,
                    tmuxSession: tmuxSession
                )
                break
            }
        }

        if clientsByTTY.isEmpty, shouldWriteEmptyDiagnostic {
            writeDiagnostic(
                "tty fallback no matches tabs=\(terminalTabs.count) psFailures=\(psFailureCount) commandLines=\(commandLineCount) tmuxLines=\(tmuxLineCount)"
            )
        }

        return clientsByTTY.values.sorted { $0.tty < $1.tty }
    }

    private nonisolated static func fetchSMWatchWindowAnnotations(
        summary: SMWatchSummary
    ) async -> [SMWatchWindowAnnotation] {
        await Task.detached(priority: .utility) {
            guard let terminalTabs = fetchTerminalTabs() else {
                return []
            }

            return makeSMWatchWindowAnnotations(
                terminalTabs: terminalTabs,
                summary: summary
            )
        }.value
    }

    private nonisolated static func makeSMWatchWindowAnnotations(
        terminalTabs: [SMTerminalTabSnapshot],
        summary: SMWatchSummary
    ) -> [SMWatchWindowAnnotation] {
        var annotationsByTTY: [String: SMWatchWindowAnnotation] = [:]

        for terminalTab in terminalTabs {
            let ttyName = terminalTab.tty.replacingOccurrences(of: "/dev/", with: "")
            guard !ttyName.isEmpty,
                  let output = runCommand(
                    "/bin/ps",
                    arguments: ["-t", ttyName, "-o", "command="],
                    timeout: 2.0
                  )
            else {
                continue
            }

            guard output
                .split(separator: "\n")
                .contains(where: { commandLooksLikeSMWatch(String($0)) })
            else {
                continue
            }

            annotationsByTTY[terminalTab.tty] = SMWatchWindowAnnotation(
                terminalWindowID: terminalTab.windowID,
                terminalTTY: terminalTab.tty,
                terminalFrame: terminalTab.frame,
                isSelectedTerminalTab: terminalTab.isSelected,
                summary: summary
            )
        }

        return annotationsByTTY.values.sorted {
            if $0.isSelectedTerminalTab != $1.isSelectedTerminalTab {
                return $0.isSelectedTerminalTab
            }

            if $0.terminalWindowID != $1.terminalWindowID {
                return $0.terminalWindowID < $1.terminalWindowID
            }

            return $0.terminalTTY < $1.terminalTTY
        }
    }

    nonisolated static func commandLooksLikeSMWatch(_ command: String) -> Bool {
        let tokens = command
            .split(whereSeparator: { $0.isWhitespace })
            .map { cleanShellToken(String($0)) }
            .filter { !$0.isEmpty }

        for index in tokens.indices {
            let token = tokens[index]
            let executableName = (token as NSString).lastPathComponent
            if executableName == "sm",
               commandToken(after: index, in: tokens) == "watch" {
                return true
            }

            if isLegacySMWatchEntrypoint(token),
               commandToken(after: index, in: tokens) == "watch" {
                return true
            }
        }

        return false
    }

    private nonisolated static func isLegacySMWatchEntrypoint(_ token: String) -> Bool {
        let normalized = token.replacingOccurrences(of: "\\", with: "/")
        return normalized.hasSuffix("/session-manager/src/cli/main.py") ||
            normalized.hasSuffix("/session-manager/src/cli/commands.py") ||
            normalized.hasSuffix("/session-manager/src/cli/watch_tui.py")
    }

    private nonisolated static func commandToken(after index: Int, in tokens: [String]) -> String? {
        var tokenIndex = index + 1
        while tokenIndex < tokens.count {
            let token = tokens[tokenIndex]
            if token == "--api-url", tokenIndex + 1 < tokens.count {
                tokenIndex += 2
                continue
            }
            if token.hasPrefix("--api-url=") {
                tokenIndex += 1
                continue
            }
            return token
        }

        return nil
    }

    nonisolated static func tmuxAttachTarget(in command: String) -> String? {
        let tokens = command
            .split(whereSeparator: { $0.isWhitespace })
            .map { cleanShellToken(String($0)) }
        guard tokens.contains(where: { $0 == "tmux" || $0.hasSuffix("/tmux") }) else {
            return nil
        }

        var sawAttachCommand = false
        for index in tokens.indices {
            let token = tokens[index]
            if token == "attach" || token == "attach-session" {
                sawAttachCommand = true
                continue
            }

            guard sawAttachCommand else {
                continue
            }

            if token == "-t", tokens.indices.contains(index + 1) {
                return cleanShellToken(tokens[index + 1])
            }

            if token.hasPrefix("-t"), token.count > 2 {
                return cleanShellToken(String(token.dropFirst(2)))
            }
        }

        return nil
    }

    private nonisolated static func cleanShellToken(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet(charactersIn: "'\";"))
    }

    private nonisolated static func smExecutablePath() -> String? {
        let candidatePaths = [
            "/Users/rajesh/Desktop/automation/session-manager/venv/bin/sm",
            "/opt/homebrew/bin/sm",
            "/usr/local/bin/sm",
            "/usr/bin/sm",
            "/bin/sm"
        ]

        return candidatePaths.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private nonisolated static func fetchTerminalTabs() -> [SMTerminalTabSnapshot]? {
        let script = """
        set fieldDelimiter to ASCII character 9
        set oldDelimiters to AppleScript's text item delimiters
        set AppleScript's text item delimiters to linefeed
        set rows to {}
        tell application id "com.apple.Terminal"
            repeat with terminalWindow in windows
                try
                    set windowID to id of terminalWindow
                    set windowBounds to bounds of terminalWindow
                    repeat with terminalTab in tabs of terminalWindow
                        set tabTTY to tty of terminalTab
                        set tabSelected to selected of terminalTab
                        set end of rows to (windowID as text) & fieldDelimiter & tabTTY & fieldDelimiter & (tabSelected as text) & fieldDelimiter & (item 1 of windowBounds as text) & fieldDelimiter & (item 2 of windowBounds as text) & fieldDelimiter & (item 3 of windowBounds as text) & fieldDelimiter & (item 4 of windowBounds as text)
                    end repeat
                end try
            end repeat
        end tell
        set renderedRows to rows as text
        set AppleScript's text item delimiters to oldDelimiters
        return renderedRows
        """

        guard let output = runCommand("/usr/bin/osascript", arguments: ["-e", script], timeout: 5.0) else {
            return nil
        }

        return output
            .split(separator: "\n")
            .compactMap { line in
                let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard columns.count >= 7,
                      let windowID = CGWindowID(String(columns[0]).trimmingCharacters(in: .whitespacesAndNewlines))
                else {
                    return nil
                }

                let tty = String(columns[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !tty.isEmpty else {
                    return nil
                }

                let isSelected = String(columns[2])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare("true") == .orderedSame

                let frame = terminalFrame(
                    left: String(columns[3]),
                    top: String(columns[4]),
                    right: String(columns[5]),
                    bottom: String(columns[6])
                )

                return SMTerminalTabSnapshot(
                    windowID: windowID,
                    tty: tty,
                    frame: frame,
                    isSelected: isSelected
                )
            }
    }

    private nonisolated static func terminalFrame(
        left: String,
        top: String,
        right: String,
        bottom: String
    ) -> CGRect? {
        guard
            let left = Double(left.trimmingCharacters(in: .whitespacesAndNewlines)),
            let top = Double(top.trimmingCharacters(in: .whitespacesAndNewlines)),
            let right = Double(right.trimmingCharacters(in: .whitespacesAndNewlines)),
            let bottom = Double(bottom.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return nil
        }

        let width = right - left
        let height = bottom - top
        guard width > 0, height > 0 else {
            return nil
        }

        return CGRect(x: left, y: top, width: width, height: height)
    }

    private nonisolated static func selectedWindowAnnotations(
        from annotations: [SMAgentWindowAnnotation]
    ) -> [CGWindowID: SMAgentWindowAnnotation] {
        var selectedAnnotations: [CGWindowID: SMAgentWindowAnnotation] = [:]
        for annotation in annotations where annotation.isSelectedTerminalTab {
            selectedAnnotations[annotation.terminalWindowID] = annotation
        }
        return selectedAnnotations
    }

    private nonisolated static func activateTerminalTab(windowID: CGWindowID, tty: String) {
        let escapedTTY = tty.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        set targetWindowID to \(windowID)
        set targetTTY to "\(escapedTTY)"
        tell application id "com.apple.Terminal"
            repeat with terminalWindow in windows
                if id of terminalWindow is targetWindowID then
                    repeat with terminalTab in tabs of terminalWindow
                        if tty of terminalTab is targetTTY then
                            set selected tab of terminalWindow to terminalTab
                            set index of terminalWindow to 1
                            activate
                            return
                        end if
                    end repeat
                end if
            end repeat
        end tell
        """

        _ = runCommand("/usr/bin/osascript", arguments: ["-e", script])
    }

    private nonisolated static func openTerminalLike(
        frame: CGRect?,
        workingDirectory: String,
        inWorkingDirectory: Bool
    ) {
        let workingDirectoryLiteral = appleScriptStringLiteral(workingDirectory)
        let shouldChangeDirectory = inWorkingDirectory ? "true" : "false"
        let boundsScript: String
        if let frame {
            let left = Int(frame.minX.rounded())
            let top = Int(frame.minY.rounded())
            let right = Int(frame.maxX.rounded())
            let bottom = Int(frame.maxY.rounded())
            boundsScript = "set bounds of front window to {\(left), \(top), \(right), \(bottom)}"
        } else {
            boundsScript = ""
        }

        let script = """
        set targetDirectory to \(workingDirectoryLiteral)
        set shouldChangeDirectory to \(shouldChangeDirectory)
        tell application id "com.apple.Terminal"
            activate
            set newTab to do script ""
            delay 0.05
            try
                \(boundsScript)
            end try
            if shouldChangeDirectory then
                do script "cd " & quoted form of targetDirectory & "; clear" in newTab
            end if
        end tell
        """

        _ = runCommand("/usr/bin/osascript", arguments: ["-e", script])
    }

    private nonisolated static func openSMWatchTerminal(frame: CGRect? = nil) {
        let boundsScript: String
        if let frame {
            let left = Int(frame.minX.rounded())
            let top = Int(frame.minY.rounded())
            let right = Int(frame.maxX.rounded())
            let bottom = Int(frame.maxY.rounded())
            boundsScript = "set bounds of front window to {\(left), \(top), \(right), \(bottom)}"
        } else {
            boundsScript = ""
        }

        let script = """
        tell application id "com.apple.Terminal"
            activate
            set newTab to do script "sm watch"
            delay 0.05
            try
                \(boundsScript)
            end try
        end tell
        """

        _ = runCommand("/usr/bin/osascript", arguments: ["-e", script])
    }

    private nonisolated static func retireAgent(sessionID: String) async -> Bool {
        if await retireAgentViaAPI(sessionID: sessionID) {
            return true
        }

        guard let smExecutablePath = smExecutablePath() else {
            return false
        }

        return runCommand(
            smExecutablePath,
            arguments: ["retire", sessionID],
            timeout: retireTimeout
        ) != nil
    }

    private nonisolated static func renameAgentViaAPI(
        sessionID: String,
        newName: String
    ) async -> (success: Bool, errorMessage: String?) {
        guard
            let encodedSessionID = sessionID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let renameURL = SMClientConfiguration.apiURL(path: "/sessions/\(encodedSessionID)")
        else {
            return (false, "Invalid session id.")
        }

        var request = URLRequest(url: renameURL)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["friendly_name": newName])
        request.timeoutInterval = retireTimeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, "No response from Session Manager.")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                return (false, apiErrorMessage(from: data) ?? "Session Manager returned \(httpResponse.statusCode).")
            }

            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private nonisolated static func apiErrorMessage(from data: Data) -> String? {
        guard
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let detail = payload["detail"]
        else {
            return nil
        }

        if let message = detail as? String {
            return message
        }

        if let detailPayload = detail as? [String: Any],
           let message = detailPayload["message"] as? String {
            return message
        }

        return nil
    }

    @MainActor
    private static func presentRenameFailureAlert(message: String?) {
        let alert = NSAlert()
        alert.messageText = "Rename Failed"
        alert.informativeText = message ?? "DeskBar could not rename this session."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private nonisolated static func retireAgentViaAPI(sessionID: String) async -> Bool {
        guard
            let encodedSessionID = sessionID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let retireURL = SMClientConfiguration.apiURL(path: "/sessions/\(encodedSessionID)/kill")
        else {
            return false
        }

        var request = URLRequest(url: retireURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = retireTimeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return false
            }

            guard
                let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                payload["error"] == nil
            else {
                return false
            }

            return payload["status"] as? String == "killed"
        } catch {
            return false
        }
    }

    private nonisolated static func closeTerminalTab(windowID: CGWindowID, tty: String) {
        let escapedTTY = tty.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        set targetWindowID to \(windowID)
        set targetTTY to "\(escapedTTY)"
        set shouldCreateReplacementTab to false
        set didSelectTargetTab to false
        set targetBounds to missing value

        tell application id "com.apple.Terminal"
            repeat with terminalWindow in windows
                if id of terminalWindow is targetWindowID then
                    set shouldCreateReplacementTab to ((count of tabs of terminalWindow) is less than or equal to 1)
                    set targetBounds to bounds of terminalWindow
                    repeat with terminalTab in tabs of terminalWindow
                        if tty of terminalTab is targetTTY then
                            set selected tab of terminalWindow to terminalTab
                            set index of terminalWindow to 1
                            activate
                            set didSelectTargetTab to true
                            exit repeat
                        end if
                    end repeat
                    exit repeat
                end if
            end repeat
        end tell

        if didSelectTargetTab is false then
            return "not-found"
        end if

        delay 0.1

        if shouldCreateReplacementTab then
            tell application "System Events" to tell process "Terminal"
                keystroke "t" using command down
            end tell
            delay 0.3

            tell application id "com.apple.Terminal"
                repeat with terminalWindow in windows
                    if id of terminalWindow is targetWindowID then
                        repeat with terminalTab in tabs of terminalWindow
                            if tty of terminalTab is targetTTY then
                                set selected tab of terminalWindow to terminalTab
                                set index of terminalWindow to 1
                                activate
                                exit repeat
                            end if
                        end repeat
                        exit repeat
                    end if
                end repeat
            end tell
            delay 0.1
        end if

        set didConfirmTerminate to false
        tell application "System Events" to tell process "Terminal"
            keystroke "w" using command down
            repeat 30 times
                delay 0.1
                if (count of windows) > 0 and (count of sheets of window 1) > 0 then
                    set confirmationSheet to sheet 1 of window 1
                    if exists button "Terminate" of confirmationSheet then
                        click button "Terminate" of confirmationSheet
                        set didConfirmTerminate to true
                        exit repeat
                    end if
                end if
            end repeat
        end tell

        if shouldCreateReplacementTab and targetBounds is not missing value then
            delay 0.1
            tell application id "com.apple.Terminal"
                try
                    set bounds of front window to targetBounds
                end try
            end tell
        end if

        if didConfirmTerminate then
            return "terminated"
        end if

        return "closed"
        """

        _ = runCommand("/usr/bin/osascript", arguments: ["-e", script], timeout: 6.0)
    }

    private nonisolated static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private nonisolated static func runCommand(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = commandTimeout
    ) -> String? {
        autoreleasepool {
            let result = runCommandResult(
                executable,
                arguments: arguments,
                timeout: timeout
            )

            guard !result.didTimeOut, result.terminationStatus == 0 else {
                writeCommandFailureDiagnostic(
                    executable: executable,
                    result: result
                )
                return nil
            }

            return String(data: result.stdout, encoding: .utf8)
        }
    }

    private nonisolated static func runCommandResult(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> SMCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        let stdoutBuffer = SMCommandOutputBuffer()
        let stderrBuffer = SMCommandOutputBuffer()

        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stdoutBuffer.append(data)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                stderrBuffer.append(data)
            }
        }

        defer {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            try? stdout.fileHandleForReading.close()
            try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForReading.close()
            try? stderr.fileHandleForWriting.close()
        }

        do {
            try process.run()
        } catch {
            return SMCommandResult(
                stdout: stdoutBuffer.data(),
                stderr: Data(error.localizedDescription.utf8),
                terminationStatus: nil,
                didTimeOut: false
            )
        }
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()

        var didTimeOut = false
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        if process.isRunning {
            didTimeOut = true
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(0.5)
            while process.isRunning, Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        process.waitUntilExit()
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        drainRemainingData(from: stdout.fileHandleForReading, into: stdoutBuffer)
        drainRemainingData(from: stderr.fileHandleForReading, into: stderrBuffer)

        return SMCommandResult(
            stdout: stdoutBuffer.data(),
            stderr: stderrBuffer.data(),
            terminationStatus: process.terminationStatus,
            didTimeOut: didTimeOut
        )
    }

    private nonisolated static func drainRemainingData(
        from fileHandle: FileHandle,
        into buffer: SMCommandOutputBuffer
    ) {
        let data = fileHandle.readDataToEndOfFile()
        if !data.isEmpty {
            buffer.append(data)
        }
    }

    private nonisolated static func writeCommandFailureDiagnostic(
        executable: String,
        result: SMCommandResult
    ) {
        guard executable == "/usr/bin/osascript" || executable.hasSuffix("/tmux") else {
            return
        }

        let status = result.didTimeOut
            ? "timed out"
            : "status \(result.terminationStatus.map(String.init) ?? "unknown")"
        let stderr = String(data: result.stderr, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let stderr, !stderr.isEmpty {
            writeDiagnostic("\((executable as NSString).lastPathComponent) \(status): \(stderr)")
        } else {
            writeDiagnostic("\((executable as NSString).lastPathComponent) \(status)")
        }
    }

    private nonisolated static func writeDiagnostic(_ message: String) {
        let now = Date()
        diagnosticLogLock.lock()
        defer { diagnosticLogLock.unlock() }

        pruneDiagnosticThrottleCache(now: now)
        if let previousWrite = diagnosticLastWriteByMessage[message],
           now.timeIntervalSince(previousWrite) < diagnosticRepeatInterval {
            return
        }
        if diagnosticLastWriteByMessage.count >= maxDiagnosticThrottleKeys,
           diagnosticLastWriteByMessage[message] == nil,
           let oldestEntry = diagnosticLastWriteByMessage.min(by: { $0.value < $1.value }) {
            diagnosticLastWriteByMessage.removeValue(forKey: oldestEntry.key)
        }
        diagnosticLastWriteByMessage[message] = now

        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: now)) \(message)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }

        if FileManager.default.fileExists(atPath: diagnosticLogURL.path) {
            guard let handle = try? FileHandle(forWritingTo: diagnosticLogURL) else {
                return
            }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: diagnosticLogURL)
        }
    }

    private nonisolated static func pruneDiagnosticThrottleCache(now: Date) {
        diagnosticLastWriteByMessage = diagnosticLastWriteByMessage.filter { _, lastWrite in
            now.timeIntervalSince(lastWrite) < diagnosticRepeatInterval
        }
    }
}

private struct SMCommandResult {
    let stdout: Data
    let stderr: Data
    let terminationStatus: Int32?
    let didTimeOut: Bool
}

private final class SMCommandOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class SMPluginRenameViewController: NSViewController, NSTextFieldDelegate {
    static let preferredSize = NSSize(width: 360, height: 166)

    private let annotation: SMAgentWindowAnnotation
    private let onRename: (String) -> Void
    private let onCancel: () -> Void
    private let nameField = NSTextField()
    private let renameButton = NSButton(title: "Rename", target: nil, action: nil)

    init(
        annotation: SMAgentWindowAnnotation,
        onRename: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.annotation = annotation
        self.onRename = onRename
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = Self.preferredSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = NSView(frame: NSRect(origin: .zero, size: Self.preferredSize))
        rootView.translatesAutoresizingMaskIntoConstraints = true

        let titleLabel = NSTextField(labelWithString: "Rename Agent")
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let sessionLabel = NSTextField(labelWithString: annotation.sessionID)
        sessionLabel.textColor = .secondaryLabelColor
        sessionLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        sessionLabel.translatesAutoresizingMaskIntoConstraints = false

        nameField.stringValue = annotation.friendlyName
        nameField.delegate = self
        nameField.target = self
        nameField.action = #selector(rename(_:))
        nameField.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        renameButton.target = self
        renameButton.action = #selector(rename(_:))
        renameButton.keyEquivalent = "\r"
        renameButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = NSStackView(views: [cancelButton, renameButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        [titleLabel, sessionLabel, nameField, buttonStack].forEach(rootView.addSubview)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -18),

            sessionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            sessionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            sessionLabel.trailingAnchor.constraint(lessThanOrEqualTo: rootView.trailingAnchor, constant: -18),

            nameField.topAnchor.constraint(equalTo: sessionLabel.bottomAnchor, constant: 14),
            nameField.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            nameField.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -18),
            nameField.heightAnchor.constraint(equalToConstant: 28),

            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 78),
            renameButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),

            buttonStack.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 16),
            buttonStack.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            buttonStack.bottomAnchor.constraint(lessThanOrEqualTo: rootView.bottomAnchor, constant: -18)
        ])

        view = rootView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(nameField)
        nameField.selectText(nil)
        updateRenameButton()
    }

    func controlTextDidChange(_ notification: Notification) {
        updateRenameButton()
    }

    private func updateRenameButton() {
        let proposedName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        renameButton.isEnabled = !proposedName.isEmpty && proposedName != annotation.friendlyName
    }

    @objc
    private func rename(_ sender: Any?) {
        let proposedName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !proposedName.isEmpty, proposedName != annotation.friendlyName else {
            return
        }

        onRename(proposedName)
    }

    @objc
    private func cancel(_ sender: Any?) {
        onCancel()
    }
}

private struct SMSessionsResponse: Decodable {
    let sessions: [SMAPISession]
}

private struct SMEventStateResponse: Decodable {
    let tmuxClientEventVersion: Int

    enum CodingKeys: String, CodingKey {
        case tmuxClientEventVersion = "tmux_client_event_version"
    }
}

private struct SMAPISession: Decodable {
    let id: String
    let friendlyName: String?
    let workingDirectory: String
    let node: String?
    let provider: String?
    let status: String
    let activityState: String
    let currentTask: String?
    let agentStatusText: String?
    let lastToolName: String?
    let lastActionSummary: String?
    let tokensUsed: Int?
    let tmuxSession: String
    let tmuxSocketName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case friendlyName = "friendly_name"
        case workingDirectory = "working_dir"
        case node
        case provider
        case status
        case activityState = "activity_state"
        case currentTask = "current_task"
        case agentStatusText = "agent_status_text"
        case lastToolName = "last_tool_name"
        case lastActionSummary = "last_action_summary"
        case tokensUsed = "tokens_used"
        case tmuxSession = "tmux_session"
        case tmuxSocketName = "tmux_socket_name"
    }
}
