import Foundation
import Observation

/// Shared year + seasonType + week state injected at the app root.
///
/// Pigskin pattern: tabs that drill into a specific week (Predictions,
/// Results) read this; tabs that browse a whole season (Games, Standings,
/// Teams) read only `year`. Changing the week in Predictions propagates
/// to Results without coupling them.
@MainActor
@Observable
final class WeekSelection {
    var year: Int
    var seasonType: String
    var week: Int

    let availableSeasons: [Int]
    let availableWeeks: [Int]

    init(year: Int = WeekSelection.defaultYear,
         seasonType: String = "regular",
         week: Int = 1) {
        self.year = year
        self.seasonType = seasonType
        self.week = week
        self.availableSeasons = Array((2020...WeekSelection.defaultYear).reversed())
        self.availableWeeks = Array(1...18)
    }

    /// Defaults to the most recently *completed* NFL season (Feb cutoff).
    /// In May 2026 this is 2025; in October 2026 it would be 2026 since the
    /// new season has started. Tabs that need "browse current week" can
    /// keep their own override.
    nonisolated static var defaultYear: Int {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        // NFL season begins September; before Sept the "current season" is
        // the one that ended this past Feb.
        return month < 9 ? year - 1 : year
    }
}
