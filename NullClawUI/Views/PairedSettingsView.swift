import SwiftUI

// MARK: - PairedSettingsView

/// Settings tab shown when already paired.
struct PairedSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(GatewayStore.self) private var store
    var pairingVM: PairingViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                // Subtle gradient
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
                    VStack(spacing: 0) {
                        agentHero
                            .padding(.bottom, 28)

                        VStack(spacing: 16) {
                            gatewaysRow
                            gatewayInfoRow
                            authCard
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Agent hero header

    private var agentHero: some View {
        VStack(spacing: 14) {
            // Avatar circle with initial or brain icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)

                if let name = appModel.agentCard?.name, let initial = name.first {
                    Text(String(initial))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .shadow(color: Color.accentColor.opacity(0.2), radius: 12, x: 0, y: 6)
            .padding(.top, 28)

            VStack(spacing: 4) {
                Text(appModel.agentCard?.name ?? "NullClaw")
                    .font(.title3.bold())

                if let desc = appModel.agentCard?.description {
                    Text(desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 24)
                }

                ConnectionBadge(status: appModel.connectionStatus)
                    .padding(.top, 4)
            }

            // Capability badges
            if let caps = appModel.agentCard?.capabilities {
                HStack(spacing: 6) {
                    if caps.streaming == true { CapBadge("Streaming", icon: "waveform") }
                    if caps.multiModal == true { CapBadge("Multi-modal", icon: "photo") }
                    if caps.history == true    { CapBadge("History", icon: "clock") }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Gateways navigation row (Phase 9)

    private var gatewaysRow: some View {
        GlassCard {
            NavigationLink(destination: GatewayListView()) {
                HStack(spacing: 14) {
                    iconCircle(systemName: "network", color: .purple)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gateways")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("\(store.profiles.count) gateway\(store.profiles.count == 1 ? "" : "s") saved")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.quaternary)
                }
            }
            .accessibilityLabel("Gateways")
            .accessibilityHint("Manage and switch between NullClaw gateway connections")
        }
    }

    // MARK: - Gateway Info navigation row

    private var gatewayInfoRow: some View {
        GlassCard {
            NavigationLink(destination: GatewayInfoView(appModel: appModel)) {
                HStack(spacing: 14) {
                    iconCircle(systemName: "info.circle.fill", color: .blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gateway Info")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(appModel.gatewayURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.quaternary)
                }
            }
            .accessibilityLabel("Gateway Info")
            .accessibilityHint("View agent name, version, capabilities, and connection status")
        }
    }

    // MARK: - Auth card

    private var authCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    iconCircle(systemName: "key.fill", color: .orange)
                    Text("Authentication")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }

                Text("Paired with this gateway. Your credentials are stored securely in the system Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    pairingVM.unpair()
                } label: {
                    HStack {
                        Spacer()
                        Label("Unpair Device", systemImage: "person.slash.fill")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.large)
                .accessibilityLabel("Unpair this device")
                .accessibilityHint("Removes stored credentials and returns to the setup screen")
            }
        }
    }

    // MARK: - Helper

    private func iconCircle(systemName: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: 36, height: 36)
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
        }
    }
}

// MARK: - GatewayInfoView

/// Full-screen navigation push showing all agent card fields, gateway URL, and connection status.
struct GatewayInfoView: View {
    var appModel: AppModel

    var body: some View {
        List {
            if let card = appModel.agentCard {
                Section("Agent") {
                    LabeledContent("Name", value: card.name)
                    LabeledContent("Version", value: card.version)
                    if let description = card.description {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(description)
                        }
                    }
                }
                if let caps = card.capabilities {
                    Section("Capabilities") {
                        LabeledContent("Streaming") {
                            capValue(caps.streaming == true)
                        }
                        if let mm = caps.multiModal {
                            LabeledContent("Multi-modal") { capValue(mm) }
                        }
                        if let hist = caps.history {
                            LabeledContent("History") { capValue(hist) }
                        }
                    }
                }
            } else {
                Section {
                    Text("Agent card not available.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Gateway") {
                LabeledContent("URL") {
                    Text(appModel.gatewayURL)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Status") {
                    ConnectionBadge(status: appModel.connectionStatus)
                }
            }
        }
        .navigationTitle("Gateway Info")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func capValue(_ enabled: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(enabled ? .green : .secondary)
            Text(enabled ? "Yes" : "No")
        }
    }
}
