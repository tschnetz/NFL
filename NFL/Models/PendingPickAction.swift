import Foundation

/// One outstanding picks-mutation that failed to reach the backend.
/// Persisted to UserDefaults via `OfflinePicksQueue` and replayed when
/// connectivity returns.
///
/// Scope is intentionally narrow — only the player-driven actions that
/// users hit on a flaky connection (pick / unpick). Admin actions
/// (open / close / score / advanceTurn / markDoubles / markPresses) are
/// not queued; if they fail offline, surface the error normally so the
/// user can retry intentionally.
nonisolated struct PendingPickAction: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case makePick
        case unpick
    }

    let id: UUID
    let kind: Kind
    let season: Int
    let week: Int
    let seasonType: String
    let picker: Player
    let gameId: Int

    // makePick-only
    let teamId: Int?
    let teamName: String?

    let createdAt: Date
    var lastAttemptedAt: Date?
    var attempts: Int
    var lastError: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        season: Int,
        week: Int,
        seasonType: String,
        picker: Player,
        gameId: Int,
        teamId: Int? = nil,
        teamName: String? = nil,
        createdAt: Date = Date(),
        lastAttemptedAt: Date? = nil,
        attempts: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.season = season
        self.week = week
        self.seasonType = seasonType
        self.picker = picker
        self.gameId = gameId
        self.teamId = teamId
        self.teamName = teamName
        self.createdAt = createdAt
        self.lastAttemptedAt = lastAttemptedAt
        self.attempts = attempts
        self.lastError = lastError
    }

    /// Replay this action against the API. Returns the resulting
    /// `PicksState` envelope on success. Throws on failure so the queue
    /// can classify and decide whether to keep retrying.
    func execute(client: APIClient) async throws -> APIEnvelope<PicksState> {
        switch kind {
        case .makePick:
            guard let teamId else {
                throw OfflinePicksError.malformedAction("makePick missing teamId")
            }
            nonisolated struct Body: Encodable {
                let season: Int
                let week: Int
                let seasonType: String
                let userId: String
                let gameId: Int
                let teamId: Int
                let teamName: String?
            }
            let body = Body(
                season: season, week: week, seasonType: seasonType,
                userId: picker.rawValue, gameId: gameId,
                teamId: teamId, teamName: teamName
            )
            return try await client.post("/api/picks/pick", body: body)

        case .unpick:
            nonisolated struct Body: Encodable {
                let season: Int
                let week: Int
                let seasonType: String
                let userId: String
                let gameId: Int
            }
            let body = Body(
                season: season, week: week, seasonType: seasonType,
                userId: picker.rawValue, gameId: gameId
            )
            return try await client.post("/api/picks/unpick", body: body)
        }
    }
}

nonisolated enum OfflinePicksError: Error {
    case malformedAction(String)
}
