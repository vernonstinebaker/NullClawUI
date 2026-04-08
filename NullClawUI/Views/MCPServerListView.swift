import SwiftUI

// NOTE: No unit test — pure layout change; covered by visual inspection in Simulator.

// MARK: - MCPServerListView

/// Phase 18: MCP Server Management.
/// Displays all MCP servers registered in the gateway config with transport type
/// and connection status. Accessed via a NavigationLink inside GatewayDetailView.
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
                    ForEach(viewModel.servers) { server in
                        NavigationLink {
                            MCPServerDetailView(viewModel: viewModel, serverName: server.name)
                        } label: {
                            serverRow(server)
                        }
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

            // Confirmation banner
            if let msg = viewModel.confirmationMessage {
                Section {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Success: \(msg)")
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
        .refreshable { await viewModel.load() }
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
                await viewModel.load()
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

        HStack(spacing: 12) {
            // Transport icon
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

                    // Transport badge
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

            // Connection status badge — only shown after a Check Status has been run.
            if let connected = server.connected {
                connectionBadge(for: connected)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: server))
        .accessibilityHint("Tap to view details. Swipe left to remove.")
    }

    @ViewBuilder
    private func connectionBadge(for connected: Bool) -> some View {
        let (label, color, icon): (String, Color, String) = connected
            ? ("Connected", .green, "circle.fill")
            : ("Failed", .red, "exclamationmark.circle.fill")
        Label(label, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .accessibilityLabel("Status: \(label)")
    }

    // MARK: - Helpers

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

// MARK: - MCPServerDetailView

/// Read-only detail view for a single MCP server, with an on-demand "Check Status" button.
private struct MCPServerDetailView: View {
    @Bindable var viewModel: MCPServerViewModel
    let serverName: String

    /// Live server from the VM — falls back to a placeholder if removed between load cycles.
    private var server: MCPServer? {
        viewModel.servers.first(where: { $0.name == serverName })
    }

    private var isCheckingStatus: Bool {
        viewModel.checkingStatusName == serverName
    }

    var body: some View {
        Group {
            if let server {
                serverDetail(server)
            } else {
                ContentUnavailableView(
                    "Server Not Found",
                    systemImage: "puzzlepiece.extension",
                    description: Text("This MCP server may have been removed.")
                )
            }
        }
        .navigationTitle(serverName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isCheckingStatus {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Checking server status")
                }
            }
        }
    }

    private func serverDetail(_ server: MCPServer) -> some View {
        List {
            Section("Identity") {
                LabeledContent("Name", value: server.name)
                LabeledContent("Transport", value: server.transportLabel)
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        statusContent(for: server.connected)
                        if isCheckingStatus {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Checking status")
                        }
                    }
                    .font(.subheadline)
                }
                Button {
                    Task { await viewModel.checkStatus(for: serverName) }
                } label: {
                    if isCheckingStatus {
                        Label("Checking…", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Check Status", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isCheckingStatus)
                .accessibilityLabel("Check connection status")
                .accessibilityHint("Probes the MCP server to verify it is reachable")
            }

            if server.transport.lowercased() == "http" {
                Section("HTTP") {
                    if let url = server.url {
                        LabeledContent("URL") {
                            Text(url)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if let headers = server.headers, !headers.isEmpty {
                        LabeledContent("Headers", value: "")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(headers.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            LabeledContent(key, value: value)
                                .font(.caption.monospaced())
                        }
                    }
                }
            } else {
                Section("Subprocess") {
                    if let cmd = server.command {
                        LabeledContent("Command") {
                            Text(cmd)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if let args = server.args, !args.isEmpty {
                        LabeledContent("Arguments") {
                            Text(args.joined(separator: " "))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if let env = server.env, !env.isEmpty {
                        LabeledContent("Environment", value: "")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(env.sorted(by: { $0.key < $1.key }), id: \.key) { key, _ in
                            LabeledContent(key, value: "●●●●●●")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let timeout = server.timeoutMs {
                Section("Options") {
                    LabeledContent("Timeout", value: "\(timeout) ms")
                }
            }

            // Confirmation / error banners scoped to this detail view's last check.
            if let msg = viewModel.confirmationMessage, viewModel.checkingStatusName == nil {
                Section {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Status: \(msg)")
                }
            }
            if let err = viewModel.errorMessage, viewModel.checkingStatusName == nil {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Error: \(err)")
                }
            }
        }
    }

    @ViewBuilder
    private func statusContent(for connected: Bool?) -> some View {
        switch connected {
        case true:
            Image(systemName: "circle.fill").foregroundStyle(.green)
            Text("Connected")
        case false:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            Text("Failed")
        case nil:
            Image(systemName: "circle.dotted").foregroundStyle(.secondary)
            Text("Unknown")
        }
    }
}

// MARK: - AddMCPServerSheet

/// Form for registering a new MCP server via the agent.
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
