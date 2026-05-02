import Foundation

// MARK: - MCPServerParseError

enum MCPServerParseError: Error, LocalizedError {
    case noConfigFound
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noConfigFound:
            "No MCP server configuration found in the agent reply."
        case let .decodingFailed(detail):
            "Failed to parse MCP server configuration: \(detail)"
        }
    }
}

// MARK: - ViewModel

/// Phase 18: MCP Server Management.
///
/// Uses REST Admin API endpoints (GET /api/mcp, GET /api/mcp/:name) for listing
/// and checking server status. Add/remove still use A2A prompts since the gateway
/// doesn't expose mutation endpoints for MCP servers yet.
///
/// Lifecycle:
///   • Call load() to fetch the current MCP server list.
///   • Call addServer(_:) to register a new server (sends a creation prompt, then refreshes).
///   • Call remove(_:) to remove a server (sends a deletion prompt, then refreshes).
@Observable
@MainActor
final class MCPServerViewModel {
    // MARK: Published state

    var servers: [MCPServer] = []
    private(set) var isLoading: Bool = false
    private(set) var removingName: String?
    var errorMessage: String?
    var confirmationMessage: String?

    // MARK: Dependencies

    let client: HubGatewayClient
    let instance: String
    let component: String

    // MARK: Init

    init(client: HubGatewayClient, instance: String = "default", component: String = "nullclaw") {
        self.client = client
        self.instance = instance
        self.component = component
    }

