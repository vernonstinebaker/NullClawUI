import SwiftUI
import Observation

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
    private var agentCardCache: [String: AgentCard] = [:]

    /// Returns the best available agent card — live card first, then cached.
    var effectiveAgentCard: AgentCard? {
        agentCard ?? agentCardCache[activeCacheKey]
    }

    /// Current gateway reachability state.
    var connectionStatus: ConnectionStatus = .unknown

    // MARK: - Convenience passthroughs (keep callers compatible)

    /// URL of the currently-active gateway profile.
    var gatewayURL: String { store.activeURL }

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
