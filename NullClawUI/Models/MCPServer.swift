import Foundation

// MARK: - MCPServer Model

/// Represents a single MCP server entry from the NullClaw gateway's config.
/// Fields mirror the gateway `mcp_servers` config block schema.
struct MCPServer: Codable, Identifiable, Equatable {
    // MARK: Identity

    /// Human-readable name used to identify this server.
    var name: String

    // MARK: Transport

    /// Transport type: "stdio" for subprocess servers, "http" for remote HTTP servers.
    var transport: String

    // MARK: stdio fields

    /// Executable path (stdio transport only).
    var command: String?
    /// Command-line arguments (stdio transport only).
    var args: [String]?
    /// Environment variable overrides (stdio transport only).
    var env: [String: String]?

    // MARK: HTTP fields

    /// Base URL (http transport only).
    var url: String?
    /// Custom HTTP headers (http transport only).
    var headers: [String: String]?

    // MARK: Common

    /// Connection timeout in milliseconds. Nil means gateway default.
    var timeoutMs: Int?

    // MARK: Runtime status (not stored in config — added by parse layer)

    /// True if the server is currently connected, false if failed, nil if unknown.
    var connected: Bool?

    // MARK: Identifiable

    var id: String {
        name
    }

    // MARK: - Computed helpers

    /// Human-readable transport label shown in the UI.
    var transportLabel: String {
        transport.lowercased() == "http" ? "HTTP" : "stdio"
    }

    /// Primary endpoint description: command+args for stdio, URL for http.
    var endpointDescription: String {
        if transport.lowercased() == "http" {
            return url ?? "(no URL)"
        } else {
            guard let cmd = command else { return "(no command)" }
            let argStr = args?.joined(separator: " ") ?? ""
            return argStr.isEmpty ? cmd : "\(cmd) \(argStr)"
        }
    }
}
