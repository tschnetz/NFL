import Foundation
import Observation

@MainActor
@Observable
final class TeamRepository {
    static let shared = TeamRepository()

    private(set) var teamsByAbbr: [String: Team] = [:]

    private var loadingTask: Task<Void, Never>?
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func ensureLoaded() async {
        if !teamsByAbbr.isEmpty { return }
        if let loadingTask {
            await loadingTask.value
            return
        }
        let task = Task { @MainActor in
            do {
                let res: TeamsResponse = try await self.client.get("/api/team")
                self.teamsByAbbr = Dictionary(
                    uniqueKeysWithValues: res.teams.map { ($0.abbreviation, $0) }
                )
            } catch {
                // Fail open — logo views show a placeholder.
            }
        }
        loadingTask = task
        await task.value
        loadingTask = nil
    }

    func team(abbr: String) -> Team? {
        teamsByAbbr[abbr]
    }
}
