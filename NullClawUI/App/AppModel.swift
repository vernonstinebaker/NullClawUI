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

    /// The parsed agent card retrieved from /.well-known/agent-card.json
    var agentCard: AgentCard? = nil

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
