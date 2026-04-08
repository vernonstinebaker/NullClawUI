import Observation
import SwiftUI

/// Top-level application state shared across the entire view hierarchy.
/// Phase 9+: gateway identity (URL, isPaired) is delegated to GatewayStore.
/// AppModel holds per-connection transient state: agentCard, connectionStatus.
@Observable
@MainActor
final class AppModel {
    // MARK: - Gateway store (source of truth for profiles)

    var store: GatewayStore

    // MARK: - Per-connection transient state

    /// Cache key for the active profile — UUID string when available, normalized URL as fallback.
    private var activeCacheKey: String {
        store.activeProfileID?.uuidString ?? store.activeURL
    }

    /// The parsed agent card retrieved from /.well-known/agent-card.json.
    /// Setting this also persists the card into the per-profile cache so the title
    /// stays correct during reconnect.
    var agentCard: AgentCard? {
        didSet {
            if let card = agentCard {
                agentCardCache[activeCacheKey] = card
            }
        }
    }

    /// Cache of agent cards keyed by profile UUID (or normalized URL as fallback).
    /// Used to show the correct agent name while a reconnect is in progress.
    /// Bounded to the number of known profiles; stale entries are removed on profile deletion.
    private var agentCardCache: [String: AgentCard] = [:]

    /// Returns the best available agent card — live card first, then cached.
    var effectiveAgentCard: AgentCard? {
        agentCard ?? agentCardCache[activeCacheKey]
    }

    /// Removes the cached agent card for a deleted profile so stale data is not served.
    func evictAgentCard(for profileID: UUID) {
        agentCardCache.removeValue(forKey: profileID.uuidString)
    }

    /// Current gateway reachability state.
    var connectionStatus: ConnectionStatus = .unknown

    /// True while the app is performing the initial open-gateway probe at launch.
    /// ContentView shows a loading spinner instead of SettingsView during this window.
    var isCheckingGateway: Bool = true

    // MARK: - Centralized Error Presentation

    /// The error message currently being presented to the user via the root alert.
    /// Set this property (or call `presentError(_:)`) to show a global error alert.
    /// Clear it by setting to nil to dismiss the alert.
    var presentedErrorMessage: String?

    /// Presents an error message in the root alert.
    /// Extracts `LocalizedError.errorDescription` when available, otherwise uses
    /// `localizedDescription`.
    func presentError(_ error: Error) {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            presentedErrorMessage = description
        } else {
            presentedErrorMessage = error.localizedDescription
        }
    }

    /// Dismisses the currently presented error alert.
    func dismissError() {
        presentedErrorMessage = nil
    }

    // MARK: - Convenience passthroughs (keep callers compatible)

    /// URL of the currently-active gateway profile.
    var gatewayURL: String {
        store.activeURL
    }

    /// Whether the active profile has a valid Keychain token.
    var isPaired: Bool {
        get { store.activeProfile?.isPaired ?? false }
        set {
            if let id = store.activeProfileID ?? store.profiles.first?.id {
                store.setProfilePaired(id, isPaired: newValue)
            }
        }
    }

    // MARK: - Lifecycle

    init(store: GatewayStore) {
        self.store = store
    }
}

enum ConnectionStatus {
    case unknown
    case online
    case offline
}
