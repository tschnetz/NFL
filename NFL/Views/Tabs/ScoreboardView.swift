import SwiftUI

// MARK: - Models for /api/scoreboard/day

nonisolated struct ScoreboardPayload: Decodable, Sendable {
    let events: [ScoreboardEvent]
}

nonisolated struct ScoreboardEvent: Decodable, Identifiable, Sendable {
    let id: String
    let date: Date
    let shortName: String
    let status: ScoreboardStatus
    let competitions: [ScoreboardCompetition]
    let season: SeasonInfo?
    let week: WeekInfo?

    nonisolated struct SeasonInfo: Decodable, Sendable {
        let year: Int
        let type: Int?
    }

    nonisolated struct WeekInfo: Decodable, Sendable {
        let number: Int
    }

    var competition: ScoreboardCompetition? { competitions.first }
    var home: ScoreboardCompetitor? {
        competition?.competitors.first { $0.homeAway == "home" }
    }
    var away: ScoreboardCompetitor? {
        competition?.competitors.first { $0.homeAway == "away" }
    }

    /// Build a ScheduleGame so the card can drill into GameDetailView with
    /// the same model the rest of the app uses. Some fields (roof, surface,
    /// stadium) aren't carried by the scoreboard payload — left nil.
    func asScheduleGame() -> ScheduleGame? {
        guard let homeAbbr = home?.team.abbreviation,
              let awayAbbr = away?.team.abbreviation else { return nil }
        let espnId = Int(id) ?? 0
        let seasonYear = season?.year ?? 0
        let weekNum = week?.number ?? 0
        let seasonType: String = {
            switch season?.type {
            case 1: return "preseason"
            case 3: return "postseason"
            default: return "regular"
            }
        }()
        return ScheduleGame(
            gameId: "\(seasonYear)_\(String(format: "%02d", weekNum))_\(awayAbbr)_\(homeAbbr)",
            season: seasonYear,
            week: weekNum,
            seasonType: seasonType,
            kickoff: date,
            homeTeam: homeAbbr,
            awayTeam: awayAbbr,
            homeScore: home?.scoreInt,
            awayScore: away?.scoreInt,
            overtime: nil,
            stadium: competition?.venue?.fullName,
            roof: nil,
            surface: nil,
            espnId: espnId
        )
    }
}

nonisolated struct ScoreboardStatus: Decodable, Sendable {
    let type: StatusType
    let displayClock: String?
    let period: Int?

    nonisolated struct StatusType: Decodable, Sendable {
        let state: String        // "pre" | "in" | "post"
        let description: String  // "Scheduled" | "In Progress" | "Final"
    }
}

nonisolated struct ScoreboardCompetition: Decodable, Sendable {
    let competitors: [ScoreboardCompetitor]
    let venue: ScoreboardVenue?
}

nonisolated struct ScoreboardVenue: Decodable, Sendable {
    let fullName: String?
}

nonisolated struct ScoreboardCompetitor: Decodable, Identifiable, Sendable {
    let id: String
    let homeAway: String
    let score: String?
    let team: ScoreboardTeam

    var scoreInt: Int? { score.flatMap(Int.init) }
}

nonisolated struct ScoreboardTeam: Decodable, Sendable {
    let abbreviation: String?
    let displayName: String
    let shortDisplayName: String?
}

// MARK: - View model

@MainActor
@Observable
final class ScoreboardViewModel {
    var state: LoadState<[ScoreboardEvent]> = .idle

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func load() async {
        if case .idle = state { state = .loading }
        do {
            let payload: ScoreboardPayload = try await client.get("/api/scoreboard/day")
            state = .loaded(payload.events)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct ScoreboardView: View {
    @State private var model = ScoreboardViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Scoreboard")
                .task {
                    await model.load()
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(10)) } catch { return }
                        await model.load()
                    }
                }
                .refreshable { await model.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView().controlSize(.large)
        case .failed(let message):
            ContentUnavailableView("Couldn’t load scoreboard",
                                   systemImage: "wifi.exclamationmark",
                                   description: Text(message))
        case .loaded(let events) where events.isEmpty:
            ContentUnavailableView("No games today",
                                   systemImage: "sportscourt",
                                   description: Text("Check back closer to game day."))
        case .loaded(let events):
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(events) { event in
                        if let game = event.asScheduleGame() {
                            NavigationLink {
                                GameDetailView(game: game, prediction: nil)
                            } label: {
                                ScoreboardCard(event: event)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ScoreboardCard(event: event)
                        }
                    }
                }
                .padding(16)
            }
        }
    }
}

/// Visually mirrors `ResultsRow` from ResultsView so the Scoreboard and
/// Results tabs feel like the same game-card surface. Differences:
/// the status block uses live clock + period for in-progress games, and
/// there's no inline model-pick badge (predictions are surfaced on
/// drill-in via GameDetailView).
private struct ScoreboardCard: View {
    let event: ScoreboardEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    teamLine(competitor: event.away, isWinner: isWinner(event.away))
                    teamLine(competitor: event.home, isWinner: isWinner(event.home))
                }
                Spacer()
                statusBlock
            }
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func teamLine(competitor: ScoreboardCompetitor?, isWinner: Bool) -> some View {
        let abbr = competitor?.team.abbreviation ?? "—"
        let teamColor = TeamRepository.shared.team(abbr: abbr)?.primarySwiftUIColor
        return HStack(spacing: 10) {
            TeamLogoView(abbr: abbr, size: 26)
            Text(abbr)
                .font(.headline)
                .frame(width: 44, alignment: .leading)
                .foregroundStyle(teamColor ?? .primary)
            Spacer(minLength: 0)
            Text(competitor?.scoreInt.map(String.init) ?? "—")
                .font(.title3.weight(isWinner ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isWinner ? .primary : .secondary)
        }
    }

    private func isWinner(_ competitor: ScoreboardCompetitor?) -> Bool {
        guard event.status.type.state == "post",
              let mine = competitor?.scoreInt else { return false }
        let other = (competitor?.id == event.home?.id
                     ? event.away : event.home)?.scoreInt
        return other.map { mine > $0 } ?? false
    }

    private var statusBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            switch event.status.type.state {
            case "post":
                Text("Final")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            case "in":
                if let period = event.status.period,
                   let clock = event.status.displayClock {
                    Text("Q\(period)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(clock)
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                } else {
                    Text(event.status.type.description)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            default:
                Text(event.date, style: .date)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(event.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    ScoreboardView()
}
