import SwiftUI

/// Root content view — routes between Settings/Pairing and the main chat interface.
struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(GatewayViewModel.self) private var gatewayVM: GatewayViewModel
    @Environment(ChatViewModel.self) private var chatVM: ChatViewModel
    @Environment(GatewayStore.self) private var store

    var body: some View {
        if appModel.isCheckingGateway {
            GatewayCheckingView()
        } else if appModel.isPaired || hasHubProfile {
            MainTabView(gatewayViewModel: gatewayVM, chatViewModel: chatVM)
        } else {
            SettingsView()
        }
    }

    /// Hub profiles don't need instance pairing — show the main interface immediately.
    private var hasHubProfile: Bool {
        store.profiles.contains { $0.hubURL != nil }
    }
}

// MARK: - GatewayCheckingView

/// Shown at launch while the initial open-gateway probe is in-flight.
/// Replaced by MainTabView (paired) or SettingsView (pairing required) once the probe completes.
struct GatewayCheckingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel("Connecting to gateway")
            Text("Connecting…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        // NOTE: No unit test — pure layout change; covered by visual inspection in Simulator.
    }
}
