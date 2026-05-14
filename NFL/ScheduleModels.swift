import Foundation

nonisolated struct ScheduleResponse: Decodable, Sendable {
    let season: Int
    let games: [ScheduleGame]
}

nonisolated struct ScheduleGame: Decodable, Identifiable, Sendable {
    let gameId: String
    let season: Int
    let week: Int
    let seasonType: String
    let kickoff: Date
    let homeTeam: String
    let awayTeam: String
    let homeScore: Int?
    let awayScore: Int?
    let overtime: Bool?
    let stadium: String?
    let roof: String?
    let surface: String?
    let espnId: Int

    var id: String { gameId }
    var isFinal: Bool { homeScore != nil && awayScore != nil && (homeScore != 0 || awayScore != 0) }

    var winnerAbbr: String? {
        guard let h = homeScore, let a = awayScore, isFinal else { return nil }
        if h > a { return homeTeam }
        if a > h { return awayTeam }
        return nil
    }
}
