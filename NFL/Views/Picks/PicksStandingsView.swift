import SwiftUI

/// Cumulative Jim vs Tom totals for the season. Read-only.
@MainActor
@Observable
final class PicksStandingsViewModel {
    var season: Int {
        didSet { Task { await load() } }
    }
    var state: LoadState<PicksSeasonStandings> = .idle

    let availableSeasons: [Int] = Array((2020...WeekSelection.latestSelectableSeason).reversed())

    private let client: APIClient

    init(season: Int = WeekSelection.defaultYear, client: APIClient = .shared) {
        self.season = season
        self.client = client
    }

    func load() async {
        state = .loading
        do {
            let env: APIEnvelope<PicksSeasonStandings> = try await client.get(
                "/api/picks/standings",
                queryItems: [URLQueryItem(name: "season", value: String(season))]
            )
            state = .loaded(env.data)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

nonisolated struct PicksSeasonStandings: Decodable, Sendable {
    let season: Int
    let seasonType: String?
    let weeksPlayed: Int
    let weeks: [WeekRow]
    let totals: Totals

    nonisolated struct WeekRow: Decodable, Identifiable, Sendable {
        let week: Int
        let jim: Int
        let tom: Int
        let scoredAt: Date?

        var id: Int { week }
    }

    nonisolated struct Totals: Decodable, Sendable {
        let jim: Int
        let tom: Int

        enum CodingKeys: String, CodingKey {
            case jim = "Jim"
            case tom = "Tom"
        }
    }
}

struct PicksStandingsView: View {
    @State private var model = PicksStandingsViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Picks · Standings")
                .navBarInline()
                .toolbar { toolbarContent }
                .task { await model.load() }
                .refreshable { await model.load() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(model.availableSeasons, id: \.self) { s in
                    Button {
                        model.season = s
                    } label: {
                        if s == model.season { Label(String(s), systemImage: "checkmark") }
                        else { Text(String(s)) }
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
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView().controlSize(.large)
        case .failed(let message):
            ContentUnavailableView("Couldn’t load standings",
                                   systemImage: "wifi.exclamationmark",
                                   description: Text(message))
        case .loaded(let payload) where payload.weeksPlayed == 0:
            ContentUnavailableView("No scored weeks yet",
                                   systemImage: "trophy",
                                   description: Text("Standings populate after a week is scored."))
        case .loaded(let payload):
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    scoreboardCard(payload)
                    weeksList(payload)
                }
                .padding(16)
            }
        }
    }

    private func scoreboardCard(_ payload: PicksSeasonStandings) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Season \(String(payload.season))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(payload.weeksPlayed) weeks")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 24) {
                pickerTotal(name: "Jim", value: payload.totals.jim,
                            isLeader: payload.totals.jim > payload.totals.tom)
                Divider().frame(height: 80)
                pickerTotal(name: "Tom", value: payload.totals.tom,
                            isLeader: payload.totals.tom > payload.totals.jim)
            }
            if payload.totals.jim == payload.totals.tom && payload.weeksPlayed > 0 {
                Text("Tied")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: .rect(cornerRadius: 16))
    }

    private func pickerTotal(name: String, value: Int, isLeader: Bool) -> some View {
        VStack(spacing: 6) {
            Text(name)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isLeader ? Color.accentColor : .primary)
            if isLeader {
                Text("LEADING")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func weeksList(_ payload: PicksSeasonStandings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per week")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(spacing: 0) {
                HStack {
                    Text("WEEK").frame(width: 60, alignment: .leading)
                    Spacer()
                    Text("JIM").frame(width: 60, alignment: .trailing)
                    Text("TOM").frame(width: 60, alignment: .trailing)
                    Text("Δ").frame(width: 50, alignment: .trailing)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                Divider()
                ForEach(payload.weeks) { row in
                    weekRow(row)
                    if row.id != payload.weeks.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(.background.secondary, in: .rect(cornerRadius: 12))
        }
    }

    private func weekRow(_ row: PicksSeasonStandings.WeekRow) -> some View {
        let diff = row.jim - row.tom
        return HStack {
            Text("\(row.week)")
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .frame(width: 60, alignment: .leading)
            Spacer()
            Text("\(row.jim)")
                .font(.callout)
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
                .foregroundStyle(row.jim > row.tom ? .primary : .secondary)
            Text("\(row.tom)")
                .font(.callout)
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
                .foregroundStyle(row.tom > row.jim ? .primary : .secondary)
            Text(diff == 0 ? "—" : (diff > 0 ? "+\(diff)" : "\(diff)"))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(diff > 0 ? .green : (diff < 0 ? .red : .secondary))
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

#Preview {
    PicksStandingsView()
        .environment(WeekSelection())
        .environment(AppSettings.shared)
}
