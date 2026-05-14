import SwiftUI

struct PredictionsView: View {
    @Environment(WeekSelection.self) private var selection

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Predictions", systemImage: "chart.bar.xaxis")
            } description: {
                Text("Week \(selection.week) · \(String(selection.year))\nComing in slice F2.")
                    .multilineTextAlignment(.center)
            }
            .navigationTitle("Predictions")
        }
    }
}
