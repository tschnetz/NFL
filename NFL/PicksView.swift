import SwiftUI

enum PickSide { case home, away }

@MainActor
@Observable
final class PicksViewModel {
    var season: Int = 2025
    var week: Int = 1

    var state: LoadState<PicksState> = .idle
    var schedule: LoadState<[ScheduleGame]> = .idle

    var actionError: String?
    var isMutating: Bool = false

    let availableSeasons: [Int] = [2025, 2024, 2023, 2022]
    let availableWeeks: [Int] = Array(1...18)

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    var picksState: PicksState? {
        if case .loaded(let s) = state { return s }
        return nil
    }

    var weekGames: [ScheduleGame] {
        guard case .loaded(let all) = schedule else { return [] }
        return all
            .filter { $0.week == week && $0.seasonType == "regular" }
            .sorted { $0.kickoff < $1.kickoff }
    }

    var unpickedGames: [ScheduleGame] {
        let picked = Set(pickedGameIds)
        return weekGames.filter { !picked.contains($0.espnId) }
    }

    var pickedGameIds: [Int] {
        guard let s = picksState else { return [] }
        return s.picks.keys.compactMap(Int.init)
    }

    func team(byAbbr abbr: String) -> Team? {
        TeamRepository.shared.team(abbr: abbr)
    }

    func game(byEspnId espnId: Int) -> ScheduleGame? {
        weekGames.first { $0.espnId == espnId }
    }

    func picks(for picker: String) -> [(gameId: Int, entry: PickEntry)] {
        guard let s = picksState else { return [] }
        return s.picks.compactMap { key, entry in
            guard entry.picker == picker, let id = Int(key) else { return nil }
            return (id, entry)
        }.sorted { $0.gameId < $1.gameId }
    }

    func load() async {
        async let a: () = loadState()
        async let b: () = loadSchedule()
        async let c: () = TeamRepository.shared.ensureLoaded()
        _ = await (a, b, c)
    }

    func onWeekOrSeasonChange() async {
        // Schedule is per-season; reload only when season changes.
        if case .loaded = schedule {
            await loadState()
        } else {
            async let a: () = loadState()
            async let b: () = loadSchedule()
            _ = await (a, b)
        }
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

    func openWeek(totalGames: Int, firstTurn: String) async {
        nonisolated struct Body: Encodable {
            let season: Int
            let week: Int
            let seasonType: String
            let totalGames: Int
            let firstTurn: String
        }
        let body = Body(season: season, week: week, seasonType: "regular",
                        totalGames: totalGames, firstTurn: firstTurn)
        await runMutation { try await self.client.post("/api/picks/open", body: body) }
    }

    func makePick(game: ScheduleGame, picker: String, side: PickSide) async {
        let abbr = side == .home ? game.homeTeam : game.awayTeam
        guard let team = team(byAbbr: abbr), let teamId = team.espnIdInt else {
            actionError = "Couldn't resolve team id for \(abbr)"
            return
        }
        nonisolated struct Body: Encodable {
            let season: Int
            let week: Int
            let seasonType: String
            let userId: String
            let gameId: Int
            let teamId: Int
            let teamName: String
        }
        let body = Body(season: season, week: week, seasonType: "regular",
                        userId: picker, gameId: game.espnId, teamId: teamId,
                        teamName: team.displayName)
        await runMutation { try await self.client.post("/api/picks/pick", body: body) }
    }

    func unpick(gameId: Int, picker: String) async {
        nonisolated struct Body: Encodable {
            let season: Int
            let week: Int
            let seasonType: String
            let userId: String
            let gameId: Int
        }
        let body = Body(season: season, week: week, seasonType: "regular",
                        userId: picker, gameId: gameId)
        await runMutation { try await self.client.post("/api/picks/unpick", body: body) }
    }

    func advanceTurn() async {
        nonisolated struct Body: Encodable {
            let season: Int
            let week: Int
            let seasonType: String
        }
        let body = Body(season: season, week: week, seasonType: "regular")
        await runMutation { try await self.client.post("/api/picks/advanceTurn", body: body) }
    }

    private func runMutation(
        _ call: @Sendable () async throws -> APIEnvelope<PicksState>
    ) async {
        isMutating = true
        defer { isMutating = false }
        actionError = nil
        do {
            let env = try await call()
            state = .loaded(env.data)
        } catch {
            actionError = error.localizedDescription
        }
    }
}

struct PicksView: View {
    @State private var model = PicksViewModel()
    @State private var showOpenSheet = false
    @State private var pickTarget: PickTarget?
    @State private var showWeekPicker = false

