import SwiftUI

// MARK: - ServersView

/// Card-based dashboard showing all configured gateway profiles.
/// Replaces the former flat-list PairedSettingsView.
/// Each gateway is displayed as a tappable ServerCard with live health status.
///
/// On iPhone, this is embedded in a Tab (which provides a NavigationStack).
/// On iPad, this is shown in the NavigationSplitView content column.
/// Either way, ServersView must NOT wrap itself in its own NavigationStack.
struct ServersView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(GatewayStore.self) private var store
    @Environment(GatewayViewModel.self) private var gatewayVM
    @Environment(ChatViewModel.self) private var chatVM
    @Environment(GatewayStatusViewModel.self) private var statusVM

    @State private var showingAddSheet = false
    @State private var showingDeleteLastAlert = false

    var body: some View {
        ScrollView {
            if store.profiles.isEmpty {
                emptyState
            } else {
                VStack(spacing: DesignTokens.Spacing.minimal) {
                    ForEach(store.profiles) { profile in
                        serverCard(for: profile)
                    }
                }
                .padding(.horizontal)
                .padding(.top, DesignTokens.Spacing.minimal)
            }
        }
        .navigationTitle("Servers")
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
                    Label("Add Server", systemImage: "plus")
                }
                .accessibilityLabel("Add a new gateway")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddGatewaySheet { name, url, isPaired, requiresPairing, hubURL in
                let profile = store.addProfile(
                    name: name,
                    url: url,
                    isPaired: isPaired,
                    requiresPairing: requiresPairing,
                    hubURL: hubURL
                )
                Task {
                    let newClient = await gatewayVM.switchGateway(to: profile)
                    chatVM.resetForNewGateway(client: newClient, gateway: profile)
                }
            }
        }
        .alert("Cannot Delete Last Gateway", isPresented: $showingDeleteLastAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("At least one gateway must remain. Add another gateway before deleting this one.")
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Servers", systemImage: "server.rack")
        } description: {
            Text("Tap + to add your first NullClaw gateway.")
        } actions: {
            Button {
                showingAddSheet = true
            } label: {
                Label("Add Gateway", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 80)
    }

    @ViewBuilder
    private func serverCard(for profile: GatewayProfile) -> some View {
        let state = statusVM.healthState(for: profile)

        NavigationLink {
            GatewayDetailView(profile: profile)
        } label: {
            ServerCardContent(
                profile: profile,
                healthStatus: state.status,
                lastChecked: state.lastChecked,
                cronJobCount: state.cronJobCount,
                mcpServerCount: state.mcpServerCount,
                channelCount: state.channelCount
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(profile.name), \(state.status == .online ? "online" : "offline")")
        .accessibilityHint("Tap to view gateway details")
        .contextMenu {
            Button(role: .destructive) {
                handleDeleteSingle(profile: profile)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func handleDeleteSingle(profile: GatewayProfile) {
        guard store.profiles.count > 1 else {
            showingDeleteLastAlert = true
            return
        }
        store.deleteProfile(id: profile.id)
        appModel.evictAgentCard(for: profile.id)
        if let newActive = store.activeProfile {
            Task {
                let newClient = await gatewayVM.switchGateway(to: newActive)
                chatVM.resetForNewGateway(client: newClient, gateway: newActive)
            }
        }
    }
}
