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
            // Agent info card
            Section {
                agentInfoCard
            } header: {
                Text("Agent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }

            if let caps = agentCard?.capabilities {
                Section {
                    capRow("Streaming", value: caps.streaming == true)
                    if let mm = caps.multiModal { capRow("Multi-modal", value: mm) }
                    if let hist = caps.history   { capRow("History", value: hist) }
                } header: {
                    Text("Capabilities")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }

            // Gateway info card
            Section {
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
            } header: {
                Text("Gateway")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }

            // Management links
            if URL(string: profile.url) != nil {
                Section {
                    managementLink(icon: "clock.badge.checkmark", label: "Cron Jobs", hint: "View, add, pause, and delete scheduled cron jobs") {
                        CronJobListView(profile: profile)
                    }
                    managementLink(icon: "puzzlepiece.extension.fill", label: "MCP Servers", hint: "View, add, and remove MCP server integrations") {
                        MCPServerListView(profile: profile)
                    }
                    managementLink(icon: "antenna.radiowaves.left.and.right", label: "Channels", hint: "View connection status of communication channels") {
                        ChannelStatusListView(profile: profile)
                    }
                    managementLink(icon: "slider.horizontal.3", label: "Agent Configuration", hint: "Adjust model, temperature, and limits") {
                        AgentConfigView(profile: profile)
                    }
                    managementLink(icon: "shield.lefthalf.filled", label: "Autonomy & Safety", hint: "Adjust autonomy level and safety controls") {
                        AutonomyView(profile: profile)
                    }
                    managementLink(icon: "chart.bar.fill", label: "Cost & Usage", hint: "View token usage and configure spend limits") {
                        UsageStatsView(profile: profile)
                    }
                } header: {
                    Text("Management")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }

            // Actions
            Section {
                Button {
                    editingProfile = profile
                } label: {
                    Label("Edit Gateway", systemImage: "pencil")
                }
            }

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

    // MARK: - Subviews

    @ViewBuilder
    private var agentInfoCard: some View {
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

    private func managementLink<Destination: View>(
        icon: String,
        label: String,
        hint: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label(label, systemImage: icon)
        }
        .accessibilityLabel(label)
        .accessibilityHint(hint)
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
