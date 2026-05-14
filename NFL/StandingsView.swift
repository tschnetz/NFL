import SwiftUI

@MainActor
@Observable
final class StandingsViewModel {
    var state: LoadState<DivisionalStandings> = .idle

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func load(season: Int, includePostseason: Bool) async {
        state = .loading
        do {
            let path = "/api/standings/divisional"
            let payload: DivisionalStandings = try await client.get(
                path,
                queryItems: [
                    URLQueryItem(name: "season", value: String(season)),
                    URLQueryItem(name: "seasonType",
                                 value: includePostseason ? "all" : "regular"),
                ]
            )
            state = .loaded(payload)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct StandingsView: View {
    @Environment(WeekSelection.self) private var selection
    @State private var model = StandingsViewModel()
    @State private var conferenceFilter: ConferenceFilter = .both
    @State private var includePostseason: Bool = false

    enum ConferenceFilter: String, CaseIterable, Identifiable {
        case both = "Both"
        case afc = "AFC"
        case nfc = "NFC"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Standings")
                .toolbar { toolbarContent }
                .task(id: pivotKey) {
                    await model.load(season: selection.year,
                                     includePostseason: includePostseason)
                }
                .refreshable {
                    await model.load(season: selection.year,
                                     includePostseason: includePostseason)
                }
        }
    }

    private var pivotKey: String { "\(selection.year)-\(includePostseason)" }

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
                Section {
                    Toggle("Include postseason", isOn: $includePostseason)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(String(selection.year))
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
        case .loaded(let standings):
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Conference", selection: $conferenceFilter) {
                        ForEach(ConferenceFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    ForEach(filteredConferences(standings)) { conference in
                        conferenceSection(conference)
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    private func filteredConferences(_ standings: DivisionalStandings) -> [DivisionalStandings.Conference] {
        switch conferenceFilter {
        case .both: standings.conferences
        case .afc: standings.conferences.filter { $0.name == "AFC" }
        case .nfc: standings.conferences.filter { $0.name == "NFC" }
        }
    }

    private func conferenceSection(_ conference: DivisionalStandings.Conference) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(conference.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 4)

            ForEach(conference.divisions) { division in
                divisionCard(conference: conference, division: division)
            }
        }
    }

    private func divisionCard(
        conference: DivisionalStandings.Conference,
        division: DivisionalStandings.Division
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(conference.name) \(division.name)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("W-L")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .frame(width: 56, alignment: .trailing)
                Text("PCT")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .frame(width: 44, alignment: .trailing)
                Text("PF/PA")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .frame(width: 76, alignment: .trailing)
                Text("DIFF")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .frame(width: 48, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            ForEach(Array(division.teams.enumerated()), id: \.element.id) { idx, team in
                teamRow(team, leader: idx == 0)
                if team.id != division.teams.last?.id {
                    Divider().padding(.leading, 14)
                }
            }
        }
        .background(.background.secondary, in: .rect(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    private func teamRow(_ team: DivisionalStandings.TeamRecord, leader: Bool) -> some View {
        let teamColor = TeamRepository.shared.team(abbr: team.team)?.primarySwiftUIColor
        return HStack(spacing: 10) {
            TeamLogoView(abbr: team.team, size: 26)
            Text(team.team)
                .font(.headline)
                .foregroundStyle(teamColor ?? .primary)
                .frame(width: 44, alignment: .leading)
            Spacer()
            Text(team.record)
                .font(.callout.weight(leader ? .semibold : .regular))
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
            Text(String(format: "%.3f", team.winPct))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
            Text("\(team.pointsFor)/\(team.pointsAgainst)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 76, alignment: .trailing)
            Text(signed(team.pointDiff))
                .font(.caption.weight(.medium))
                .foregroundStyle(diffColor(team.pointDiff))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private func diffColor(_ value: Int) -> Color {
        if value > 0 { return .green }
        if value < 0 { return .red }
        return .secondary
    }
}

#Preview {
    StandingsView()
        .environment(WeekSelection())
        .environment(AppSettings.shared)
}
