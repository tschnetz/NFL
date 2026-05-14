import Foundation

nonisolated struct EventOddsResponse: Decodable, Sendable {
    let eventId: Int
    let source: String?
    let espn: ESPNOddsEnvelope?

    var items: [OddsItem] { espn?.items ?? [] }
}

nonisolated struct ESPNOddsEnvelope: Decodable, Sendable {
    let items: [OddsItem]
}

nonisolated struct OddsItem: Decodable, Identifiable, Sendable {
    let provider: OddsProvider
    let details: String?
    let spread: Double?
    let overUnder: Double?
    let moneylineWinner: String?
    let spreadWinner: String?

    var id: String { provider.id }
}

nonisolated struct OddsProvider: Decodable, Sendable {
    let id: String
    let name: String
    let priority: Int?
}
