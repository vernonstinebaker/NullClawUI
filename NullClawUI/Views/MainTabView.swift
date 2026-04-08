import SwiftUI

// MARK: - Tab selection

enum AppTab: Hashable {
    case servers
    case chat
}

// MARK: - iPad Sidebar Selection

enum SidebarSelection: Hashable {
    case chat
    case servers
}

// MARK: - MainTabView

struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(GatewayStore.self) private var gatewayStore

    var gatewayViewModel: GatewayViewModel
    var chatViewModel: ChatViewModel

    @State private var sidebarSelection: SidebarSelection = .chat
    @State private var selectedTab: AppTab = .servers

    var body: some View {
        if horizontalSizeClass == .regular {
            ipadBody
        } else {
            iphoneBody
        }
    }

    // iPad: two-column NavigationSplitView.
    private var ipadBody: some View {
        NavigationSplitView {
            List {
                Section {
                    Button {
                        sidebarSelection = .chat
                    } label: {
                        Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                    }
                    .listRowBackground(sidebarSelection == .chat ? Color.accentColor.opacity(0.08) : nil)
                }

                Section("Servers") {
                    ForEach(gatewayStore.profiles) { profile in
                        Button {
                            sidebarSelection = .servers
                        } label: {
                            Label(profile.name, systemImage: "server.rack")
                        }
                        .listRowBackground(sidebarSelection == .servers ? Color.accentColor.opacity(0.08) : nil)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("NullClaw")
        } detail: {
            switch sidebarSelection {
            case .chat:
                ChatView(viewModel: chatViewModel, gatewayViewModel: gatewayViewModel)
            case .servers:
                NavigationStack {
                    ServersView()
                }
            }
        }
    }

    // iPhone: Servers (1st), Chat (2nd) — centered tab bar
    private var iphoneBody: some View {
        TabView(selection: $selectedTab) {
            Tab("Servers", systemImage: "server.rack", value: AppTab.servers) {
                NavigationStack {
                    ServersView()
                }
            }
            Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: AppTab.chat) {
                ChatView(viewModel: chatViewModel, gatewayViewModel: gatewayViewModel)
            }
        }
        .onChange(of: chatViewModel.chatTabRequested) { _, _ in
            selectedTab = .chat
        }
    }
}
