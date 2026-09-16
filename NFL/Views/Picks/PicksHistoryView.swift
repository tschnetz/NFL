import SwiftUI

/// Read-only browse of past picks weeks. Same shape as the active picks
/// columns but no buttons. Defaults to the most recent scored week of
/// the user's selected season.
@MainActor
@Observable
final class PicksHistoryViewModel {
    var season: Int {
        didSet { Task { await reload() } }
    }
    var week: Int {
        didSet { Task { await reloadState() } }
    }

    var state: LoadState<PicksState> = .idle
    var schedule: LoadState<[ScheduleGame]> = .idle
    var history: LoadState<[PicksHistoryItem]> = .idle

    let availableSeasons: [Int] = Array((1999...WeekSelection.latestSelectableSeason).reversed())
    let availableWeeks: [Int] = Array(1...18)

    private let client: APIClient

    init(season: Int = WeekSelection.defaultYear,
         week: Int = WeekSelection.currentWeek(for: WeekSelection.defaultYear),
         client: APIClient = .shared) {
        self.season = season
        self.week = week
        self.client = client
    }

    var picksState: PicksState? {
        if case .loaded(let s) = state { return s }
        return nil
    }

    func game(byEspnId espnId: Int) -> ScheduleGame? {
        if case .loaded(let games) = schedule {
            return games.first { $0.espnId == espnId }
        }
        return nil
    }

    func picks(for picker: String) -> [(gameId: Int, entry: PickEntry)] {
        guard let s = picksState else { return [] }
        return s.picks.compactMap { key, entry in
            guard entry.picker == picker, let id = Int(key) else { return nil }
            return (id, entry)
        }.sorted { $0.gameId < $1.gameId }
    }

    func reload() async {
        async let a: () = loadHistory()
        async let b: () = loadSchedule()
        _ = await (a, b)
        // After history loads, snap to the most recent scored week of
        // the selected season if the user hasn't manually navigated.
        if case .loaded(let items) = history {
            let scored = items
                .filter { $0.season == season && $0.status == "scored" }
                .sorted { $0.week > $1.week }
            if let latest = scored.first, week != latest.week {
                week = latest.week
                return
            }
        }
        await loadState()
    }

    func reloadState() async { await loadState() }

    private func loadState() async {
        state = .loading
        do {
            let env: APIEnvelope<PicksState> = try await client.get(
                "/api/picks/state",
                queryItems: [
                    URLQueryItem(name: "season", value: String(season)),
                    URLQueryItem(name: "week", value: String(week)),
                ]
            )
            state = .loaded(env.data)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func loadSchedule() async {
        schedule = .loading
        do {
            let res: ScheduleResponse = try await client.get("/api/schedule/\(season)")
            schedule = .loaded(res.games)
        } catch {
            schedule = .failed(error.localizedDescription)
        }
    }

    private func loadHistory() async {
        history = .loading
        do {
            let env: APIEnvelope<PicksHistoryItems> = try await client.get("/api/picks/history")
            history = .loaded(env.data.items)
        } catch {
            history = .failed(error.localizedDescription)
        }
    }
}

nonisolated struct PicksHistoryItems: Decodable, Sendable {
    let items: [PicksHistoryItem]
}

nonisolated struct PicksHistoryItem: Decodable, Identifiable, Sendable {
    let season: Int
    let week: Int
    let seasonType: String
    let status: String
    let jimTotal: Int?
    let tomTotal: Int?

    var id: String { "\(season)-\(seasonType)-\(week)" }
}

struct PicksHistoryView: View {
    @State private var model = PicksHistoryViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Picks · History")
                .navBarInline()
                .toolbar { toolbarContent }
                .task { await model.reload() }
                .refreshable { await model.reloadState() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        SeasonWeekToolbar(season: $model.season, week: $model.week,
                          seasons: model.availableSeasons, weeks: model.availableWeeks)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView().controlSize(.large)
        case .failed(let message):
            ContentUnavailableView("Couldn’t load picks history",
                                   systemImage: "wifi.exclamationmark",
                                   description: Text(message))
        case .loaded(let state):
            if state.totalGames == 0 {
                ContentUnavailableView("No picks recorded",
                                       systemImage: "tray",
                                       description: Text("Week \(state.week) of \(String(state.season)) wasn’t opened."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        summaryCard(state)
                        pickerCard(name: "Jim", state: state)
                        pickerCard(name: "Tom", state: state)
                    }
                    .padding(16)
                }
            }
        }
    }

    private func summaryCard(_ state: PicksState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Week \(state.week) · \(String(state.season))")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(state.status.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.18), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            if let scores = state.scores {
                HStack(spacing: 24) {
                    score(label: "Jim", value: scores.jim)
                    score(label: "Tom", value: scores.tom)
                }
            }
            if let when = state.scoredAt {
                Text("Scored \(when, format: .relative(presentation: .named))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    private func score(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text("\(value)")
                .font(.title2.weight(.bold))
                .monospacedDigit()
        }
    }

    private func pickerCard(name: String, state: PicksState) -> some View {
        let picks = model.picks(for: name)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(name).font(.headline)
                Spacer()
                Text("\(picks.count) picks")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if picks.isEmpty {
                Text("No picks recorded.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(picks, id: \.gameId) { item in
                        pickRow(item)
                        if item.gameId != picks.last?.gameId {
                            Divider().padding(.leading, 4)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    private func pickRow(_ item: (gameId: Int, entry: PickEntry)) -> some View {
        let game = model.game(byEspnId: item.gameId)
        let pickedAbbr = pickedAbbreviation(for: item.entry, in: game)
        let teamColor = pickedAbbr.flatMap { TeamRepository.shared.team(abbr: $0)?.primarySwiftUIColor }
        return HStack(spacing: 10) {
            if let abbr = pickedAbbr {
                TeamLogoView(abbr: abbr, size: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pickedAbbr ?? item.entry.teamName ?? "—")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(teamColor ?? .primary)
                    if item.entry.double {
                        Text("2×")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.22), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    if item.entry.press, let by = item.entry.pressedBy {
                        Text("Press: \(by)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.18), in: Capsule())
                            .foregroundStyle(.red)
                    }
                }
                if let g = game {
                    Text("\(g.awayTeam) @ \(g.homeTeam)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let pts = item.entry.points {
                Text("\(pts) pts")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(pts >= 0 ? .green : .red)
            }
        }
        .padding(.vertical, 6)
    }

    private func pickedAbbreviation(for entry: PickEntry, in game: ScheduleGame?) -> String? {
        guard let teamId = entry.teamId, let game else { return entry.teamName }
        if teamId == entry.homeTeamId { return game.homeTeam }
        if teamId == entry.awayTeamId { return game.awayTeam }
        return entry.teamName
    }
}

#Preview {
    PicksHistoryView()
        .environment(WeekSelection())
        .environment(AppSettings.shared)
}
