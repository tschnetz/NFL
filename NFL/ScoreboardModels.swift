import Foundation

nonisolated struct ScoreboardPayload: Decodable, Sendable {
    let events: [ScoreboardEvent]
}

nonisolated struct ScoreboardEvent: Decodable, Identifiable, Sendable {
    let id: String
    let date: Date
    let shortName: String
    let status: ScoreboardStatus
    let competitions: [ScoreboardCompetition]

    var competition: ScoreboardCompetition? { competitions.first }
    var home: ScoreboardCompetitor? { competition?.competitors.first { $0.homeAway == "home" } }
    var away: ScoreboardCompetitor? { competition?.competitors.first { $0.homeAway == "away" } }
}

nonisolated struct ScoreboardStatus: Decodable, Sendable {
    let type: StatusType
    let displayClock: String?
    let period: Int?

    nonisolated struct StatusType: Decodable, Sendable {
        let state: String        // "pre" | "in" | "post"
        let description: String  // "Scheduled" | "In Progress" | "Final"
    }
}

nonisolated struct ScoreboardCompetition: Decodable, Sendable {
    let competitors: [ScoreboardCompetitor]
}

nonisolated struct ScoreboardCompetitor: Decodable, Identifiable, Sendable {
    let id: String
    let homeAway: String
    let score: String?
    let team: ScoreboardTeam

    var scoreInt: Int? { score.flatMap(Int.init) }
}

nonisolated struct ScoreboardTeam: Decodable, Sendable {
    let abbreviation: String?
    let displayName: String
    let shortDisplayName: String?
    let logo: String?
}
