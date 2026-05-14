import Foundation

nonisolated struct PredictionsResponse: Decodable, Sendable {
    let season: Int
    let week: Int
    let seasonType: String?
    let version: String?
    let source: String?
    let predictions: [GamePrediction]
}

nonisolated struct GamePrediction: Decodable, Identifiable, Sendable {
    let gameId: String
    let espnId: Int
    let season: Int
    let week: Int
    let homeTeam: String
    let awayTeam: String
    let spreadLine: Double?
    let overUnderLine: Double?

    let predHomeMargin: Double
    let predHomeWinProb: Double?
    let predCoverProbCal: Double?

    let spreadPick: String?
    let spreadBetStrength: String?
    let totalPick: String?
    let totalBetStrength: String?
    let bestBet: String?
    let bestBetStrength: String?
    let bestBetEdge: Double?
    let bestBetMarket: String?

    let muPost: Double?
    let sigmaPost: Double?
    let marginCi80Lower: Double?
    let marginCi80Upper: Double?
    let kellyFraction: Double?

    var id: String { gameId }

    enum CodingKeys: String, CodingKey {
        case gameId = "game_id"
        case espnId = "id"
        case season, week
        case homeTeam = "home_team"
        case awayTeam = "away_team"
        case spreadLine = "spread_line"
        case overUnderLine = "over_under_line"
        case predHomeMargin = "pred_home_margin"
        case predHomeWinProb = "pred_home_win_prob"
        case predCoverProbCal = "pred_cover_prob_cal"
        case spreadPick = "spread_pick"
        case spreadBetStrength = "spread_bet_strength"
        case totalPick = "total_pick"
        case totalBetStrength = "total_bet_strength"
        case bestBet = "best_bet"
        case bestBetStrength = "best_bet_strength"
        case bestBetEdge = "best_bet_edge"
        case bestBetMarket = "best_bet_market"
        case muPost = "mu_post"
        case sigmaPost = "sigma_post"
        case marginCi80Lower = "margin_ci_80_lower"
        case marginCi80Upper = "margin_ci_80_upper"
        case kellyFraction = "kelly_fraction"
    }
}

extension GamePrediction {
    enum Strength: String {
        case strong = "Strong"
        case medium = "Medium"
        case lean = "Lean"
        case pass = "Pass"

        var displayColor: BetColorRole {
            switch self {
            case .strong: .strong
            case .medium: .medium
            case .lean: .lean
            case .pass: .pass
            }
        }
    }

    enum BetColorRole {
        case strong, medium, lean, pass
    }

    var bestBetStrengthValue: Strength? {
        bestBetStrength.flatMap(Strength.init)
    }
}

// MARK: - Predictions weekly summary (from /api/preds/summary/...)

nonisolated struct PredictionsSummary: Decodable, Sendable {
    let season: Int
    let week: Int
    let seasonType: String?
    let version: String?
    let games: Int
    let strength: [String: Int]
    let spread: StrengthBucket
    let total: TotalBucket
    let topSpreads: [SummaryRow]
    let topTotals: [SummaryRow]
    let topBestBets: [SummaryRow]

    func strengthCount(_ key: GamePrediction.Strength) -> Int {
        strength[key.rawValue] ?? 0
    }
}

nonisolated struct StrengthBucket: Decodable, Sendable {
    let byStrength: [String: Int]
}

nonisolated struct TotalBucket: Decodable, Sendable {
    let byStrength: [String: Int]
    let overCount: Int
    let underCount: Int
}

nonisolated struct SummaryRow: Decodable, Identifiable, Sendable {
    let gameId: String?
    let espnId: Int?
    let homeTeam: String?
    let awayTeam: String?
    let pick: String?
    let market: String?
    let strength: String?
    let edge: Double?
    let predHomeMargin: Double?
    let line: Double?

    var id: String {
        if let gameId { return gameId }
        if let espnId { return String(espnId) }
        return "\(homeTeam ?? "")_\(awayTeam ?? "")_\(pick ?? "")"
    }

    var strengthValue: GamePrediction.Strength? {
        strength.flatMap(GamePrediction.Strength.init)
    }

    enum CodingKeys: String, CodingKey {
        case gameId, homeTeam, awayTeam, pick, market, strength, edge,
             predHomeMargin, line
        case espnId = "id"
    }
}
