import SwiftUI

// MARK: - Design Tokens

/// Centralized design tokens for consistent spacing, corner radii, and
/// animation timing across the NullClawUI app.
///
/// These values are derived from the existing UI patterns found throughout
/// the codebase (ChatView, GlassCard, SettingsView, etc.) and formalized
/// into a single source of truth.

enum DesignTokens {

    // MARK: Corner Radii

    /// Standard corner radius values used throughout the app.
    enum CornerRadius {
        /// 20 — GlassCard, main containers, search bar
        static let card: CGFloat = 20
        /// 12 — Input fields, action buttons, secondary containers
        static let medium: CGFloat = 12
        /// 10 — Chat bubbles, error banners, attachment thumbnails
        static let bubble: CGFloat = 10
        /// 8 — Status badges, small containers
        static let small: CGFloat = 8
        /// 6 — Inner content, config rows
        static let inner: CGFloat = 6
        /// 2 — Minimal rounding for subtle shapes
        static let tiny: CGFloat = 2
    }

    // MARK: Spacing

    /// Standard spacing values for VStack/HStack/ScrollView padding.
    enum Spacing {
        /// 24 — Major section separation
        static let section: CGFloat = 24
        /// 20 — Card-to-card spacing, GlassCard padding
        static let card: CGFloat = 20
        /// 16 — Internal card padding, form section spacing
        static let standard: CGFloat = 16
        /// 12 — Tight spacing within cards, between related elements
        static let tight: CGFloat = 12
        /// 8 — Minimal spacing, badge padding
        static let minimal: CGFloat = 8
        /// 4 — Very tight, dot indicators
        static let tiny: CGFloat = 4
    }

    // MARK: Animation

    /// Standard animation curves and durations.
    enum Animation {
        /// Spring for most UI transitions (0.35s, bounce 0.2)
        static func spring() -> SwiftUI.Animation {
            .spring(duration: 0.35, bounce: 0.2)
        }

        /// Quick spring for small state changes (0.25s response)
        static func quick() -> SwiftUI.Animation {
            .spring(response: 0.25)
        }

        /// Standard fade transition
        static func fade() -> AnyTransition {
            .opacity
        }

        /// Expand/collapse transition
        static func expand() -> AnyTransition {
            .opacity.combined(with: .move(edge: .top))
        }
    }

    // MARK: Font Sizes

    /// Semantic font size references.
    enum FontSize {
        static let title: CGFloat = 28
        static let headline: CGFloat = 17
        static let body: CGFloat = 17
        static let callout: CGFloat = 16
        static let subheadline: CGFloat = 15
        static let footnote: CGFloat = 13
        static let caption: CGFloat = 12
        static let caption2: CGFloat = 11
    }
}
