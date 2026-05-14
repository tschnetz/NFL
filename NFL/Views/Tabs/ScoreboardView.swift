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

    var competition: ScoreboardCompetition? { competitions.first }
    var home: ScoreboardCompetitor? {
        competition?.competitors.first { $0.homeAway == "home" }
    }
    var away: ScoreboardCompetitor? {
        competition?.competitors.first { $0.homeAway == "away" }
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
                        ScoreboardCard(event: event)
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct ScoreboardCard: View {
    let event: ScoreboardEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                statusBadge
                Spacer()
                if event.status.type.state == "pre" {
                    Text(event.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 8) {
                teamLine(competitor: event.away)
                teamLine(competitor: event.home)
            }
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    private func teamLine(competitor: ScoreboardCompetitor?) -> some View {
        let abbr = competitor?.team.abbreviation ?? "—"
        let teamColor = TeamRepository.shared.team(abbr: abbr)?.primarySwiftUIColor
        let isWinner: Bool = {
            guard event.status.type.state == "post",
                  let mine = competitor?.scoreInt else { return false }
            let other = (competitor?.id == event.home?.id
                         ? event.away : event.home)?.scoreInt
            return other.map { mine > $0 } ?? false
        }()
        return HStack(spacing: 10) {
            TeamLogoView(abbr: abbr, size: 30, style: .helmet)
            Text(abbr)
                .font(.headline)
                .frame(width: 48, alignment: .leading)
                .foregroundStyle(teamColor ?? .primary)
            Text(competitor?.team.shortDisplayName
                 ?? competitor?.team.displayName ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(competitor?.scoreInt.map(String.init) ?? "—")
                .font(.title3.weight(isWinner ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isWinner ? .primary : .secondary)
        }
    }

    private var statusBadge: some View {
        Text(badgeText)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.18), in: Capsule())
            .foregroundStyle(badgeColor)
    }

    private var badgeText: String {
        switch event.status.type.state {
        case "in":
            if let period = event.status.period,
               let clock = event.status.displayClock {
                return "Q\(period) · \(clock)"
            }
            return event.status.type.description
        default:
            return event.status.type.description
        }
    }

    private var badgeColor: Color {
        switch event.status.type.state {
        case "in": .orange
        case "post": .secondary
        default: .blue
        }
    }
}

#Preview {
    ScoreboardView()
}
