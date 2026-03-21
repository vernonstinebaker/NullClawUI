import Foundation

// MARK: - MCPServerParseError

enum MCPServerParseError: Error, LocalizedError, Sendable {
    case noConfigFound
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noConfigFound:
            return "No MCP server configuration found in the agent reply."
        case .decodingFailed(let detail):
            return "Failed to parse MCP server configuration: \(detail)"
        }
    }
}

// MARK: - ViewModel

/// Phase 18: MCP Server Management.
///
/// Communicates with the active gateway exclusively through A2A natural-language prompts.
/// There is no dedicated REST endpoint for MCP server management.
///
/// Lifecycle:
///   • Call load() to fetch the current MCP server list.
///   • Call addServer(_:) to register a new server (sends a creation prompt, then refreshes).
///   • Call remove(_:) to remove a server (sends a deletion prompt, then refreshes).
@Observable
@MainActor
final class MCPServerViewModel {

    // MARK: Published state

    /// Current list of MCP servers, ordered as returned by the agent.
    var servers: [MCPServer] = []
    /// True while a load or add round-trip is in flight.
    private(set) var isLoading: Bool = false
    /// Non-nil while a remove operation is executing. Contains the server name being removed.
    private(set) var removingName: String? = nil
    /// Non-nil when the last operation failed.
    var errorMessage: String? = nil
    /// Non-nil after a successful mutation.
    var confirmationMessage: String? = nil

    // MARK: Dependencies

    var client: GatewayClient

    // MARK: Init

    init(client: GatewayClient) {
        self.client = client
    }

    // MARK: - Load

    /// Fetches the MCP server list from the gateway config via the agent.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isLoading = false }

        await loadInternal(client: client)
    }

    // MARK: - Private load helper

    /// Performs the actual network fetch without touching `isLoading`.
    /// Called internally by mutating operations that already own `isLoading`.
    private func loadInternal(client: GatewayClient) async {
        do {
            let reply = try await client.sendOneShotNonStreaming(Self.loadPrompt)
            servers = try parseMCPServers(from: reply)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Remove

    /// Removes the named MCP server by instructing the agent to delete it from config.
    func remove(_ server: MCPServer) async {
        guard removingName == nil else { return }
        removingName = server.name
        errorMessage = nil
        confirmationMessage = nil
        defer { removingName = nil }

        let prompt = "Remove the MCP server named \"\(server.name)\" from ~/.nullclaw/config.json."
        do {
            _ = try await client.sendOneShot(prompt)
            confirmationMessage = "MCP server \"\(server.name)\" removed."
            await loadInternal(client: client)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Check Status

    /// Non-nil while a check-status operation is executing. Contains the server name being checked.
    private(set) var checkingStatusName: String? = nil

    /// Asks the gateway agent whether the named MCP server is currently reachable and updates
    /// `servers[i].connected` with the result.
    ///
    /// The agent is asked to attempt a connectivity probe (e.g. spawn the subprocess briefly or
    /// send an HTTP OPTIONS request) and reply with a JSON object: `{"connected": true|false}`.
    /// If the reply cannot be parsed, `connected` is set to `false` and an error is surfaced.
    func checkStatus(for serverName: String) async {
        guard checkingStatusName == nil else { return }
        checkingStatusName = serverName
        errorMessage = nil
        confirmationMessage = nil
        defer { checkingStatusName = nil }

        let prompt = Self.checkStatusPrompt(for: serverName)
        do {
            let reply = try await client.sendOneShotNonStreaming(prompt)
            let connected = parseCheckStatus(from: reply)
            // Update the matching server in-place.
            if let idx = servers.firstIndex(where: { $0.name == serverName }) {
                servers[idx].connected = connected
            }
            confirmationMessage = connected
                ? "\"\(serverName)\" is reachable."
                : "\"\(serverName)\" is not reachable."
        } catch {
            // On network/RPC error, mark the server as failed.
            if let idx = servers.firstIndex(where: { $0.name == serverName }) {
                servers[idx].connected = false
            }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Add

    /// Adds a new MCP server by instructing the agent to write the entry to config.
    func addServer(_ draft: MCPServerDraft) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isLoading = false }

        let prompt = draft.toPrompt()
        do {
            _ = try await client.sendOneShot(prompt)
            confirmationMessage = "MCP server \"\(draft.name)\" added."
            await loadInternal(client: client)
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
        if let arrayStart = text.firstIndex(of: "["),
           let arrayEnd   = text.lastIndex(of: "]") {
            let jsonString = String(text[arrayStart...arrayEnd])
            if let data = jsonString.data(using: .utf8),
               let servers = try? JSONDecoder().decode([MCPServerRaw].self, from: data) {
                return servers.map(\.toMCPServer)
            }
        }

        // Strategy 2: JSON object with mcp_servers key { ... }.
        guard let objStart = text.firstIndex(of: "{"),
              let objEnd   = text.lastIndex(of: "}") else {
            throw MCPServerParseError.noConfigFound
        }

        let jsonString = String(text[objStart...objEnd])
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

    /// Returns the prompt used to check reachability of a specific MCP server.
    ///
    /// The agent is asked to probe connectivity and reply with ONLY a JSON object
    /// `{"connected": true}` or `{"connected": false}`. No prose.
    static func checkStatusPrompt(for name: String) -> String {
        """
        Check whether the MCP server named "\(name)" is currently reachable. \
        For stdio transport, attempt to spawn the subprocess briefly (pass --version or --help). \
        For HTTP transport, send an HTTP GET or OPTIONS request to the server URL. \
        Reply with ONLY a JSON object, no extra text: {"connected": true} or {"connected": false}.
        """
    }

    // MARK: - Parse helpers (internal — visible for tests)

    /// Parses the `connected` boolean from a `{"connected": true|false}` reply.
    /// Returns `false` if the reply cannot be parsed.
    func parseCheckStatus(from text: String) -> Bool {
        guard let start = text.firstIndex(of: "{"),
              let end   = text.lastIndex(of: "}"),
              let data  = String(text[start...end]).data(using: .utf8) else {
            return false
        }
        struct ConnectedWrapper: Decodable { let connected: Bool }
        return (try? JSONDecoder().decode(ConnectedWrapper.self, from: data))?.connected ?? false
    }
}

// MARK: - MCPServerDraft

/// Value type used by AddMCPServerSheet to collect user input before submission.
struct MCPServerDraft: Sendable {
    var name: String = ""
    var transport: String = "stdio"   // "stdio" | "http"
    var command: String = ""          // stdio only
    var args: String = ""             // stdio only — space-separated
    var url: String = ""              // http only
    var timeoutMs: String = ""        // optional, parsed as Int

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
