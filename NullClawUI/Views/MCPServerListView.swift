import SwiftUI

// NOTE: No unit test — pure layout change; covered by visual inspection in Simulator.

// MARK: - MCPServerListView

/// MCP Server Management with inline status display.
/// On load, fetches the server list and checks each server's status concurrently.
/// Status is shown inline with green/red dots — no sub-navigation required.
struct MCPServerListView: View {
    let profile: GatewayProfile

    @State private var viewModel: MCPServerViewModel
    @State private var showingAddSheet: Bool = false

    init(profile: GatewayProfile) {
        self.profile = profile
        let url = URL(string: profile.url) ?? URL(string: "http://localhost:5111")!
        let token = (try? KeychainService.retrieveToken(for: profile.url)) ?? ""
        _viewModel = State(wrappedValue: MCPServerViewModel(
            client: GatewayClient(baseURL: url, token: token, requiresPairing: profile.requiresPairing)
        ))
    }

    private var sortedServers: [MCPServer] {
        viewModel.servers.sorted { a, b in
            let typeA = a.transport.lowercased() == "http" ? 1 : 0
            let typeB = b.transport.lowercased() == "http" ? 1 : 0
            if typeA != typeB { return typeA < typeB }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        List {
            if !profile.isPaired {
                Section {
                    Label(
                        "Pair this gateway to manage MCP servers.",
                        systemImage: "lock.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            } else if viewModel.isLoading, viewModel.servers.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Loading MCP servers…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Loading MCP servers")
                }
            } else if viewModel.servers.isEmpty, !viewModel.isLoading {
                Section {
                    ContentUnavailableView(
                        "No MCP Servers",
                        systemImage: "network.slash",
                        description: Text("Tap + to register a new MCP server.")
                    )
                }
            } else {
                Section {
                    ForEach(sortedServers) { server in
                        serverRow(server)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { await viewModel.remove(server) }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                .tint(.red)
                                .accessibilityLabel("Remove MCP server \(server.name)")
                            }
                    }
                }
            }

            // Error banner
            if let err = viewModel.errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Error: \(err)")
                }
            }
        }
        .navigationTitle("MCP Servers")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await fullRefresh() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add MCP Server", systemImage: "plus")
                }
                .disabled(!profile.isPaired)
                .accessibilityLabel("Add a new MCP server")
                .accessibilityHint("Opens a form to register a new MCP server with this gateway")
            }
            if viewModel.isLoading, !viewModel.servers.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .task {
            if viewModel.servers.isEmpty, profile.isPaired {
                await fullRefresh()
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddMCPServerSheet { draft in
                Task { await viewModel.addServer(draft) }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func serverRow(_ server: MCPServer) -> some View {
        let isRemoving = viewModel.removingName == server.name
        let isChecking = viewModel.checkingStatusName == server.name

        HStack(spacing: 12) {
            // Transport icon with status overlay
            ZStack {
                Circle()
                    .fill(transportColor(for: server.transport))
                    .frame(width: 36, height: 36)
                if isRemoving {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: transportIcon(for: server.transport))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(server.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(server.transportLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(transportColor(for: server.transport), in: Capsule())
                }

                Text(server.endpointDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Status indicator + refresh button
            if isChecking {
                ProgressView()
                    .controlSize(.small)
            } else {
                HStack(spacing: 6) {
                    statusDot(for: server.connected)
                    Button {
                        Task { await viewModel.checkStatus(for: server.name) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh status for \(server.name)")
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: server))
        .accessibilityHint("Swipe left to remove")
    }

    @ViewBuilder
    private func statusDot(for connected: Bool?) -> some View {
        switch connected {
        case true:
            Circle()
                .fill(.green)
                .frame(width: 10, height: 10)
        case false:
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
        case nil:
            Circle()
                .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3]))
                .frame(width: 10, height: 10)
        }
    }

    // MARK: - Helpers

    private func fullRefresh() async {
        await viewModel.load()
        if !viewModel.servers.isEmpty {
            await viewModel.checkAllStatuses()
        }
    }

    private func transportIcon(for transport: String) -> String {
        transport.lowercased() == "http" ? "globe" : "terminal.fill"
    }

    private func transportColor(for transport: String) -> Color {
        transport.lowercased() == "http" ? Color.blue : Color.indigo
    }

    private func accessibilityLabel(for server: MCPServer) -> String {
        var parts = ["\(server.name)", "\(server.transportLabel) transport"]
        if let connected = server.connected {
            parts.append(connected ? "Connected" : "Failed")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - AddMCPServerSheet

private struct AddMCPServerSheet: View {
    let onAdd: (MCPServerDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = MCPServerDraft()

    private var isValid: Bool {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        if draft.transport == "http" {
            return !draft.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            return !draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name (e.g. filesystem)", text: $draft.name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Server name")
                        .accessibilityHint("Unique name for this MCP server")

                    Picker("Transport", selection: $draft.transport) {
                        Text("stdio (subprocess)").tag("stdio")
                        Text("HTTP (remote)").tag("http")
                    }
                    .accessibilityLabel("Transport type")
                    .accessibilityHint("stdio launches a local subprocess; HTTP connects to a remote server")
                }

                if draft.transport == "http" {
                    Section("HTTP") {
                        TextField("Server URL (e.g. http://localhost:8080)", text: $draft.url)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .accessibilityLabel("Server URL")
                            .accessibilityHint("Base URL for the HTTP MCP server")
                    }
                } else {
                    Section("Subprocess") {
                        TextField("Command (e.g. /usr/bin/python3)", text: $draft.command)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.body.monospaced())
                            .accessibilityLabel("Command executable")
                            .accessibilityHint("Path to the MCP server executable")

                        TextField("Arguments (space-separated, optional)", text: $draft.args)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.body.monospaced())
                            .accessibilityLabel("Command arguments")
                            .accessibilityHint("Arguments passed to the executable, separated by spaces")
                    }
                }

                Section("Options") {
                    TextField("Timeout ms (optional)", text: $draft.timeoutMs)
                        .autocorrectionDisabled()
                        .keyboardType(.numberPad)
                        .accessibilityLabel("Connection timeout in milliseconds")
                        .accessibilityHint("Leave blank to use the gateway default timeout")
                }
            }
            .navigationTitle("Add MCP Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(draft)
                        dismiss()
                    }
                    .disabled(!isValid)
                    .accessibilityLabel("Add MCP server")
                    .accessibilityHint("Submits the new MCP server configuration to the gateway agent")
                }
            }
        }
        .presentationDetents([.large])
    }
}
