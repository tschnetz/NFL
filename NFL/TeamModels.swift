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

// MARK: - Team detail payloads

nonisolated struct TeamSeasonStats: Decodable, Sendable {
    let team: String
    let season: Int
    let conference: String?
    let division: String?
    let weeksPlayed: Int
    let totals: [String: Double]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.team = try container.decode(String.self, forKey: .team)
        self.season = try container.decode(Int.self, forKey: .season)
        self.conference = try container.decodeIfPresent(String.self, forKey: .conference)
        self.division = try container.decodeIfPresent(String.self, forKey: .division)
        self.weeksPlayed = try container.decode(Int.self, forKey: .weeksPlayed)
        // Backend returns mixed Int/Double values per key; normalize to Double.
        let raw = try container.decode([String: AnyNumber].self, forKey: .totals)
        self.totals = raw.mapValues { $0.doubleValue }
    }

    enum CodingKeys: String, CodingKey {
        case team, season, conference, division, weeksPlayed, totals
    }
}

nonisolated struct TeamLeaders: Decodable, Sendable {
    let team: String
    let season: Int
    let categories: [Category]

    nonisolated struct Category: Decodable, Identifiable, Sendable {
        let key: String
        let label: String
        let players: [Player]

        var id: String { key }
    }

    nonisolated struct Player: Decodable, Identifiable, Sendable {
        let playerId: String
        let playerName: String?
        let position: String?
        let value: Double

        var id: String { playerId }
    }
}

nonisolated struct RosterPayload: Decodable, Sendable {
    let team: String
    let season: Int
    let week: Int?
    let roster: [Player]
    let depth: [DepthEntry]

    nonisolated struct Player: Decodable, Identifiable, Sendable {
        let playerId: String
        let playerName: String?
        let position: String?
        let jersey: String?
        let status: String?

        var id: String { playerId }
    }

    nonisolated struct DepthEntry: Decodable, Sendable {
        let position: String?
        let depthPosition: String?
        let playerId: String?
        let playerName: String?
    }
}

/// Helper to decode a JSON number that may arrive as either Int or Double.
private struct AnyNumber: Decodable, Sendable {
    let doubleValue: Double

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let i = try? container.decode(Int.self) {
            doubleValue = Double(i)
        } else {
            doubleValue = try container.decode(Double.self)
        }
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
