import SwiftUI

struct StandingsView: View {
    @Environment(WeekSelection.self) private var selection

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Standings", systemImage: "list.number")
            } description: {
                Text("\(String(selection.year)) — coming in slice F3.")
            }
            .navigationTitle("Standings")
        }
    }
}
