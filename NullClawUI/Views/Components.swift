import SwiftUI

// MARK: - HealthIndicator

/// Maps a health state to a semantic color for consistent status display.
enum HealthIndicator: Equatable {
    case healthy
    case degraded
    case unhealthy
    case unknown

    var color: Color {
        switch self {
        case .healthy:   return .green
        case .degraded:  return .yellow
        case .unhealthy: return .red
        case .unknown:   return .orange
        }
    }
}

// MARK: - StatusBadge

/// Capsule-shaped status indicator with a pulsing dot and label.
struct StatusBadge: View {
    let label: String
    let health: HealthIndicator
    var isPulsing: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(health.color)
                .frame(width: 8, height: 8)
                .symbolEffect(.pulse.wholeSymbol, isActive: isPulsing)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - StatCard

/// Icon + numeric value + title card with optional health indicator dot.
/// Tappable — triggers `onTap` when present.
struct StatCard: View {
    let icon: String
    let count: String
    let title: String
    let color: Color
    var health: HealthIndicator = .unknown
    var onTap: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(color)
                    Text(count)
                        .font(.title2.weight(.bold))
                        .contentTransition(.numericText())
                    Spacer()
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .contentShape(.rect)

            Circle()
                .fill(health.color)
                .frame(width: 8, height: 8)
                .padding(10)
                .shadow(color: health.color.opacity(0.4), radius: 3)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { onTap?() }
    }
}

// MARK: - LoadingView

/// Centered loading indicator with optional message.
struct LoadingView: View {
    var message: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ActionButton

/// Quick-action button with icon, label, and tinted background.
struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .foregroundStyle(color)
        .accessibilityLabel(title)
    }
}
