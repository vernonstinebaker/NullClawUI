import SwiftUI

// MARK: - ServerCard

/// Tappable card representing a single gateway profile in the Servers dashboard.
/// Shows status, URL, mini-stats, and last-checked time.
struct ServerCard: View {
    let profile: GatewayProfile
    let healthStatus: ConnectionStatus
    let lastChecked: Date?
    let taskCount: Int
    let cronJobCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.tight) {
                // Top row: status dot + name + chevron
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

                // Mini stats grid
                if healthStatus == .online {
                    miniStatsGrid
                }

                // Footer: last checked
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
            .contentShape(.rect(cornerRadius: DesignTokens.CornerRadius.card))
        }
        .buttonStyle(.plain)
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
        .accessibilityLabel("\(profile.name), \(healthStatus == .online ? "online" : "offline")")
        .accessibilityHint("Tap to view gateway details")
    }

    // MARK: - Subviews

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
            return (.green, false)
        case .offline:
            return (.red, false)
        case .unknown:
            return (.orange, true)
        }
    }

    @ViewBuilder
    private var miniStatsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: DesignTokens.Spacing.minimal) {
            miniStatItem(icon: "bubble.left.and.bubble.right", value: "\(taskCount)", label: "Tasks", color: .blue)
            miniStatItem(icon: "clock.badge.checkmark", value: "\(cronJobCount)", label: "Cron", color: .orange)
            miniStatItem(icon: "server.rack", value: profile.isPaired ? "✓" : "—", label: "Paired", color: .green)
        }
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
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