    private struct PickTarget: Identifiable {
        let picker: String
        var id: String { picker }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Picks")
                .toolbar { toolbarContent }
                .task { await model.load() }
                .refreshable { await model.reloadState() }
                .sheet(isPresented: $showOpenSheet) {
                    OpenWeekSheet(season: model.season, week: model.week) { total, first in
                        Task {
                            await model.openWeek(totalGames: total, firstTurn: first)
                            showOpenSheet = false
                        }
                    }
                }
                .sheet(item: $pickTarget) { target in
                    PickGameSheet(picker: target.picker, model: model) {
                        pickTarget = nil
                    }
                }
                .alert("Action failed",
                       isPresented: Binding(
                        get: { model.actionError != nil },
                        set: { if !$0 { model.actionError = nil } }
                       )) {
                    Button("OK", role: .cancel) { model.actionError = nil }
                } message: {
                    Text(model.actionError ?? "")
                }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Season") {
                    ForEach(model.availableSeasons, id: \.self) { s in
                        Button {
                            model.season = s
                            Task { await model.onWeekOrSeasonChange() }
                        } label: {
                            if s == model.season { Label(String(s), systemImage: "checkmark") }
                            else { Text(String(s)) }
                        }
                    }
                }
                Section("Week") {
                    ForEach(model.availableWeeks, id: \.self) { w in
                        Button {
                            model.week = w
                            Task { await model.onWeekOrSeasonChange() }
                        } label: {
                            if w == model.week { Label("Week \(w)", systemImage: "checkmark") }
                            else { Text("Week \(w)") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(String(model.season)) · W\(model.week)")
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(.subheadline.weight(.medium))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView().controlSize(.large)
        case .failed(let message):
            ContentUnavailableView("Couldn’t load picks",
                                   systemImage: "wifi.exclamationmark",
                                   description: Text(message))
        case .loaded(let state):
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summaryCard(state)

                    if state.totalGames == 0 && state.status == .picking {
                        openCTA
                    } else if state.status == .picking {
                        actionRow(state)
                    }

                    pickerColumns(state)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private func summaryCard(_ state: PicksState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Week \(state.week) · \(String(state.season))")
                    .font(.title3.weight(.semibold))
                Spacer()
                statusBadge(state.status)
            }
            HStack(spacing: 18) {
                labelStat("Games", "\(state.totalGames)")
                labelStat("Base", "\(state.basePoints)")
                if let turn = state.currentTurn {
                    labelStat("On the clock", turn)
                }
                if let scores = state.scores {
                    labelStat("Jim", "\(scores.jim)")
                    labelStat("Tom", "\(scores.tom)")
                }
            }
            Text("Updated \(state.updatedAt, format: .relative(presentation: .named))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    private var openCTA: some View {
        Button {
            showOpenSheet = true
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text("Open Week").font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tint.opacity(0.18), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(model.isMutating)
    }

    private func actionRow(_ state: PicksState) -> some View {
        HStack(spacing: 10) {
            if let turn = state.currentTurn {
                Button {
                    pickTarget = PickTarget(picker: turn)
                } label: {
                    HStack {
                        Image(systemName: "hand.tap")
                        Text("\(turn): pick a game")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.tint, in: .capsule)
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(model.isMutating || model.unpickedGames.isEmpty)
            }
            Button {
                Task { await model.advanceTurn() }
            } label: {
                Image(systemName: "arrow.uturn.right")
                    .padding(10)
                    .background(.background.secondary, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(model.isMutating)
        }
    }

    private func pickerColumns(_ state: PicksState) -> some View {
        VStack(spacing: 12) {
            pickerCard(name: "Jim", state: state)
            pickerCard(name: "Tom", state: state)
        }
    }

    private func pickerCard(name: String, state: PicksState) -> some View {
        let picks = model.picks(for: name)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(name).font(.headline)
                Spacer()
                Text("\(picks.count) / \(state.totalGames > 0 ? "\(state.totalGames)" : "—")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if state.currentTurn == name {
                    Text("Picking")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
            if picks.isEmpty {
                Text("No picks yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(picks, id: \.gameId) { item in
                        pickRow(item: item, picker: name)
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

    private func pickRow(item: (gameId: Int, entry: PickEntry), picker: String) -> some View {
        let game = model.game(byEspnId: item.gameId)
        let pickedAbbr = pickedAbbreviation(for: item.entry, in: game)
        return HStack(spacing: 10) {
            if let abbr = pickedAbbr {
                TeamLogoView(abbr: abbr, size: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(pickedAbbr ?? item.entry.teamName ?? "—")
                    .font(.subheadline.weight(.semibold))
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
            Button(role: .destructive) {
                Task { await model.unpick(gameId: item.gameId, picker: picker) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .disabled(model.isMutating)
        }
        .padding(.vertical, 6)
    }

    private func pickedAbbreviation(for entry: PickEntry, in game: ScheduleGame?) -> String? {
        guard let teamId = entry.teamId, let game else { return entry.teamName }
        if teamId == entry.homeTeamId { return game.homeTeam }
        if teamId == entry.awayTeamId { return game.awayTeam }
        return entry.teamName
    }

    private func labelStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func statusBadge(_ status: PicksState.Status) -> some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor(status).opacity(0.18), in: Capsule())
            .foregroundStyle(statusColor(status))
    }

    private func statusColor(_ status: PicksState.Status) -> Color {
        switch status {
        case .picking: .blue
        case .locked: .orange
        case .scored: .green
        case .unknown: .secondary
        }
    }
}

// MARK: - Open Week sheet

private struct OpenWeekSheet: View {
    let season: Int
    let week: Int
    let onOpen: (Int, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var totalGames: Int = 15
    @State private var firstTurn: String = "Jim"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Total games: \(totalGames)", value: $totalGames, in: 1...20)
                    Picker("First pick", selection: $firstTurn) {
                        Text("Jim").tag("Jim")
                        Text("Tom").tag("Tom")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Week \(week) · \(String(season))")
                } footer: {
                    Text("Opens the slate for picking. You can reopen or change later.")
                }
            }
            .navigationTitle("Open Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") { onOpen(totalGames, firstTurn) }
                        .bold()
                }
            }
        }
    }
}

// MARK: - Pick Game sheet

private struct PickGameSheet: View {
    let picker: String
    let model: PicksViewModel
    let onClose: () -> Void

    @State private var selectedGame: ScheduleGame?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("\(picker): pick a game")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { onClose() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        let unpicked = model.unpickedGames
        if unpicked.isEmpty {
            ContentUnavailableView("All games picked",
                                   systemImage: "checkmark.circle",
                                   description: Text("No games left for week \(model.week)."))
        } else if let game = selectedGame {
            sideChooser(for: game)
        } else {
            List(unpicked) { game in
                Button {
                    selectedGame = game
                } label: {
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            TeamLogoView(abbr: game.awayTeam, size: 22)
                            TeamLogoView(abbr: game.homeTeam, size: 22)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(game.awayTeam) @ \(game.homeTeam)")
                                .font(.subheadline.weight(.semibold))
                            Text(game.kickoff, format: .dateTime.weekday().month().day().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    private func sideChooser(for game: ScheduleGame) -> some View {
        VStack(spacing: 20) {
            Text("Who covers?")
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                sideButton(abbr: game.awayTeam, label: "Away") {
                    Task {
                        await model.makePick(game: game, picker: picker, side: .away)
                        onClose()
                    }
                }
                sideButton(abbr: game.homeTeam, label: "Home") {
                    Task {
                        await model.makePick(game: game, picker: picker, side: .home)
                        onClose()
                    }
                }
            }
            Button("Choose a different game") {
                selectedGame = nil
            }
            .font(.subheadline)
            .padding(.top, 8)
        }
        .padding(24)
    }

    private func sideButton(abbr: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                TeamLogoView(abbr: abbr, size: 52)
                Text(abbr)
                    .font(.title2.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(.background.secondary, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(model.isMutating)
    }
}

#Preview {
    PicksView()
}
