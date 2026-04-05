import SwiftUI

// MARK: - Tab selection

enum AppTab: Hashable {
    case servers
    case chat
    case search
}

// MARK: - iPad Sidebar Selection

enum SidebarSelection: Hashable {
    case servers
    case chat
}

// MARK: - MainTabView

struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(GatewayStore.self) private var gatewayStore

    var gatewayViewModel: GatewayViewModel
    var chatViewModel: ChatViewModel

    @State private var sidebarSelection: SidebarSelection = .servers
    @State private var selectedTab: AppTab = .servers
    @State private var previousTab: AppTab = .servers

    var body: some View {
        if horizontalSizeClass == .regular {
            ipadBody
        } else {
            iphoneBody
        }
    }

    // iPad: two-column NavigationSplitView.
    @ViewBuilder
    private var ipadBody: some View {
        NavigationSplitView {
            List {
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

                Section {
                    Button {
                        sidebarSelection = .chat
                    } label: {
                        Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                    }
                    .listRowBackground(sidebarSelection == .chat ? Color.accentColor.opacity(0.08) : nil)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("NullClaw")
        } detail: {
            switch sidebarSelection {
            case .servers:
                NavigationStack {
                    ServersView()
                }
            case .chat:
                ChatView(viewModel: chatViewModel, gatewayViewModel: gatewayViewModel)
            }
        }
    }

    // iPhone: Servers (1st), Chat (2nd), Search (3rd)
    @ViewBuilder
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
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchResultsView(chatViewModel: chatViewModel, sourceTab: previousTab)
            }
        }
        .onChange(of: selectedTab) { old, new in
            if old != .search {
                previousTab = old
            }
        }
        .onChange(of: chatViewModel.chatTabRequested) { _, _ in
            selectedTab = .chat
        }
    }
}

// MARK: - SearchResultsView

private struct SearchResultsView: View {
    var chatViewModel: ChatViewModel
    var sourceTab: AppTab

    @State private var searchText: String = ""
    @Environment(ConversationStore.self) private var conversationStore
    @Environment(GatewayStore.self) private var gatewayStore
    @Environment(GatewayViewModel.self) private var gatewayViewModel

    private var searchPrompt: String {
        switch sourceTab {
        case .chat: return "Search conversations"
        case .servers: return "Search servers"
        default: return "Search conversations & servers"
        }
    }

    private var showConversations: Bool { sourceTab != .servers }
    private var showServers: Bool { sourceTab != .chat }

    private var filteredRecords: [ConversationRecord] {
        guard showConversations else { return [] }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return conversationStore.records }
        return conversationStore.records.filter {
            $0.title.lowercased().contains(q) || $0.gatewayName.lowercased().contains(q)
        }
    }

    private var filteredProfiles: [GatewayProfile] {
        guard showServers else { return [] }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return gatewayStore.profiles }
        return gatewayStore.profiles.filter {
            $0.name.lowercased().contains(q) || $0.displayHost.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Search",
                        systemImage: "magnifyingglass",
                        description: Text(emptyPromptDescription)
                    )
                } else if filteredRecords.isEmpty && filteredProfiles.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        if !filteredRecords.isEmpty {
                            Section("Conversations") {
                                ForEach(filteredRecords) { record in
                                    let isActive = chatViewModel.activeRecordID == record.id
                                    let isLoading = isActive && chatViewModel.isLoadingHistory
                                    Button {
                                        guard !chatViewModel.isLoadingHistory else { return }
                                        Task { await chatViewModel.openRecord(record, gatewayViewModel: gatewayViewModel) }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Circle()
                                                .fill(Color.accentColor.opacity(0.12))
                                                .frame(width: 36, height: 36)
                                                .overlay {
                                                    Image(systemName: "bubble.left.and.bubble.right.fill")
                                                        .font(.system(size: 14, weight: .medium))
                                                        .foregroundStyle(Color.accentColor)
                                                }
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(record.title)
                                                    .font(.subheadline.weight(.medium))
                                                    .lineLimit(1)
                                                Text(record.gatewayName)
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(Color.accentColor)
                                            }
                                            Spacer(minLength: 0)
                                            if isLoading {
                                                ProgressView().controlSize(.small)
                                            } else if isActive {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(Color.accentColor)
                                                    .font(.caption)
                                            }
                                        }
                                    }
                                    .accessibilityLabel("Conversation: \(record.title) on \(record.gatewayName)")
                                    .accessibilityHint("Tap to open this conversation in Chat")
                                }
                            }
                        }
                        if !filteredProfiles.isEmpty {
                            Section("Servers") {
                                ForEach(filteredProfiles) { profile in
                                    NavigationLink {
                                        GatewayDetailView(profile: profile)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Circle()
                                                .fill(Color(.systemFill))
                                                .frame(width: 36, height: 36)
                                                .overlay {
                                                    Image(systemName: "server.rack")
                                                        .font(.system(size: 14, weight: .medium))
                                                        .foregroundStyle(.secondary)
                                                }
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(profile.name)
                                                    .font(.subheadline.weight(.medium))
                                                Text(profile.displayHost)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .accessibilityLabel("Server: \(profile.name) at \(profile.displayHost)")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: searchPrompt)
        }
    }

    private var emptyPromptDescription: String {
        switch sourceTab {
        case .chat: return "Search your conversation history."
        case .servers: return "Search your configured servers."
        default: return "Search conversations and servers."
        }
    }
}
