import Foundation

// MARK: - ChannelInfo Model

/// Represents a single communication channel configured in the NullClaw gateway.
/// Fields are populated from the gateway `channels` config block via agent query.
/// This is a richer version of the lightweight `ChannelStatus` used in Live Status;
/// it adds read-only config detail fields for Phase 20's detail view.
struct ChannelInfo: Identifiable, Sendable, Equatable {

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

    var id: String { name }

    // MARK: - Computed helpers

    /// Returns a human-readable display name by capitalizing the first letter.
    var displayName: String {
        guard !name.isEmpty else { return name }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Returns the SF Symbol name appropriate for this channel type.
    var iconName: String {
        switch name.lowercased() {
        case "mattermost":  return "bubble.left.and.bubble.right.fill"
        case "discord":     return "gamecontroller.fill"
        case "telegram":    return "paperplane.fill"
        case "slack":       return "number.square.fill"
        case "whatsapp":    return "phone.bubble.left.fill"
        case "irc":         return "terminal.fill"
        case "matrix":      return "grid.circle.fill"
        case "email":       return "envelope.fill"
        case "sms":         return "message.fill"
        case "pushover":    return "bell.fill"
        default:            return "antenna.radiowaves.left.and.right"
        }
    }

    /// Returns a color-coding hint for the channel type icon.
    /// (Used as a tint, not a status indicator.)
    var accentColorName: String {
        switch name.lowercased() {
        case "discord":   return "purple"
        case "telegram":  return "blue"
        case "slack":     return "orange"
        case "whatsapp":  return "green"
        default:          return "secondary"
        }
    }
}
