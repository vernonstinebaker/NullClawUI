import SwiftUI

/// Reusable card container with regular material background.
/// Adopts the LLMServerControl pattern (regularMaterial, 16pt radius, 16pt padding).
struct GlassCard<Content: View>: View {
    var padding: CGFloat = DesignTokens.Spacing.standard
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card, style: .continuous)
            )
    }
}
