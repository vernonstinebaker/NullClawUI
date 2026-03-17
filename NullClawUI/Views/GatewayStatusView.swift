import SwiftUI

// MARK: - GatewayStatusView

/// Phase 14: fast multi-gateway health overview.
/// Shows reachability for all known gateways simultaneously via concurrent GET /health.
/// This is a pure health view — it does not surface which gateway is selected for chat,
/// since that concept only matters inside the Chat tab.
struct GatewayStatusView: View {

    @Environment(GatewayStore.self) private var store
    var statusVM: GatewayStatusViewModel

    var body: some View {
        NavigationStack {
            Group {
                if store.profiles.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.profiles) { profile in
                            gatewayRow(profile)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await statusVM.refresh()
                    }
                }
            }
            .navigationTitle("Gateway Health")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await statusVM.refresh() }
                    } label: {
                        if statusVM.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(statusVM.isRefreshing)
                    .accessibilityLabel("Refresh all gateway health checks")
                    .accessibilityHint("Pings every gateway and updates connection status")
                }
            }
            .task {
                // Auto-check on first appearance.
                if statusVM.healthStates.isEmpty {
                    await statusVM.refresh()
                }
            }
        }
    }

    // MARK: - Gateway Row

    @ViewBuilder
    private func gatewayRow(_ profile: GatewayProfile) -> some View {
        let state = statusVM.healthState(for: profile)

        HStack(spacing: 14) {
            // Status dot
            ZStack {
                if state.isChecking {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 12, height: 12)
                } else {
                    Circle()
                        .fill(dotColor(state.status))
                        .frame(width: 12, height: 12)
                }
            }
            .frame(width: 12)

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

            statusLabel(state.status)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(profile: profile, state: state))
    }

    // MARK: - Status label (text beside the dot)

    @ViewBuilder
    private func statusLabel(_ status: ConnectionStatus) -> some View {
        switch status {
        case .online:
            Text("Online")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        case .offline:
            Text("Offline")
                .font(.caption.weight(.medium))
                .foregroundStyle(.red)
        case .unknown:
            EmptyView()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No gateways configured.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Add one in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("No gateways configured. Add one in Settings.")
    }

    // MARK: - Helpers

    private func dotColor(_ status: ConnectionStatus) -> Color {
        switch status {
        case .online:  return .green
        case .offline: return .red
        case .unknown: return Color(.systemFill)
        }
    }

    private func accessibilityLabel(profile: GatewayProfile, state: ProfileHealthState) -> String {
        let statusWord: String
        if state.isChecking {
            statusWord = "checking"
        } else {
            switch state.status {
            case .online:  statusWord = "online"
            case .offline: statusWord = "offline"
            case .unknown: statusWord = "unknown"
            }
        }
        return "\(profile.name), \(profile.displayHost), \(statusWord)"
    }
}
