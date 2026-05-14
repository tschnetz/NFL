import Foundation

nonisolated struct APIEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    let ok: Bool
    let data: T
}

nonisolated struct PicksState: Decodable, Sendable {
    let season: Int
    let week: Int
    let seasonType: String
    let status: Status
    let currentTurn: String?
    let totalGames: Int
    let basePoints: Int
    let lockedAt: Date?
    let scoredAt: Date?
    let updatedAt: Date

    nonisolated enum Status: String, Decodable, Sendable {
        case picking
        case locked
        case scored
        case unknown

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }

        var label: String {
            switch self {
            case .picking: "Picking"
            case .locked: "Locked"
            case .scored: "Scored"
            case .unknown: "—"
            }
        }
    }
}
