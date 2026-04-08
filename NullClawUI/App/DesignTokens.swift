import SwiftUI

// MARK: - Design Tokens

// Centralized design tokens for consistent spacing, corner radii, and
// animation timing across the NullClawUI app.
//
// These values are derived from the existing UI patterns found throughout
// the codebase (ChatView, GlassCard, SettingsView, etc.) and formalized
// into a single source of truth.

enum DesignTokens {
    // MARK: Corner Radii

    /// Standard corner radius values used throughout the app.
    enum CornerRadius {
        /// 16 — GlassCard, main containers, server cards, chat bubbles
        static let card: CGFloat = 16
        /// 12 — Input fields, action buttons, secondary containers
        static let medium: CGFloat = 12
        /// 16 — Chat bubbles (matches llmservercontrol — all bubbles use 16)
        static let bubble: CGFloat = 16
        /// 8 — Status badges, small containers, thinking bubble inner
        static let small: CGFloat = 8
        /// 6 — Inner content, config rows, thinking bubble internal spacing
        static let inner: CGFloat = 6
        /// 2 — Minimal rounding for subtle shapes
        static let tiny: CGFloat = 2
    }

    // MARK: Spacing

    /// Standard spacing values for VStack/HStack/ScrollView padding.
    enum Spacing {
        /// 20 — Major section separation
        static let section: CGFloat = 20
        /// 16 — Card-to-card spacing, GlassCard padding
        static let card: CGFloat = 16
        /// 16 — Internal card padding, form section spacing
        static let standard: CGFloat = 16
        /// 14 — Bubble horizontal padding (matches llmservercontrol)
        static let comfortable: CGFloat = 14
        /// 12 — Tight spacing within cards, between related elements
        static let tight: CGFloat = 12
        /// 10 — Bubble vertical padding, input field internal padding
        static let relaxed: CGFloat = 10
        /// 8 — Minimal spacing, badge padding
        static let minimal: CGFloat = 8
        /// 6 — Thinking bubble internal spacing
        static let compact: CGFloat = 6
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

        /// Quick spring for small state changes (0.3s response)
        static func quick() -> SwiftUI.Animation {
            .spring(response: 0.3)
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
