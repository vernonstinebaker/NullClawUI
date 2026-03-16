import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct NullClawUIApp: App {
    @State private var store: GatewayStore
    @State private var conversationStore: ConversationStore
    @State private var appModel: AppModel
    @State private var gatewayVM: GatewayViewModel
    @State private var chatVM: ChatViewModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let args = CommandLine.arguments

        // --uitesting-paired: start the app already paired with a stubbed profile and agent card.
        if args.contains("--uitesting-paired") {
            let fakeProfile = GatewayProfile(
                id: UUID(),
                name: "TestAgent",
                url: "http://127.0.0.1:19999",
                isPaired: true
            )
            let s = GatewayStore(testProfile: fakeProfile)
            let cs = ConversationStore(empty: true)
            let m = AppModel(store: s)
            m.isPaired = true
            m.connectionStatus = .online
            m.agentCard = AgentCard(
                name: "TestAgent",
                version: "0.0.1",
                description: "Stub agent for UI tests",
                capabilities: AgentCard.AgentCapabilities(
                    streaming: true,
                    multiModal: nil,
                    history: true
                ),
                accentColor: nil
            )
            let gvm = GatewayViewModel(appModel: m)
            let cvm = ChatViewModel(appModel: m, client: gvm.client, conversationStore: cs)
            _store = State(wrappedValue: s)
            _conversationStore = State(wrappedValue: cs)
            _appModel = State(wrappedValue: m)
            _gatewayVM = State(wrappedValue: gvm)
            _chatVM = State(wrappedValue: cvm)
            return
        }

        // --uitesting: clean unpaired state.
        if args.contains("--uitesting") {
            let fakeProfile = GatewayProfile(
                id: UUID(),
                name: "Local",
                url: "http://127.0.0.1:19999",
                isPaired: false
            )
            let s = GatewayStore(testProfile: fakeProfile)
            let cs = ConversationStore(empty: true)
            let m = AppModel(store: s)
            let gvm = GatewayViewModel(appModel: m)
            let cvm = ChatViewModel(appModel: m, client: gvm.client, conversationStore: cs)
            _store = State(wrappedValue: s)
            _conversationStore = State(wrappedValue: cs)
            _appModel = State(wrappedValue: m)
            _gatewayVM = State(wrappedValue: gvm)
            _chatVM = State(wrappedValue: cvm)
            return
        }

        // Normal launch: migrate legacy single-gateway UserDefaults if needed.
        let s = GatewayStore()
        s.migrateFromLegacyIfNeeded()

        // If no profiles exist at all, seed a default one.
        if s.profiles.isEmpty {
            _ = s.addProfile(name: "Local", url: "http://localhost:5111")
        }

        let cs = ConversationStore()
        let m = AppModel(store: s)
        let gvm = GatewayViewModel(appModel: m)
        let cvm = ChatViewModel(appModel: m, client: gvm.client, conversationStore: cs)

        _store = State(wrappedValue: s)
        _conversationStore = State(wrappedValue: cs)
        _appModel = State(wrappedValue: m)
        _gatewayVM = State(wrappedValue: gvm)
        _chatVM = State(wrappedValue: cvm)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(conversationStore)
                .environment(appModel)
                .environment(gatewayVM)
                .environment(chatVM)
                .tint(appModel.agentCard?.accentColor.flatMap(Color.init(hex:)) ?? .accentColor)
                .task {
                    await setupGateway()
                }
                .onReceive(memoryWarningPublisher) { _ in
                    chatVM.handleMemoryPressure()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await gatewayVM.connect() }
            }
        }
        .onChange(of: appModel.isPaired) { _, isPaired in
            // Skip during UI tests — the test harness pre-seeds the token directly.
            let args = CommandLine.arguments
            guard !args.contains("--uitesting"), !args.contains("--uitesting-paired") else { return }
            if isPaired {
                Task {
                    if let tok = (try? KeychainService.retrieveToken(for: appModel.gatewayURL)) ?? nil,
                       !tok.isEmpty {
                        await gatewayVM.client.setToken(tok)
                    }
                }
            } else {
                Task { await gatewayVM.client.setToken(nil) }
            }
        }
    }

    // MARK: - Memory pressure

    /// Publisher that fires when iOS sends a memory warning.
    /// Uses the UIApplication notification name via canImport to stay cross-platform safe.
    private var memoryWarningPublisher: NotificationCenter.Publisher {
        #if canImport(UIKit)
        return NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
        #else
        // Fallback for macOS / visionOS previews — never fires in practice.
        return NotificationCenter.default.publisher(for: Notification.Name("_NullClaw_NoOp_MemoryWarning"))
        #endif
    }

    @MainActor
    private func setupGateway() async {
        let args = CommandLine.arguments
        guard !args.contains("--uitesting"), !args.contains("--uitesting-paired") else { return }

        // Register the active profile ID so per-gateway slot tracking works from launch.
        if let profile = appModel.store.activeProfile {
            chatVM.setActiveProfile(profile)
        }

        // If a valid token exists for the active gateway, mark it paired.
        // The onChange(of: appModel.isPaired) observer will call setToken.
        if let tok = (try? KeychainService.retrieveToken(for: appModel.gatewayURL)) ?? nil,
           !tok.isEmpty {
            // Set token directly — the observer is guarded against UI-test args and this is
            // the normal launch path, so it will re-read and setToken. To avoid the double
            // Keychain read we set the token here and mark paired without going through isPaired's
            // setter (which would re-trigger the observer on the same run-loop pass).
            await gatewayVM.client.setToken(tok)
            if let id = appModel.store.activeProfileID ?? appModel.store.profiles.first?.id {
                appModel.store.setProfilePaired(id, isPaired: true)
            }
        } else {
            // No stored token — probe the gateway to see if pairing is disabled.
            // pair(code:) returns "" and sets pairingMode = .notRequired on a 403 response.
            let probeResult = try? await gatewayVM.client.pair(code: "")
            if probeResult == "" {
                // Gateway has require_pairing: false — mark paired without a token.
                if let id = appModel.store.activeProfileID ?? appModel.store.profiles.first?.id {
                    appModel.store.setProfilePaired(id, isPaired: true)
                }
            }
        }

        await gatewayVM.connect()
    }
}
