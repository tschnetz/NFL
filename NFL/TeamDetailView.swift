import SwiftUI

@MainActor
@Observable
final class TeamDetailViewModel {
    var schedule: LoadState<[ScheduleGame]> = .idle
    var stats: LoadState<TeamSeasonStats> = .idle
    var leaders: LoadState<TeamLeaders> = .idle
    var roster: LoadState<RosterPayload> = .idle

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func loadAll(abbr: String, season: Int) async {
        async let a: () = loadSchedule(abbr: abbr, season: season)
        async let b: () = loadStats(abbr: abbr, season: season)
        async let c: () = loadLeaders(abbr: abbr, season: season)
        async let d: () = loadRoster(abbr: abbr, season: season)
        _ = await (a, b, c, d)
    }

    private func loadSchedule(abbr: String, season: Int) async {
        schedule = .loading
        do {
            let response: ScheduleResponse = try await client.get(
                "/api/schedule/team/\(abbr)",
                queryItems: [URLQueryItem(name: "season", value: String(season))]
            )
            schedule = .loaded(response.games.sorted { $0.kickoff < $1.kickoff })
        } catch {
            schedule = .failed(error.localizedDescription)
        }
    }

    private func loadStats(abbr: String, season: Int) async {
        stats = .loading
        do {
            let payload: TeamSeasonStats = try await client.get(
                "/api/team-stats/\(season)/\(abbr)"
            )
            stats = .loaded(payload)
        } catch {
            stats = .failed(error.localizedDescription)
        }
    }

    private func loadLeaders(abbr: String, season: Int) async {
        leaders = .loading
        do {
            let payload: TeamLeaders = try await client.get(
                "/api/team-stats/\(season)/\(abbr)/leaders"
            )
            leaders = .loaded(payload)
        } catch {
            leaders = .failed(error.localizedDescription)
        }
    }

    private func loadRoster(abbr: String, season: Int) async {
        roster = .loading
        do {
            let payload: RosterPayload = try await client.get(
                "/api/team/\(abbr)/roster",
                queryItems: [URLQueryItem(name: "season", value: String(season))]
            )
            roster = .loaded(payload)
        } catch {
            roster = .failed(error.localizedDescription)
        }
    }
}

struct TeamDetailView: View {
    let abbr: String

    @Environment(WeekSelection.self) private var selection
    @Environment(AppSettings.self) private var settings
    @State private var model = TeamDetailViewModel()
    @State private var subtab: SubTab = .schedule

    enum SubTab: String, CaseIterable, Identifiable {
        case schedule = "Schedule"
        case stats = "Stats"
        case leaders = "Leaders"
        case roster = "Roster"
        var id: String { rawValue }
    }

