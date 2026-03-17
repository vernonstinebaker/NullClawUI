import SwiftUI

// MARK: - GatewayStatusView

/// Phase 14 (redesigned): fast multi-gateway health overview.
/// Fires a GET /health against every known profile simultaneously — no A2A prompts,
/// results appear in under a second on LAN.
struct GatewayStatusView: View {

    @Environment(GatewayStore.self) private var store
    @Environment(GatewayViewModel.self) private var gatewayVM
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
            .navigationTitle("Gateways")
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
        let isActive = profile.id == store.activeProfile?.id

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
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if isActive {
                        Text("Active")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(.tint)
                    }
                }
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

            // Quick-switch button for inactive gateways
            if !isActive {
                Button {
                    Task { await switchTo(profile) }
                } label: {
                    Image(systemName: "arrow.trianglehead.2.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Switch to \(profile.name)")
                .accessibilityHint("Makes this gateway the active one")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(profile: profile, state: state, isActive: isActive))
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

    private func accessibilityLabel(
        profile: GatewayProfile,
        state: ProfileHealthState,
        isActive: Bool
    ) -> String {
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
        let activeWord = isActive ? ", active" : ""
        return "\(profile.name), \(profile.displayHost)\(activeWord), \(statusWord)"
    }

    private func switchTo(_ profile: GatewayProfile) async {
        _ = await gatewayVM.switchGateway(to: profile)
    }
}
