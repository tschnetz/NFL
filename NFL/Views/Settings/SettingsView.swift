import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var bindable = settings
        return NavigationStack {
            Form {
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
                        .iOSNoAutocapitalization()
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
                    HStack {
                        Text("Backend")
                        Spacer()
                        Text(Config.baseURL.host() ?? Config.baseURL.absoluteString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    HStack {
                        Text("iCloud sync")
                        Spacer()
                        Text(cloudLabel)
                            .font(.caption)
                            .foregroundStyle(cloudColor)
                    }
                    if let when = settings.lastCloudSyncAt {
                        HStack {
                            Text("Last sync")
                            Spacer()
                            Text(when, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Button("Force iCloud sync") {
                        settings.forceCloudSync()
                    }
                    .disabled(!kvsConfigured)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var kvsConfigured: Bool {
        settings.cloudSyncStatus != .unavailable
    }

    private var cloudLabel: String {
        switch settings.cloudSyncStatus {
        case .synced: "Synced"
        case .failed: "Sync failed"
        case .accountUnavailable: "Sign in to iCloud"
        case .unavailable: "Not configured"
        }
    }

    private var cloudColor: Color {
        switch settings.cloudSyncStatus {
        case .synced: .green
        case .failed: .orange
        case .accountUnavailable, .unavailable: .secondary
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings.shared)
}
