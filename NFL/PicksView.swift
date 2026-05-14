import SwiftUI

@MainActor
@Observable
final class PicksViewModel {
    var season: Int = 2025
    var week: Int = 1
    var state: LoadState<PicksState> = .idle

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func load() async {
        state = .loading
        do {
            let envelope: APIEnvelope<PicksState> = try await client.get(
                "/api/picks/state",
                queryItems: [
                    URLQueryItem(name: "season", value: String(season)),
                    URLQueryItem(name: "week", value: String(week)),
                ]
            )
            state = .loaded(envelope.data)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct PicksView: View {
    @State private var model = PicksViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Picks")
                .task { await model.load() }
                .refreshable { await model.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView().controlSize(.large)
        case .failed(let message):
            ContentUnavailableView("Couldn’t load picks",
                                   systemImage: "wifi.exclamationmark",
                                   description: Text(message))
        case .loaded(let state):
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard(state)
                    pickerColumns(state)
                }
                .padding(16)
            }
        }
    }

    private func summaryCard(_ state: PicksState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Week \(state.week) · \(String(state.season))")
                    .font(.title3.weight(.semibold))
                Spacer()
                statusBadge(state.status)
            }
            HStack(spacing: 16) {
                labelStat("Games", "\(state.totalGames)")
                labelStat("Base", "\(state.basePoints)")
                if let turn = state.currentTurn {
                    labelStat("On the clock", turn.capitalized)
                }
            }
            Text("Updated \(state.updatedAt, format: .relative(presentation: .named))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    private func pickerColumns(_ state: PicksState) -> some View {
        HStack(spacing: 12) {
            pickerCard(name: "Jim", isOnClock: state.currentTurn == "jim")
            pickerCard(name: "Tom", isOnClock: state.currentTurn == "tom")
        }
    }

    private func pickerCard(name: String, isOnClock: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.headline)
                Spacer()
                if isOnClock {
                    Text("Picking")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
            }
            Text("No picks yet")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    private func labelStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }

    private func statusBadge(_ status: PicksState.Status) -> some View {
        Text(status.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor(status).opacity(0.18), in: Capsule())
            .foregroundStyle(statusColor(status))
    }

    private func statusColor(_ status: PicksState.Status) -> Color {
        switch status {
        case .picking: .blue
        case .locked: .orange
        case .scored: .green
        case .unknown: .secondary
        }
    }
}

#Preview {
    PicksView()
}
