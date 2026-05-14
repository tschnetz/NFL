import SwiftUI

nonisolated enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

@MainActor
@Observable
final class ScoreboardViewModel {
    var state: LoadState<[ScoreboardEvent]> = .idle

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func load() async {
        state = .loading
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
                .task { await model.load() }
                .refreshable { await model.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView().controlSize(.large)
        case .failed(let message):
            ContentUnavailableView("Couldn’t load games",
                                   systemImage: "wifi.exclamationmark",
                                   description: Text(message))
        case .loaded(let events) where events.isEmpty:
            ContentUnavailableView("No games today",
                                   systemImage: "sportscourt",
                                   description: Text("Check back closer to game day."))
        case .loaded(let events):
            List(events) { event in
                GameRowView(event: event)
                    .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            .listStyle(.plain)
        }
    }
}

private struct GameRowView: View {
    let event: ScoreboardEvent

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                teamLine(event.away)
                teamLine(event.home)
            }
            Spacer()
            statusBadge
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }

    private func teamLine(_ competitor: ScoreboardCompetitor?) -> some View {
        HStack(spacing: 10) {
            Text(competitor?.team.abbreviation ?? "—")
                .font(.headline)
                .frame(width: 44, alignment: .leading)
            Text(competitor?.team.shortDisplayName ?? competitor?.team.displayName ?? "")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(competitor?.scoreInt.map(String.init) ?? "—")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(competitor.map(isWinner) == true ? .primary : .secondary)
        }
    }

    private func isWinner(_ competitor: ScoreboardCompetitor) -> Bool {
        guard event.status.type.state == "post",
              let mine = competitor.scoreInt else { return false }
        let other = (competitor.id == event.home?.id ? event.away : event.home)?.scoreInt
        return other.map { mine > $0 } ?? false
    }

    private var statusBadge: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(badgeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(badgeColor)
            if event.status.type.state == "pre" {
                Text(event.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var badgeText: String {
        switch event.status.type.state {
        case "in":
            if let period = event.status.period, let clock = event.status.displayClock {
                return "Q\(period) \(clock)"
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
        default: .secondary
        }
    }
}

#Preview {
    ScoreboardView()
}
