import SwiftUI

/// Root content view — routes between Settings/Pairing and the main chat interface.
struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(GatewayViewModel.self) private var gatewayVM: GatewayViewModel
    @Environment(ChatViewModel.self) private var chatVM: ChatViewModel

    var body: some View {
        if appModel.isPaired {
            MainTabView(gatewayViewModel: gatewayVM, chatViewModel: chatVM)
        } else {
            SettingsView()
        }
    }
}
