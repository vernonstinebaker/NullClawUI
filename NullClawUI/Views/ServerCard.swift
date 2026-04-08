import SwiftUI

// MARK: - ServerCardContent

struct ServerCardContent: View {
    let profile: GatewayProfile
    let healthStatus: ConnectionStatus
    let lastChecked: Date?
    let cronJobCount: Int?
    let mcpServerCount: Int?
    let channelCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.tight) {
            HStack {
                statusDot
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.title3.weight(.semibold))
                    Text(profile.displayHost)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
            }

            if healthStatus == .online {
                miniStatsGrid
            }

            if let lastChecked {
                HStack(spacing: DesignTokens.Spacing.tiny) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(lastChecked, style: .relative)
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(DesignTokens.Spacing.standard)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card, style: .continuous)
                .strokeBorder(
                    healthStatus == .offline ? Color.red.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private var statusDot: some View {
        let (color, isPulsing) = statusInfo
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .symbolEffect(.pulse.wholeSymbol, isActive: isPulsing)
    }

    private var statusInfo: (Color, Bool) {
        switch healthStatus {
        case .online:
            (.green, false)
        case .offline:
            (.red, false)
        case .unknown:
            (.orange, true)
        }
    }

    private var miniStatsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: DesignTokens.Spacing.minimal) {
            miniStatItem(
                icon: "clock.badge.checkmark",
                value: countText(cronJobCount),
                label: "Cron",
                color: .orange
            )
            miniStatItem(
                icon: "puzzlepiece.extension.fill",
                value: countText(mcpServerCount),
                label: "MCP",
                color: .purple
            )
            miniStatItem(
                icon: "antenna.radiowaves.left.and.right",
                value: countText(channelCount),
                label: "Channels",
                color: .teal
            )
            miniStatItem(
                icon: "checkmark.shield.fill",
                value: profile.isPaired ? "✓" : "—",
                label: "Paired",
                color: .green
            )
        }
    }

    private func countText(_ count: Int?) -> String {
        if let count { "\(count)" } else { "—" }
    }

    private func miniStatItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.caption.weight(.bold))
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - ServerCard (standalone tappable version)

struct ServerCard: View {
    let profile: GatewayProfile
    let healthStatus: ConnectionStatus
    let lastChecked: Date?
    let cronJobCount: Int?
    let mcpServerCount: Int?
    let channelCount: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ServerCardContent(
                profile: profile,
                healthStatus: healthStatus,
                lastChecked: lastChecked,
                cronJobCount: cronJobCount,
                mcpServerCount: mcpServerCount,
                channelCount: channelCount
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(profile.name), \(healthStatus == .online ? "online" : "offline")")
        .accessibilityHint("Tap to view gateway details")
    }
}
