import Foundation

/// Decoded from GET /.well-known/agent-card.json
struct AgentCard: Codable, Sendable {
    let name: String
    let version: String
    let description: String?
    let capabilities: AgentCapabilities?
    let accentColor: String?

    struct AgentCapabilities: Codable, Sendable {
        let streaming: Bool?
        let multiModal: Bool?
        let history: Bool?
    }
}
