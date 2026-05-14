import Foundation

nonisolated struct TeamsResponse: Decodable, Sendable {
    let teams: [Team]
}

nonisolated struct Team: Decodable, Identifiable, Sendable {
    let id: Int
    let espnId: String
    let abbreviation: String
    let location: String
    let nickname: String
    let displayName: String
    let shortDisplayName: String?
    let logoUrl: String?
    let primaryColor: String?
    let alternateColor: String?

    var espnIdInt: Int? { Int(espnId) }

    enum CodingKeys: String, CodingKey {
        case id, abbreviation, location, nickname
        case espnId = "espn_id"
        case displayName = "display_name"
        case shortDisplayName = "short_display_name"
        case logoUrl = "logo_url"
        case primaryColor = "primary_color"
        case alternateColor = "alternate_color"
    }
}
