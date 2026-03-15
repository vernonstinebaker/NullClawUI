import SwiftUI

/// Reusable Liquid Glass card container.
/// Uses the iOS 26 `.glassEffect` modifier for authentic Liquid Glass appearance.
struct GlassCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
