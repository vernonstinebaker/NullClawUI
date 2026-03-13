import SwiftUI

@main
struct NullClawUIApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .tint(appModel.agentCard?.accentColor.flatMap(Color.init(hex:)) ?? .accentColor)
        }
    }
}
