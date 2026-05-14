import Foundation
import SwiftUI

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

    var primarySwiftUIColor: Color? {
        primaryColor.flatMap { Color(hex: $0) }
    }

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

extension Color {
    /// Parses a six-character RGB hex string like "002a5c" or "#002a5c".
    nonisolated init?(hex raw: String) {
        let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
