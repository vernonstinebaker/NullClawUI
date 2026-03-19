import SwiftUI

// MARK: - PairedSettingsView

/// Settings tab shown when already paired.
/// Presents a list of gateway profiles with live health status;
/// each row navigates to a detail page. Pull-to-refresh pings all gateways simultaneously.
/// Search is handled exclusively via the dedicated Search tab (Tab role: .search).
///
/// On iPhone, this is embedded in a Tab (which provides a NavigationStack).
/// On iPad, this is shown in the NavigationSplitView content column (which also provides a NavigationStack).
/// Either way, PairedSettingsView must NOT wrap itself in its own NavigationStack.
struct PairedSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(GatewayStore.self) private var store
    @Environment(GatewayViewModel.self) private var gatewayVM
    @Environment(ChatViewModel.self) private var chatVM
    @Environment(GatewayStatusViewModel.self) private var statusVM

    @State private var showingAddSheet = false

    var body: some View {
        List {
            ForEach(store.profiles) { profile in
                NavigationLink {
                    GatewayDetailView(profile: profile)
                } label: {
                    gatewayRow(profile)
                }
                .accessibilityLabel("\(profile.name), \(profile.displayHost)")
            }
            .onDelete { offsets in
                handleDelete(offsets: offsets)
            }
        }
        .navigationTitle("Gateways")
        .refreshable {
            await statusVM.refresh()
        }
        .task {
            if statusVM.healthStates.isEmpty {
                await statusVM.refresh()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Gateway", systemImage: "plus")
                }
                .accessibilityLabel("Add a new gateway")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddGatewaySheet { name, url in
                let profile = store.addProfile(name: name, url: url)
                // Switch to the new profile so the chat client is connected to it.
                Task {
                    let newClient = await gatewayVM.switchGateway(to: profile)
                    chatVM.resetForNewGateway(client: newClient, gateway: profile)
                }
            }
        }
    }

    // MARK: - Gateway row

    private func gatewayRow(_ profile: GatewayProfile) -> some View {
        let state = statusVM.healthState(for: profile)

        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusCircleColor(state))
                    .frame(width: 36, height: 36)
                if state.isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "server.rack")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(profile.displayHost)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let checked = state.lastChecked {
                    Text("Checked \(checked.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if profile.isPaired {
                Image(systemName: "key.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusCircleColor(_ state: ProfileHealthState) -> Color {
        guard !state.isChecking else { return Color(.systemFill) }
        switch state.status {
        case .online:  return .green
        case .offline: return .red
        case .unknown: return Color(.systemFill)
        }
    }

    // MARK: - Helpers

    private func handleDelete(offsets: IndexSet) {
        // Map offsets back to the unfiltered profiles array.
        let idsToDelete = offsets.map { store.profiles[$0].id }
        guard store.profiles.count > idsToDelete.count else { return }
        for id in idsToDelete {
            store.deleteProfile(id: id)
            appModel.evictAgentCard(for: id)
        }
        // Silently reconnect the chat client to whatever profile the store now considers active.
        if let newActive = store.activeProfile {
            Task {
                let newClient = await gatewayVM.switchGateway(to: newActive)
                chatVM.resetForNewGateway(client: newClient, gateway: newActive)
            }
        }
    }
}

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

            // Live Status and Cron Jobs — available for every gateway with a valid URL.
            if URL(string: profile.url) != nil {
                Section {
                    NavigationLink {
                        GatewayLiveStatusView(profile: profile)
                    } label: {
                        Label("Live Status", systemImage: "waveform.path.ecg")
                    }
                    .accessibilityLabel("Live Status")
                    .accessibilityHint("Shows MCP server and channel connection state from the gateway agent")

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
            EditGatewaySheet(profile: prof) { updated in
                store.updateProfile(updated)
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

// MARK: - GatewayPairSheet

/// Sheet for pairing an already-saved-but-unpaired gateway profile.
/// Reuses AddGatewayPairingModel (connect probe → auto or code entry).
struct GatewayPairSheet: View {
    let profile: GatewayProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(GatewayStore.self) private var store

    @State private var pairingModel: AddGatewayPairingModel? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let pm = pairingModel {
                    pairForm(pm: pm)
                } else {
                    ProgressView("Connecting…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Pair Gateway")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            if let url = URL(string: profile.url) {
                let pm = AddGatewayPairingModel(url: url)
                pairingModel = pm
                await pm.connect()
                // Auto-complete open gateways — no user action needed.
                if pm.step == .notRequired {
                    pm.completeOpenGateway(store: store, profile: profile)
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func pairForm(pm: AddGatewayPairingModel) -> some View {
        Form {
            Section {
                LabeledContent("Name", value: profile.name)
                LabeledContent("URL") {
                    Text(profile.url)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            switch pm.step {
            case .connecting:
                Section {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Connecting to gateway…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

            case .requiresPairing:
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "number")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        @Bindable var bpm = pm
                        TextField("000000", text: $bpm.pairingCode)
                            .keyboardType(.numberPad)
                            .font(.title3.monospacedDigit())
                            .accessibilityLabel("Pairing code")
                            .accessibilityHint("6-digit code from the NullClaw admin interface")
                    }
                    .padding(.vertical, 4)

                    Button {
                        Task { await pm.pair(profileURL: profile.url, store: store, profile: profile) }
                    } label: {
                        HStack {
                            Spacer()
                            if pm.isPairing {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Label("Pair", systemImage: "checkmark.seal.fill")
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(pm.isPairing || pm.pairingCode.count != 6)
                } header: {
                    Text("Pair Device")
                } footer: {
                    Text("Enter the 6-digit code shown in the NullClaw admin interface.")
                }

            case .notRequired:
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Gateway is open — no pairing code required.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    Button("Complete") {
                        pm.completeOpenGateway(store: store, profile: profile)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }

            case .success:
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Paired successfully.")
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }

            case .failed(let message):
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Could not connect")
                                .font(.subheadline.weight(.semibold))
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    Button("Retry") {
                        Task { await pm.connect() }
                    }
                } header: {
                    Text("Connection Error")
                }
            }
        }
    }
}

// MARK: - URL Validation

/// Returns true if the string is a well-formed http/https URL with a non-empty host.
func isValidGatewayURL(_ string: String) -> Bool {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed),
          let scheme = url.scheme,
          scheme == "http" || scheme == "https",
          let host = url.host,
          !host.isEmpty else { return false }
    return true
}

