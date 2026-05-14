import SwiftUI

/// Top-level Picks tab. Hosts a segmented control with three sub-pages:
///
/// - **Active** — current week's picking flow (PicksActiveView)
/// - **History** — read-only browse of past weeks (PicksHistoryView)
/// - **Standings** — Jim vs Tom season totals (PicksStandingsView)
struct PicksView: View {
    @SceneStorage("picks.subtab") private var subtab: SubTab = .active

    enum SubTab: String, CaseIterable, Identifiable, Codable {
        case active = "Active"
        case history = "History"
        case standings = "Standings"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Picks section", selection: $subtab) {
                ForEach(SubTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            switch subtab {
            case .active: PicksActiveView()
            case .history: PicksHistoryView()
            case .standings: PicksStandingsView()
            }
        }
    }
}

#Preview {
    PicksView()
        .environment(WeekSelection())
        .environment(AppSettings.shared)
}
