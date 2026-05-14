import Foundation
import Observation

/// Singleton settings store backed by UserDefaults. iCloud KV sync can
/// layer on later; for now everything is device-local.
///
/// Tracked:
/// - `apiKey` — bearer token for /api/* when backend `API_KEY` is set.
/// - `activePicker` — Jim / Tom / nil. Used to highlight "your" turn.
/// - `favoriteTeamAbbrs` — set of team abbreviations for Pigskin-style
///   favorites filtering (e.g. Results screen, Teams browser).
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let apiKey = "nfl.apiKey"
        static let activePicker = "nfl.activePicker"
        static let favoriteTeams = "nfl.favoriteTeamAbbrs"
    }

    private let defaults: UserDefaults

    var apiKey: String {
        didSet { defaults.set(apiKey, forKey: Key.apiKey) }
    }

    var activePicker: String? {
        didSet { defaults.set(activePicker, forKey: Key.activePicker) }
    }

    var favoriteTeamAbbrs: Set<String> {
        didSet {
            defaults.set(Array(favoriteTeamAbbrs).sorted(),
                         forKey: Key.favoriteTeams)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.apiKey = defaults.string(forKey: Key.apiKey) ?? ""
        self.activePicker = defaults.string(forKey: Key.activePicker)
        self.favoriteTeamAbbrs = Set(
            defaults.stringArray(forKey: Key.favoriteTeams) ?? []
        )
    }

    func toggleFavorite(_ abbr: String) {
        let upper = abbr.uppercased()
        if favoriteTeamAbbrs.contains(upper) {
            favoriteTeamAbbrs.remove(upper)
        } else {
            favoriteTeamAbbrs.insert(upper)
        }
    }
}
