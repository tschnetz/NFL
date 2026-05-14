import Foundation

/// Standard four-case loading enum used by every data-fetching view
/// model. `.idle` is the pre-fetch state, `.loading` covers in-flight
/// requests, `.loaded(Value)` carries the decoded payload, `.failed`
/// carries a human-readable message for surface in ContentUnavailableView.
nonisolated enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}
