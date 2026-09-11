import AppKit
import Testing
@testable import DeskBar

@MainActor
struct TaskButtonWaitingBadgeTests {
    @Test
    func waitingAgentGetsABadgeTooltipAndAccessibleText() {
        let button = makeButton(waiting: makeWaitingState())

        let badge = try! #require(findActivityBadge(in: button))
        // Not color alone: an hourglass glyph plus the elapsed wait.
        #expect(badge.isHidden == false)
        #expect(findBadgeIcon(in: badge)?.isHidden == false)
        #expect(findBadgeLabel(in: badge)?.stringValue == "4m")

        let toolTip = try! #require(button.toolTip)
        #expect(toolTip.contains("Waiting: deskbar-tests - 4m"))
        #expect(toolTip.contains("Job deskbar-tests - running - 4m"))

        let accessibilityLabel = try! #require(button.accessibilityLabel())
        #expect(accessibilityLabel.contains("Idle"))
        #expect(accessibilityLabel.contains("Waiting: deskbar-tests - 4m"))
    }

    @Test
    func availableIdleAgentKeepsItsPlainTreatment() {
        let button = makeButton(waiting: nil)

        #expect(findActivityBadge(in: button)?.isHidden == true)
        let toolTip = try! #require(button.toolTip)
        #expect(!toolTip.contains("Waiting"))
        #expect(button.accessibilityLabel()?.contains("Waiting") == false)
    }

    @Test
    func waitingBadgeFollowsTheActivityIndicatorSetting() {
        let settings = makeSettings()
        settings.showSessionManagerActivityIndicators = false
        let button = makeButton(waiting: makeWaitingState(), settings: settings)

        // The badge is an activity indicator, but the tooltip detail stays.
        #expect(findActivityBadge(in: button)?.isHidden == true)
        #expect(button.toolTip?.contains("Waiting: deskbar-tests - 4m") == true)
    }

    @Test
    func agentMenuListsThePendingResults() {
        let menu = SMPluginAgentMenuFactory.makeMenu(
            annotation: makeAnnotation(waiting: makeWaitingState()),
            target: nil,
            action: Selector(("performMenuCommand:"))
        )

        let titles = menu.items.map(\.title)
        #expect(titles.contains("Waiting: deskbar-tests - 4m"))
        #expect(titles.contains("Job deskbar-tests - running - 4m"))
    }

    private func makeWaitingState(isStale: Bool = false) -> SMAgentWaitingState {
        SMAgentWaitingState(
            items: [
                SMWaitingItem(
                    kind: .queueJob,
                    id: "job_9",
                    label: "deskbar-tests",
                    state: "running",
                    elapsedMinutes: 4,
                    requesterDisplayName: nil,
                    repo: nil,
                    prNumber: nil,
                    lastError: nil,
                    reviewHistory: nil
                )
            ],
            elapsedMinutes: 4,
            isStale: isStale
        )
    }

    private func makeSettings() -> TaskbarSettings {
        let suiteName = "com.deskbar.tests.waiting.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return TaskbarSettings(defaults: defaults)
    }

    private func makeAnnotation(waiting: SMAgentWaitingState?) -> SMAgentWindowAnnotation {
        SMAgentWindowAnnotation(
            sessionID: "bf964c3a",
            friendlyName: "1384-engineer",
            workingDirectory: "/Users/rajesh/projects/deskbar",
            node: "primary",
            provider: "claude",
            sessionStatus: "running",
            activityState: .idle,
            currentTask: nil,
            agentStatusText: nil,
            lastToolName: nil,
            lastActionSummary: nil,
            tokensUsed: nil,
            tmuxSession: "claude-bf964c3a",
            terminalWindowID: 42,
            terminalTTY: "/dev/ttys001",
            terminalFrame: nil,
            isSelectedTerminalTab: true,
            waiting: waiting
        )
    }

    private func makeButton(
        waiting: SMAgentWaitingState?,
        settings: TaskbarSettings? = nil
    ) -> TaskButtonView {
        TaskButtonView(
            windowInfo: WindowInfo(
                pid: 123,
                cgWindowID: 456,
                appName: "Terminal",
                title: "1384-engineer",
                icon: nil,
                bundleIdentifier: SMPluginService.terminalBundleIdentifier
            ),
            isActive: false,
            hasBadge: false,
            isAccessibilityAvailable: false,
            runtimeState: AppRuntimeState(),
            showsActivityOverlay: false,
            agentAnnotation: makeAnnotation(waiting: waiting),
            settings: settings ?? makeSettings(),
            blacklistManager: BlacklistManager(),
            activationHandler: { _ in }
        )
    }

    private func findActivityBadge(in view: NSView) -> NSVisualEffectView? {
        if let badge = view as? NSVisualEffectView, findBadgeLabel(in: badge) != nil {
            return badge
        }

        for subview in view.subviews {
            if let badge = findActivityBadge(in: subview) {
                return badge
            }
        }

        return nil
    }

    private func findBadgeLabel(in view: NSView) -> NSTextField? {
        view.subviews.compactMap { $0 as? NSTextField }.first
    }

    private func findBadgeIcon(in view: NSView) -> NSImageView? {
        view.subviews.compactMap { $0 as? NSImageView }.first
    }
}
