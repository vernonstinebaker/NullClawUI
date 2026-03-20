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
    @State private var showingDeleteLastAlert = false

    var body: some View {
        List {
            if store.profiles.isEmpty {
                // NOTE: No unit test — pure layout change; covered by visual inspection in Simulator.
                ContentUnavailableView {
                    Label("No Gateways", systemImage: "server.rack")
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
            } else {
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
        .alert("Cannot Delete Last Gateway", isPresented: $showingDeleteLastAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("At least one gateway must remain. Add another gateway before deleting this one.")
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
        // Prevent deleting the last gateway — show an alert to inform the user.
        guard store.profiles.count > idsToDelete.count else {
            showingDeleteLastAlert = true
            return
        }
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


