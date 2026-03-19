import Foundation
import Observation
import SwiftData

// MARK: - GatewayStore

private let activeIDKey = "activeGatewayProfileID"

/// Manages the list of saved NullClaw gateway profiles and the currently-active one.
/// Backed by SwiftData (Phase 11+). Previously persisted to UserDefaults.
@Observable
@MainActor
final class GatewayStore {

    // MARK: - Stored state

    /// All saved gateway profiles, sorted by creation order.
    var profiles: [GatewayProfile] = []

    /// The ID of the currently-active profile (the one the app is connected to).
    var activeProfileID: UUID? = nil

    // MARK: - Private

    /// Retained so the ModelContainer (and its underlying Core Data stack) is not
    /// deallocated while this store is alive. Without this strong reference, ARC
    /// would release the container immediately after init, triggering
    /// ModelContext.reset() and invalidating every @Model instance.
    private var _container: ModelContainer?
    private var context: ModelContext

    // MARK: - Derived

    var activeProfile: GatewayProfile? {
        guard let id = activeProfileID else { return profiles.first }
        return profiles.first(where: { $0.id == id }) ?? profiles.first
    }

    var activeURL: String { activeProfile?.url ?? "http://localhost:5111" }

    // MARK: - Init

    /// Normal init — takes the shared ModelContext from the app container.
    init(context: ModelContext) {
        self._container = nil   // Container lifetime is managed by the caller (NullClawUIApp).
        self.context = context
        loadProfiles()
        // Restore active profile ID from UserDefaults (it's just a UUID, not sensitive data).
        if let uuidStr = UserDefaults.standard.string(forKey: activeIDKey),
           let uuid = UUID(uuidString: uuidStr) {
            activeProfileID = uuid
        } else {
            activeProfileID = profiles.first?.id
        }
    }

