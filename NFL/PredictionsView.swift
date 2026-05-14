import SwiftUI

@MainActor
@Observable
final class PredictionsViewModel {
    var state: LoadState<PredictionsSummary> = .idle

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func load(season: Int, week: Int) async {
        state = .loading
        do {
            let path = "/api/preds/summary/\(season)/w\(week)"
            let summary: PredictionsSummary = try await client.get(path)
            state = .loaded(summary)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct PredictionsView: View {
    @Environment(WeekSelection.self) private var selection
    @State private var model = PredictionsViewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Predictions")
                .toolbar { toolbarContent }
                .task(id: pivotKey) {
                    await model.load(season: selection.year, week: selection.week)
                }
                .refreshable {
                    await model.load(season: selection.year, week: selection.week)
                }
        }
    }

    private var pivotKey: String { "\(selection.year)-\(selection.week)" }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section("Season") {
                    ForEach(selection.availableSeasons, id: \.self) { s in
                        Button {
                            selection.year = s
                        } label: {
                            if s == selection.year {
                                Label(String(s), systemImage: "checkmark")
                            } else {
                                Text(String(s))
                            }
                        }
                    }
                }
                Section("Week") {
                    ForEach(selection.availableWeeks, id: \.self) { w in
                        Button {
                            selection.week = w
                        } label: {
                            if w == selection.week {
                                Label("Week \(w)", systemImage: "checkmark")
                            } else {
                                Text("Week \(w)")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("\(String(selection.year)) · W\(selection.week)")
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(.subheadline.weight(.medium))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView().controlSize(.large)
        case .failed(let message):
            ContentUnavailableView("Couldn’t load predictions",
                                   systemImage: "wifi.exclamationmark",
                                   description: Text(message))
        case .loaded(let summary) where summary.games == 0:
            ContentUnavailableView("No predictions",
                                   systemImage: "chart.bar.xaxis",
                                   description: Text("Nothing graded for week \(summary.week) of \(String(summary.season))."))
        case .loaded(let summary):
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summaryCard(summary)
                    strengthTiles(summary)
                    overUnderSplit(summary)
                    topList("Top best bets", rows: summary.topBestBets, valueKey: .edge, showMarket: true)
                    topList("Top spreads", rows: summary.topSpreads, valueKey: .margin)
                    topList("Top totals", rows: summary.topTotals, valueKey: .line)
                }
                .padding(16)
            }
        }
    }

    // MARK: - Cards

    private func summaryCard(_ summary: PredictionsSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Week \(summary.week) · \(String(summary.season))")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(summary.games) games")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if let version = summary.version {
                Text("Model v\(version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    private func strengthTiles(_ summary: PredictionsSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Best bet strength")
            HStack(spacing: 8) {
                strengthTile(.strong, count: summary.strengthCount(.strong))
                strengthTile(.medium, count: summary.strengthCount(.medium))
                strengthTile(.lean, count: summary.strengthCount(.lean))
                strengthTile(.pass, count: summary.strengthCount(.pass))
            }
        }
    }

    private func strengthTile(_ strength: GamePrediction.Strength, count: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(strengthColor(strength))
            Text(strength.rawValue)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(strengthColor(strength).opacity(0.12), in: .rect(cornerRadius: 12))
    }

    private func overUnderSplit(_ summary: PredictionsSummary) -> some View {
        HStack(spacing: 12) {
            tile(label: "Over", value: "\(summary.total.overCount)", color: .blue)
            tile(label: "Under", value: "\(summary.total.underCount)", color: .indigo)
        }
    }

    private func tile(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(color)
            Spacer()
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }

    // MARK: - Top lists

    private enum ValueKey { case edge, margin, line }

    private func topList(_ title: String,
                         rows: [SummaryRow],
                         valueKey: ValueKey,
                         showMarket: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title)
            if rows.isEmpty {
                Text("Nothing to rank.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        rowView(row, valueKey: valueKey, showMarket: showMarket)
                        if row.id != rows.last?.id {
                            Divider().padding(.leading, 8)
                        }
                    }
                }
                .background(.background.secondary, in: .rect(cornerRadius: 14))
            }
        }
    }

    private func rowView(_ row: SummaryRow,
                         valueKey: ValueKey,
                         showMarket: Bool) -> some View {
        HStack(spacing: 10) {
            if let away = row.awayTeam {
                TeamLogoView(abbr: away, size: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.pick ?? "—")
                        .font(.subheadline.weight(.semibold))
                    if showMarket, let market = row.market {
                        Text(market.uppercased())
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                if let away = row.awayTeam, let home = row.homeTeam {
                    Text("\(away) @ \(home)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let strength = row.strengthValue {
                strengthCapsule(strength)
            }
            valueLabel(for: row, key: valueKey)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func valueLabel(for row: SummaryRow, key: ValueKey) -> some View {
        let text: String
        let caption: String
        switch key {
        case .edge:
            text = row.edge.map { String(format: "%+.1f", $0) } ?? "—"
            caption = "edge"
        case .margin:
            text = row.predHomeMargin.map { String(format: "%+.1f", $0) } ?? "—"
            caption = "margin"
        case .line:
            text = row.line.map { String(format: "%.1f", $0) } ?? "—"
            caption = "line"
        }
        return VStack(alignment: .trailing, spacing: 2) {
            Text(text)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
        }
    }

    // MARK: - Bits

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func strengthCapsule(_ strength: GamePrediction.Strength) -> some View {
        Text(strength.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(strengthColor(strength).opacity(0.18), in: Capsule())
            .foregroundStyle(strengthColor(strength))
    }

    private func strengthColor(_ strength: GamePrediction.Strength) -> Color {
        switch strength {
        case .strong: .green
        case .medium: .blue
        case .lean: .orange
        case .pass: .secondary
        }
    }
}

#Preview {
    PredictionsView()
        .environment(WeekSelection())
        .environment(AppSettings.shared)
}
