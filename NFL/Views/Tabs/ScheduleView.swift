import SwiftUI

/// Forward-looking schedule for the current season only. Pigskin's
/// pattern: no season picker, just week chips. Empty state when the
/// league hasn't dropped this season's schedule yet.
@MainActor
@Observable
final class ScheduleViewModel {
    let season: Int = WeekSelection.currentSeason
    var week: Int = 1

    var schedule: LoadState<[ScheduleGame]> = .idle

    let availableWeeks: [Int] = Array(1...18)

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    var gamesForCurrentWeek: [ScheduleGame] {
        guard case .loaded(let all) = schedule else { return [] }
        return all
            .filter { $0.week == week && $0.seasonType == "regular" }
            .sorted { $0.kickoff < $1.kickoff }
    }

    func reload() async {
        schedule = .loading
        do {
            let response: ScheduleResponse = try await client.get("/api/schedule/\(season)")
            schedule = .loaded(response.games)
        } catch {
            schedule = .failed(error.localizedDescription)
        }
    }
}

struct ScheduleView: View {
    @State private var model = ScheduleViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Schedule")
                .navigationSubtitle(String(model.season))
                .task {
                    await model.reload()
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(60)) } catch { return }
                        await model.reload()
                    }
                }
                .refreshable { await model.reload() }
        }
    }

    private var weekChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.availableWeeks, id: \.self) { week in
                        weekChip(week)
                            .id(week)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onAppear { proxy.scrollTo(model.week, anchor: .center) }
            .onChange(of: model.week) { _, new in
                withAnimation { proxy.scrollTo(new, anchor: .center) }
            }
        }
    }

    private func weekChip(_ week: Int) -> some View {
        let isSelected = model.week == week
        return Button {
            model.week = week
        } label: {
            Text("Week \(week)")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : .primary)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor : Color.gray.opacity(0.18))
                )
                .overlay(
                    Capsule().strokeBorder(isSelected ? Color.clear : Color.gray.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch model.schedule {
        case .idle, .loading:
            VStack { Spacer(); ProgressView().controlSize(.large); Spacer() }
        case .failed(let message):
            ContentUnavailableView("Couldn’t load schedule",
                                   systemImage: "wifi.exclamationmark",
                                   description: Text(message))
        case .loaded:
            let games = model.gamesForCurrentWeek
            if games.isEmpty {
                ContentUnavailableView("Schedule not published",
                                       systemImage: "calendar.badge.exclamationmark",
                                       description: Text("Week \(model.week) of \(String(model.season)) isn’t available yet."))
            } else {
                List {
                    Section {
                        weekChips
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    Section {
                        ForEach(games) { game in
                            NavigationLink {
                                GameDetailView(game: game, prediction: nil)
                            } label: {
                                ScheduleRow(game: game)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(.init(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct ScheduleRow: View {
    let game: ScheduleGame

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                TeamLogoView(abbr: game.awayTeam, size: 30, style: .helmet)
                TeamLogoView(abbr: game.homeTeam, size: 30, style: .helmet)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(game.awayTeam) @ \(game.homeTeam)")
                    .font(.subheadline.weight(.semibold))
                if let stadium = game.stadium {
                    Text(stadium)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(game.kickoff, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(game.kickoff, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ScheduleView()
        .environment(WeekSelection())
        .environment(AppSettings.shared)
}
