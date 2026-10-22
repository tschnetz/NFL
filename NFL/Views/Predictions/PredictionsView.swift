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
        /// Final score by ESPN event id — only games the schedule marks final.
        /// ⚠️ The schedule is a calendar snapshot, so a game that just ended
        /// can still read as "to play" here until the next refresh.
        let finals: [Int: FinalScore]
    }

    /// How many of the week's picks the Top section shows.
    static let topPickCount = 7

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
            let weekGames = (sched?.games ?? []).filter { $0.week == week }
            let kickoffs = Dictionary(
                weekGames.map { ($0.espnId, $0.kickoff) },
                uniquingKeysWith: { a, _ in a }
            )
            let finals = Dictionary(
                weekGames.compactMap { g -> (Int, FinalScore)? in
                    guard g.isFinal, let h = g.homeScore, let a = g.awayScore else { return nil }
                    return (g.espnId, FinalScore(home: h, away: a))
                },
                uniquingKeysWith: { a, _ in a }
            )
            state = .loaded(Week(season: season, week: week,
                                 games: response.predictions,
                                 kickoffs: kickoffs, finals: finals))
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

    /// The week's strongest picks across BOTH markets: every game offers a
    /// spread pick and a total pick, and the seven with the largest absolute
    /// edge win — so one game can appear twice. Ties break on id so the
    /// order is stable across reloads.
    func topPicks(_ week: Week) -> [MarketPick] {
        let picks = week.games
            .flatMap { [MarketPick(game: $0, market: .spread), MarketPick(game: $0, market: .total)] }
            .compactMap { pick -> (MarketPick, Double)? in
                guard !pick.isPass, let edge = pick.edge else { return nil }
                return (pick, abs(edge))
            }
            .sorted { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 > $1.1 }
        return picks.prefix(Self.topPickCount).map(\.0)
    }
}

struct FinalScore: Sendable {
    let home: Int
    let away: Int
}

/// One market's pick for one game, spelled out — shared by the game cards
/// and the Top 7 so both say the same thing the same way.
struct MarketPick: Identifiable {
    enum Market: String { case spread = "Spread", total = "Total" }
    enum Outcome { case won, lost, push }

    let game: GamePrediction
    let market: Market

    var id: String { "\(game.gameId)-\(market.rawValue)" }

    var edge: Double? {
        market == .spread ? game.spreadEdge : game.totalEdge
    }

    var strength: GamePrediction.Strength? {
        market == .spread ? game.spreadStrengthValue : game.totalStrengthValue
    }

    var isPass: Bool {
        switch market {
        case .spread: game.spreadPickTeam == nil || game.spreadPick == nil
        case .total: (game.totalPick ?? "PASS") == "PASS" || game.overUnderLine == nil
        }
    }

    var isBestBet: Bool {
        game.bestBetIsSpread == (market == .spread)
    }

    // Spread: "Take Miami Dolphins +11.5" · Total: "Over 40.5"
    var title: String {
        switch market {
        case .spread:
            guard let team = game.spreadPickTeam, let pick = game.spreadPick else { return "No spread pick" }
            let line = pick.split(separator: " ").dropFirst().joined(separator: " ")
            return "Take \(Self.displayName(team)) \(line)"
        case .total:
            if isPass { return "No total pick" }
            return "\(game.totalPick ?? "") \(Self.fmt(game.overUnderLine ?? 0))"
        }
    }

    // Spread: "Model: MIA by 6.3 · Line: KC by 11.5 · Edge 17.8"
    // Total:  "Model 48.0 · Edge +7.5"
    var reason: String {
        var parts: [String] = []
        switch market {
        case .spread:
            parts.append("Model: " + (game.modelFavorite.map { "\($0.team) by \(Self.fmt($0.by))" } ?? "pick ’em"))
            parts.append("Line: " + (game.marketFavorite.map { "\($0.team) by \(Self.fmt($0.by))" } ?? "pick ’em"))
            if let e = game.spreadEdge { parts.append("Edge \(Self.fmt(abs(e)))") }
            // Unseen availability news pulled the spread toward the line (totals untouched).
            if let news = game.newsSummary { parts.append("News: \(news)") }
        case .total:
            if let t = game.predTotalPoints { parts.append("Model \(Self.fmt(t))") }
            if let l = game.overUnderLine, isPass { parts.append("Line \(Self.fmt(l))") }
            if let e = game.totalEdge { parts.append("Edge \(e >= 0 ? "+" : "−")\(Self.fmt(abs(e)))") }
        }
        return parts.joined(separator: " · ")
    }

