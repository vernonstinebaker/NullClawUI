import SwiftUI

/// Root content view — routes between Settings/Pairing and the main chat interface.
struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(GatewayViewModel.self) private var gatewayVM: GatewayViewModel
    @Environment(ChatViewModel.self) private var chatVM: ChatViewModel

    var body: some View {
        if appModel.isCheckingGateway {
            // Show a neutral loading screen while the launch probe runs.
            // This prevents the pairing UI from flashing on open gateways.
            GatewayCheckingView()
        } else if appModel.isPaired {
            MainTabView(gatewayViewModel: gatewayVM, chatViewModel: chatVM)
        } else {
            SettingsView()
        }
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
