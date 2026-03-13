import SwiftUI

/// Phase 6: adaptive layout (Sidebar on iPad, Stack/Tabs on iPhone).
struct MainTabView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var chatVM: ChatViewModel?
    @State private var gatewayVM: GatewayViewModel?
    
    // For SplitView navigation
    @State private var selectedTaskID: String? = nil
    @State private var showingSettings = false

    var body: some View {
        Group {
            if let cvm = chatVM, let gvm = gatewayVM {
                if horizontalSizeClass == .regular {
                    // iPadOS: SplitView
                    NavigationSplitView {
                        SidebarView(viewModel: cvm, selectedTaskID: $selectedTaskID, showingSettings: $showingSettings)
                    } detail: {
                        ChatView(viewModel: cvm, gatewayViewModel: gvm)
                    }
                } else {
                    // iPhone: TabView
                    TabView {
                        Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill") {
                            ChatView(viewModel: cvm, gatewayViewModel: gvm)
                        }
                        Tab("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
                            TaskHistoryView(viewModel: cvm)
                        }
                        Tab("Settings", systemImage: "gear") {
                            PairedSettingsView(pairingVM: makePairingVM(gvm: gvm))
                        }
                    }
                }
            } else {
                ProgressView("Loading…")
            }
        }
        .sheet(isPresented: $showingSettings) {
            if let gvm = gatewayVM {
                PairedSettingsView(pairingVM: makePairingVM(gvm: gvm))
            }
        }
        .task {
            let gvm = GatewayViewModel(appModel: appModel)
            await gvm.connect()
            gatewayVM = gvm

            let token = (try? KeychainService.retrieveToken(for: appModel.gatewayURL)) ?? ""
            await gvm.client.setToken(token)

            chatVM = ChatViewModel(appModel: appModel, client: gvm.client)
        }
    }

    private func makePairingVM(gvm: GatewayViewModel) -> PairingViewModel {
        return PairingViewModel(appModel: appModel, client: gvm.client)
    }
}

private struct SidebarView: View {
    var viewModel: ChatViewModel
    @Binding var selectedTaskID: String?
    @Binding var showingSettings: Bool

    var body: some View {
        List {
            Section("Current Chat") {
                Button { 
                    selectedTaskID = nil 
                    viewModel.activeTaskID = nil
                    viewModel.messages.removeAll()
                } label: {
                    Label("New Conversation", systemImage: "plus.message")
                }
            }

            Section("History") {
                if viewModel.taskSummaries.isEmpty {
                    Text("No previous conversations.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(viewModel.taskSummaries) { summary in
                        Button {
                            selectedTaskID = summary.id
                            Task { await viewModel.loadTask(id: summary.id) }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(summary.id)
                                    .font(.caption.monospaced())
                                    .lineLimit(1)
                                Text(summary.statusLabel.capitalized)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("NullClaw")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingSettings = true } label: { Label("Settings", systemImage: "gear") }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button { Task { await viewModel.loadTaskHistory() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
        .task {
            await viewModel.loadTaskHistory()
        }
    }
}
