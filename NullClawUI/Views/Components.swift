import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

// MARK: - HealthIndicator

/// Maps a health state to a semantic color for consistent status display.
enum HealthIndicator: Equatable {
    case healthy
    case degraded
    case unhealthy
    case unknown

    var color: Color {
        switch self {
        case .healthy: .green
        case .degraded: .yellow
        case .unhealthy: .red
        case .unknown: .orange
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
        HStack(spacing: DesignTokens.Spacing.tiny) {
            Circle()
                .fill(health.color)
                .frame(width: 12, height: 12)
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
    var onTap: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.minimal) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(color)
                        .symbolEffect(.pulse.wholeSymbol, isActive: health != .healthy)
                    Text(count)
                        .font(.title2.weight(.bold))
                        .contentTransition(.numericText())
                    Spacer()
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(DesignTokens.Spacing.standard)
            .contentShape(.rect)

            if health != .healthy {
                Circle()
                    .fill(health.color)
                    .frame(width: 8, height: 8)
                    .padding(10)
                    .shadow(color: health.color.opacity(0.4), radius: 3)
            }
        }
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card, style: .continuous)
        )
        .onTapGesture { onTap?() }
    }
}

// MARK: - LoadingView

/// Centered loading indicator with optional message.
struct LoadingView: View {
    var message: String?

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

// MARK: - CopyButton

struct CopyButton: View {
    let text: String
    var tint: Color = .secondary
    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                .font(.caption2)
                .foregroundStyle(copied ? .green : tint)
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(copied)
    }

    private func copy() {
        #if canImport(UIKit)
            UIPasteboard.general.string = text
        #endif
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

// MARK: - MarkdownText

struct MarkdownText: View {
    let content: String
    private let attributedString: AttributedString

    init(_ content: String) {
        self.content = content
        if
            let parsed = try? AttributedString(
                markdown: content,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        {
            attributedString = parsed
        } else {
            attributedString = AttributedString(content)
        }
    }

    var body: some View {
        Text(attributedString)
    }
}
