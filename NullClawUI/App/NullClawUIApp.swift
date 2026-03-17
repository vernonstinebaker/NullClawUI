import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

// MARK: - NullClawUIApp

@main
struct NullClawUIApp: App {
    @State private var store: GatewayStore
    @State private var conversationStore: ConversationStore
    @State private var appModel: AppModel
    @State private var gatewayVM: GatewayViewModel
    @State private var chatVM: ChatViewModel
    // Phase 13: periodic health monitor — nil during UI testing (no real gateway).
    @State private var healthMonitor: GatewayHealthMonitor? = nil
    // Phase 14: gateway status dashboard view model.
    @State private var statusVM: GatewayStatusViewModel
    @Environment(\.scenePhase) private var scenePhase

    // Shared SwiftData container — held here so it stays alive for the app lifetime.
    private let container: ModelContainer

    init() {
        let args = CommandLine.arguments

        // --uitesting-paired / --uitesting: use an in-memory container so tests
        // never touch the real CloudKit store.
        if args.contains("--uitesting-paired") || args.contains("--uitesting") {
            let cfg = ModelConfiguration(isStoredInMemoryOnly: true)
            let c = try! ModelContainer(for: GatewayProfile.self, ConversationRecord.self,
                                        configurations: cfg)
            container = c

            let fakeProfile = GatewayProfile(
                id: UUID(),
                name: args.contains("--uitesting-paired") ? "TestAgent" : "Local",
                url: "http://127.0.0.1:19999",
                isPaired: args.contains("--uitesting-paired")
            )
            let s = GatewayStore(testProfile: fakeProfile)
            let cs = ConversationStore(inMemory: true)
            let m = AppModel(store: s)

            if args.contains("--uitesting-paired") {
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
            }

            let gvm = GatewayViewModel(appModel: m)
            let cvm = ChatViewModel(appModel: m, client: gvm.client, conversationStore: cs)
            let svm = GatewayStatusViewModel(store: s)
            _store = State(wrappedValue: s)
            _conversationStore = State(wrappedValue: cs)
            _appModel = State(wrappedValue: m)
            _gatewayVM = State(wrappedValue: gvm)
            _chatVM = State(wrappedValue: cvm)
            _statusVM = State(wrappedValue: svm)
            // healthMonitor stays nil for UI tests — no real gateway to poll.
            return
        }

        // Normal launch: create the CloudKit-backed SwiftData container.
        // The App Group container path ensures the future macOS menubar target can
        // share the same ModelContainer via the group identifier.
        let schema = Schema([GatewayProfile.self, ConversationRecord.self])
        let cloudKitConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        let c: ModelContainer
        do {
            c = try ModelContainer(for: schema, configurations: cloudKitConfig)
        } catch {
            // Fallback to local-only if CloudKit is unavailable (e.g., simulator without
            // a signed-in iCloud account, or unit-test host where Application Support
            // directory may not yet exist).
            do {
                let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                c = try ModelContainer(for: schema, configurations: localConfig)
            } catch {
                // Final fallback: in-memory only (test hosts, fresh simulators).
                let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                c = try! ModelContainer(for: schema, configurations: memConfig)
            }
        }
        container = c

        let ctx = c.mainContext
        let s = GatewayStore(context: ctx)

        // Migration chain: Phase 9 UserDefaults JSON → SwiftData, then legacy single-URL key.
        s.migrateFromUserDefaultsIfNeeded()
        s.migrateFromLegacyIfNeeded()

        // Seed a default profile if none exist after migration.
        if s.profiles.isEmpty {
            _ = s.addProfile(name: "Local", url: "http://localhost:5111")
        }

        let cs = ConversationStore(context: ctx)
        cs.migrateFromUserDefaultsIfNeeded()

        let m = AppModel(store: s)
        let gvm = GatewayViewModel(appModel: m)
        let cvm = ChatViewModel(appModel: m, client: gvm.client, conversationStore: cs)
        let svm = GatewayStatusViewModel(store: s)

        _store = State(wrappedValue: s)
        _conversationStore = State(wrappedValue: cs)
        _appModel = State(wrappedValue: m)
        _gatewayVM = State(wrappedValue: gvm)
        _chatVM = State(wrappedValue: cvm)
        _statusVM = State(wrappedValue: svm)
        // healthMonitor is created in setupGateway() so it can close over the @State
        // objects that are fully initialised by the time the first .task fires.
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(conversationStore)
                .environment(appModel)
                .environment(gatewayVM)
                .environment(chatVM)
                .environment(statusVM)
                .tint(appModel.agentCard?.accentColor.flatMap(Color.init(hex:)) ?? .accentColor)
                .task {
                    await setupGateway()
                }
                .onReceive(memoryWarningPublisher) { _ in
                    chatVM.handleMemoryPressure()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // Immediate check so the status badge updates without waiting for the
                // next 30 s tick. The monitor's loop itself also resumes from here.
                healthMonitor?.checkNow()
                healthMonitor?.start()
            case .background, .inactive:
                // Pause polling while backgrounded to conserve battery / network.
                healthMonitor?.stop()
            default:
                break
            }
        }
        .onChange(of: appModel.isPaired) { _, isPaired in
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

    private var memoryWarningPublisher: NotificationCenter.Publisher {
        #if canImport(UIKit)
        return NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
        #else
        return NotificationCenter.default.publisher(for: Notification.Name("_NullClaw_NoOp_MemoryWarning"))
        #endif
    }

    @MainActor
    private func setupGateway() async {
        let args = CommandLine.arguments
        guard !args.contains("--uitesting"), !args.contains("--uitesting-paired") else { return }

        if let profile = appModel.store.activeProfile {
            chatVM.setActiveProfile(profile)
        }

        if let tok = (try? KeychainService.retrieveToken(for: appModel.gatewayURL)) ?? nil,
           !tok.isEmpty {
            await gatewayVM.client.setToken(tok)
            if let id = appModel.store.activeProfileID ?? appModel.store.profiles.first?.id {
                appModel.store.setProfilePaired(id, isPaired: true)
            }
        } else {
            let probeResult = try? await gatewayVM.client.pair(code: "")
            if probeResult == "" {
                if let id = appModel.store.activeProfileID ?? appModel.store.profiles.first?.id {
                    appModel.store.setProfilePaired(id, isPaired: true)
                }
            }
        }

        // Initial connect (health + agent card fetch).
        await gatewayVM.connect()

        // Phase 13: start the health monitor after the initial connect so the first
        // status is always driven by the explicit connect() call above.
        // The monitor fires chatVM.beginStream() on reconnect only if a stream was
        // in-progress when the gateway went offline.
        healthMonitor = GatewayHealthMonitor(
            appModel: appModel,
            clientProvider: { [gatewayVM] in gatewayVM.client },
            onReconnect: { [chatVM] in
                // Resume a stream that was interrupted by a gateway outage.
                // Only restart if there is unsent/unfinished input — the user
                // would need to re-send in any other case.
                if chatVM.isStreaming {
                    chatVM.beginStream()
                }
            }
        )
        healthMonitor?.start()
    }
}
