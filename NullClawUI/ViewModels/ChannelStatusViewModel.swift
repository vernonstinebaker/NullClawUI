import Foundation

// MARK: - Parse error

enum ChannelStatusParseError: Error, LocalizedError, Sendable {
    case noDataFound
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDataFound:
            return "No channel data found in the agent reply."
        case .decodingFailed(let detail):
            return "Failed to parse channel data: \(detail)"
        }
    }
}

// MARK: - ViewModel

@Observable @MainActor
final class ChannelStatusViewModel {

    // MARK: Published state

    private(set) var channels: [ChannelInfo] = []
    private(set) var isLoading: Bool = false
    var errorMessage: String? = nil

    // MARK: Dependencies

    var client: GatewayClient?

    // MARK: Init

    init(client: GatewayClient? = nil) {
        self.client = client
    }

    /// Invalidates the underlying URLSession. Call from the view's `.onDisappear` to
    /// release the session and avoid orphaned network connections.
    func invalidate() {
        let c = client
        Task { await c?.invalidate() }
    }

    // MARK: - Load

    /// Asks the agent for the current channel configuration and parses the reply.
    func load() async {
        guard !isLoading else { return }
        guard let c = client else {
            errorMessage = "No gateway client available."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let reply = try await c.sendOneShot(Self.loadPrompt)
            channels = try parseChannels(from: reply)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Parse (internal — visible for tests)

    /// Parses a `[ChannelInfo]` from an agent reply that contains a JSON object.
    /// The parser is lenient: it extracts the first `{…}` block found in `text`.
    func parseChannels(from text: String) throws -> [ChannelInfo] {
        guard
            let start = text.firstIndex(of: "{"),
            let end = text.lastIndex(of: "}")
        else {
            throw ChannelStatusParseError.noDataFound
        }

        let jsonString = String(text[start...end])
        guard let data = jsonString.data(using: .utf8) else {
            throw ChannelStatusParseError.decodingFailed("UTF-8 encoding failed")
        }

        do {
            let raw = try JSONDecoder().decode(ChannelStatusRaw.self, from: data)
            return (raw.channels ?? []).map { entry in
                ChannelInfo(
                    name: entry.name,
                    connected: entry.connected,
                    serverURL: entry.server_url,
                    botName: entry.bot_name
                )
            }
        } catch {
            throw ChannelStatusParseError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Prompt constant (visible for tests)

    static let loadPrompt = """
        Read ~/.nullclaw/config.json and respond with ONLY a valid JSON object, no extra text. \
        The JSON must have exactly one key: \
        "channels" (array of objects). Each object must have: \
        "name" (string — the channel key, e.g. "mattermost", "discord", "telegram"), \
        "connected" (bool — true for any channel present in the config, false only if known to be disabled), \
        "server_url" (string or null — the server/host URL if present, e.g. mattermost.server or discord gateway URL), \
        "bot_name" (string or null — the bot username or display name if present). \
        Include every key present under the top-level "channels" object in the config.
        """
}

// MARK: - Private decoding shim

/// Intermediate Decodable used only by `parseChannels(from:)`.
private struct ChannelStatusRaw: Decodable {
    struct ChannelEntry: Decodable {
        var name: String
        var connected: Bool?
        var server_url: String?
        var bot_name: String?
    }
    var channels: [ChannelEntry]?
}