    /// UI-test init — injects a fake profile without touching disk.
    init(testProfile: GatewayProfile) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: GatewayProfile.self, ConversationRecord.self, configurations: config)
        self._container = container
        self.context = container.mainContext
        context.insert(testProfile)
        do { try context.save() } catch { print("[GatewayStore] Warning: failed to save test profile: \(error)") }
        profiles = [testProfile]
        activeProfileID = testProfile.id
    }

    /// In-memory init for unit tests — no disk or CloudKit access.
    init(inMemory: Bool = true) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: GatewayProfile.self, ConversationRecord.self, configurations: config)
        self._container = container
        self.context = container.mainContext
        profiles = []
        activeProfileID = nil
    }

    // MARK: - CRUD

    @discardableResult
    func addProfile(name: String, url: String) -> GatewayProfile {
        let sortOrder = profiles.count
        let profile = GatewayProfile(name: name, url: url, sortOrder: sortOrder)
        context.insert(profile)
        save()
        loadProfiles()
        if profiles.count == 1 { activate(id: profile.id) }
        return profile
    }

    func updateProfile(_ profile: GatewayProfile) {
        guard let existing = profiles.first(where: { $0.id == profile.id }) else { return }

        if existing.normalizedURL != profile.normalizedURL {
            do {
                try KeychainService.moveToken(from: existing.url, to: profile.url)
            } catch {
                // Preserve the old token mapping if migration fails.
            }
        }

        existing.name = profile.name
        existing.url = profile.url
        // For open gateways (requiresPairing == false), isPaired was set via completeOpenGateway
        // and must not be re-derived from the Keychain (no token is ever stored for them).
        existing.requiresPairing = profile.requiresPairing
        if profile.requiresPairing {
            existing.isPaired = KeychainService.hasToken(for: profile.url)
        } else {
            existing.isPaired = profile.isPaired
        }
        save()
        loadProfiles()
    }

    func deleteProfile(id: UUID) {
        if let profile = profiles.first(where: { $0.id == id }) {
            KeychainService.deleteToken(for: profile.url)
            context.delete(profile)
            save()
        }
        if activeProfileID == id {
            activeProfileID = profiles.first(where: { $0.id != id })?.id
            saveActiveID()
        }
        loadProfiles()
    }

    func setProfilePaired(_ id: UUID, isPaired: Bool) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        profile.isPaired = isPaired
        save()
    }

    /// Marks whether the gateway at `id` requires a pairing token.
    /// Call with `false` when the gateway responds 403 to /pair (require_pairing: false).
    func setProfileRequiresPairing(_ id: UUID, requiresPairing: Bool) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        profile.requiresPairing = requiresPairing
        save()
    }

    @discardableResult
    func activate(id: UUID) -> GatewayProfile? {
        guard let profile = profiles.first(where: { $0.id == id }) else { return nil }
        activeProfileID = id
        saveActiveID()
        return profile
    }

    // MARK: - Persistence

    private func save() {
        do { try context.save() } catch { print("[GatewayStore] Save failed: \(error)") }
    }

    private func saveActiveID() {
        UserDefaults.standard.set(activeProfileID?.uuidString, forKey: activeIDKey)
    }

    private func loadProfiles() {
        let descriptor = FetchDescriptor<GatewayProfile>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        profiles = (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Migration from pre-Phase-9 single-gateway UserDefaults

    /// Called once on first launch after Phase 9 upgrade.
    /// If a legacy "gatewayURL" key exists and the profile list is empty, import it.
    func migrateFromLegacyIfNeeded() {
        guard profiles.isEmpty,
              let legacyURL = UserDefaults.standard.string(forKey: "gatewayURL"),
              !legacyURL.isEmpty else { return }

        let isPaired = (try? KeychainService.retrieveToken(for: legacyURL)).flatMap { $0 } != nil
        let profile = GatewayProfile(name: "Default", url: legacyURL, isPaired: isPaired, sortOrder: 0)
        context.insert(profile)
        save()
        loadProfiles()
        activeProfileID = profile.id
        saveActiveID()
        UserDefaults.standard.removeObject(forKey: "gatewayURL")
    }

    // MARK: - Migration from Phase 9 UserDefaults JSON (Phase 11)

    /// One-time migration: reads the old "gatewayProfiles" UserDefaults JSON blob and
    /// inserts profiles into SwiftData. Safe to call on every launch.
    func migrateFromUserDefaultsIfNeeded() {
        guard profiles.isEmpty else { return }

        let key = "gatewayProfiles"
        guard let data = UserDefaults.standard.data(forKey: key) else { return }

        struct LegacyProfile: Codable {
            let id: UUID
            var name: String
            var url: String
            var isPaired: Bool
        }

        guard let legacyProfiles = try? JSONDecoder().decode([LegacyProfile].self, from: data) else { return }

        for (index, legacy) in legacyProfiles.enumerated() {
            let profile = GatewayProfile(id: legacy.id, name: legacy.name, url: legacy.url,
                                         isPaired: legacy.isPaired, sortOrder: index)
            context.insert(profile)
        }
        save()
        loadProfiles()

        // Restore active profile ID.
        if let uuidStr = UserDefaults.standard.string(forKey: activeIDKey),
           let uuid = UUID(uuidString: uuidStr) {
            activeProfileID = uuid
        } else {
            activeProfileID = profiles.first?.id
        }

        // Remove legacy keys so this runs only once.
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Migration: fix requiresPairing for open gateways (Phase 15 fix)

    /// One-time migration: for any profile that is `isPaired = true` but has no Keychain token,
    /// set `requiresPairing = false` so that updateProfile does not clobber `isPaired`.
    /// Safe to call on every launch (no-op when all profiles already have correct state).
    func migrateOpenGatewayFlagsIfNeeded() {
        var changed = false
        for profile in profiles where profile.isPaired && profile.requiresPairing {
            if !KeychainService.hasToken(for: profile.url) {
                profile.requiresPairing = false
                changed = true
            }
        }
        if changed { save() }
    }
}
