import SwiftUI

struct GameDetailView: View {
    let game: ScheduleGame
    let prediction: GamePrediction?

    @State private var odds: LoadState<[OddsItem]> = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                if let prediction { predictionSection(prediction) }
                oddsSection
                metaSection
            }
            .padding(16)
        }
        .navigationTitle("\(game.awayTeam) @ \(game.homeTeam)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadOdds() }
    }

    // MARK: - Odds

    private func loadOdds() async {
        guard case .idle = odds else { return }
        odds = .loading
        do {
            let response: EventOddsResponse = try await APIClient.shared
                .get("/api/event-odds/\(game.espnId)")
            odds = .loaded(response.items)
        } catch {
            odds = .failed(error.localizedDescription)
        }
    }

    @ViewBuilder
    private var oddsSection: some View {
        switch odds {
        case .idle, .loading:
            EmptyView()
        case .failed:
            EmptyView()
        case .loaded(let items) where items.isEmpty:
            EmptyView()
        case .loaded(let items):
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Live odds")
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        oddsRow(item)
                        if item.id != items.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 14))
        }
    }

    private func oddsRow(_ item: OddsItem) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.provider.name)
                    .font(.subheadline.weight(.semibold))
                if let details = item.details {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let ou = item.overUnder {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("O/U")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    Text(String(format: "%.1f", ou))
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                teamColumn(abbr: game.awayTeam, score: game.awayScore,
                           isWinner: game.winnerAbbr == game.awayTeam)
                Spacer()
                Text("@")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                teamColumn(abbr: game.homeTeam, score: game.homeScore,
                           isWinner: game.winnerAbbr == game.homeTeam)
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(game.kickoff, format: .dateTime.weekday().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let stadium = game.stadium {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(stadium)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    private func teamColumn(abbr: String, score: Int?, isWinner: Bool) -> some View {
        let teamColor = TeamRepository.shared.team(abbr: abbr)?.primarySwiftUIColor
        return VStack(spacing: 6) {
            TeamLogoView(abbr: abbr, size: 56)
            Text(abbr)
                .font(.title2.weight(.bold))
                .foregroundStyle(teamColor ?? .primary)
            Text(score.map(String.init) ?? "—")
                .font(.largeTitle.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isWinner ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Prediction

    private func predictionSection(_ p: GamePrediction) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Model prediction")

            HStack(alignment: .top, spacing: 16) {
                bestBetCard(p)
                Divider().frame(height: 56)
                marginCard(p)
            }

            VStack(spacing: 0) {
                pickRow("Spread", pick: p.spreadPick,
                        strength: p.spreadBetStrength.flatMap(GamePrediction.Strength.init))
                Divider()
                pickRow("Total", pick: p.totalPick,
                        strength: p.totalBetStrength.flatMap(GamePrediction.Strength.init))
                Divider()
                statRow("Home win prob", value: percent(p.predHomeWinProb))
                Divider()
                statRow("Cover prob (calibrated)", value: percent(p.predCoverProbCal))
                Divider()
                statRow("Kelly fraction",
                        value: p.kellyFraction.map { String(format: "%.2f%% of bankroll", $0 * 100) })
                if let mu = p.muPost, let sigma = p.sigmaPost {
                    Divider()
                    statRow("Margin ± σ",
                            value: String(format: "%+.1f ± %.1f", mu, sigma))
                }
                if let lo = p.marginCi80Lower, let hi = p.marginCi80Upper {
                    Divider()
                    statRow("80% interval",
                            value: String(format: "%+.1f to %+.1f", lo, hi))
                }
                Divider()
                statRow("Vegas spread",
                        value: p.spreadLine.map { String(format: "%+.1f", $0) })
                Divider()
                statRow("Total line",
                        value: p.overUnderLine.map { String(format: "%.1f", $0) })
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    private func bestBetCard(_ p: GamePrediction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Best bet")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(p.bestBet ?? "—")
                .font(.title3.weight(.semibold))
            if let strength = p.bestBetStrengthValue {
                strengthCapsule(strength)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func marginCard(_ p: GamePrediction) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("Predicted margin")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            Text(String(format: "%+.1f", p.predHomeMargin))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(p.predHomeMargin >= 0 ? p.homeTeam : p.awayTeam)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func pickRow(_ label: String, pick: String?, strength: GamePrediction.Strength?) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(pick ?? "—")
                .font(.callout.weight(.medium))
            if let strength { strengthCapsule(strength) }
        }
        .padding(.vertical, 8)
    }

    private func statRow(_ label: String, value: String?) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—")
                .font(.callout.weight(.medium))
                .monospacedDigit()
        }
        .padding(.vertical, 8)
    }

    private func percent(_ value: Double?) -> String? {
        value.map { "\(Int(round($0 * 100)))%" }
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

    // MARK: - Meta

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Game info")
            VStack(spacing: 0) {
                statRow("Season", value: String(game.season))
                Divider()
                statRow("Week", value: "Week \(game.week)")
                Divider()
                statRow("Season type", value: game.seasonType.capitalized)
                if let roof = game.roof {
                    Divider()
                    statRow("Roof", value: roof.capitalized)
                }
                if let surface = game.surface {
                    Divider()
                    statRow("Surface", value: surface.capitalized)
                }
                if game.overtime == true {
                    Divider()
                    statRow("Overtime", value: "Yes")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}
