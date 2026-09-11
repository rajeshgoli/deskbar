import Foundation

/// Decodes `GET /session-obligations` responses. Every field except the session
/// id and obligation kind is optional so a server that adds or drops detail
/// cannot cost DeskBar the whole snapshot, and an unsupported `schema_version`
/// is reported as a failure rather than guessed at.
enum SMSessionObligationsParser {
    static let supportedSchemaVersion = 1

    static func parse(_ data: Data) -> [String: SMSessionObligations]? {
        guard let response = try? JSONDecoder().decode(SMSessionObligationsResponse.self, from: data) else {
            return nil
        }

        guard response.schemaVersion == supportedSchemaVersion else {
            return nil
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]
        let parseDate: (String?) -> Date? = { value in
            guard let value, !value.isEmpty else {
                return nil
            }

            return fractionalFormatter.date(from: value) ?? plainFormatter.date(from: value)
        }

        let obligations = response.sessions.compactMap { session -> (String, SMSessionObligations)? in
            let sessionID = session.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sessionID.isEmpty else {
                return nil
            }

            let items = (session.waitingOn ?? []).compactMap { item -> SMObligationItem? in
                guard let kind = SMWaitingKind(rawValue: item.kind) else {
                    return nil
                }

                return SMObligationItem(
                    kind: kind,
                    id: item.id,
                    label: item.label,
                    state: item.state,
                    since: parseDate(item.since),
                    requesterSessionID: item.requesterSessionID,
                    repo: item.repo,
                    prNumber: item.prNumber,
                    lastError: item.lastError
                )
            }

            let reviewHistory = (session.reviewHistory ?? []).compactMap { entry -> SMReviewHistoryEntry? in
                guard let repo = entry.repo, let prNumber = entry.prNumber else {
                    return nil
                }

                return SMReviewHistoryEntry(
                    repo: repo,
                    prNumber: prNumber,
                    requestCount: entry.requestCount ?? 0,
                    requestedByAgent: entry.requestedByAgent ?? 0,
                    landedCount: entry.landedCount ?? 0,
                    landedRequestedByAgent: entry.landedRequestedByAgent ?? 0
                )
            }

            // The server computes `waiting_since` over every obligation it
            // tracks, including kinds this build does not know how to show.
            // Falling back to the retained items keeps the elapsed wait tied to
            // what is actually listed, rather than reporting days against a
            // result the user cannot see.
            let droppedUnsupportedItems = items.count != (session.waitingOn ?? []).count
            let waitingSince = droppedUnsupportedItems
                ? items.compactMap(\.since).min()
                : parseDate(session.waitingSince)

            return (sessionID, SMSessionObligations(
                sessionID: sessionID,
                items: items,
                waitingSince: waitingSince,
                reviewHistory: reviewHistory
            ))
        }

        return Dictionary(preservingFirstValues: obligations)
    }
}

private struct SMSessionObligationsResponse: Decodable {
    let schemaVersion: Int
    let sessions: [SMAPISessionObligations]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessions
    }
}

private struct SMAPISessionObligations: Decodable {
    let sessionID: String
    let waitingOn: [SMAPIWaitingItem]?
    let waitingSince: String?
    let reviewHistory: [SMAPIReviewHistoryEntry]?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case waitingOn = "waiting_on"
        case waitingSince = "waiting_since"
        case reviewHistory = "review_history"
    }
}

private struct SMAPIWaitingItem: Decodable {
    let kind: String
    let id: String
    let label: String?
    let state: String?
    let since: String?
    let requesterSessionID: String?
    let repo: String?
    let prNumber: Int?
    let lastError: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case id
        case label
        case state
        case since
        case requesterSessionID = "requester_session_id"
        case repo
        case prNumber = "pr_number"
        case lastError = "last_error"
    }
}

private struct SMAPIReviewHistoryEntry: Decodable {
    let repo: String?
    let prNumber: Int?
    let requestCount: Int?
    let requestedByAgent: Int?
    let landedCount: Int?
    let landedRequestedByAgent: Int?

    enum CodingKeys: String, CodingKey {
        case repo
        case prNumber = "pr_number"
        case requestCount = "request_count"
        case requestedByAgent = "requested_by_agent"
        case landedCount = "landed_count"
        case landedRequestedByAgent = "landed_requested_by_agent"
    }
}