    private var team: Team? { TeamRepository.shared.team(abbr: abbr) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                subtabPicker
                subtabContent
            }
            .padding(16)
        }
        .navigationTitle(team?.displayName ?? abbr)
        .navigationSubtitle(divisionLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    settings.toggleFavorite(abbr)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? Color.yellow : .secondary)
                }
                .accessibilityLabel(isFavorite ? "Unfavorite team" : "Favorite team")
            }
        }
        .task(id: pivotKey) {
            await model.loadAll(abbr: abbr, season: selection.year)
        }
        .refreshable {
            await model.loadAll(abbr: abbr, season: selection.year)
        }
    }

    private var isFavorite: Bool {
        settings.favoriteTeamAbbrs.contains(abbr)
    }

    private var pivotKey: String { "\(abbr)-\(selection.year)" }

    private var divisionLabel: String {
        let info = team.flatMap { TeamRepository.shared.team(abbr: $0.abbreviation) }
        _ = info
        // Pull from the active conference/division map (same as standings).
        switch abbr {
        case "BUF","MIA","NE","NYJ": return "AFC East"
        case "BAL","CIN","CLE","PIT": return "AFC North"
        case "HOU","IND","JAX","TEN": return "AFC South"
        case "DEN","KC","LAC","LV": return "AFC West"
        case "DAL","NYG","PHI","WAS": return "NFC East"
        case "CHI","DET","GB","MIN": return "NFC North"
        case "ATL","CAR","NO","TB": return "NFC South"
        case "ARI","LAR","SEA","SF": return "NFC West"
        default: return ""
        }
    }

    // MARK: - Hero

    private var hero: some View {
        let teamColor = team?.primarySwiftUIColor
        return HStack(spacing: 14) {
            TeamLogoView(abbr: abbr, size: 64, style: .helmet)
            VStack(alignment: .leading, spacing: 4) {
                Text(team?.location ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(team?.nickname ?? abbr)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(teamColor ?? .primary)
                Text("Season \(String(selection.year))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (teamColor ?? .secondary).opacity(0.12),
            in: .rect(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder((teamColor ?? .clear).opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Subtab picker + dispatcher

    private var subtabPicker: some View {
        Picker("Section", selection: $subtab) {
            ForEach(SubTab.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var subtabContent: some View {
        switch subtab {
        case .schedule: scheduleSection
        case .stats: statsSection
        case .leaders: leadersSection
        case .roster: rosterSection
        }
    }

    // MARK: - Schedule

    @ViewBuilder
    private var scheduleSection: some View {
        switch model.schedule {
        case .idle, .loading:
            ProgressView()
        case .failed(let m):
            Text(m).font(.caption).foregroundStyle(.red)
        case .loaded(let games) where games.isEmpty:
            Text("No games scheduled.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .loaded(let games):
            VStack(spacing: 0) {
                ForEach(games) { game in
                    scheduleRow(game)
                    if game.id != games.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(.background.secondary, in: .rect(cornerRadius: 14))
        }
    }

    private func scheduleRow(_ game: ScheduleGame) -> some View {
        let isHome = game.homeTeam == abbr
        let opponent = isHome ? game.awayTeam : game.homeTeam
        let myScore = isHome ? game.homeScore : game.awayScore
        let oppScore = isHome ? game.awayScore : game.homeScore
        let result: String? = {
            guard let mine = myScore, let other = oppScore, game.isFinal else { return nil }
            if mine > other { return "W" }
            if mine < other { return "L" }
            return "T"
        }()
        return HStack(spacing: 10) {
            Text("W\(game.week)")
                .font(.caption.weight(.semibold))
                .frame(width: 32, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(isHome ? "vs" : "@")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 24, alignment: .leading)
            TeamLogoView(abbr: opponent, size: 22)
            Text(opponent)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, alignment: .leading)
            Spacer()
            if let result {
                Text(result)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(result == "W" ? .green : (result == "L" ? .red : .secondary))
                Text("\(myScore!)–\(oppScore!)")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            } else {
                Text(game.kickoff, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Stats

    @ViewBuilder
    private var statsSection: some View {
        switch model.stats {
        case .idle, .loading: ProgressView()
        case .failed(let m): Text(m).font(.caption).foregroundStyle(.red)
        case .loaded(let stats):
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(stats.weeksPlayed) weeks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                statGroup("Passing", keys: ["completions", "attempts", "passing_yards", "passing_tds", "interceptions", "sacks"], from: stats.totals)
                statGroup("Rushing", keys: ["carries", "rushing_yards", "rushing_tds", "rushing_first_downs"], from: stats.totals)
                statGroup("Receiving", keys: ["targets", "receptions", "receiving_yards", "receiving_tds"], from: stats.totals)
            }
        }
    }

    private func statGroup(_ title: String, keys: [String], from totals: [String: Double]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(spacing: 0) {
                ForEach(keys, id: \.self) { key in
                    HStack {
                        Text(humanize(key))
                            .font(.callout)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(format(totals[key] ?? 0))
                            .font(.callout.weight(.medium))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    if key != keys.last {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(.background.secondary, in: .rect(cornerRadius: 12))
        }
    }

    private func humanize(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    // MARK: - Leaders

    @ViewBuilder
    private var leadersSection: some View {
        switch model.leaders {
        case .idle, .loading: ProgressView()
        case .failed(let m): Text(m).font(.caption).foregroundStyle(.red)
        case .loaded(let leaders) where leaders.categories.allSatisfy({ $0.players.isEmpty }):
            Text("No leader data yet.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .loaded(let leaders):
            VStack(spacing: 12) {
                ForEach(leaders.categories) { cat in
                    if !cat.players.isEmpty {
                        leaderCard(cat)
                    }
                }
            }
        }
    }

    private func leaderCard(_ cat: TeamLeaders.Category) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(cat.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(spacing: 0) {
                ForEach(cat.players) { player in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.playerName ?? player.playerId)
                                .font(.callout.weight(.semibold))
                            if let pos = player.position {
                                Text(pos)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Text(format(player.value))
                            .font(.callout.weight(.medium))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    if player.id != cat.players.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(.background.secondary, in: .rect(cornerRadius: 12))
        }
    }

    // MARK: - Roster

    @ViewBuilder
    private var rosterSection: some View {
        switch model.roster {
        case .idle, .loading: ProgressView()
        case .failed(let m): Text(m).font(.caption).foregroundStyle(.red)
        case .loaded(let payload) where payload.roster.isEmpty:
            Text("No roster for this season yet.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .loaded(let payload):
            let groups = groupByPosition(payload.roster)
            VStack(alignment: .leading, spacing: 12) {
                if let week = payload.week {
                    Text("Roster as of week \(week)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(groups, id: \.position) { group in
                    rosterGroupCard(group)
                }
            }
        }
    }

    private struct RosterGroup {
        let position: String
        let players: [RosterPayload.Player]
    }

    private func groupByPosition(_ players: [RosterPayload.Player]) -> [RosterGroup] {
        var buckets: [String: [RosterPayload.Player]] = [:]
        for p in players {
            let pos = p.position ?? "—"
            buckets[pos, default: []].append(p)
        }
        return buckets.keys.sorted().map { key in
            RosterGroup(position: key,
                        players: buckets[key]!.sorted {
                            ($0.playerName ?? $0.playerId) < ($1.playerName ?? $1.playerId)
                        })
        }
    }

    private func rosterGroupCard(_ group: RosterGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(group.position)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(group.players.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            ForEach(group.players) { player in
                HStack {
                    if let jersey = player.jersey, !jersey.isEmpty {
                        Text("#\(jersey)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .frame(width: 40, alignment: .leading)
                    }
                    Text(player.playerName ?? player.playerId)
                        .font(.callout)
                    Spacer()
                    if let status = player.status {
                        Text(status)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                if player.id != group.players.last?.id {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        TeamDetailView(abbr: "KC")
            .environment(WeekSelection(year: 2024))
            .environment(AppSettings.shared)
    }
}
