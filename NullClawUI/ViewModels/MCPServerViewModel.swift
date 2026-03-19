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
    private(set) var servers: [MCPServer] = []
    /// True while a load or add round-trip is in flight.
    private(set) var isLoading: Bool = false
    /// Non-nil while a remove operation is executing. Contains the server name being removed.
    private(set) var removingName: String? = nil
    /// Non-nil when the last operation failed.
    var errorMessage: String? = nil
    /// Non-nil after a successful mutation.
    var confirmationMessage: String? = nil

    // MARK: Dependencies

    var client: GatewayClient?

    // MARK: Init

    init(client: GatewayClient? = nil) {
        self.client = client
    }

    // MARK: - Load

    /// Fetches the MCP server list from the gateway config via the agent.
    func load() async {
        guard !isLoading else { return }
        guard let c = client else {
            errorMessage = "No gateway client available."
            return
        }
        isLoading = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isLoading = false }

        do {
            let reply = try await c.sendOneShot(Self.loadPrompt)
            servers = try parseMCPServers(from: reply)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Remove

    /// Removes the named MCP server by instructing the agent to delete it from config.
    func remove(_ server: MCPServer) async {
        guard let c = client else {
            errorMessage = "No gateway client available."
            return
        }
        guard removingName == nil else { return }
        removingName = server.name
        errorMessage = nil
        confirmationMessage = nil
        defer { removingName = nil }

        let prompt = "Remove the MCP server named \"\(server.name)\" from ~/.nullclaw/config.json."
        do {
            _ = try await c.sendOneShot(prompt)
            confirmationMessage = "MCP server \"\(server.name)\" removed."
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Add

    /// Adds a new MCP server by instructing the agent to write the entry to config.
    func addServer(_ draft: MCPServerDraft) async {
        guard let c = client else {
            errorMessage = "No gateway client available."
            return
        }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isLoading = false }

        let prompt = draft.toPrompt()
        do {
            _ = try await c.sendOneShot(prompt)
            confirmationMessage = "MCP server \"\(draft.name)\" added."
            await load()
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
            // Object found but no mcp_servers key — treat as empty list.
            return []
        } catch {
            throw MCPServerParseError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Prompt constants (visible for tests)

    /// Instructs the agent to read config.json directly and return the mcp_servers array.
    static let loadPrompt = """
        Read ~/.nullclaw/config.json and respond with ONLY a valid JSON object, no extra text. \
        The JSON must have exactly one key: \
        "mcp_servers" (array of objects). Each object in the array must have these keys: \
        "name" (string), "transport" (string, either "stdio" or "http"), \
        "command" (string or null), "args" (array of strings or null), \
        "url" (string or null), "timeout_ms" (integer or null), \
        "connected" (boolean — true if the server is currently reachable/running, false if not, \
        null if unknown).
        """
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
