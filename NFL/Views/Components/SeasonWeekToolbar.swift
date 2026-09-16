import SwiftUI

/// Season + week selection as TWO short toolbar menus, week first.
///
/// ⚠️ Until 2026-09-16 every week-scoped screen (Predictions, Results, Picks
/// Active, Picks History) carried its own copy of ONE combined menu with a
/// Season section above a Week section. Seasons run 2026 → 1999, so the Week
/// section only appeared after scrolling past 28 rows — on the Mac and the
/// phone alike — and "there is no way to see week 2" was the reported symptom
/// while the control technically existed. Two menus, each shorter than a
/// screen, keep both reachable without scrolling; the labels show the current
/// choice so the selection reads at a glance on Mac / iPad sidebars too.
struct SeasonWeekToolbar: ToolbarContent {
    @Binding var season: Int
    @Binding var week: Int
    var seasons: [Int]
    var weeks: [Int]

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Week", selection: $week) {
                    ForEach(weeks, id: \.self) { w in
                        Text("Week \(w)").tag(w)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                chip("Week \(week)")
            }
            .accessibilityLabel("Week \(week)")

            Menu {
                Picker("Season", selection: $season) {
                    ForEach(seasons, id: \.self) { s in
                        Text(String(s)).tag(s)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                chip(String(season))
            }
            .accessibilityLabel("Season \(String(season))")
        }
    }

    private func chip(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .font(.subheadline.weight(.medium))
    }
}
