import AppKit
import Testing
@testable import DeskBar

@MainActor
struct TaskButtonWaitingBadgeTests {
    @Test
    func waitingAgentTakesOverTheSMPill() {
        let button = makeButton(waiting: makeWaitingState(), showsActionButton: true)
        let pill = try! #require(findPluginActionButton(in: button))

        // The hourglass and elapsed wait replace the "sm" label, and the
        // trailing badge stands down so the wait is shown once.
        #expect(pill.title == "4m")
        #expect(pill.image != nil)
        #expect(findActivityBadge(in: button)?.isHidden == true)
        #expect(button.toolTip?.contains("Waiting: deskbar-tests - 4m") == true)
    }

    @Test
    func availableAgentKeepsThePlainSMPill() {
        let button = makeButton(waiting: nil, showsActionButton: true)
        let pill = try! #require(findPluginActionButton(in: button))

        #expect(pill.title == "sm")
        #expect(pill.image == nil)
    }

    @Test
    func waitingHourglassAnimatesThroughItsSteps() {
        let button = makeButton(waiting: makeWaitingState(), showsActionButton: true)
        let pill = try! #require(findPluginActionButton(in: button))

        let firstFrame = pill.image
        TaskButtonView.advanceWaitingAnimation()
        let secondFrame = pill.image
        #expect(secondFrame !== firstFrame)

        // Stepping through the cycle returns to where it started, and only the
        // glyph changes - the elapsed text is driven by the SM poll.
        TaskButtonView.advanceWaitingAnimation()
        TaskButtonView.advanceWaitingAnimation()
        #expect(pill.image === firstFrame)
        #expect(pill.title == "4m")
    }

    @Test
    func compactWaitingPillKeepsAnimating() {
        let button = makeButton(waiting: makeWaitingState(elapsedMinutes: 64), showsActionButton: true)
        let pill = try! #require(findPluginActionButton(in: button))

        // Narrow enough that the pill shows the hourglass alone - which is then
        // the only visible waiting cue, so it has to keep animating.
        button.setWidthMode(usesAdaptiveWidth: true, widthCap: 80)
        #expect(pill.title == "")

        let firstFrame = pill.image
        TaskButtonView.advanceWaitingAnimation()
        #expect(pill.image !== firstFrame)
        #expect(pill.title == "")
    }

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
    func narrowButtonsDropTheElapsedTextRatherThanClipIt() {
        let button = makeButton(waiting: makeWaitingState(elapsedMinutes: 64), showsActionButton: true)
        let pill = try! #require(findPluginActionButton(in: button))
        let badge = try! #require(findActivityBadge(in: button))

        // Room for the pill and the elapsed text.
        button.setWidthMode(usesAdaptiveWidth: true, widthCap: 200)
        #expect(pill.title == "1h 4m")
        #expect(badge.isHidden)

        // Capped below that: keep the animated hourglass, drop the text rather
        // than push the icon and title out of the button.
        button.setWidthMode(usesAdaptiveWidth: true, widthCap: 80)
        #expect(!pill.isHidden)
        #expect(pill.title == "")
        #expect(pill.image != nil)
        #expect(badge.isHidden)

        // Icon-only layout has no room for the pill at all; the tooltip keeps
        // the detail.
        button.setWidthMode(usesAdaptiveWidth: true, widthCap: 32)
        #expect(pill.isHidden)
        #expect(button.toolTip?.contains("Waiting: deskbar-tests - 1h 4m") == true)
    }

    @Test
    func fallbackBadgeFitsItselfToTheButtonWidth() {
        // With the sm action button turned off the badge carries the wait, so it
        // has to fit whatever width the responsive layout leaves it.
        let button = makeButton(waiting: makeWaitingState(elapsedMinutes: 64))
        let badge = try! #require(findActivityBadge(in: button))
        let label = try! #require(findBadgeLabel(in: badge))

        button.setWidthMode(usesAdaptiveWidth: true, widthCap: 200)
        #expect(!badge.isHidden)
        #expect(label.stringValue == "1h 4m")

        button.setWidthMode(usesAdaptiveWidth: true, widthCap: 70)
        #expect(!badge.isHidden)
        #expect(findBadgeIcon(in: badge)?.isHidden == false)
        #expect(label.stringValue == "")

        button.setWidthMode(usesAdaptiveWidth: true, widthCap: 32)
        #expect(badge.isHidden)
        #expect(button.toolTip?.contains("Waiting: deskbar-tests - 1h 4m") == true)
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

    private func makeWaitingState(
        isStale: Bool = false,
        elapsedMinutes: Int = 4
    ) -> SMAgentWaitingState {
        SMAgentWaitingState(
            items: [
                SMWaitingItem(
                    kind: .queueJob,
                    id: "job_9",
                    label: "deskbar-tests",
                    state: "running",
                    elapsedMinutes: elapsedMinutes,
                    requesterDisplayName: nil,
                    repo: nil,
                    prNumber: nil,
                    lastError: nil,
                    reviewHistory: nil
                )
            ],
            elapsedMinutes: elapsedMinutes,
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

    private func findPluginActionButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.toolTip == "Session Manager actions" {
            return button
        }

        for subview in view.subviews {
            if let button = findPluginActionButton(in: subview) {
                return button
            }
        }

        return nil
    }

    private func makeButton(
        waiting: SMAgentWaitingState?,
        settings: TaskbarSettings? = nil,
        showsActionButton: Bool = false
    ) -> TaskButtonView {
        let button = TaskButtonView(
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
            pluginMenuConfiguration: showsActionButton
                ? TaskButtonPluginMenuConfiguration(
                    buttonTitle: "sm",
                    tintColor: .secondaryLabelColor,
                    showsActionButton: true,
                    menuProvider: { NSMenu() }
                )
                : nil,
            activationHandler: { _ in }
        )
        // The inline pill only appears once the button is wide enough for it.
        button.setWidthMode(usesAdaptiveWidth: false, widthCap: nil)
        return button
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
