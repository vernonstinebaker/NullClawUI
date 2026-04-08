import SwiftUI

// MARK: - GatewayDetailView

struct GatewayDetailView: View {
    let profile: GatewayProfile

    @Environment(GatewayStore.self) private var store
    @Environment(GatewayViewModel.self) private var gatewayVM
    @Environment(ChatViewModel.self) private var chatVM
    @Environment(GatewayStatusViewModel.self) private var statusVM
    @State private var editingProfile: GatewayProfile? = nil
    @State private var showingPairSheet: Bool = false

    @State private var agentCard: AgentCard? = nil
    @State private var isLoadingCard: Bool = false
    @State private var cardError: String? = nil
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
                    if let hist = caps.history { capRow("History", value: hist) }
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
            } header: {
                Text("Gateway")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }

            // Management links
            if URL(string: profile.url) != nil {
                Section {
                    let state = statusVM.healthState(for: profile)

                    managementLink(
                        icon: "clock.badge.checkmark",
                        label: "Cron Jobs",
                        hint: "View, add, pause, and delete scheduled cron jobs",
                        badge: state.cronJobCount.map { "\($0)" }
                    ) {
                        CronJobListView(profile: profile)
                    }
                    managementLink(
                        icon: "puzzlepiece.extension.fill",
                        label: "MCP Servers",
                        hint: "View, add, and remove MCP server integrations",
                        badge: state.mcpServerCount.map { "\($0)" }
                    ) {
                        MCPServerListView(profile: profile)
                    }
                    managementLink(
                        icon: "antenna.radiowaves.left.and.right",
                        label: "Channels",
                        hint: "View connection status of communication channels",
                        badge: state.channelCount.map { "\($0)" }
                    ) {
                        ChannelStatusListView(profile: profile)
                    }
                    managementLink(
                        icon: "slider.horizontal.3",
                        label: "Agent Configuration",
                        hint: "Adjust model, temperature, and limits",
                        badge: nil
                    ) {
                        AgentConfigView(profile: profile)
                    }
                    managementLink(
                        icon: "shield.lefthalf.filled",
                        label: "Autonomy & Safety",
                        hint: "Adjust autonomy level and safety controls",
                        badge: nil
                    ) {
                        AutonomyView(profile: profile)
                    }

                    // NOTE: Cost & Usage temporarily hidden — UsageStatsViewModel uses
                    // sendOneShot which can hang on some gateway configurations.
                    // Uncomment when REST API endpoint is available.
                    // managementLink(
                    //     icon: "chart.bar.fill",
                    //     label: "Cost & Usage",
                    //     hint: "View token usage and configure spend limits",
                    //     badge: nil
                    // ) {
                    //     UsageStatsView(profile: profile)
                    // }
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
                if
                    updated.id == store.activeProfile?.id,
                    let refreshed = store.activeProfile
                {
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

    private func managementLink(
        icon: String,
        label: String,
        hint: String,
        badge: String?,
        @ViewBuilder destination: () -> some View
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Label(label, systemImage: icon)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.fill.tertiary, in: Capsule())
                }
            }
        }
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    // MARK: - Per-profile fetch

    @MainActor
    private func loadProfileInfo() async {
        guard let url = URL(string: profile.url) else { return }
        let client = GatewayClient(baseURL: url)

        healthStatus = .unknown
        async let healthTask: ConnectionStatus = {
            do {
                _ = try await client.checkHealth()
                return .online
            } catch {
                return .offline
            }
        }()

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
