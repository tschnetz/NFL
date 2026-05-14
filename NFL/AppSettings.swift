import Foundation
import Observation
import SwiftUI

/// Singleton settings store backed by UserDefaults. iCloud KV sync can
/// layer on later; for now everything is device-local.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    nonisolated enum Appearance: String, CaseIterable, Identifiable, Sendable {
        case system, light, dark

        var id: String { rawValue }
        var label: String { rawValue.capitalized }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    private enum Key {
        static let apiKey = "nfl.apiKey"
        static let activePicker = "nfl.activePicker"
        static let favoriteTeams = "nfl.favoriteTeamAbbrs"
        static let appearance = "nfl.appearance"
        static let hasCompletedOnboarding = "nfl.hasCompletedOnboarding"
    }

    private let defaults: UserDefaults

    var apiKey: String {
        didSet {
            defaults.set(apiKey, forKey: Key.apiKey)
            let token = apiKey
            Task { await APIClient.shared.setAuthToken(token) }
        }
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

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.apiKey = defaults.string(forKey: Key.apiKey) ?? ""
        self.activePicker = defaults.string(forKey: Key.activePicker)
        self.favoriteTeamAbbrs = Set(
            defaults.stringArray(forKey: Key.favoriteTeams) ?? []
        )
        self.appearance = Appearance(
            rawValue: defaults.string(forKey: Key.appearance) ?? ""
        ) ?? .system
        self.hasCompletedOnboarding = defaults.bool(
            forKey: Key.hasCompletedOnboarding
        )

        // Push the persisted auth token into the API client so the first
        // request after launch carries the bearer header.
        let initialToken = self.apiKey
        Task { await APIClient.shared.setAuthToken(initialToken) }
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
