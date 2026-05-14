import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            ScoreboardView()
                .tabItem { Label("Scoreboard", systemImage: "sportscourt") }

            ScheduleView()
                .tabItem { Label("Schedule", systemImage: "calendar") }

            ResultsView()
                .tabItem { Label("Results", systemImage: "trophy") }

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }

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
