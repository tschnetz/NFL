import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            GamesView()
                .tabItem { Label("Games", systemImage: "sportscourt") }

            PicksView()
                .tabItem { Label("Picks", systemImage: "checkmark.circle") }
        }
    }
}

#Preview {
    RootView()
}
