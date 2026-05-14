import SwiftUI

struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var pickerChoice: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Who are you?")
                            .font(.headline)
                        Text("Pick the side that's yours. We'll emphasize your turn and your picks on the Picks tab.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            choiceButton("Jim")
                            choiceButton("Tom")
                            choiceButton(nil, label: "Skip")
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary, in: .rect(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 8) {
                        bulletPoint(systemImage: "sportscourt",
                                    title: "Games + Results",
                                    detail: "Browse any week of the schedule, with the model's per-game pick inline.")
                        bulletPoint(systemImage: "chart.bar.xaxis",
                                    title: "Predictions",
                                    detail: "Week-level rollups of best bets, strength distribution, top spreads + totals.")
                        bulletPoint(systemImage: "list.number",
                                    title: "Standings + Teams",
                                    detail: "AFC/NFC divisional view and a per-team browser with schedule, stats, leaders, roster.")
                        bulletPoint(systemImage: "checkmark.circle",
                                    title: "Picks",
                                    detail: "Open a week, pick games, mark doubles, call presses, close, score.")
                    }
                }
                .padding(20)
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NFL")
                .font(.largeTitle.weight(.bold))
            Text("Picks + predictions, paired with the live nflverse data.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func choiceButton(_ name: String?, label: String? = nil) -> some View {
        let displayLabel = label ?? name ?? "Skip"
        let isSelected = pickerChoice == name && name != nil
        return Button {
            pickerChoice = name
            settings.activePicker = name
            settings.hasCompletedOnboarding = true
            dismiss()
        } label: {
            Text(displayLabel)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.background.tertiary),
                    in: .capsule
                )
                .foregroundStyle(isSelected ? Color.white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func bulletPoint(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppSettings.shared)
}
