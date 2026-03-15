import Foundation
import Observation

private let profilesKey  = "gatewayProfiles"
private let activeIDKey  = "activeGatewayProfileID"

/// Manages the list of saved NullClaw gateway profiles and the currently-active one.
/// Persists to UserDefaults; Keychain tokens are keyed by each profile's URL (existing scheme).
@Observable
@MainActor
final class GatewayStore {

    // MARK: - Stored state

    /// All saved gateway profiles.
    var profiles: [GatewayProfile] = []

    /// The ID of the currently-active profile (the one the app is connected to).
    var activeProfileID: UUID? = nil

    // MARK: - Derived

    var activeProfile: GatewayProfile? {
        guard let id = activeProfileID else { return profiles.first }
        return profiles.first(where: { $0.id == id }) ?? profiles.first
    }

    /// Convenience — the URL of the active gateway (or a non-routable fallback).
    var activeURL: String { activeProfile?.url ?? "http://localhost:5111" }

    // MARK: - Init

    init() {
        load()
    }

    // Designated init for UI tests — injects a fake profile without touching UserDefaults.
    init(testProfile: GatewayProfile) {
        profiles = [testProfile]
        activeProfileID = testProfile.id
    }

    // MARK: - CRUD

    func addProfile(name: String, url: String) -> GatewayProfile {
        let profile = GatewayProfile(name: name, url: url)
        profiles.append(profile)
        if profiles.count == 1 { activeProfileID = profile.id }
        save()
        return profile
    }

    func updateProfile(_ profile: GatewayProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        save()
    }

    func deleteProfile(id: UUID) {
        // Remove Keychain token if it exists.
        if let profile = profiles.first(where: { $0.id == id }) {
            KeychainService.deleteToken(for: profile.url)
        }
        profiles.removeAll { $0.id == id }
        // If we deleted the active profile, switch to the first remaining one.
        if activeProfileID == id {
            activeProfileID = profiles.first?.id
        }
        save()
    }

    /// Marks a profile as paired / unpaired in memory and persists.
    func setProfilePaired(_ id: UUID, isPaired: Bool) {
        guard let idx = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[idx].isPaired = isPaired
        save()
    }

    /// Switches the active gateway. Returns the new active profile (or nil if id not found).
    @discardableResult
    func activate(id: UUID) -> GatewayProfile? {
        guard let profile = profiles.first(where: { $0.id == id }) else { return nil }
        activeProfileID = id
        save()
        return profile
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: profilesKey)
        UserDefaults.standard.set(activeProfileID?.uuidString, forKey: activeIDKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([GatewayProfile].self, from: data) {
            profiles = decoded
        }
        if let uuidStr = UserDefaults.standard.string(forKey: activeIDKey),
           let uuid = UUID(uuidString: uuidStr) {
            activeProfileID = uuid
        } else {
            activeProfileID = profiles.first?.id
        }
    }

    // MARK: - Migration from pre-Phase-9 single-gateway UserDefaults

    /// Called once on first launch after Phase 9 upgrade.
    /// If a legacy "gatewayURL" key exists and the profile list is empty, import it.
    func migrateFromLegacyIfNeeded() {
        guard profiles.isEmpty,
              let legacyURL = UserDefaults.standard.string(forKey: "gatewayURL"),
              !legacyURL.isEmpty else { return }

        let isPaired = (try? KeychainService.retrieveToken(for: legacyURL)).flatMap { $0 } != nil
        let profile = GatewayProfile(name: "Default", url: legacyURL, isPaired: isPaired)
        profiles = [profile]
        activeProfileID = profile.id
        save()
        // Remove the legacy key so this runs only once.
        UserDefaults.standard.removeObject(forKey: "gatewayURL")
    }
}
