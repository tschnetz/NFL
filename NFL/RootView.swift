import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            GamesView()
                .tabItem { Label("Games", systemImage: "sportscourt") }

            PredictionsView()
                .tabItem { Label("Predictions", systemImage: "chart.bar.xaxis") }

            StandingsView()
                .tabItem { Label("Standings", systemImage: "list.number") }

            TeamsView()
                .tabItem { Label("Teams", systemImage: "person.3") }

            PicksView()
                .tabItem { Label("Picks", systemImage: "checkmark.circle") }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview {
    RootView()
        .environment(WeekSelection())
        .environment(AppSettings.shared)
}
