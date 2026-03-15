import SwiftUI

// MARK: - SettingsView

/// Phase 1 & 2: URL configuration, connectivity status, and pairing entry.
struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(GatewayStore.self) private var store
    @State private var gatewayVM: GatewayViewModel?
    @State private var pairingVM: PairingViewModel?
    @State private var isConnecting = false
    /// Editable copy of the active profile URL (bound to the text field).
    @State private var editableURL: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                // Subtle gradient background
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color.accentColor.opacity(0.08),
                        Color(.systemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        heroHeader
                        gatewayCard
                        if appModel.connectionStatus == .online {
                            pairingCard
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 48)
                    .animation(.spring(duration: 0.45, bounce: 0.15), value: appModel.connectionStatus)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            // Initialise the editable URL from the active profile.
            editableURL = store.activeURL
            let gvm = GatewayViewModel(appModel: appModel)
            gatewayVM = gvm
            if let tok = (try? KeychainService.retrieveToken(for: appModel.gatewayURL)) ?? nil,
               !tok.isEmpty {
                await gvm.client.setToken(tok)
                appModel.isPaired = true
            }
            await gvm.connect()
            if let gvm = gatewayVM {
                pairingVM = PairingViewModel(appModel: appModel, client: gvm.client)
            }
        }
    }

    // MARK: - Hero header

    private var heroHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 90, height: 90)
                if appModel.connectionStatus == .online {
                    Circle()
                        .fill(Color.accentColor.opacity(0.06))
                        .frame(width: 110, height: 110)
                        .scaleEffect(appModel.connectionStatus == .online ? 1 : 0.8)
                        .animation(
                            .easeInOut(duration: 2).repeatForever(autoreverses: true),
                            value: appModel.connectionStatus
                        )
                }
                Image(systemName: appModel.connectionStatus == .online
                      ? "brain.head.profile.fill"
                      : "brain.head.profile")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(
                        appModel.connectionStatus == .online ? Color.accentColor : .secondary
                    )
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.spring(duration: 0.4), value: appModel.connectionStatus)
            }
            .padding(.top, 20)

            VStack(spacing: 4) {
                if let card = appModel.agentCard {
                    Text(card.name)
                        .font(.title2.bold())
                        .transition(.opacity)
                    if let desc = card.description {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .transition(.opacity)
                    }
                } else {
                    Text("NullClaw")
                        .font(.title2.bold())
                    Text("AI Gateway Interface")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: appModel.agentCard?.name)
        }
    }

    // MARK: - Gateway card

    private var gatewayCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Label("Gateway", systemImage: "network")
                    .font(.headline)

                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    TextField("http://localhost:5111", text: $editableURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityLabel("Gateway URL")
                        .accessibilityHint("Enter the NullClaw gateway address")
                        .onTapGesture {
                            Task { @MainActor in
                                UIApplication.shared.sendAction(
                                    #selector(UIResponder.selectAll(_:)),
                                    to: nil, from: nil, for: nil
                                )
                            }
                        }
                        .onChange(of: editableURL) { _, newURL in
                            // Persist the edit to the active profile in the store.
                            if var profile = store.activeProfile {
                                profile.url = newURL
                                store.updateProfile(profile)
                            }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 12) {
                    ConnectionBadge(status: appModel.connectionStatus)

                    Spacer()

                    Button {
                        isConnecting = true
                        Task {
                            await gatewayVM?.connect()
                            isConnecting = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isConnecting {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(isConnecting ? "Connecting…" : "Connect")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(isConnecting)
                    .accessibilityHint("Check gateway connectivity and fetch agent info")
                }

                if let card = appModel.agentCard {
                    Divider().padding(.vertical, 2)
                    AgentCardView(card: card)
                }
            }
        }
    }

    // MARK: - Pairing card

    @ViewBuilder private var pairingCard: some View {
        if let vm = pairingVM {
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Pair Device", systemImage: "key.fill")
                        .font(.headline)

                    Text("Enter the 6-digit code shown in the NullClaw admin interface.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    @Bindable var pvm = vm
                    HStack(spacing: 10) {
                        Image(systemName: "number")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        TextField("000000", text: $pvm.pairingCode)
                            .keyboardType(.numberPad)
                            .font(.title3.monospacedDigit())
                            .accessibilityLabel("Pairing code")
                            .accessibilityHint("6-digit code from the admin interface")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if let err = vm.errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(err)
                                .foregroundStyle(.red)
                        }
                        .font(.caption)
                    }

                    Button {
                        Task { await vm.pair() }
                    } label: {
                        HStack {
                            Spacer()
                            if vm.isPairing {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Label("Pair", systemImage: "checkmark.seal.fill")
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(vm.isPairing || vm.pairingCode.count != 6)
                    .accessibilityLabel("Pair with gateway")
                }
            }
        }
    }
}

// MARK: - AgentCardView

/// Displays decoded agent-card data inline.
struct AgentCardView: View {
    let card: AgentCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(card.name)
                    .font(.subheadline.weight(.semibold))
                Text("v\(card.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
            }
            if let desc = card.description {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if let caps = card.capabilities {
                HStack(spacing: 6) {
                    if caps.streaming == true { CapBadge("Streaming", icon: "waveform") }
                    if caps.multiModal == true { CapBadge("Multi-modal", icon: "photo") }
                    if caps.history == true    { CapBadge("History", icon: "clock") }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agent: \(card.name), version \(card.version)")
    }
}

// MARK: - CapBadge

struct CapBadge: View {
    let label: String
    let icon: String
    init(_ label: String, icon: String = "") { self.label = label; self.icon = icon }

    var body: some View {
        HStack(spacing: 3) {
            if !icon.isEmpty { Image(systemName: icon).font(.caption2) }
            Text(label).font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.13), in: Capsule())
        .foregroundStyle(Color.accentColor)
    }
}

// MARK: - ConnectionBadge

struct ConnectionBadge: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.6), radius: statusColor == .green ? 4 : 0)
            Text(statusLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection status: \(statusLabel)")
        .accessibilityIdentifier("connectionBadge")
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
