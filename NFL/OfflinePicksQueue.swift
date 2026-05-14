import Foundation
import Observation

/// Persistent queue of picks mutations that failed to reach the backend.
///
/// Persisted to UserDefaults (key `pendingPickActions`) as a JSON array.
/// Not iCloud-synced on purpose — pending actions are device-local
/// (the device that made the pick is responsible for landing it).
///
/// Replay triggers:
/// - The PicksView's polling task ticks every 10s and calls `flush()`
/// - Pull-to-refresh on PicksView
/// - App foreground (handled in NFLApp via scenePhase)
///
/// Drop rules on replay (see `classify(_:)`):
/// - Success → drop the action.
/// - APIError.server / APIError.status(4xx) / APIError.decoding →
///   permanent (rule violation, bad team id, opponent already chose).
///   Drop + surface a DropEvent for one-time UI display.
/// - APIError.status(5xx) / APIError.badResponse → transient. Keep, bump
///   attempts.
@MainActor
@Observable
final class OfflinePicksQueue {
    static let shared = OfflinePicksQueue()

    private static let defaultsKey = "pendingPickActions"

    private(set) var pending: [PendingPickAction] = [] {
        didSet { persist() }
    }

    /// Surfaces a permanent-drop event to the UI so we can show
    /// "this pick couldn't be saved — <reason>" once.
    private(set) var lastDropError: DropEvent?

    /// True while a flush pass is running.
    private(set) var isFlushing: Bool = false

    var count: Int { pending.count }

    nonisolated struct DropEvent: Equatable, Identifiable, Sendable {
        let id: UUID
        let summary: String
        let reason: String
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([PendingPickAction].self, from: data)
        else { return }
        pending = decoded
    }

    private func persist() {
        if pending.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
            return
        }
        if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    // MARK: - Enqueue

    /// Append a freshly-failed action. Coalesces with an existing
    /// identical action for the same (kind, picker, gameId) so a
    /// rapid tap-tap doesn't pile up duplicates.
    func enqueue(_ action: PendingPickAction) {
        let dupeIdx = pending.firstIndex { other in
            other.kind == action.kind
                && other.picker == action.picker
                && other.gameId == action.gameId
        }
        if let dupeIdx {
            pending[dupeIdx] = action
        } else {
            pending.append(action)
        }
    }

    func removeAll() { pending.removeAll() }

    func dismissLastDropError() { lastDropError = nil }

    /// Try to replay every queued action. Returns the most recent
    /// PicksState produced by any successful replay (or nil if none
    /// landed). Caller (PicksViewModel) typically uses it to refresh
    /// its own state if one comes back.
    @discardableResult
    func flush(client: APIClient = .shared) async -> PicksState? {
        guard !isFlushing, !pending.isEmpty else { return nil }
        isFlushing = true
        defer { isFlushing = false }

        var latest: PicksState?
        var stillPending: [PendingPickAction] = []

        for action in pending {
            do {
                let envelope = try await action.execute(client: client)
                latest = envelope.data
                // success → drop
            } catch {
                let kind = Self.classify(error)
                switch kind {
                case .permanent:
                    lastDropError = DropEvent(
                        id: action.id,
                        summary: Self.summarize(action),
                        reason: Self.messageFor(error)
                    )
                    // drop
                case .transient:
                    var updated = action
                    updated.attempts += 1
                    updated.lastAttemptedAt = Date()
                    updated.lastError = Self.messageFor(error)
                    stillPending.append(updated)
                }
            }
        }
        pending = stillPending
        return latest
    }

    // MARK: - Error classification

    private enum FailureKind { case permanent, transient }

    private static func classify(_ error: Error) -> FailureKind {
        if let api = error as? APIError {
            switch api {
            case .status(let code):
                return (400..<500).contains(code) ? .permanent : .transient
            case .server:
                // FastAPI's {detail.error} envelope, always raised as 4xx.
                return .permanent
            case .decoding:
                return .permanent
            case .badResponse:
                return .transient
            }
        }
        if error is OfflinePicksError {
            return .permanent
        }
        return .transient
    }

    /// True when the just-failed-from-the-UI error should be queued
    /// silently rather than surfaced as a "save failed" alert.
    static func shouldQueue(_ error: Error) -> Bool {
        classify(error) == .transient
    }

    private static func messageFor(_ error: Error) -> String {
        if let api = error as? APIError {
            return api.localizedDescription
        }
        return error.localizedDescription
    }

    private static func summarize(_ action: PendingPickAction) -> String {
        switch action.kind {
        case .makePick:
            return "\(action.picker.displayName) pick on game \(action.gameId)"
        case .unpick:
            return "\(action.picker.displayName) un-pick on game \(action.gameId)"
        }
    }
}
