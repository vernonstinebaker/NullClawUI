import SwiftUI

/// Root content view — routes between Settings/Pairing and the main chat interface.
struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if appModel.isPaired {
            MainTabView()
        } else {
            SettingsView()
        }
    }
}
