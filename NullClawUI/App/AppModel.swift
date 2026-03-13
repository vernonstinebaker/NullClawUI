import SwiftUI
import Observation

/// Top-level application state shared across the entire view hierarchy.
@Observable
@MainActor
final class AppModel {
    // MARK: - Gateway
    var gatewayURL: String = "http://localhost:5111" {
        didSet { UserDefaults.standard.set(gatewayURL, forKey: "gatewayURL") }
    }

    /// The parsed agent card retrieved from /.well-known/agent-card.json
    var agentCard: AgentCard? = nil

    /// Current gateway reachability state.
    var connectionStatus: ConnectionStatus = .unknown

    // MARK: - Auth
    /// Whether the app currently holds a valid Bearer token for the active gateway.
    var isPaired: Bool = false

    // MARK: - Lifecycle
    init() {
        if let saved = UserDefaults.standard.string(forKey: "gatewayURL") {
            gatewayURL = saved
        }
    }
}

enum ConnectionStatus {
    case unknown
    case online
    case offline
}
