import Foundation

nonisolated struct DivisionalStandings: Decodable, Sendable {
    let season: Int
    let conferences: [Conference]

    nonisolated struct Conference: Decodable, Identifiable, Sendable {
        let name: String
        let divisions: [Division]

        var id: String { name }
    }

    nonisolated struct Division: Decodable, Identifiable, Sendable {
        let name: String
        let teams: [TeamRecord]

        var id: String { name }
    }

    nonisolated struct TeamRecord: Decodable, Identifiable, Sendable {
        let team: String
        let season: Int
        let conference: String?
        let division: String?
        let wins: Int
        let losses: Int
        let ties: Int
        let gamesPlayed: Int
        let pointsFor: Int
        let pointsAgainst: Int
        let pointDiff: Int
        let winPct: Double

        var id: String { team }

        var record: String {
            if ties > 0 { return "\(wins)-\(losses)-\(ties)" }
            return "\(wins)-\(losses)"
        }
    }
}
