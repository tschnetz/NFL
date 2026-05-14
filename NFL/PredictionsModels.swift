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
