import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var bindable = settings
        return NavigationStack {
            Form {
                Section {
                    Picker("Active picker", selection: $bindable.activePicker) {
                        Text("None").tag(String?.none)
                        Text("Jim").tag(String?.some("Jim"))
                        Text("Tom").tag(String?.some("Tom"))
                    }
                } header: {
                    Text("Picker")
                } footer: {
                    Text("Determines which picker the Picks tab highlights as ‘you.’")
                }

                Section {
                    Picker("Theme", selection: $bindable.appearance) {
                        ForEach(AppSettings.Appearance.allCases) { app in
                            Text(app.label).tag(app)
                        }
                    }
                } header: {
                    Text("Appearance")
                }

                Section {
                    SecureField("Bearer token", text: $bindable.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("Used as Authorization: Bearer … when the backend has API_KEY set. Leave blank otherwise.")
                }

                if !settings.favoriteTeamAbbrs.isEmpty {
                    Section("Favorite teams") {
                        ForEach(settings.favoriteTeamAbbrs.sorted(), id: \.self) { abbr in
                            HStack(spacing: 10) {
                                TeamLogoView(abbr: abbr, size: 24)
                                Text(TeamRepository.shared.team(abbr: abbr)?.displayName ?? abbr)
                                    .font(.subheadline)
                                Spacer()
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    settings.toggleFavorite(abbr)
                                } label: {
                                    Label("Remove", systemImage: "star.slash")
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        settings.hasCompletedOnboarding = false
                    } label: {
                        Label("Replay onboarding", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("Debug")
                }

                Section {
                    HStack {
                        Text("Backend")
                        Spacer()
                        Text(Config.baseURL.host() ?? Config.baseURL.absoluteString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings.shared)
}
