import SwiftUI

/// Drill-down menu for secondary surfaces — Teams, Standings, Predictions,
/// Settings. Keeps the top-level tab bar at 5 (Scoreboard / Schedule /
/// Results / More / Picks) like Pigskin.
struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(value: Destination.teams) {
                        row(systemImage: "person.3", title: "Teams",
                            subtitle: "Roster, stats, schedule per team")
                    }
                    NavigationLink(value: Destination.standings) {
                        row(systemImage: "list.number", title: "Standings",
                            subtitle: "AFC / NFC by division")
                    }
                    NavigationLink(value: Destination.predictions) {
                        row(systemImage: "chart.bar.xaxis", title: "Predictions",
                            subtitle: "Weekly model summary")
                    }
                }

                Section {
                    NavigationLink(value: Destination.settings) {
                        row(systemImage: "gearshape", title: "Settings",
                            subtitle: "Picker, theme, API, favorites, iCloud")
                    }
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: Destination.self) { destination in
                destination.view
            }
        }
    }

    enum Destination: Hashable {
        case teams
        case standings
        case predictions
        case settings

        @ViewBuilder
        var view: some View {
            switch self {
            case .teams: TeamsView()
            case .standings: StandingsView()
            case .predictions: PredictionsView()
            case .settings: SettingsView()
            }
        }
    }

    private func row(systemImage: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MoreView()
        .environment(WeekSelection())
        .environment(AppSettings.shared)
}
