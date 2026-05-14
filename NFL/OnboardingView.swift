import SwiftUI

/// Focused first-launch picker selection. Replaces an earlier feature-
/// bullets onboarding — Pigskin's pattern is to put the picker choice
/// front and center and trust the user to discover features once they
/// land on the main UI.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            header
            choices
            footer
            Spacer(minLength: 0)
        }
        .padding(28)
        .interactiveDismissDisabled()
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image("Logos/NFL")
                .resizable()
                .scaledToFit()
                .frame(height: 72)
                .accessibilityHidden(true)
            Text("Who's picking?")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text("On this device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var choices: some View {
        VStack(spacing: 12) {
            choiceButton(.jim, tint: .blue)
            choiceButton(.tom, tint: .red)
            Button("Maybe later") {
                settings.hasCompletedOnboarding = true
                dismiss()
            }
            .font(.subheadline)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
        }
    }

    private func choiceButton(_ player: Player, tint: Color) -> some View {
        Button {
            settings.activePicker = player.rawValue
            settings.hasCompletedOnboarding = true
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.fill")
                    .font(.title2)
                Text(player.displayName)
                    .font(.title2.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.headline)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(tint.opacity(0.16), in: .rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        Text("This affects which picker the Picks tab highlights as ‘you’ and which admin controls you see. Change it later in Settings.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

#Preview {
    OnboardingView()
        .environment(AppSettings.shared)
}
