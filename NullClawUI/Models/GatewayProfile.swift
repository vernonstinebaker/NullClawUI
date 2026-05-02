import Foundation
import SwiftData

// MARK: - GatewayProfile

/// Represents a saved gateway connection — either a NullHub (management plane)
/// or a direct NullClaw instance (data plane). Migrating toward dual-URL model:
/// `hubURL` for hub APIs, `instanceURL` for direct instance APIs.
/// Persisted via SwiftData.
@Model
final class GatewayProfile {
    // MARK: - Stored properties

    @Attribute(.unique) var id: UUID
    var name: String
    /// Primary URL (instance URL for backward compatibility).
    var url: String
    /// NullHub management URL (e.g. http://host:19800). Nil for direct instance connections.
    var hubURL: String?
    /// Direct NullClaw instance URL for A2A, agent card, pairing. Defaults to `url`.
    var instanceURL: String?
    var isPaired: Bool
    /// False when the gateway responded 403 to /pair (require_pairing: false).
    /// Persisted so that updateProfile does not clobber isPaired by re-checking the Keychain.
    var requiresPairing: Bool
    var sortOrder: Int
    /// Instance name on the hub (default "default").
    var instanceName: String
    /// Component name on the hub (default "nullclaw").
    var component: String

    /// One-to-many: all conversation records for this gateway.
    @Relationship(deleteRule: .cascade, inverse: \ConversationRecord.gateway)
    var conversationRecords: [ConversationRecord]

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        url: String,
        hubURL: String? = nil,
        instanceURL: String? = nil,
        isPaired: Bool = false,
        requiresPairing: Bool = true,
        sortOrder: Int = 0,
        instanceName: String = "default",
        component: String = "nullclaw"
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.hubURL = hubURL
        self.isPaired = isPaired
        self.requiresPairing = requiresPairing
        self.sortOrder = sortOrder
        self.instanceURL = instanceURL ?? url
        self.instanceName = instanceName
        self.component = component
        conversationRecords = []
    }

    // MARK: - Derived

    /// Normalized URL used as the Keychain key (no trailing slash, lowercased).
    /// Delegates to KeychainService to ensure both use identical normalization logic.
    var normalizedURL: String {
        KeychainService.normalizedGatewayURL(url)
    }

    /// Hub admin token, stored in Keychain keyed by `hubURL`.
    var hubToken: String? {
        get {
            guard let hub = hubURL else { return nil }
            return KeychainService.retrieveTokenIfAvailable(for: hub)
        }
        set {
            guard let hub = hubURL else { return }
            if let token = newValue {
                try? KeychainService.storeToken(token, for: hub)
            } else {
                KeychainService.deleteToken(for: hub)
            }
        }
    }

    /// Human-readable host:port extracted from the URL.
    var displayHost: String {
        URL(string: url)
            .flatMap { u -> String? in
                guard let host = u.host else { return nil }
                if let port = u.port { return "\(host):\(port)" }
                return host
            } ?? url
    }
}
