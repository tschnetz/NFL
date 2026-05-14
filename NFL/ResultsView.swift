import SwiftUI

@MainActor
@Observable
final class ResultsViewModel {
    var schedule: LoadState<[ScheduleGame]> = .idle
    var predictions: LoadState<[Int: GamePrediction]> = .idle

    private let client: APIClient
    private var loadedSeason: Int?

    init(client: APIClient = .shared) {
        self.client = client
    }

    func load(season: Int, week: Int) async {
        // Schedule is per-season — only refetch when the season changes.
        let needSchedule = loadedSeason != season
        if needSchedule {
            async let a: () = loadSchedule(season: season)
            async let b: () = loadPredictions(season: season, week: week)
            _ = await (a, b)
        } else {
            await loadPredictions(season: season, week: week)
        }
    }

    func games(forWeek week: Int) -> [ScheduleGame] {
        guard case .loaded(let all) = schedule else { return [] }
        return all
            .filter { $0.week == week && $0.seasonType == "regular" }
            .sorted { $0.kickoff < $1.kickoff }
    }

    func prediction(for game: ScheduleGame) -> GamePrediction? {
        guard case .loaded(let map) = predictions else { return nil }
        return map[game.espnId]
    }

    private func loadSchedule(season: Int) async {
        schedule = .loading
        do {
            let response: ScheduleResponse = try await client.get("/api/schedule/\(season)")
            schedule = .loaded(response.games)
            loadedSeason = season
        } catch {
            schedule = .failed(error.localizedDescription)
        }
    }

    private func loadPredictions(season: Int, week: Int) async {
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

struct ResultsView: View {
    @Environment(WeekSelection.self) private var selection
    @Environment(AppSettings.self) private var settings
    @State private var model = ResultsViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Results")
                .toolbar { toolbarContent }
                .task(id: pivotKey) {
                    await model.load(season: selection.year, week: selection.week)
                }
                .refreshable {
                    await model.load(season: selection.year, week: selection.week)
                }
        }
    }

    private var pivotKey: String { "\(selection.year)-\(selection.week)" }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Season") {
                    ForEach(selection.availableSeasons, id: \.self) { s in
                        Button {
                            selection.year = s
                        } label: {
                            if s == selection.year {
                                Label(String(s), systemImage: "checkmark")
                            } else {
                                Text(String(s))
                            }
                        }
                    }
                }
                Section("Week") {
                    ForEach(selection.availableWeeks, id: \.self) { w in
                        Button {
                            selection.week = w
                        } label: {
                            if w == selection.week {
                                Label("Week \(w)", systemImage: "checkmark")
                            } else {
                                Text("Week \(w)")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(String(selection.year)) · W\(selection.week)")
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(.subheadline.weight(.medium))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.schedule {
        case .idle, .loading:
            ProgressView().controlSize(.large)
        case .failed(let message):
            ContentUnavailableView("Couldn’t load results",
                                   systemImage: "wifi.exclamationmark",
                                   description: Text(message))
        case .loaded:
            let weekGames = model.games(forWeek: selection.week)
            if weekGames.isEmpty {
                ContentUnavailableView("No games",
                                       systemImage: "sportscourt",
                                       description: Text("Nothing scheduled for week \(selection.week)."))
            } else {
                resultsList(weekGames)
            }
        }
    }

    private func resultsList(_ games: [ScheduleGame]) -> some View {
        let favorites = settings.favoriteTeamAbbrs
        let favoriteGames = games.filter {
            favorites.contains($0.homeTeam) || favorites.contains($0.awayTeam)
        }
        let finalGames = games.filter { $0.isFinal }
        let pendingGames = games.filter { !$0.isFinal }
        return List {
            if !favoriteGames.isEmpty {
                Section("Favorites") {
                    ForEach(favoriteGames) { game in
                        navRow(game)
                    }
                }
            }
            if !finalGames.isEmpty {
                Section("Final") {
                    ForEach(finalGames) { game in
                        navRow(game)
                    }
                }
            }
            if !pendingGames.isEmpty {
                Section(finalGames.isEmpty ? "Upcoming" : "Upcoming / In Progress") {
                    ForEach(pendingGames) { game in
                        navRow(game)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func navRow(_ game: ScheduleGame) -> some View {
        NavigationLink {
            GameDetailView(game: game, prediction: model.prediction(for: game))
        } label: {
            row(game)
        }
        .buttonStyle(.plain)
    }

    private func row(_ game: ScheduleGame) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                TeamLogoView(abbr: game.awayTeam, size: 24)
                TeamLogoView(abbr: game.homeTeam, size: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(game.awayTeam) @ \(game.homeTeam)")
                    .font(.subheadline.weight(.semibold))
                if let stadium = game.stadium {
                    Text(stadium)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            trailingDisplay(for: game)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func trailingDisplay(for game: ScheduleGame) -> some View {
        if game.isFinal, let away = game.awayScore, let home = game.homeScore {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(away)")
                        .font(.callout.weight(game.winnerAbbr == game.awayTeam ? .bold : .regular))
                        .monospacedDigit()
                    Text("–")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("\(home)")
                        .font(.callout.weight(game.winnerAbbr == game.homeTeam ? .bold : .regular))
                        .monospacedDigit()
                }
                Text(game.overtime == true ? "Final · OT" : "Final")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Text(game.kickoff, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(game.kickoff, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

#Preview {
    ResultsView()
        .environment(WeekSelection())
        .environment(AppSettings.shared)
}
