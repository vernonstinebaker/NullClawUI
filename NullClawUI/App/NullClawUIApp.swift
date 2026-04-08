import OSLog
import SwiftData
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

private let appLog = Logger(subsystem: "com.nullclaw.NullClawUI", category: "AppInit")

// MARK: - NullClawUIApp

@main
struct NullClawUIApp: App {
    @State private var store: GatewayStore
    @State private var conversationStore: ConversationStore
    @State private var appModel: AppModel
    @State private var gatewayVM: GatewayViewModel
    @State private var chatVM: ChatViewModel
    /// Phase 13: periodic health monitor — nil during UI testing (no real gateway).
    @State private var healthMonitor: GatewayHealthMonitor? = nil
    /// Phase 14: gateway status dashboard view model.
    @State private var statusVM: GatewayStatusViewModel
    /// Tracks the in-flight setToken task spawned by the isPaired observer so we can
    /// cancel a previous one before starting a new one (avoids racing token writes).
    @State private var setTokenTask: Task<Void, Never>? = nil
    @Environment(\.scenePhase) private var scenePhase

    /// Shared SwiftData container — held here so it stays alive for the app lifetime.
    private let container: ModelContainer

    init() {
        let args = CommandLine.arguments

        // --uitesting-paired / --uitesting: use an in-memory container so tests
        // never touch the real CloudKit store.
        if
            args.contains("--uitesting-paired") || args.contains("--uitesting")
            || args.contains("--uitesting-paired-multi")
        {
            let cfg = ModelConfiguration(isStoredInMemoryOnly: true)
            let c = try! ModelContainer(
                for: GatewayProfile.self,
                ConversationRecord.self,
                configurations: cfg
            )
            container = c

            let isPaired = args.contains("--uitesting-paired") || args.contains("--uitesting-paired-multi")
            let fakeProfile = GatewayProfile(
                id: UUID(),
                name: isPaired ? "TestAgent" : "Local",
                url: "http://127.0.0.1:19999",
                isPaired: isPaired,
                requiresPairing: false // Test profiles don't require real pairing
            )
            let s = GatewayStore(testProfile: fakeProfile)

            // --uitesting-paired-multi: add a second gateway so the picker chevron appears.
            if args.contains("--uitesting-paired-multi") {
                _ = s.addProfile(name: "SecondAgent", url: "http://127.0.0.1:19998", requiresPairing: false)
            }

            let cs = ConversationStore(inMemory: true)
            let m = AppModel(store: s)

            if isPaired {
                m.isPaired = true
                m.isCheckingGateway = false
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
            // For unpaired UI tests, skip the probe — show SettingsView immediately.
            if !isPaired {
                m.isCheckingGateway = false
            }
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
            appLog.info("ModelContainer: CloudKit-backed store initialised.")
        } catch {
            // Fallback to local-only if CloudKit is unavailable (e.g., simulator without
            // a signed-in iCloud account).
            appLog
                .warning(
                    "ModelContainer: CloudKit init failed (\(error.localizedDescription, privacy: .public)); falling back to local SQLite."
                )
            do {
                // Explicit URL keeps the store in Application Support — never in-memory.
                // Using the url: overload of ModelConfiguration pins the SQLite file path.
                let storeURL = URL.applicationSupportDirectory
                    .appending(path: "NullClawUI", directoryHint: .isDirectory)
                    .appending(path: "default.store")
                try FileManager.default.createDirectory(
                    at: storeURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let localConfig = ModelConfiguration(
                    "NullClawUI",
                    schema: schema,
                    url: storeURL,
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
                c = try ModelContainer(for: schema, configurations: localConfig)
                appLog.info("ModelContainer: local SQLite store at \(storeURL.path, privacy: .public).")
            } catch {
                // This should never happen on a real device; only on unit-test hosts where
                // Application Support is sandboxed away. Log prominently so we know.
                appLog
                    .error(
                        "ModelContainer: local SQLite init also failed (\(error.localizedDescription, privacy: .public)); using in-memory store — DATA WILL NOT PERSIST."
                    )
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
        // Fix requiresPairing for open (no-token) gateways that pre-date this field.
        s.migrateOpenGatewayFlagsIfNeeded()

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
            setTokenTask?.cancel()
            if isPaired {
                setTokenTask = Task {
                    if
                        let tok = try? KeychainService.retrieveToken(for: appModel.gatewayURL),
                        !tok.isEmpty
                    {
                        await gatewayVM.client.setToken(tok)
                    }
                }
            } else {
                setTokenTask = Task { await gatewayVM.client.setToken(nil) }
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

        if
            let tok = try? KeychainService.retrieveToken(for: appModel.gatewayURL),
            !tok.isEmpty
        {
            await gatewayVM.client.setToken(tok)
            if let id = appModel.store.activeProfileID ?? appModel.store.profiles.first?.id {
                appModel.store.setProfilePaired(id, isPaired: true)
            }
        } else {
            let probeResult = try? await gatewayVM.client.pair(code: "")
            if probeResult?.isEmpty == true {
                // Gateway returned 403 — open gateway, no token needed.
                // Mark requiresPairing=false so updateProfile never re-derives isPaired
                // from the Keychain (which would clobber it since no token is stored).
                if let id = appModel.store.activeProfileID ?? appModel.store.profiles.first?.id {
                    appModel.store.setProfileRequiresPairing(id, requiresPairing: false)
                    appModel.store.setProfilePaired(id, isPaired: true)
                }
            }
        }

        // Probe complete — ContentView can now route to MainTabView or SettingsView.
        appModel.isCheckingGateway = false

        // Initial connect (health + agent card fetch).
        await gatewayVM.connect()

        // Phase 13: start the health monitor after the initial connect so the first
        // status is always driven by the explicit connect() call above.
        // The monitor fires chatVM.beginStream() on reconnect only if a stream was
        // in-progress when the gateway went offline.
        healthMonitor = GatewayHealthMonitor(
            appModel: appModel,
            clientProvider: { [gatewayVM] in gatewayVM.client },
            onReconnect: { [weak chatVM] in
                // Resume a stream that was interrupted by a gateway outage.
                // Only restart if there is unsent/unfinished input — the user
                // would need to re-send in any other case.
                guard let chatVM else { return }
                if chatVM.isStreaming {
                    chatVM.beginStream()
                }
            }
        )
        healthMonitor?.start()
    }
}
