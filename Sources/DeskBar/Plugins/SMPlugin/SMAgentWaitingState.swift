import Foundation

/// Kind of pending result an agent can be waiting on. Mirrors the `kind` field
/// of `/session-obligations`; unknown kinds are dropped so a newer server adding
/// a kind cannot make DeskBar mislabel a wait.
enum SMWaitingKind: String, Equatable {
    case queueJob = "queue_job"
    case review
}

/// One pending result exactly as `/session-obligations` reported it, before it
/// is aged and joined against the live session list.
struct SMObligationItem: Equatable {
    let kind: SMWaitingKind
    let id: String
    let label: String?
    let state: String?
    let since: Date?
    let requesterSessionID: String?
    let repo: String?
    let prNumber: Int?
    let lastError: String?
}

/// Per-PR review counts tracked by sm. These are the reviews sm requested and
/// saw land, not every review on the GitHub PR.
struct SMReviewHistoryEntry: Equatable {
    let repo: String
    let prNumber: Int
    let requestCount: Int
    let requestedByAgent: Int
    let landedCount: Int
    let landedRequestedByAgent: Int
}

/// The obligations snapshot for a single session.
struct SMSessionObligations: Equatable {
    let sessionID: String
    let items: [SMObligationItem]
    let waitingSince: Date?
    let reviewHistory: [SMReviewHistoryEntry]
}

/// A whole `/session-obligations` response plus the freshness bookkeeping the
/// plugin needs. `isStale` means the last fetch failed and these obligations are
/// the previous successful snapshot rather than current truth.
struct SMObligationsSnapshot: Equatable {
    let obligationsBySessionID: [String: SMSessionObligations]
    let fetchedAt: Date
    let isStale: Bool

    func markedStale() -> SMObligationsSnapshot {
        guard !isStale else {
            return self
        }

        return SMObligationsSnapshot(
            obligationsBySessionID: obligationsBySessionID,
            fetchedAt: fetchedAt,
            isStale: true
        )
    }
}

/// One pending result, aged against a poll timestamp and joined to the friendly
/// name of the agent that requested it.
struct SMWaitingItem: Equatable {
    let kind: SMWaitingKind
    let id: String
    let label: String?
    let state: String?
    let elapsedMinutes: Int?
    /// Set only when the requesting agent is not the waiting agent itself.
    let requesterDisplayName: String?
    let repo: String?
    let prNumber: Int?
    let lastError: String?
    let reviewHistory: SMReviewHistoryEntry?

    var kindLabel: String {
        switch kind {
        case .queueJob:
            return "Job"
        case .review:
            return "Review"
        }
    }

    /// Friendly job label, or `owner/repo #pr` for a review. The server's review
    /// label already carries a "Review" prefix, so it is only a fallback.
    var displayLabel: String {
        if kind == .review, let repo, let prNumber {
            return "\(repo) #\(prNumber)"
        }

        let trimmedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedLabel, !trimmedLabel.isEmpty {
            return trimmedLabel
        }

        return id
    }

    var elapsedText: String {
        SMWaitingFormatter.elapsedText(minutes: elapsedMinutes)
    }

    /// "Job deskbar-tests - running - 4m - requested by shy-otter (sm-tracked: 3 requested, 2 landed)"
    var detailLine: String {
        var parts = ["\(kindLabel) \(displayLabel)"]
        if let state = SMWaitingFormatter.trimmed(state) {
            parts.append(state)
        }
        parts.append(elapsedText)
        if let requesterDisplayName {
            parts.append("requested by \(requesterDisplayName)")
        }

        var line = parts.joined(separator: " - ")
        if let reviewHistory {
            line += " (sm-tracked: \(reviewHistory.requestCount) requested, \(reviewHistory.landedCount) landed)"
        }

        return line
    }

    var errorLine: String? {
        guard let lastError = SMWaitingFormatter.trimmed(lastError) else {
            return nil
        }

        return "Last error: \(SMWaitingFormatter.truncated(lastError))"
    }
}

/// Presentation state for an idle agent that owes the user a result. Only built
/// for idle agents with a nonempty `waiting_on`; every other activity state
/// keeps its existing treatment.
struct SMAgentWaitingState: Equatable {
    static let maxListedItems = 4

    let items: [SMWaitingItem]
    let elapsedMinutes: Int?
    let isStale: Bool

    var elapsedText: String {
        SMWaitingFormatter.elapsedText(minutes: elapsedMinutes)
    }

    /// Short text for the task-button badge. The badge also carries an hourglass
    /// glyph, so the state never rests on color alone.
    var badgeText: String {
        isStale ? "\(elapsedText)?" : elapsedText
    }