    // MARK: - Load

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isLoading = false }

        await loadInternal()
    }

    private func loadInternal() async {
        do {
            servers = try await client.listMCPServers(instance: instance, component: component)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Remove

    func remove(_ server: MCPServer) async {
        guard removingName == nil else { return }
        removingName = server.name
        errorMessage = nil
        confirmationMessage = nil
        defer { removingName = nil }

        let prompt = "Remove the MCP server named \"\(server.name)\" from ~/.nullclaw/config.json."
        do {
            _ = try await invokeAgent(prompt: prompt)
            confirmationMessage = "MCP server \"\(server.name)\" removed."
            await loadInternal()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Check Status

    private(set) var checkingStatusName: String?

    func checkStatus(for serverName: String) async {
        guard checkingStatusName == nil else { return }
        checkingStatusName = serverName
        errorMessage = nil
        confirmationMessage = nil
        defer { checkingStatusName = nil }

        do {
            let all = try await client.listMCPServers(instance: instance, component: component)
            let found = all.contains { $0.name == serverName }
            if let idx = servers.firstIndex(where: { $0.name == serverName }) {
                servers[idx].connected = found
            }
            confirmationMessage = found
                ? "\"\(serverName)\" is configured."
                : "\"\(serverName)\" is not configured."
        } catch {
            if let idx = servers.firstIndex(where: { $0.name == serverName }) {
                servers[idx].connected = false
            }
            errorMessage = error.localizedDescription
        }
    }

    /// Checks status of all servers by fetching the full list once.
    func checkAllStatuses() async {
        let names = servers.map(\.name)
        do {
            let all = try await client.listMCPServers(instance: instance, component: component)
            let configuredNames = Set(all.map(\.name))
            for name in names {
                if let idx = servers.firstIndex(where: { $0.name == name }) {
                    servers[idx].connected = configuredNames.contains(name)
                }
            }
        } catch {
            for name in names {
                if let idx = servers.firstIndex(where: { $0.name == name }) {
                    servers[idx].connected = false
                }
            }
        }
    }

    // MARK: - Add

    func addServer(_ draft: MCPServerDraft) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isLoading = false }

        let prompt = draft.toPrompt()
        do {
            _ = try await invokeAgent(prompt: prompt)
            confirmationMessage = "MCP server \"\(draft.name)\" added."
            await loadInternal()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Parse (internal — visible for tests)

    /// Parses a `[MCPServer]` from an agent reply containing a JSON array or object.
    ///
    /// The agent is instructed to return a JSON array of server objects under a top-level
    /// `"mcp_servers"` key. The parser first tries to extract a `[…]` block directly,
    /// then tries to unwrap `{ "mcp_servers": […] }`.
    func parseMCPServers(from text: String) throws -> [MCPServer] {
        // Strategy 1: bare JSON array [...].
        if
            let arrayStart = text.firstIndex(of: "["),
            let arrayEnd = text.lastIndex(of: "]")
        {
            let jsonString = String(text[arrayStart ... arrayEnd])
            if
                let data = jsonString.data(using: .utf8),
                let servers = try? JSONDecoder().decode([MCPServerRaw].self, from: data)
            {
                return servers.map(\.toMCPServer)
            }
        }

        // Strategy 2: JSON object with mcp_servers key { ... }.
        guard
            let objStart = text.firstIndex(of: "{"),
            let objEnd = text.lastIndex(of: "}") else
        {
            throw MCPServerParseError.noConfigFound
        }

        let jsonString = String(text[objStart ... objEnd])
        guard let data = jsonString.data(using: .utf8) else {
            throw MCPServerParseError.decodingFailed("UTF-8 encoding failed")
        }

        do {
            let wrapper = try JSONDecoder().decode(MCPServerListWrapper.self, from: data)
            if let list = wrapper.mcp_servers {
                return list.map(\.toMCPServer)
            }
            // Object found but no mcp_servers key — the agent returned an unexpected shape.
            throw MCPServerParseError.noConfigFound
        } catch let e as MCPServerParseError {
            throw e
        } catch {
            throw MCPServerParseError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Prompt constants (visible for tests)

    /// Instructs the agent to read config.json directly and return the mcp_servers array.
    ///
    /// Note: `connected` is intentionally omitted — the LLM cannot reliably determine
    /// runtime connectivity and asking it to do so is slow and inaccurate. Connection status
    /// is surfaced via an on-demand "Check Status" action in the detail view instead.
    static let loadPrompt = """
    Read ~/.nullclaw/config.json and respond with ONLY a valid JSON object, no extra text. \
    The JSON must have exactly one key: \
    "mcp_servers" (array of objects). Each object in the array must have these keys: \
    "name" (string), "transport" (string, either "stdio" or "http"), \
    "command" (string or null), "args" (array of strings or null), \
    "url" (string or null), "timeout_ms" (integer or null).
    """

    /// Returns the prompt used to verify that a specific MCP server is configured.
    ///
    /// Rather than attempting an unreliable (and slow) subprocess spawn or HTTP probe,
    /// the agent is asked to read config.json and confirm the named entry exists and
    /// has a non-empty command or URL — a fast file-read identical in cost to loadPrompt.
    /// The reply shape is the same `{"connected": true|false}` so the rest of the
    /// call-site and parse logic are unchanged.
    static func checkStatusPrompt(for name: String) -> String {
        """
        Read ~/.nullclaw/config.json and check whether an MCP server entry named "\(name)" exists \
        and is validly configured (has a non-empty "command" for stdio transport, or a non-empty "url" \
        for http transport). Reply with ONLY a JSON object, no extra text: \
        {"connected": true} if the entry is present and valid, {"connected": false} otherwise.
        """
    }

    // MARK: - Parse helpers (internal — visible for tests)

    /// Parses the `connected` boolean from a `{"connected": true|false}` reply.
    /// Returns `false` if the reply cannot be parsed.
    func parseCheckStatus(from text: String) -> Bool {
        guard
            let start = text.firstIndex(of: "{"),
            let end = text.lastIndex(of: "}"),
            let data = String(text[start ... end]).data(using: .utf8) else
        {
            return false
        }
        struct ConnectedWrapper: Decodable { let connected: Bool }
        return (try? JSONDecoder().decode(ConnectedWrapper.self, from: data))?.connected ?? false
    }

    // MARK: - Hub helpers (internal — visible for tests)

    /// Sends a prompt via Hub's invokeAgent and returns the raw response dict.
    private func invokeAgent(prompt: String) async throws -> Data {
        let body: [String: String] = ["message": prompt]
        let data = try JSONEncoder().encode(body)
        return try await client.invokeAgent(instance: instance, component: component, body: data)
    }
}

// MARK: - MCPServerDraft

/// Value type used by AddMCPServerSheet to collect user input before submission.
struct MCPServerDraft {
    var name: String = ""
    var transport: String = "stdio" // "stdio" | "http"
    var command: String = "" // stdio only
    var args: String = "" // stdio only — space-separated
    var url: String = "" // http only
    var timeoutMs: String = "" // optional, parsed as Int

    /// Composes the natural-language prompt sent to the agent to add this server.
    func toPrompt() -> String {
        var lines: [String] = [
            "Add a new MCP server to ~/.nullclaw/config.json with the following settings:",
            "name: \(name.trimmingCharacters(in: .whitespacesAndNewlines))",
            "transport: \(transport)"
        ]
        if transport == "http" {
            let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
            if !u.isEmpty { lines.append("url: \(u)") }
        } else {
            let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cmd.isEmpty { lines.append("command: \(cmd)") }
            let a = args.trimmingCharacters(in: .whitespacesAndNewlines)
            if !a.isEmpty { lines.append("args: \(a)") }
        }
        let t = timeoutMs.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { lines.append("timeout_ms: \(t)") }
        lines.append("Confirm by replying with: \"MCP server added.\"")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Private decoding shims

/// Intermediate Decodable for the mcp_servers wrapper object.
private struct MCPServerListWrapper: Decodable {
    var mcp_servers: [MCPServerRaw]?
}

/// Intermediate Decodable for a single MCP server entry.
/// Uses snake_case keys matching the gateway config schema.
private struct MCPServerRaw: Decodable {
    var name: String?
    var transport: String?
    var command: String?
    var args: [String]?
    var env: [String: String]?
    var url: String?
    var headers: [String: String]?
    var timeout_ms: Int?
    var connected: Bool?

    var toMCPServer: MCPServer {
        MCPServer(
            name: name ?? "(unnamed)",
            transport: transport ?? "stdio",
            command: command,
            args: args,
            env: env,
            url: url,
            headers: headers,
            timeoutMs: timeout_ms,
            connected: connected
        )
    }
}
