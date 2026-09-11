import Foundation
import Testing
@testable import DeskBar

// A trimmed capture of a real `GET /session-obligations` response: one agent
// waiting on two queue jobs and a review, plus the sm-tracked review history
// for the PRs it has touched.
private let smObligationsFixture = """
{
  "schema_version": 1,
  "sessions": [
    {
      "session_id": "4e4cd6fa",
      "waiting_on": [
        {
          "id": "job_41f58e3fee64",
          "kind": "queue_job",
          "label": "1365-inspection-api",
          "requester_session_id": "4e4cd6fa",
          "since": "2026-09-11T17:37:33.143798Z",
          "state": "running"
        },
        {
          "id": "job_da766b393338",
          "kind": "queue_job",
          "label": "1365-inspection-frontend",
          "requester_session_id": "bf964c3a",
          "since": "2026-09-11T17:37:36.473956Z",
          "state": "pending"
        },
        {
          "id": "9583f0b000b9",
          "kind": "review",
          "label": "Review \\u00b7 rajeshgoli/fractal-algo-rust #1388",
          "last_error": null,
          "last_polled_at": "2026-09-11T17:56:18.659937Z",
          "pr_number": 1388,
          "repo": "rajeshgoli/fractal-algo-rust",
          "requester_session_id": "4e4cd6fa",
          "since": "2026-09-11T17:53:42.339499Z",
          "state": "active"
        }
      ],
      "waiting_since": "2026-09-11T17:37:33.143798Z",
      "review_history": [
        {
          "landed_count": 6,
          "landed_requested_by_agent": 6,
          "pr_number": 1376,
          "repo": "rajeshgoli/fractal-algo-rust",
          "request_count": 6,
          "requested_by_agent": 6,
          "scope": "sm_tracked"
        },
        {
          "landed_count": 2,
          "landed_requested_by_agent": 1,
          "pr_number": 1388,
          "repo": "rajeshgoli/fractal-algo-rust",
          "request_count": 3,
          "requested_by_agent": 1,
          "scope": "sm_tracked"
        }
      ]
    },
    {
      "session_id": "0037f74b",
      "waiting_on": [],
      "waiting_since": null,
      "review_history": []
    }
  ]
}
"""

private let fixtureNow = ISO8601DateFormatter().date(from: "2026-09-11T17:57:33Z")!

private func smObligations(_ json: String = smObligationsFixture) -> [String: SMSessionObligations] {
    SMSessionObligationsParser.parse(Data(json.utf8)) ?? [:]
}

private func smObligationsSnapshot(
    _ json: String = smObligationsFixture,
    fetchedAt: Date = fixtureNow,
    isStale: Bool = false
) -> SMObligationsSnapshot {
    SMObligationsSnapshot(
        obligationsBySessionID: smObligations(json),
        fetchedAt: fetchedAt,
        isStale: isStale
    )
}

private func smSession(
    id: String,
    friendlyName: String? = nil,
    activityState: SMAgentActivityState
) -> SMSessionSnapshot {
    SMSessionSnapshot(
        id: id,
        friendlyName: friendlyName,
        workingDirectory: "/Users/rajesh/projects/deskbar",
        node: "primary",
        provider: "claude",
        status: "running",
        activityState: activityState,
        currentTask: nil,
        agentStatusText: nil,
        lastToolName: nil,
        lastActionSummary: nil,
        tokensUsed: nil,
        tmuxSession: "claude-\(id)",
        tmuxSocketName: "session-manager",
        waiting: nil
    )
}

private func smWaitingState(
    for session: SMSessionSnapshot,
    snapshot: SMObligationsSnapshot = smObligationsSnapshot(),
    otherSessions: [SMSessionSnapshot] = [],
    now: Date = fixtureNow
) -> SMAgentWaitingState? {
    SMPluginService.sessionsWithWaitingStates(
        [session] + otherSessions,
        obligations: snapshot,
        now: now
    ).first?.waiting
}

@Test
func smObligationsParserReadsWaitingResultsAndHistory() {
    let obligations = try! #require(smObligations()["4e4cd6fa"])

    #expect(obligations.items.count == 3)
    #expect(obligations.items.first?.kind == .queueJob)
    #expect(obligations.items.first?.label == "1365-inspection-api")
    #expect(obligations.items.first?.state == "running")
    // Fractional-second RFC 3339 timestamps parse.
    #expect(obligations.waitingSince == obligations.items.first?.since)
    #expect(obligations.items.last?.kind == .review)
    #expect(obligations.items.last?.repo == "rajeshgoli/fractal-algo-rust")
    #expect(obligations.items.last?.prNumber == 1388)
    #expect(obligations.reviewHistory.count == 2)
    #expect(obligations.reviewHistory.last?.requestCount == 3)
    #expect(obligations.reviewHistory.last?.landedCount == 2)
    // A session with no pending results is still present, with nothing tracked.
    #expect(smObligations()["0037f74b"]?.items.isEmpty == true)
}

