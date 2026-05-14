import SwiftUI

struct TeamsView: View {
    @Environment(WeekSelection.self) private var selection
    @Environment(AppSettings.self) private var settings
    @State private var repo = TeamRepository.shared
    @State private var search: String = ""
    @State private var conferenceFilter: ConferenceTag = .both

    enum ConferenceTag: String, CaseIterable, Identifiable {
        case both = "Both"
        case afc = "AFC"
        case nfc = "NFC"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Teams")
                .toolbar { toolbarContent }
                .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
                .navigationDestination(for: String.self) { abbr in
                    TeamDetailView(abbr: abbr)
                }
                .task { await repo.ensureLoaded() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Conference", selection: $conferenceFilter) {
                    ForEach(ConferenceTag.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if repo.teamsByAbbr.isEmpty {
            ProgressView().controlSize(.large)
        } else {
            List {
                ForEach(groupedTeams(), id: \.division) { group in
                    Section(group.division) {
                        ForEach(group.teams) { team in
                            NavigationLink(value: team.abbreviation) {
                                row(team)
                            }
                            .swipeActions(edge: .trailing) {
                                let isFav = settings.favoriteTeamAbbrs
                                    .contains(team.abbreviation)
                                Button {
                                    settings.toggleFavorite(team.abbreviation)
                                } label: {
                                    Label(isFav ? "Unfavorite" : "Favorite",
                                          systemImage: isFav ? "star.slash" : "star")
                                }
                                .tint(isFav ? .secondary : .yellow)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func row(_ team: Team) -> some View {
        let isFavorite = settings.favoriteTeamAbbrs.contains(team.abbreviation)
        return HStack(spacing: 12) {
            TeamLogoView(abbr: team.abbreviation, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.displayName)
                    .font(.headline)
                    .foregroundStyle(team.primarySwiftUIColor ?? .primary)
                Text(team.abbreviation)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Favorite")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private struct Group {
        let division: String
        let teams: [Team]
    }

    private func groupedTeams() -> [Group] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        let conferenceFiltered = repo.teamsByAbbr.values.filter { team in
            guard let conf = conference(for: team.abbreviation) else { return false }
            switch conferenceFilter {
            case .both: return true
            case .afc: return conf == "AFC"
            case .nfc: return conf == "NFC"
            }
        }
        let searchFiltered = conferenceFiltered.filter { team in
            guard !needle.isEmpty else { return true }
            return team.abbreviation.lowercased().contains(needle)
                || team.displayName.lowercased().contains(needle)
                || team.location.lowercased().contains(needle)
                || team.nickname.lowercased().contains(needle)
        }

        var buckets: [String: [Team]] = [:]
        for team in searchFiltered {
            guard let conf = conference(for: team.abbreviation),
                  let div = division(for: team.abbreviation) else { continue }
            let key = "\(conf) \(div)"
            buckets[key, default: []].append(team)
        }
        let divisionOrder = [
            "AFC East", "AFC North", "AFC South", "AFC West",
            "NFC East", "NFC North", "NFC South", "NFC West",
        ]
        return divisionOrder.compactMap { key in
            guard let teams = buckets[key]?.sorted(by: { $0.abbreviation < $1.abbreviation }),
                  !teams.isEmpty else { return nil }
            return Group(division: key, teams: teams)
        }
    }

    private func conference(for abbr: String) -> String? {
        Self.divisionMap[abbr]?.0
    }

    private func division(for abbr: String) -> String? {
        Self.divisionMap[abbr]?.1
    }

    // Same 32-team map as backend app/core/divisions.py. Kept client-side
    // so we don't need a /api/divisions endpoint for the list grouping.
    private static let divisionMap: [String: (String, String)] = [
        "BUF": ("AFC", "East"), "MIA": ("AFC", "East"), "NE": ("AFC", "East"), "NYJ": ("AFC", "East"),
        "BAL": ("AFC", "North"), "CIN": ("AFC", "North"), "CLE": ("AFC", "North"), "PIT": ("AFC", "North"),
        "HOU": ("AFC", "South"), "IND": ("AFC", "South"), "JAX": ("AFC", "South"), "TEN": ("AFC", "South"),
        "DEN": ("AFC", "West"), "KC": ("AFC", "West"), "LAC": ("AFC", "West"), "LV": ("AFC", "West"),
        "DAL": ("NFC", "East"), "NYG": ("NFC", "East"), "PHI": ("NFC", "East"), "WAS": ("NFC", "East"),
        "CHI": ("NFC", "North"), "DET": ("NFC", "North"), "GB": ("NFC", "North"), "MIN": ("NFC", "North"),
        "ATL": ("NFC", "South"), "CAR": ("NFC", "South"), "NO": ("NFC", "South"), "TB": ("NFC", "South"),
        "ARI": ("NFC", "West"), "LAR": ("NFC", "West"), "SEA": ("NFC", "West"), "SF": ("NFC", "West"),
    ]
}

#Preview {
    TeamsView()
        .environment(WeekSelection())
        .environment(AppSettings.shared)
}