    var leading: PickRow.Leading {
        switch market {
        case .spread:
            return game.spreadPickTeam.map { .team($0) } ?? .none
        case .total:
            if isPass { return .none }
            return .symbol(game.totalPick == "Over" ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
        }
    }

    /// Graded against a final score. Same sign rules as `best_bets.py`:
    /// `spread_line` is the expected HOME margin, and a non-negative edge
    /// picks home / Over. Nil when there is no pick to grade.
    func outcome(_ score: FinalScore) -> Outcome? {
        guard !isPass, let edge else { return nil }
        let diff: Double
        switch market {
        case .spread:
            guard let line = game.spreadLine else { return nil }
            diff = Double(score.home - score.away) - line
        case .total:
            guard let line = game.overUnderLine else { return nil }
            diff = Double(score.home + score.away) - line
        }
        if diff == 0 { return .push }
        return (diff > 0) == (edge >= 0) ? .won : .lost
    }

    private static func displayName(_ abbr: String) -> String {
        TeamRepository.shared.team(abbr: abbr)?.displayName ?? abbr
    }

    static func fmt(_ v: Double) -> String {
        v.rounded() == v ? String(format: "%.0f", v) : String(format: "%.1f", v)
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
                    TopPicksCard(picks: model.topPicks(week), finals: week.finals)
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

// MARK: - Top 7

/// The week's seven strongest picks, spread or total, ranked by edge. Once
/// games are final each row is graded, and the header keeps the record.
private struct TopPicksCard: View {
    let picks: [MarketPick]
    let finals: [Int: FinalScore]

    var body: some View {
        if !picks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                header
                ForEach(Array(picks.enumerated()), id: \.element.id) { index, pick in
                    Divider()
                    PickRow(kind: "#\(index + 1) · \(pick.market.rawValue) · \(pick.game.awayTeam) @ \(pick.game.homeTeam)",
                            leading: pick.leading,
                            title: pick.title, reason: pick.reason,
                            strength: pick.strength,
                            isBestBet: false,
                            outcome: finals[pick.game.espnId].flatMap(pick.outcome))
                }
            }
            .padding(14)
            .background(.background.secondary, in: .rect(cornerRadius: 14))
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Top \(picks.count) picks")
                .font(.headline)
            Spacer()
            if let record {
                Text(record)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "4–2 · 1 push · 1 to play" — nil until at least one pick is graded.
    private var record: String? {
        let outcomes = picks.map { pick in finals[pick.game.espnId].flatMap(pick.outcome) }
        let won = outcomes.filter { $0 == .won }.count
        let lost = outcomes.filter { $0 == .lost }.count
        let push = outcomes.filter { $0 == .push }.count
        let pending = outcomes.filter { $0 == nil }.count
        guard won + lost + push > 0 else { return nil }
        var parts = ["\(won)–\(lost)"]
        if push > 0 { parts.append("\(push) push") }
        if pending > 0 { parts.append("\(pending) to play") }
        return parts.joined(separator: " · ")
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
            if let news = game.newsSummary {
                Label(news, systemImage: "newspaper")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Availability news: \(news)")
            }
            Divider()
            row(MarketPick(game: game, market: .spread))
            Divider()
            row(MarketPick(game: game, market: .total))
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

    private func row(_ pick: MarketPick) -> PickRow {
        PickRow(kind: pick.market.rawValue,
                leading: pick.leading,
                title: pick.title, reason: pick.reason,
                strength: pick.strength,
                isBestBet: pick.isBestBet)
    }
}

struct PickRow: View {
    enum Leading { case team(String), symbol(String), none }

    let kind: String
    let leading: Leading
    let title: String
    let reason: String
    let strength: GamePrediction.Strength?
    let isBestBet: Bool
    /// Graded result, shown only in the Top 7 once the game is final.
    var outcome: MarketPick.Outcome? = nil

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
            if let outcome {
                outcomeIcon(outcome)
                    .font(.title3)
                    .frame(width: 24)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // A loss is not a warning, so it stays .secondary — red is reserved
    // for critical states (style guide §10).
    @ViewBuilder
    private func outcomeIcon(_ outcome: MarketPick.Outcome) -> some View {
        switch outcome {
        case .won:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Won")
        case .lost:
            Image(systemName: "xmark.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Lost")
        case .push:
            Image(systemName: "equal.circle")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Push")
        }
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
            legendRow("Top 7 picks",
                      "The week’s seven biggest edges, spread or total, so a game can appear twice. Once a game is final, a check means the pick won and an × means it lost.")
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
