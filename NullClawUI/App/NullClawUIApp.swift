import SwiftUI

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
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await gatewayVM.connect() }
            }
        }
        .onChange(of: appModel.isPaired) { _, isPaired in
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

    @MainActor
    private func setupGateway() async {
        let args = CommandLine.arguments
        guard !args.contains("--uitesting"), !args.contains("--uitesting-paired") else { return }

        if let tok = (try? KeychainService.retrieveToken(for: appModel.gatewayURL)) ?? nil,
           !tok.isEmpty {
            await gatewayVM.client.setToken(tok)
            appModel.isPaired = true
            // Create a new session record for this app launch.
            if let profile = appModel.store.activeProfile {
                chatVM.ensureSessionRecord(gateway: profile)
            }
        }

        await gatewayVM.connect()
    }
}
