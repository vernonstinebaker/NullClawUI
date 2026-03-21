import SwiftUI

// MARK: - GatewayDetailView

/// Detail page for a single gateway profile.
/// Fetches agent card and health directly from this profile's URL — no dependency
/// on which gateway the chat client is currently pointed at.
/// Gateway switching is done exclusively from the Chat tab nav-bar picker.
struct GatewayDetailView: View {
    let profile: GatewayProfile

    @Environment(GatewayStore.self) private var store
    @Environment(GatewayViewModel.self) private var gatewayVM
    @Environment(ChatViewModel.self) private var chatVM
    @State private var editingProfile: GatewayProfile? = nil
    @State private var showingPairSheet: Bool = false

    // Per-profile agent card (fetched on appear, independent of chat client)
    @State private var agentCard: AgentCard? = nil
    @State private var isLoadingCard: Bool = false
    @State private var cardError: String? = nil

    // Per-profile health (fetched on appear)
    @State private var healthStatus: ConnectionStatus = .unknown

    var body: some View {
        List {
            // Agent info — fetched directly from this gateway, always shown.
            Section("Agent") {
                if isLoadingCard {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Fetching agent info…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let card = agentCard {
                    LabeledContent("Name", value: card.name)
                    LabeledContent("Version", value: card.version)
                    if let desc = card.description, !desc.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Description")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(desc)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Label(
                        cardError ?? "Unable to fetch agent info",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                }
            }

            if let caps = agentCard?.capabilities {
                Section("Capabilities") {
                    capRow("Streaming", value: caps.streaming == true)
                    if let mm = caps.multiModal { capRow("Multi-modal", value: mm) }
                    if let hist = caps.history   { capRow("History", value: hist) }
                }
            }

            Section("Gateway") {
                LabeledContent("Name", value: profile.name)
                LabeledContent("URL") {
                    Text(profile.url)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Status") {
                    ConnectionBadge(status: healthStatus)
                }
                LabeledContent("Paired") {
                    HStack(spacing: 4) {
                        Image(systemName: profile.isPaired ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(profile.isPaired ? .green : .secondary)
                        Text(profile.isPaired ? "Yes" : "No")
                    }
                }
            }

            // Gateway management — available for every gateway with a valid URL.
            if URL(string: profile.url) != nil {
                Section {
                    NavigationLink {
                        CronJobListView(profile: profile)
                    } label: {
                        Label("Cron Jobs", systemImage: "clock.badge.checkmark")
                    }
                    .accessibilityLabel("Cron Jobs")
                    .accessibilityHint("View, add, pause, and delete scheduled cron jobs on this gateway")

                    NavigationLink {
                        AgentConfigView(profile: profile)
                    } label: {
                        Label("Agent Configuration", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Agent Configuration")
                    .accessibilityHint("View and adjust live-editable agent settings such as model, temperature, and limits")

                    NavigationLink {
                        AutonomyView(profile: profile)
                    } label: {
                        Label("Autonomy & Safety", systemImage: "shield.lefthalf.filled")
                    }
                    .accessibilityLabel("Autonomy & Safety")
                    .accessibilityHint("View and adjust autonomy level, action limits, and safety controls for this gateway")

                    NavigationLink {
                        MCPServerListView(profile: profile)
                    } label: {
                        Label("MCP Servers", systemImage: "puzzlepiece.extension.fill")
                    }
                    .accessibilityLabel("MCP Servers")
                    .accessibilityHint("View, add, and remove MCP server integrations for this gateway")

                    NavigationLink {
                        UsageStatsView(profile: profile)
                    } label: {
                        Label("Cost & Usage", systemImage: "chart.bar.fill")
                    }
                    .accessibilityLabel("Cost & Usage")
                    .accessibilityHint("View token usage and cost data, and configure spend limits for this gateway")

                    NavigationLink {
                        ChannelStatusListView(profile: profile)
                    } label: {
                        Label("Channels", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .accessibilityLabel("Channels")
                    .accessibilityHint("View the connection status and configuration of gateway communication channels")
                }
            }

            Section {
                // Edit button — always available
                Button {
                    editingProfile = profile
                } label: {
                    Label("Edit Gateway", systemImage: "pencil")
                }
            }

            // Pair section — available for any unpaired profile
            if !profile.isPaired {
                Section {
                    Button {
                        showingPairSheet = true
                    } label: {
                        Label("Pair Device", systemImage: "key.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .accessibilityLabel("Pair this device with the gateway")
                    .accessibilityHint("Opens the pairing flow for this gateway")
                } footer: {
                    Text("Pair this device to enable authenticated access to this gateway.")
                }
            }

            // Unpair section — available for any paired profile
            if profile.isPaired {
                Section {
                    Button(role: .destructive) {
                        Task { await gatewayVM.unpairGateway(profile) }
                    } label: {
                        Label("Unpair Device", systemImage: "person.slash.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .accessibilityLabel("Unpair this device")
                    .accessibilityHint("Removes stored credentials for this gateway")
                } footer: {
                    Text("Removes the stored Keychain token for this gateway. You will need to pair again to use it.")
                }
            }
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadProfileInfo() }
        .sheet(isPresented: $showingPairSheet) {
            GatewayPairSheet(profile: profile)
        }
        .sheet(item: $editingProfile) { prof in
            EditGatewaySheet(profile: prof) { updated, previousURL in
                store.updateProfile(updated, previousURL: previousURL)
                // If the edited profile is the active one, silently reconnect the chat client.
                if updated.id == store.activeProfile?.id,
                   let refreshed = store.activeProfile {
                    Task {
                        let newClient = await gatewayVM.switchGateway(to: refreshed)
                        chatVM.resetForNewGateway(client: newClient, gateway: refreshed)
                    }
                }
            }
        }
    }

    // MARK: - Per-profile fetch

    @MainActor
    private func loadProfileInfo() async {
        guard let url = URL(string: profile.url) else { return }
        let client = GatewayClient(baseURL: url)

        // Health check
        healthStatus = .unknown
        async let healthTask: ConnectionStatus = {
            do {
                _ = try await client.checkHealth()
                return .online
            } catch {
                return .offline
            }
        }()

        // Agent card fetch
        isLoadingCard = true
        cardError = nil
        async let cardTask: AgentCard? = {
            do {
                return try await client.fetchAgentCard()
            } catch {
                return nil
            }
        }()

        let (health, card) = await (healthTask, cardTask)
        healthStatus = health
        agentCard = card
        isLoadingCard = false
        if card == nil {
            cardError = "Could not reach \(profile.displayHost)"
        }
    }

    @ViewBuilder
    private func capRow(_ label: String, value: Bool) -> some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                Image(systemName: value ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(value ? .green : .secondary)
                Text(value ? "Yes" : "No")
            }
        }
    }
}
