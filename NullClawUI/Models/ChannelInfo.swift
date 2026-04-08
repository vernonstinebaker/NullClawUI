import Foundation

// MARK: - ChannelInfo Model

/// Represents a single communication channel configured in the NullClaw gateway.
/// Fields are populated from the gateway `channels` config block via agent query.
/// Includes read-only config detail fields for the channel detail view.
struct ChannelInfo: Identifiable, Equatable {
    // MARK: Identity

    /// Short key used to identify the channel type (e.g. "mattermost", "discord", "telegram").
    var name: String

    // MARK: Runtime status

    /// True if the channel is currently connected, false if disconnected, nil if unknown.
    var connected: Bool?

    // MARK: Config detail (read-only, no secrets)

    /// Server or host URL for the channel, if applicable (e.g. Mattermost server URL).
    var serverURL: String?

    /// Bot name or username used by this channel integration.
    var botName: String?

    // MARK: Identifiable

    var id: String {
        name
    }

    // MARK: - Computed helpers

    /// Returns a human-readable display name by capitalizing the first letter.
    var displayName: String {
        guard !name.isEmpty else { return name }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Returns the SF Symbol name appropriate for this channel type.
    var iconName: String {
        switch name.lowercased() {
        case "mattermost": "bubble.left.and.bubble.right.fill"
        case "discord": "gamecontroller.fill"
        case "telegram": "paperplane.fill"
        case "slack": "number.square.fill"
        case "whatsapp": "phone.bubble.left.fill"
        case "irc": "terminal.fill"
        case "matrix": "grid.circle.fill"
        case "email": "envelope.fill"
        case "sms": "message.fill"
        case "pushover": "bell.fill"
        default: "antenna.radiowaves.left.and.right"
        }
    }

    /// Returns a color-coding hint for the channel type icon.
    /// (Used as a tint, not a status indicator.)
    var accentColorName: String {
        switch name.lowercased() {
        case "discord": "purple"
        case "telegram": "blue"
        case "slack": "orange"
        case "whatsapp": "green"
        default: "secondary"
        }
    }
}
