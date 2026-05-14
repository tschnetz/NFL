import SwiftUI

nonisolated enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

@MainActor
@Observable
final class GamesViewModel {
    var season: Int {
        didSet { Task { await reload() } }
    }
    var week: Int {
        didSet { Task { await reloadPredictions() } }
    }

    var schedule: LoadState<[ScheduleGame]> = .idle
    var predictions: LoadState<[Int: GamePrediction]> = .idle

    let availableSeasons: [Int] = [2024, 2023, 2022, 2021, 2020]
    let availableWeeks: [Int] = Array(1...18)

    private let client: APIClient

    init(season: Int = 2024, week: Int = 6, client: APIClient = .shared) {
        self.season = season
        self.week = week
        self.client = client
    }

    var gamesForCurrentWeek: [ScheduleGame] {
        guard case .loaded(let all) = schedule else { return [] }
        return all
            .filter { $0.week == week && $0.seasonType == "regular" }
            .sorted { $0.kickoff < $1.kickoff }
    }

    func prediction(for game: ScheduleGame) -> GamePrediction? {
        guard case .loaded(let map) = predictions else { return nil }
        return map[game.espnId]
    }

    func reload() async {
        async let s: () = loadSchedule()
        async let p: () = loadPredictions()
        _ = await (s, p)
    }

    func reloadPredictions() async {
        await loadPredictions()
    }

    private func loadSchedule() async {
        schedule = .loading
        do {
            let response: ScheduleResponse = try await client.get("/api/schedule/\(season)")
            schedule = .loaded(response.games)
        } catch {
            schedule = .failed(error.localizedDescription)
        }
    }

    private func loadPredictions() async {
        predictions = .loading
        do {
            let path = "/api/preds/\(season)/w\(week)"
            let response: PredictionsResponse = try await client.get(path)
            let map = Dictionary(uniqueKeysWithValues: response.predictions.map { ($0.espnId, $0) })
            predictions = .loaded(map)
        } catch {
            predictions = .failed(error.localizedDescription)
        }
    }
}

struct GamesView: View {
    @State private var model = GamesViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekChips
                Divider().opacity(0.5)
                content
            }
            .navigationTitle("Games")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { seasonMenu }
            }
            .task { await model.reload() }
            .refreshable { await model.reload() }
        }
    }

    private var seasonMenu: some View {
        Menu {
            ForEach(model.availableSeasons, id: \.self) { season in
                Button {
                    model.season = season
                } label: {
                    if model.season == season {
                        Label(String(season), systemImage: "checkmark")
                    } else {
                        Text(String(season))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(String(model.season))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
        }
    }

    private var weekChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.availableWeeks, id: \.self) { week in
                        Button {
                            model.week = week
                        } label: {
                            Text("Week \(week)")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background {
                                    Capsule().fill(
                                        model.week == week
                                        ? AnyShapeStyle(.tint)
                                        : AnyShapeStyle(.background.secondary)
                                    )
                                }
                                .foregroundStyle(model.week == week ? Color.white : .primary)
                                .id(week)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onAppear { proxy.scrollTo(model.week, anchor: .center) }
            .onChange(of: model.week) { _, new in
                withAnimation { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.schedule {
        case .idle, .loading:
            VStack { Spacer(); ProgressView().controlSize(.large); Spacer() }
        case .failed(let message):
            ContentUnavailableView("Couldn’t load schedule",
                                   systemImage: "wifi.exclamationmark",
                                   description: Text(message))
        case .loaded:
            let games = model.gamesForCurrentWeek
            if games.isEmpty {
                ContentUnavailableView("No games for week \(model.week)",
                                       systemImage: "sportscourt",
                                       description: Text("Try a different week."))
            } else {
                List(games) { game in
                    NavigationLink {
                        GameDetailView(game: game, prediction: model.prediction(for: game))
                    } label: {
                        GameRowView(game: game, prediction: model.prediction(for: game))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct GameRowView: View {
    let game: ScheduleGame
    let prediction: GamePrediction?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    teamLine(abbr: game.awayTeam, score: game.awayScore, isWinner: game.winnerAbbr == game.awayTeam)
                    teamLine(abbr: game.homeTeam, score: game.homeScore, isWinner: game.winnerAbbr == game.homeTeam)
                }
                Spacer()
                statusBlock
            }
            if let pick = prediction {
                Divider().opacity(0.4)
                PredictionBadge(prediction: pick)
            }
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }

    private func teamLine(abbr: String, score: Int?, isWinner: Bool) -> some View {
        HStack(spacing: 10) {
            Text(abbr)
                .font(.headline)
                .frame(width: 44, alignment: .leading)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Text(score.map(String.init) ?? "—")
                .font(.title3.weight(isWinner ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(isWinner ? .primary : .secondary)
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if game.isFinal {
                Text("Final\(game.overtime == true ? " · OT" : "")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text(game.kickoff, style: .date)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(game.kickoff, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct PredictionBadge: View {
    let prediction: GamePrediction

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Model pick")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Text(prediction.bestBet ?? prediction.spreadPick ?? "—")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
            if let strength = prediction.bestBetStrengthValue {
                strengthBadge(strength)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(marginText)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                if let cover = prediction.predCoverProbCal {
                    Text("\(Int(cover * 100))% cover")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var marginText: String {
        let margin = prediction.predHomeMargin
        let sign = margin >= 0 ? "+" : ""
        let teamForSign = margin >= 0 ? prediction.homeTeam : prediction.awayTeam
        let absMargin = abs(margin)
        return "\(teamForSign) \(sign)\(String(format: "%.1f", margin >= 0 ? absMargin : -absMargin))"
    }

    private func strengthBadge(_ strength: GamePrediction.Strength) -> some View {
        Text(strength.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(strengthColor(strength).opacity(0.18), in: Capsule())
            .foregroundStyle(strengthColor(strength))
    }

    private func strengthColor(_ strength: GamePrediction.Strength) -> Color {
        switch strength {
        case .strong: .green
        case .medium: .blue
        case .lean: .orange
        case .pass: .secondary
        }
    }
}

#Preview {
    GamesView()
}
