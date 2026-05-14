import SwiftUI

/// Drill-down menu for secondary surfaces — Teams, Standings, Predictions,
/// Settings. Keeps the top-level tab bar at 5 (Scoreboard / Schedule /
/// Results / More / Picks) like Pigskin.
///
/// Uses closure-based NavigationLinks (not value+navigationDestination)
/// to avoid a SwiftUI-internal matching issue where the nested
/// `Destination` enum failed to resolve under `.tabViewStyle(.sidebarAdaptable)`.
struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        TeamsView()
                    } label: {
                        row(systemImage: "person.3",
                            title: "Teams",
                            subtitle: "Roster, stats, schedule per team")
                    }
                    NavigationLink {
                        StandingsView()
                    } label: {
                        row(systemImage: "list.number",
                            title: "Standings",
                            subtitle: "AFC / NFC by division")
                    }
                    NavigationLink {
                        PredictionsView()
                    } label: {
                        row(systemImage: "chart.bar.xaxis",
                            title: "Predictions",
                            subtitle: "Weekly model summary")
                    }
                }

                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        row(systemImage: "gearshape",
                            title: "Settings",
                            subtitle: "Picker, theme, API, favorites, iCloud")
                    }
                }
            }
            .navigationTitle("More")
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
