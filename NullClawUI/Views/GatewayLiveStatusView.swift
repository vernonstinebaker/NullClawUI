import SwiftUI

// MARK: - GatewayLiveStatusView

/// Sub-screen showing live MCP server and channel status fetched via A2A.
/// Builds a dedicated GatewayClient for the given profile, loading the stored
/// Keychain token so authenticated gateways work correctly.
struct GatewayLiveStatusView: View {
    let profile: GatewayProfile

    @State private var liveStatus: GatewayLiveStatus? = nil
    @State private var isLoadingLiveStatus: Bool = false
    @State private var liveStatusError: String? = nil
    @State private var client: GatewayClient? = nil

    var body: some View {
        List {
            if isLoadingLiveStatus {
                Section {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Asking gateway agent…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Loading live status")
                }
            } else if let status = liveStatus {
                Section("MCP Servers") {
                    if status.mcpServers.isEmpty {
                        Text("No MCP servers reported")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(status.mcpServers) { server in
                            liveStatusRow(name: server.name, connected: server.connected,
                                          icon: "externaldrive.connected.to.line.below")
                        }
                    }
                }
                Section("Channels") {
                    if status.channels.isEmpty {
                        Text("No channels reported")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(status.channels) { channel in
                            liveStatusRow(name: channel.name, connected: channel.connected,
                                          icon: "antenna.radiowaves.left.and.right")
                        }
                    }
                }
                if let err = liveStatusError {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } else if let err = liveStatusError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            } else {
                Section {
                    Text("Pull down to load status")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Live Status")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Build a properly-tokened client for this profile, then load.
            // Open gateways (requiresPairing == false) have no Keychain token — that is fine.
            guard let url = URL(string: profile.url) else { return }
            let tok = try? KeychainService.retrieveToken(for: profile.url)
            let c = GatewayClient(baseURL: url, token: tok ?? "", requiresPairing: profile.requiresPairing)
            client = c
            await load(using: c)
        }
        .refreshable {
            // Rebuild client if nil (e.g. first .task was skipped on a prior code path).
            if client == nil, let url = URL(string: profile.url) {
                let tok = try? KeychainService.retrieveToken(for: profile.url)
                client = GatewayClient(baseURL: url, token: tok ?? "", requiresPairing: profile.requiresPairing)
            }
            if let c = client { await load(using: c) }
        }
        .onDisappear {
            client?.invalidate()
            client = nil
        }
    }

    // MARK: - Row helper

    private func liveStatusRow(name: String, connected: Bool, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(name)
                .font(.subheadline)
            Spacer()
            Circle()
                .fill(connected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(connected ? "Connected" : "Failed")
                .font(.caption)
                .foregroundStyle(connected ? .green : .red)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(connected ? "connected" : "failed")")
    }

    // MARK: - Load

    @MainActor
    private func load(using c: GatewayClient) async {
        guard !isLoadingLiveStatus else { return }
        isLoadingLiveStatus = true
        liveStatusError = nil
        defer { isLoadingLiveStatus = false }

        var result = GatewayLiveStatus()
        do {
            let reply = try await c.sendOneShot(Self.loadPrompt)
            // Parse the reply once and branch — avoids calling parseJSONStatus twice.
            if let parsed = Self.parseJSONStatus(from: reply) {
                result.mcpServers = parsed.mcpServers
                result.channels   = parsed.channels
            } else {
                parseMCPLegacy(from: reply, into: &result)
                parseChannelsLegacy(from: reply, into: &result)
            }
        } catch {
            liveStatusError = "Failed to fetch live status: \(error.localizedDescription)"
        }

        liveStatus = result
    }

    // MARK: - Prompt constant (visible for tests)

    /// Instructs the agent to read the config file and emit a JSON object with
    /// "mcp_servers" and "channels" arrays derived directly from the config structure.
    /// This avoids the slow/unreliable NL introspection round-trip.
    static let loadPrompt = """
        Read ~/.nullclaw/config.json and respond with ONLY a valid JSON object, no extra text. \
        The JSON must have exactly these keys: \
        "mcp_servers" (array of objects with "name" (string) and "connected" (bool, true unless the server has a known startup error)), \
        "channels" (array of objects with "name" (string) and "connected" (bool, always true for configured channels)). \
        Include only subprocess-type MCP servers (those with a "command" field). \
        Include every channel key under the top-level "channels" object.
        """

    // MARK: - Parsers

    /// Legacy line-format fallback for MCP server parsing.
    /// Called only when `parseJSONStatus` returns nil.
    private func parseMCPLegacy(from text: String, into status: inout GatewayLiveStatus) {
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = extractValue(prefix: "MCP:", from: line), !value.isEmpty else { continue }
            let parts = value.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 2 {
                let statusToken = parts.last!.lowercased()
                let name = parts.dropLast().joined(separator: " ")
                status.mcpServers.append(MCPServerStatus(name: name, connected: statusToken == "connected"))
            } else if parts.count == 1 {
                status.mcpServers.append(MCPServerStatus(name: parts[0], connected: false))
            }
        }
    }

    /// Legacy line-format fallback for channel parsing.
    /// Called only when `parseJSONStatus` returns nil.
    private func parseChannelsLegacy(from text: String, into status: inout GatewayLiveStatus) {
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = extractValue(prefix: "Channel:", from: line), !value.isEmpty else { continue }
            let parts = value.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 2 {
                let statusToken = parts.last!.lowercased()
                let name = parts.dropLast().joined(separator: " ")
                status.channels.append(ChannelStatus(name: name, connected: statusToken == "connected"))
            } else if parts.count == 1 {
                status.channels.append(ChannelStatus(name: parts[0], connected: false))
            }
        }
    }

    /// Attempts to decode a `GatewayLiveStatus` from a JSON block in `text`.
    /// Returns nil if no valid JSON block is found or decoding fails.
    /// Internal for unit testing via GatewayLiveStatusView.parseJSONStatus(from:).
    static func parseJSONStatus(from text: String) -> GatewayLiveStatus? {
        guard
            let start = text.firstIndex(of: "{"),
            let end = text.lastIndex(of: "}")
        else { return nil }
        let jsonString = String(text[start...end])
        guard let data = jsonString.data(using: .utf8) else { return nil }
        guard let raw = try? JSONDecoder().decode(LiveStatusRaw.self, from: data) else { return nil }
        var s = GatewayLiveStatus()
        s.mcpServers = (raw.mcp_servers ?? []).map {
            MCPServerStatus(name: $0.name, connected: $0.connected ?? true)
        }
        s.channels = (raw.channels ?? []).map {
            ChannelStatus(name: $0.name, connected: $0.connected ?? true)
        }
        return s
    }

    private func extractValue(prefix: String, from line: String) -> String? {
        guard line.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Live Status Models (used by GatewayLiveStatusView)

struct GatewayLiveStatus: Sendable {
    var mcpServers: [MCPServerStatus] = []
    var channels: [ChannelStatus] = []
}

struct MCPServerStatus: Identifiable, Sendable {
    let id: UUID = UUID()
    var name: String
    var connected: Bool
}

struct ChannelStatus: Identifiable, Sendable {
    let id: UUID = UUID()
    var name: String
    var connected: Bool
}

// MARK: - Live Status JSON decoding shim (used by GatewayLiveStatusView.parseJSONStatus)

/// Intermediate Decodable for the JSON produced by `GatewayLiveStatusView.loadPrompt`.
struct LiveStatusRaw: Decodable {
    struct MCPEntry: Decodable {
        var name: String
        var connected: Bool?
    }
    struct ChannelEntry: Decodable {
        var name: String
        var connected: Bool?
    }
    var mcp_servers: [MCPEntry]?
    var channels: [ChannelEntry]?
}
