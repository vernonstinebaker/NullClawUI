import Foundation
import SwiftData

// MARK: - GatewayProfile

/// Represents a single saved NullClaw gateway connection.
/// Persisted via SwiftData (Phase 11+). Previously a UserDefaults JSON struct.
@Model
final class GatewayProfile {
    // MARK: - Stored properties
    @Attribute(.unique) var id: UUID
    var name: String
    var url: String
    var isPaired: Bool
    var sortOrder: Int

    /// One-to-many: all conversation records for this gateway.
    @Relationship(deleteRule: .cascade, inverse: \ConversationRecord.gateway)
    var conversationRecords: [ConversationRecord]

    // MARK: - Init

    init(id: UUID = UUID(), name: String, url: String, isPaired: Bool = false, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.url = url
        self.isPaired = isPaired
        self.sortOrder = sortOrder
        self.conversationRecords = []
    }

    // MARK: - Derived

    /// Normalized URL used as the Keychain key (no trailing slash, lowercased).
    var normalizedURL: String {
        url.trimmingCharacters(in: .init(charactersIn: "/")).lowercased()
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