@Test
func smObligationsParserRejectsUnsupportedSchemaVersions() {
    #expect(SMSessionObligationsParser.parse(Data("""
    {"schema_version": 2, "sessions": []}
    """.utf8)) == nil)
    #expect(SMSessionObligationsParser.parse(Data("not json".utf8)) == nil)
    // An old server without the endpoint answers 404 with an error body.
    #expect(SMSessionObligationsParser.parse(Data("""
    {"detail": "Not Found"}
    """.utf8)) == nil)
}

@Test
func smObligationsParserToleratesSparseEntries() {
    let obligations = smObligations("""
    {
      "schema_version": 1,
      "sessions": [
        {
          "session_id": "abc123",
          "waiting_on": [
            {"kind": "queue_job", "id": "job_1"},
            {"kind": "future_kind", "id": "x_1", "since": "2026-09-11T17:00:00Z"}
          ]
        }
      ]
    }
    """)

    let entry = try! #require(obligations["abc123"])
    // Unknown kinds are dropped rather than shown as an unlabeled wait.
    #expect(entry.items.count == 1)
    #expect(entry.items.first?.id == "job_1")
    #expect(entry.items.first?.since == nil)
    #expect(entry.waitingSince == nil)
    #expect(entry.reviewHistory.isEmpty)
}

@Test
func smWaitingDecoratesIdleAgentWithPendingResults() {
    let waiting = try! #require(smWaitingState(for: smSession(id: "4e4cd6fa", activityState: .idle)))

    #expect(waiting.items.count == 3)
    #expect(waiting.isStale == false)
    // Oldest pending result first, and the summary counts every result.
    #expect(waiting.items.first?.displayLabel == "1365-inspection-api")
    #expect(waiting.elapsedMinutes == 19)
    #expect(waiting.badgeText == "19m")
    #expect(waiting.summaryLine == "Waiting on 3 results - 19m")
    #expect(waiting.detailLines.contains("Job 1365-inspection-api - running - 19m"))
    #expect(waiting.accessibilityText.contains("Job 1365-inspection-api"))
}

@Test
func smWaitingNamesTheOnlyPendingResult() {
    let waiting = try! #require(smWaitingState(
        for: smSession(id: "solo", activityState: .idle),
        snapshot: smObligationsSnapshot("""
        {
          "schema_version": 1,
          "sessions": [
            {
              "session_id": "solo",
              "waiting_on": [
                {
                  "kind": "queue_job", "id": "job_9", "label": "deskbar-tests",
                  "state": "running", "since": "2026-09-11T17:53:33Z",
                  "requester_session_id": "solo"
                }
              ],
              "waiting_since": "2026-09-11T17:53:33Z"
            }
          ]
        }
        """)
    ))

    // A single pending result keeps its friendly label in the leading line.
    #expect(waiting.summaryLine == "Waiting: deskbar-tests - 4m")
    #expect(waiting.detailLines == [
        "Waiting: deskbar-tests - 4m",
        "Job deskbar-tests - running - 4m"
    ])
}

@Test
func smWaitingLabelsReviewsWithRepoPullRequestAndTrackedCounts() {
    let waiting = try! #require(smWaitingState(for: smSession(id: "4e4cd6fa", activityState: .idle)))
    let review = try! #require(waiting.items.first { $0.kind == .review })

    #expect(review.displayLabel == "rajeshgoli/fractal-algo-rust #1388")
    #expect(review.detailLine == "Review rajeshgoli/fractal-algo-rust #1388 - active - 3m (sm-tracked: 3 requested, 2 landed)")
    #expect(review.errorLine == nil)
}

@Test
func smWaitingCreditsARequesterOtherThanTheWaitingAgent() {
    let waiting = try! #require(smWaitingState(
        for: smSession(id: "4e4cd6fa", activityState: .idle),
        otherSessions: [smSession(id: "bf964c3a", friendlyName: "shy-otter", activityState: .working)]
    ))

    let ownJob = try! #require(waiting.items.first { $0.id == "job_41f58e3fee64" })
    let otherJob = try! #require(waiting.items.first { $0.id == "job_da766b393338" })
    // The wait belongs to the recipient; only a different requester is named.
    #expect(ownJob.requesterDisplayName == nil)
    #expect(otherJob.requesterDisplayName == "shy-otter")
    #expect(otherJob.detailLine == "Job 1365-inspection-frontend - pending - 19m - requested by shy-otter")
}

@Test
func smWaitingFallsBackToTheRequesterSessionIDWhenItIsNotLive() {
    let waiting = try! #require(smWaitingState(for: smSession(id: "4e4cd6fa", activityState: .idle)))
    let otherJob = try! #require(waiting.items.first { $0.id == "job_da766b393338" })

    #expect(otherJob.requesterDisplayName == "bf964c3a")
}

@Test
func smWaitingSkipsAgentsThatAreNotIdle() {
    for activityState in [SMAgentActivityState.working, .thinking, .waitingPermission, .waitingInput, .stopped] {
        let session = smSession(id: "4e4cd6fa", activityState: activityState)
        let decorated = SMPluginService.sessionsWithWaitingStates(
            [session],
            obligations: smObligationsSnapshot(),
            now: fixtureNow
        ).first

        // Pending work never changes the activity state or decorates a busy,
        // blocked, or stopped agent.
        #expect(decorated?.waiting == nil)
        #expect(decorated?.activityState == activityState)
    }
}

@Test
func smWaitingSkipsIdleAgentsWithoutPendingResults() {
    // Present in the snapshot with an empty waiting_on (history only)...
    #expect(smWaitingState(for: smSession(id: "0037f74b", activityState: .idle)) == nil)
    // ...and omitted from a successful snapshot entirely.
    #expect(smWaitingState(for: smSession(id: "unknown", activityState: .idle)) == nil)
}

@Test
func smWaitingClearsWhenTheResultCompletes() {
    let session = smSession(id: "4e4cd6fa", activityState: .idle)
    #expect(smWaitingState(for: session) != nil)

    let afterCompletion = smObligationsSnapshot("""
    {
      "schema_version": 1,
      "sessions": [
        {"session_id": "4e4cd6fa", "waiting_on": [], "waiting_since": null, "review_history": []}
      ]
    }
    """)

    #expect(smWaitingState(for: session, snapshot: afterCompletion) == nil)
}

@Test
func smWaitingAgesWithEachPoll() {
    let session = smSession(id: "4e4cd6fa", activityState: .idle)
    let later = fixtureNow.addingTimeInterval(45 * 60)

    #expect(smWaitingState(for: session)?.elapsedMinutes == 19)
    #expect(smWaitingState(for: session, now: later)?.elapsedMinutes == 64)
    #expect(smWaitingState(for: session, now: later)?.badgeText == "1h 4m")
}

@Test
func smWaitingMarksCachedResultsStaleWhenTheSnapshotIsStale() {
    let waiting = try! #require(smWaitingState(
        for: smSession(id: "4e4cd6fa", activityState: .idle),
        snapshot: smObligationsSnapshot(isStale: true)
    ))

    #expect(waiting.isStale)
    #expect(waiting.badgeText == "19m?")
    #expect(waiting.detailLines.last == "Waiting info may be stale (last sm refresh failed)")
    #expect(waiting.accessibilityText.hasSuffix("(may be stale)"))
}

@Test
func smWaitingLeavesSessionsUntouchedWhenObligationsAreUnavailable() {
    let sessions = [smSession(id: "4e4cd6fa", activityState: .idle)]

    // A failed fetch with nothing cached (an older server 404s forever) leaves
    // the normal session display in place with no waiting decoration.
    let undecorated = SMPluginService.sessionsWithWaitingStates(
        sessions,
        obligations: nil,
        now: fixtureNow
    )

    #expect(undecorated == sessions)
}

@Test
func smStaleObligationsAreKeptBrieflyThenDropped() {
    let snapshot = smObligationsSnapshot()

    let recent = try! #require(SMPluginService.staleObligations(
        cached: snapshot,
        now: fixtureNow.addingTimeInterval(30)
    ))
    #expect(recent.isStale)
    #expect(recent.obligationsBySessionID == snapshot.obligationsBySessionID)

    // Past the retention window the decoration is dropped rather than left
    // indefinitely stale.
    #expect(SMPluginService.staleObligations(
        cached: snapshot,
        now: fixtureNow.addingTimeInterval(300)
    ) == nil)
    #expect(SMPluginService.staleObligations(cached: nil, now: fixtureNow) == nil)
}

@Test
func smWaitingElapsedTextCoversEveryScale() {
    #expect(SMWaitingFormatter.elapsedText(minutes: nil) == "?")
    #expect(SMWaitingFormatter.elapsedText(minutes: 0) == "<1m")
    #expect(SMWaitingFormatter.elapsedText(minutes: 59) == "59m")
    #expect(SMWaitingFormatter.elapsedText(minutes: 60) == "1h")
    #expect(SMWaitingFormatter.elapsedText(minutes: 125) == "2h 5m")
    #expect(SMWaitingFormatter.elapsedText(minutes: 1440) == "1d")
    #expect(SMWaitingFormatter.elapsedText(minutes: 1440 + 120) == "1d 2h")
}

@Test
func smWaitingListingIsCappedWithARemainderLine() {
    let items = (1...6).map { index in
        """
        {
          "kind": "queue_job", "id": "job_\(index)", "label": "task-\(index)",
          "state": "pending", "since": "2026-09-11T17:5\(index):33Z",
          "requester_session_id": "busy"
        }
        """
    }.joined(separator: ",")

    let waiting = try! #require(smWaitingState(
        for: smSession(id: "busy", activityState: .idle),
        snapshot: smObligationsSnapshot("""
        {"schema_version": 1, "sessions": [{"session_id": "busy", "waiting_on": [\(items)]}]}
        """)
    ))

    #expect(waiting.items.count == 6)
    #expect(waiting.detailLines.count == SMAgentWaitingState.maxListedItems + 2)
    #expect(waiting.detailLines.last == "+2 more")
}

@Test
func smWaitingReportsTheLastReviewPollError() {
    let waiting = try! #require(smWaitingState(
        for: smSession(id: "solo", activityState: .idle),
        snapshot: smObligationsSnapshot("""
        {
          "schema_version": 1,
          "sessions": [
            {
              "session_id": "solo",
              "waiting_on": [
                {
                  "kind": "review", "id": "r_1", "label": "Review \\u00b7 rajeshgoli/deskbar #109",
                  "repo": "rajeshgoli/deskbar", "pr_number": 109, "state": "active",
                  "since": "2026-09-11T17:55:33Z", "requester_session_id": "solo",
                  "last_error": "gh api rate limit exceeded"
                }
              ]
            }
          ]
        }
        """)
    ))

    #expect(waiting.items.first?.errorLine == "Last error: gh api rate limit exceeded")
    #expect(waiting.detailLines.contains("Last error: gh api rate limit exceeded"))
}

private func smAnnotation(
    sessionID: String,
    friendlyName: String,
    activityState: SMAgentActivityState = .idle,
    waiting: SMAgentWaitingState? = nil
) -> SMAgentWindowAnnotation {
    SMAgentWindowAnnotation(
        sessionID: sessionID,
        friendlyName: friendlyName,
        workingDirectory: "/Users/rajesh/projects/deskbar",
        node: "primary",
        provider: "claude",
        sessionStatus: "running",
        activityState: activityState,
        currentTask: nil,
        agentStatusText: nil,
        lastToolName: nil,
        lastActionSummary: nil,
        tokensUsed: nil,
        tmuxSession: "claude-\(sessionID)",
        terminalWindowID: 42,
        terminalTTY: "/dev/ttys001",
        terminalFrame: nil,
        isSelectedTerminalTab: true,
        waiting: waiting
    )
}

@Test
func smWaitingKeepsAgeingOnScreenWhenTheSessionsFetchFails() {
    // A /sessions outage freezes the activity states, but the decoration is
    // re-derived from the obligations cache so the wait keeps ageing.
    let annotations = [smAnnotation(sessionID: "4e4cd6fa", friendlyName: "1365-engineer")]
    let later = fixtureNow.addingTimeInterval(10 * 60)

    let updated = SMPluginService.annotationsWithWaitingStates(
        annotations,
        obligations: smObligationsSnapshot(),
        now: later
    )

    #expect(updated.first?.waiting?.elapsedMinutes == 29)
    #expect(updated.first?.waiting?.isStale == false)
    #expect(updated.first?.activityState == .idle)
}

@Test
func smWaitingGoesStaleThenClearsWhileSMIsUnreachable() {
    let annotations = SMPluginService.annotationsWithWaitingStates(
        [smAnnotation(sessionID: "4e4cd6fa", friendlyName: "1365-engineer")],
        obligations: smObligationsSnapshot(),
        now: fixtureNow
    )

    // Both endpoints failing: the cache is marked stale and the badge says so.
    let stale = SMPluginService.annotationsWithWaitingStates(
        annotations,
        obligations: SMPluginService.staleObligations(
            cached: smObligationsSnapshot(),
            now: fixtureNow.addingTimeInterval(30)
        ),
        now: fixtureNow.addingTimeInterval(30)
    )
    #expect(stale.first?.waiting?.isStale == true)
    #expect(stale.first?.waiting?.badgeText.hasSuffix("?") == true)

    // Past the retention window the decoration is dropped rather than left
    // frozen on a stale wait.
    let expired = SMPluginService.annotationsWithWaitingStates(
        stale,
        obligations: SMPluginService.staleObligations(
            cached: smObligationsSnapshot(),
            now: fixtureNow.addingTimeInterval(300)
        ),
        now: fixtureNow.addingTimeInterval(300)
    )
    #expect(expired.first?.waiting == nil)
    #expect(expired.first?.friendlyName == "1365-engineer")
}

@Test
func smWaitingIsRefreshedOnAnnotationsRetainedThroughAPartialTerminalMapping() {
    // An agent whose terminal mapping went missing keeps its previous
    // annotation for up to a minute, including the wait it was built with.
    let stalePending = try! #require(smWaitingState(for: smSession(id: "4e4cd6fa", activityState: .idle)))
    let retained = smAnnotation(
        sessionID: "4e4cd6fa",
        friendlyName: "1365-engineer",
        waiting: stalePending
    )
    let now = fixtureNow.addingTimeInterval(60)

    let merged = SMPluginService.mergedAgentAnnotations(
        liveSessionIDs: ["4e4cd6fa"],
        freshAnnotations: [],
        previousAnnotations: [retained],
        lastObservedAtBySessionID: ["4e4cd6fa": now.addingTimeInterval(-5)],
        now: now,
        retainsMissingAnnotations: true
    )
    #expect(merged.annotations.first?.waiting == stalePending)

    // Re-deriving against the same poll's obligations ages the retained wait...
    let aged = SMPluginService.annotationsWithWaitingStates(
        merged.annotations,
        obligations: smObligationsSnapshot(),
        now: now
    )
    #expect(aged.first?.waiting?.elapsedMinutes == 20)

    // ...and drops it entirely once the results have landed, instead of showing
    // a finished wait until the mapping recovers.
    let completed = SMPluginService.annotationsWithWaitingStates(
        merged.annotations,
        obligations: smObligationsSnapshot("""
        {
          "schema_version": 1,
          "sessions": [
            {"session_id": "4e4cd6fa", "waiting_on": [], "waiting_since": null, "review_history": []}
          ]
        }
        """),
        now: now
    )
    #expect(completed.first?.waiting == nil)
    #expect(completed.first?.terminalWindowID == retained.terminalWindowID)
}

@Test
func smWaitingElapsedIgnoresObligationsItCannotShow() {
    // A newer server reports an unsupported kind that is older than everything
    // this build can display. The dropped item must not stretch the elapsed
    // wait shown for the results that are listed.
    let waiting = try! #require(smWaitingState(
        for: smSession(id: "solo", activityState: .idle),
        snapshot: smObligationsSnapshot("""
        {
          "schema_version": 1,
          "sessions": [
            {
              "session_id": "solo",
              "waiting_on": [
                {
                  "kind": "future_kind", "id": "x_1", "label": "unknown",
                  "state": "pending", "since": "2026-09-08T17:00:00Z",
                  "requester_session_id": "solo"
                },
                {
                  "kind": "queue_job", "id": "job_9", "label": "deskbar-tests",
                  "state": "running", "since": "2026-09-11T17:55:33Z",
                  "requester_session_id": "solo"
                }
              ],
              "waiting_since": "2026-09-08T17:00:00Z"
            }
          ]
        }
        """)
    ))

    #expect(waiting.items.count == 1)
    #expect(waiting.badgeText == "2m")
    #expect(waiting.summaryLine == "Waiting: deskbar-tests - 2m")
}

@Test
func smWaitingUsesTheServerWaitingSinceWhenNothingWasDropped() {
    let waiting = try! #require(smWaitingState(for: smSession(id: "4e4cd6fa", activityState: .idle)))

    #expect(waiting.items.count == 3)
    #expect(waiting.elapsedMinutes == 19)
}
