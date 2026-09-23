import SwiftUI

/// One row per game for the week, each with the model's spread pick and
/// total pick spelled out — which team, at what line, and WHY (model
/// number vs. market number, and the edge between them).
///
/// ⚠️ Until 2026-09-23 this screen rendered the `/api/preds/summary`
/// payload: aggregate strength tiles plus three top-5 lists whose rows
/// showed a bare "MIA +11.5" beside the AWAY team's logo whatever the
/// pick, with "edge" / "margin" / "line" numbers and no model total. It
/// showed the picks but hid which team they were on and never said why.
/// The per-game payload already carried everything needed.
@MainActor
@Observable
final class PredictionsViewModel {
    enum Sort: String, CaseIterable, Identifiable {
        case kickoff = "Kickoff"
        case edge = "Edge"
        var id: String { rawValue }
    }

    struct Week: Sendable {
        let season: Int
        let week: Int
        let games: [GamePrediction]
        /// Kickoff by ESPN event id, from the schedule endpoint (the
        /// predictions payload carries no date).
        let kickoffs: [Int: Date]
    }

    var state: LoadState<Week> = .idle
    var sort: Sort = .kickoff

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func load(season: Int, week: Int) async {
        state = .loading
        async let teams: () = TeamRepository.shared.ensureLoaded()
        async let preds: PredictionsResponse = client.get("/api/preds/\(season)/w\(week)")
        async let schedule: ScheduleResponse? = try? client.get("/api/schedule/\(season)")
        do {
            let response = try await preds
            let sched = await schedule
            _ = await teams
            let kickoffs = Dictionary(
                (sched?.games ?? [])
                    .filter { $0.week == week }
                    .map { ($0.espnId, $0.kickoff) },
                uniquingKeysWith: { a, _ in a }
            )
            state = .loaded(Week(season: season, week: week,
                                 games: response.predictions, kickoffs: kickoffs))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func sorted(_ week: Week) -> [GamePrediction] {
        switch sort {
        case .kickoff:
            week.games.sorted {
                let a = week.kickoffs[$0.espnId] ?? .distantFuture
                let b = week.kickoffs[$1.espnId] ?? .distantFuture
                return a == b ? $0.gameId < $1.gameId : a < b
            }
        case .edge:
            week.games.sorted { abs($0.bestBetEdge ?? 0) > abs($1.bestBetEdge ?? 0) }
        }
    }

    func strengthCount(_ week: Week, _ s: GamePrediction.Strength) -> Int {
        week.games.filter { $0.bestBetStrengthValue == s }.count
    }
}

struct PredictionsView: View {
    @Environment(WeekSelection.self) private var selection
    @State private var model = PredictionsViewModel()
    @State private var showLegend = false

    var body: some View {
        @Bindable var selection = selection
        NavigationStack {
            content
                .navigationTitle("Predictions")
                .toolbar {
                    SeasonWeekToolbar(season: $selection.year, week: $selection.week,
                                      seasons: selection.availableSeasons,
                                      weeks: selection.availableWeeks)
                    ToolbarItem(placement: .primaryAction) {
                        Button("How to read these", systemImage: "info.circle") {
                            showLegend = true
                        }
                        .popover(isPresented: $showLegend) {
                            PredictionsLegend()
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                }
                .task(id: pivotKey) {
                    await model.load(season: selection.year, week: selection.week)
                }
                .refreshable {
                    await model.load(season: selection.year, week: selection.week)
                }
        }
    }

    private var pivotKey: String { "\(selection.year)-\(selection.week)" }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView().controlSize(.large)
        case .failed(let message):
            ContentUnavailableView("Couldn’t load predictions",
                                   systemImage: "wifi.exclamationmark",
                                   description: Text(message))
        case .loaded(let week) where week.games.isEmpty:
            ContentUnavailableView("No predictions",
                                   systemImage: "chart.bar.xaxis",
                                   description: Text("Nothing graded for week \(week.week) of \(String(week.season))."))
        case .loaded(let week):
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(week)
                    Picker("Sort", selection: $model.sort) {
                        ForEach(PredictionsViewModel.Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    ForEach(model.sorted(week)) { game in
                        GamePickCard(game: game, kickoff: week.kickoffs[game.espnId])
                    }
                }
                .padding(16)
            }
        }
    }

    private func header(_ week: PredictionsViewModel.Week) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Week \(week.week) · \(String(week.season))")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(week.games.count) games")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // Best-bet strength mix for the week — a one-line summary, not a
            // dashboard. Strength is a threshold on the edge (see the legend).
            HStack(spacing: 10) {
                ForEach([GamePrediction.Strength.strong, .medium, .lean, .pass], id: \.rawValue) { s in
                    HStack(spacing: 4) {
                        Text("\(model.strengthCount(week, s))")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(s.color)
                        Text(s.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Game card

/// Matchup line + two pick rows (spread, total). The picked team leads its
/// row; the second line is the reason: model number · market number · edge.
private struct GamePickCard: View {
    let game: GamePrediction
    let kickoff: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            matchup
            Divider()
            spreadRow
            Divider()
            totalRow
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    private var matchup: some View {
        HStack(spacing: 8) {
            TeamLogoView(abbr: game.awayTeam, size: 22)
            Text(game.awayTeam)
                .font(.subheadline.weight(.semibold))
            Text("@")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            TeamLogoView(abbr: game.homeTeam, size: 22)
            Text(game.homeTeam)
                .font(.subheadline.weight(.semibold))
            Spacer()
            if let kickoff {
                Text(kickoff, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // Spread: "Take Miami +11.5" — Model: MIA by 6.3 · Line: KC by 11.5 · Edge 17.8
    private var spreadRow: some View {
        let team = game.spreadPickTeam
        let title: String = {
            guard let team, let pick = game.spreadPick else { return "No spread pick" }
            let line = pick.split(separator: " ").dropFirst().joined(separator: " ")
            return "Take \(displayName(team)) \(line)"
        }()
        let reason: String = {
            var parts: [String] = []
            parts.append("Model: " + (game.modelFavorite.map { "\($0.team) by \(fmt($0.by))" } ?? "pick ’em"))
            parts.append("Line: " + (game.marketFavorite.map { "\($0.team) by \(fmt($0.by))" } ?? "pick ’em"))
            if let e = game.spreadEdge { parts.append("Edge \(fmt(abs(e)))") }
            return parts.joined(separator: " · ")
        }()
        return PickRow(kind: "Spread",
                       leading: team.map { .team($0) } ?? .none,
                       title: title, reason: reason,
                       strength: game.spreadStrengthValue,
                       isBestBet: game.bestBetIsSpread == true)
    }

    // Total: "Over 40.5" — Model 48.0 · Edge +7.5
    private var totalRow: some View {
        let pick = game.totalPick ?? "PASS"
        let isPass = pick == "PASS" || game.overUnderLine == nil
        let title = isPass ? "No total pick"
            : "\(pick) \(fmt(game.overUnderLine ?? 0))"
        var parts: [String] = []
        if let t = game.predTotalPoints { parts.append("Model \(fmt(t))") }
        if let l = game.overUnderLine, isPass { parts.append("Line \(fmt(l))") }
        if let e = game.totalEdge { parts.append("Edge \(e >= 0 ? "+" : "−")\(fmt(abs(e)))") }
        return PickRow(kind: "Total",
                       leading: isPass ? .none : .symbol(pick == "Over" ? "arrow.up.circle.fill" : "arrow.down.circle.fill"),
                       title: title, reason: parts.joined(separator: " · "),
                       strength: game.totalStrengthValue,
                       isBestBet: game.bestBetIsSpread == false)
    }

    private func displayName(_ abbr: String) -> String {
        TeamRepository.shared.team(abbr: abbr)?.displayName ?? abbr
    }

    private func fmt(_ v: Double) -> String {
        v.rounded() == v ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }
}

private struct PickRow: View {
    enum Leading { case team(String), symbol(String), none }

    let kind: String
    let leading: Leading
    let title: String
    let reason: String
    let strength: GamePrediction.Strength?
    let isBestBet: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                switch leading {
                case .team(let abbr): TeamLogoView(abbr: abbr, size: 26)
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                case .none:
                    Image(systemName: "minus.circle")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(kind)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    if isBestBet {
                        Label("Best bet", systemImage: "star.fill")
                            .font(.caption2.weight(.semibold))
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Best bet")
                    }
                }
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(strength == .pass || strength == nil ? .secondary : .primary)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            if let strength {
                Text(strength.rawValue)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(strength.color.opacity(0.18), in: Capsule())
                    .foregroundStyle(strength.color)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Legend

private struct PredictionsLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to read these")
                .font(.headline)
            legendRow("Take Miami +11.5",
                      "Bet Miami. Plus means Miami gets those points (the underdog); minus means laying them (the favorite).")
            legendRow("Over 40.5",
                      "Bet the two teams combine for more than 40.5 points. Under is the opposite.")
            legendRow("Model · Line · Edge",
                      "What the model predicts, what Vegas says, and the gap between them in points. The bigger the edge, the more the model disagrees with the market.")
            legendRow("Strong / Medium / Lean / Pass",
                      "Edge of 3+ points, 2+, 1+, or under 1. The star marks the better of the two markets for that game.")
        }
        .padding(16)
        .frame(maxWidth: 360, alignment: .leading)
    }

    private func legendRow(_ term: String, _ meaning: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(term).font(.subheadline.weight(.semibold))
            Text(meaning).font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension GamePrediction.Strength {
    var color: Color {
        switch self {
        case .strong: .green
        case .medium: .blue
        case .lean: .orange
        case .pass: .secondary
        }
    }
}

#Preview {
    PredictionsView()
        .environment(WeekSelection())
        .environment(AppSettings.shared)
}
