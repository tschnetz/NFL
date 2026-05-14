import SwiftUI

struct TeamsView: View {
    @Environment(WeekSelection.self) private var selection

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Teams", systemImage: "person.3")
            } description: {
                Text("Team browser — coming in slice F4.")
            }
            .navigationTitle("Teams")
        }
    }
}