    /// Leading line for tooltips and menus; names the pending result when there
    /// is exactly one so the friendly job label stays prominent.
    var summaryLine: String {
        guard let onlyItem = items.first, items.count == 1 else {
            return "Waiting on \(items.count) results - \(elapsedText)"
        }

        return "Waiting: \(onlyItem.displayLabel) - \(elapsedText)"
    }

    var staleLine: String? {
        isStale ? "Waiting info may be stale (last sm refresh failed)" : nil
    }

    /// Summary plus one line per pending result, capped so a backlog cannot turn
    /// a tooltip into a wall of text.
    var detailLines: [String] {
        var lines = [summaryLine]
        for item in items.prefix(Self.maxListedItems) {
            lines.append(item.detailLine)
            if let errorLine = item.errorLine {
                lines.append(errorLine)
            }
        }

        let hiddenCount = items.count - Self.maxListedItems
        if hiddenCount > 0 {
            lines.append("+\(hiddenCount) more")
        }

        if let staleLine {
            lines.append(staleLine)
        }

        return lines
    }

    var accessibilityText: String {
        var text = summaryLine
        let labels = items.prefix(Self.maxListedItems).map { "\($0.kindLabel) \($0.displayLabel)" }
        if !labels.isEmpty {
            text += ": " + labels.joined(separator: "; ")
        }
        if isStale {
            text += " (may be stale)"
        }

        return text
    }

    /// Builds the waiting state for one session. Returns nil when the session is
    /// not idle, has no tracked obligations, or was omitted from the snapshot.
    static func make(
        sessionID: String,
        activityState: SMAgentActivityState,
        obligations: SMSessionObligations?,
        isStale: Bool,
        displayNameBySessionID: [String: String],
        now: Date
    ) -> SMAgentWaitingState? {
        guard activityState == .idle, let obligations, !obligations.items.isEmpty else {
            return nil
        }

        let reviewHistoryByPR = Dictionary(
            preservingFirstValues: obligations.reviewHistory.map { (PullRequestKey(repo: $0.repo, prNumber: $0.prNumber), $0) }
        )
        let sortedItems = obligations.items.sorted { lhs, rhs in
            switch (lhs.since, rhs.since) {
            case let (lhsSince?, rhsSince?):
                return lhsSince == rhsSince ? lhs.id < rhs.id : lhsSince < rhsSince
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.id < rhs.id
            }
        }

        let items = sortedItems.map { item -> SMWaitingItem in
            let requesterSessionID = SMWaitingFormatter.trimmed(item.requesterSessionID)
            let requesterDisplayName: String?
            if let requesterSessionID, requesterSessionID != sessionID {
                requesterDisplayName = displayNameBySessionID[requesterSessionID] ?? requesterSessionID
            } else {
                requesterDisplayName = nil
            }

            let reviewHistory: SMReviewHistoryEntry?
            if item.kind == .review, let repo = item.repo, let prNumber = item.prNumber {
                reviewHistory = reviewHistoryByPR[PullRequestKey(repo: repo, prNumber: prNumber)]
            } else {
                reviewHistory = nil
            }

            return SMWaitingItem(
                kind: item.kind,
                id: item.id,
                label: item.label,
                state: item.state,
                elapsedMinutes: elapsedMinutes(since: item.since, now: now),
                requesterDisplayName: requesterDisplayName,
                repo: item.repo,
                prNumber: item.prNumber,
                lastError: item.lastError,
                reviewHistory: reviewHistory
            )
        }

        // The server reports the oldest pending timestamp; fall back to the
        // items themselves when an older server omits it.
        let waitingSince = obligations.waitingSince ?? sortedItems.compactMap(\.since).min()

        return SMAgentWaitingState(
            items: items,
            elapsedMinutes: elapsedMinutes(since: waitingSince, now: now),
            isStale: isStale
        )
    }

    private static func elapsedMinutes(since: Date?, now: Date) -> Int? {
        guard let since else {
            return nil
        }

        return max(0, Int(now.timeIntervalSince(since) / 60))
    }

    private struct PullRequestKey: Hashable {
        let repo: String
        let prNumber: Int
    }
}

enum SMWaitingFormatter {
    private static let maxErrorLength = 120

    static func elapsedText(minutes: Int?) -> String {
        guard let minutes else {
            return "?"
        }

        guard minutes >= 1 else {
            return "<1m"
        }

        guard minutes >= 60 else {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        guard hours >= 24 else {
            let remainingMinutes = minutes % 60
            return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
        }

        let days = hours / 24
        let remainingHours = hours % 24
        return remainingHours == 0 ? "\(days)d" : "\(days)d \(remainingHours)h"
    }

    static func trimmed(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedValue, !trimmedValue.isEmpty else {
            return nil
        }

        return trimmedValue
    }

    static func truncated(_ value: String) -> String {
        guard value.count > maxErrorLength else {
            return value
        }

        return value.prefix(maxErrorLength) + "..."
    }
}
