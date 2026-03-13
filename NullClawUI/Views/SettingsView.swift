import SwiftUI

/// Phase 1 & 2: URL configuration, connectivity status, and pairing entry.
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var gatewayVM: GatewayViewModel?
    @State private var pairingVM: PairingViewModel?

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(.systemBackground), Color.accentColor.opacity(0.12)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        // MARK: App header
                        VStack(spacing: 8) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 60))
                                .foregroundStyle(.tint)
                                .symbolEffect(.bounce, value: appModel.connectionStatus == .online)

                            Text("NullClaw")
                                .font(.largeTitle.bold())
                            Text("AI Gateway Interface")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 32)

                        // MARK: Connection card
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("Gateway", systemImage: "network")
                                    .font(.headline)

                                @Bindable var model = appModel
                                TextField("http://localhost:5111", text: $model.gatewayURL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("Gateway URL")
                                    .accessibilityHint("Enter the NullClaw gateway address")

                                HStack {
                                    ConnectionBadge(status: appModel.connectionStatus)
                                    Spacer()
                                    Button {
                                        Task { await gatewayVM?.connect() }
                                    } label: {
                                        Label("Connect", systemImage: "arrow.triangle.2.circlepath")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .accessibilityHint("Check gateway connectivity and fetch agent info")
                                }

                                if let card = appModel.agentCard {
                                    Divider()
                                    AgentCardView(card: card)
                                }
                            }
                        }

                        // MARK: Pairing card
                        if appModel.connectionStatus == .online {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 14) {
                                    Label("Pair Device", systemImage: "key.fill")
                                        .font(.headline)

                                    Text("Enter the 6-digit code from the NullClaw admin interface.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if let vm = pairingVM {
                                        @Bindable var pvm = vm
                                        TextField("000000", text: $pvm.pairingCode)
                                            .keyboardType(.numberPad)
                                            .textContentType(.oneTimeCode)
                                            .textFieldStyle(.roundedBorder)
                                            .accessibilityLabel("Pairing code")
                                            .accessibilityHint("6-digit code from the admin interface")

                                        if let err = vm.errorMessage {
                                            Text(err)
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                        }

                                        Button {
                                            Task { await vm.pair() }
                                        } label: {
                                            if vm.isPairing {
                                                ProgressView()
                                                    .controlSize(.small)
                                            } else {
                                                Label("Pair", systemImage: "checkmark.seal.fill")
                                                    .frame(maxWidth: .infinity)
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(vm.isPairing || vm.pairingCode.count != 6)
                                        .accessibilityLabel("Pair with gateway")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            let gvm = GatewayViewModel(appModel: appModel)
            gatewayVM = gvm
            // Restore token if we have one
            if let token = try? KeychainService.retrieveToken(for: appModel.gatewayURL) {
                await gvm.client.setToken(token)
                appModel.isPaired = true
            }
            await gvm.connect()
            if let gvm = gatewayVM {
                pairingVM = PairingViewModel(appModel: appModel, client: gvm.client)
            }
        }
    }
}

// MARK: - Sub-views

/// Displays the decoded agent-card data.
struct AgentCardView: View {
    let card: AgentCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.name)
                    .font(.subheadline.weight(.semibold))
                Text("v\(card.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let desc = card.description {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let caps = card.capabilities {
                HStack(spacing: 8) {
                    if caps.streaming == true { CapBadge("Streaming") }
                    if caps.multiModal == true { CapBadge("Multi-modal") }
                    if caps.history == true    { CapBadge("History") }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agent: \(card.name), version \(card.version)")
    }
}

struct CapBadge: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(.tint)
    }
}

struct ConnectionBadge: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
        .accessibilityLabel("Connection status: \(statusLabel)")
    }

    private var statusColor: Color {
        switch status {
        case .online:  .green
        case .offline: .red
        case .unknown: .orange
        }
    }

    private var statusLabel: String {
        switch status {
        case .online:  "Online"
        case .offline: "Offline"
        case .unknown: "Unknown"
        }
    }
}
