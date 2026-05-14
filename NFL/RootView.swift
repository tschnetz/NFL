import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            GamesView()
                .tabItem { Label("Games", systemImage: "sportscourt") }

            ResultsView()
                .tabItem { Label("Results", systemImage: "trophy") }

            PredictionsView()
                .tabItem { Label("Predictions", systemImage: "chart.bar.xaxis") }

            StandingsView()
                .tabItem { Label("Standings", systemImage: "list.number") }

            TeamsView()
                .tabItem { Label("Teams", systemImage: "person.3") }

            PicksView()
                .tabItem { Label("Picks", systemImage: "checkmark.circle") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview {
    RootView()
        .environment(WeekSelection())
        .environment(AppSettings.shared)
}
