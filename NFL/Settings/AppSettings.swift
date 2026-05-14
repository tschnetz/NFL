import Combine
import Foundation
import Observation
import SwiftUI

/// Flip to `false` if the iCloud KVS entitlement is removed from the
/// target's Signing & Capabilities. Without the entitlement,
/// `NSUbiquitousKeyValueStore` will log "BUG IN CLIENT OF KVS" at
/// runtime — gate the touches behind this flag.
private let kICloudKVSEnabled = true

/// App-wide persistent settings. Writes to UserDefaults always; also
/// mirrors to `NSUbiquitousKeyValueStore` (iCloud KVS) when
/// `kICloudKVSEnabled` is true and the user is signed in to iCloud, so
/// values entered on one device propagate to the user's other devices.
///
/// Mirrors the Pigskin `AppSettings` pattern: local-first, cloud
/// best-effort. Adds NFL-specific keys (`favoriteTeamAbbrs`, `appearance`,
/// `hasCompletedOnboarding`).
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    nonisolated enum Appearance: String, CaseIterable, Identifiable, Sendable {
        case system, light, dark

        var id: String { rawValue }
        var label: String { rawValue.capitalized }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    enum CloudSyncStatus: Equatable {
        case unavailable
        case accountUnavailable
        case synced
        case failed

        var isSynced: Bool {
            if case .synced = self { return true }
            return false
        }
    }

    private enum Key {
        static let apiKey = "nfl.apiKey"
        static let activePicker = "nfl.activePicker"
        static let favoriteTeams = "nfl.favoriteTeamAbbrs"
        static let appearance = "nfl.appearance"
        static let hasCompletedOnboarding = "nfl.hasCompletedOnboarding"
    }

    private let defaults: UserDefaults

    /// `nil` until the iCloud KVS entitlement is wired and the flag is on.
    private let kvs: NSUbiquitousKeyValueStore? = kICloudKVSEnabled
        ? NSUbiquitousKeyValueStore.default
        : nil

    private var cancellables = Set<AnyCancellable>()
    private var cloudObserverInstalled = false
    /// Set to true while applying cloud-side updates; persist helpers
    /// skip the KVS write so a pull doesn't bounce back as a push.
    private var suppressCloudWrites = false

    var apiKey: String {
        didSet {
            persist(apiKey, forKey: Key.apiKey)
            let token = apiKey
            Task { await APIClient.shared.setAuthToken(token) }
        }
    }

    var activePicker: String? {
        didSet {
            defaults.set(activePicker, forKey: Key.activePicker)
            if !suppressCloudWrites, let kvs, cloudSyncStatus.isSynced {
                kvs.set(activePicker, forKey: Key.activePicker)
                syncCloud()
            }
        }
    }

    var favoriteTeamAbbrs: Set<String> {
        didSet { persistFavorites() }
    }

    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    // Diagnostic surface for Settings.
    private(set) var lastCloudSyncAt: Date?
    private(set) var cloudSyncStatus: CloudSyncStatus = .unavailable
    var cloudEnabled: Bool { cloudSyncStatus.isSynced }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let localKey = defaults.string(forKey: Key.apiKey) ?? ""
        let localPicker = defaults.string(forKey: Key.activePicker)
        let localFavs = Set(defaults.stringArray(forKey: Key.favoriteTeams) ?? [])
        let localAppearance = Appearance(
            rawValue: defaults.string(forKey: Key.appearance) ?? ""
        ) ?? .system
        let localOnboarded = defaults.bool(forKey: Key.hasCompletedOnboarding)

        self.apiKey = localKey
        self.activePicker = localPicker
        self.favoriteTeamAbbrs = localFavs
        self.appearance = localAppearance
        self.hasCompletedOnboarding = localOnboarded

        // Determine cloud availability without writing yet — the initial
        // status is set so writes know whether to mirror.
        if kvs != nil && Self.hasICloudAccount {
            // Optimistic; the first syncCloud() call will confirm.
            cloudSyncStatus = .unavailable
        } else if kvs != nil {
            cloudSyncStatus = .accountUnavailable
        }

        // Push the persisted auth token into the API client immediately
        // so the first request after launch carries the bearer header.
        let initialToken = self.apiKey
        Task { await APIClient.shared.setAuthToken(initialToken) }

        // Best-effort first sync — pulls any cloud values that beat
        // local on a fresh install.
        _ = syncCloud()
    }

    func toggleFavorite(_ abbr: String) {
        let upper = abbr.uppercased()
        if favoriteTeamAbbrs.contains(upper) {
            favoriteTeamAbbrs.remove(upper)
        } else {
            favoriteTeamAbbrs.insert(upper)
        }
    }

    func forceCloudSync() {
        _ = syncCloud()
    }

    // MARK: - Persistence helpers

    private func persist(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
        if !suppressCloudWrites, let kvs, cloudSyncStatus.isSynced {
            kvs.set(value, forKey: key)
            syncCloud()
        }
    }

    private func persistFavorites() {
        let array = Array(favoriteTeamAbbrs).sorted()
        defaults.set(array, forKey: Key.favoriteTeams)
        if !suppressCloudWrites, let kvs, cloudSyncStatus.isSynced {
            kvs.set(array, forKey: Key.favoriteTeams)
            syncCloud()
        }
    }

    // MARK: - Cloud sync

    @discardableResult
    private func syncCloud() -> Bool {
        guard let kvs else {
            cloudSyncStatus = .unavailable
            return false
        }
        guard Self.hasICloudAccount else {
            cloudSyncStatus = .accountUnavailable
            return false
        }
        let didSync = kvs.synchronize()
        cloudSyncStatus = didSync ? .synced : .failed
        if didSync {
            pullCloudValues(from: kvs)
            installCloudObserverIfNeeded()
        }
        return didSync
    }

    private static var hasICloudAccount: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private func pullCloudValues(from kvs: NSUbiquitousKeyValueStore) {
        lastCloudSyncAt = Date()
        suppressCloudWrites = true
        defer { suppressCloudWrites = false }

        let cloudKey = kvs.string(forKey: Key.apiKey) ?? ""
        if !cloudKey.isEmpty && cloudKey != apiKey {
            apiKey = cloudKey
        }

        let cloudPicker = kvs.string(forKey: Key.activePicker)
        if let cloudPicker, !cloudPicker.isEmpty, cloudPicker != activePicker {
            activePicker = cloudPicker
        }

        if let cloudFavs = kvs.array(forKey: Key.favoriteTeams) as? [String] {
            let cloudSet = Set(cloudFavs)
            if !cloudSet.isEmpty && cloudSet != favoriteTeamAbbrs {
                favoriteTeamAbbrs = cloudSet
            }
        }
    }

    private func installCloudObserverIfNeeded() {
        guard let kvs, cloudSyncStatus.isSynced, !cloudObserverInstalled else { return }
        cloudObserverInstalled = true
        NotificationCenter.default.publisher(
            for: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else { return }
            self.pullCloudValues(from: kvs)
        }
        .store(in: &cancellables)
    }
}
