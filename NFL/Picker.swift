import Foundation

/// Two-user picks system, hardcoded just like the legacy app + the
/// backend Pydantic model (`^(Jim|Tom)$` pattern). Used by
/// PendingPickAction + the typed picker-aware UI.
///
/// Named `Player` instead of `Picker` to avoid colliding with SwiftUI's
/// `Picker` view in the same module.
nonisolated enum Player: String, CaseIterable, Codable, Sendable, Identifiable {
    case jim = "Jim"
    case tom = "Tom"

    var id: String { rawValue }
    var displayName: String { rawValue }

    /// The other player — used for press-modifier permission rules.
    var opponent: Player {
        self == .jim ? .tom : .jim
    }
}
