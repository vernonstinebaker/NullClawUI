import SwiftUI

// MARK: - Tab selection

/// Tab identifiers for the iPhone tab bar.
/// .search is used only to remember which tab the user was on before
/// tapping the search tab — it is not used as a TabView selection value.
enum AppTab: Hashable {
    case chat
    case history
    case settings
    case search
}

// MARK: - iPad Sidebar Selection

/// Identifies what is selected in the iPad sidebar.
enum SidebarSelection: Hashable {
    case history
    case settings
}

// MARK: - MainTabView

/// Phase 6: adaptive layout (Sidebar on iPad, Stack/Tabs on iPhone).
struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var gatewayViewModel: GatewayViewModel
    var chatViewModel: ChatViewModel

    // For SplitView navigation
    @State private var selectedTaskID: String? = nil
    /// iPad sidebar selection: .history (default) or .settings.
    @State private var sidebarSelection: SidebarSelection = .history
    // For iPhone TabView — tracks the active tab so we can switch to Chat programmatically.
    @State private var selectedTab: AppTab = .chat
    // Remembers which content tab was active before the user tapped Search,
    // so SearchResultsView can scope its results to the relevant context.
    @State private var previousTab: AppTab = .chat

    var body: some View {
        if horizontalSizeClass == .regular {
            ipadBody
        } else {
            iphoneBody
        }
    }

    // iPad: two-column NavigationSplitView.
    //   Column 1 (sidebar):  conversation history list + gear button
    //   Column 2 (detail):   chat view (default) — switches to PairedSettingsView when gear is tapped
    //
    // Using two columns instead of three avoids an empty content column in history mode.
    // Settings occupies the full detail area; when closed the chat view returns.
    // NOTE: No unit test — pure layout change; covered by visual inspection in Simulator.
    @ViewBuilder
    private var ipadBody: some View {
        NavigationSplitView {
            SidebarView(
                viewModel: chatViewModel,
                gatewayViewModel: gatewayViewModel,
                selectedTaskID: $selectedTaskID,
                sidebarSelection: $sidebarSelection
            )
        } detail: {
            switch sidebarSelection {
            case .settings:
                // Wrap in NavigationStack so gateway detail NavigationLinks work inside.
                NavigationStack {
                    PairedSettingsView()
                }
            case .history:
                ChatView(viewModel: chatViewModel, gatewayViewModel: gatewayViewModel)
            }
        }
    }

    // iPhone: plain TabView with Tab(role: .search) following the Apple WishList sample pattern.
    // No .tabViewStyle(.sidebarAdaptable) — that style routes .searchable into every nav bar.
    // The search tab tracks which content tab was previously selected so results are scoped.
    // NOTE: No pure layout test — covered by visual inspection in Simulator.
    @ViewBuilder
    private var iphoneBody: some View {
        TabView(selection: $selectedTab) {
            Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: AppTab.chat) {
                ChatView(viewModel: chatViewModel, gatewayViewModel: gatewayViewModel)
            }
            Tab("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90", value: AppTab.history) {
                TaskHistoryView(viewModel: chatViewModel)
            }
            Tab("Settings", systemImage: "gear", value: AppTab.settings) {
                // NavigationStack is required here since PairedSettingsView no longer
                // wraps itself (on iPad, the NavigationSplitView content column provides it).
                NavigationStack {
                    PairedSettingsView()
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchResultsView(chatViewModel: chatViewModel, sourceTab: previousTab)
            }
        }
        .onChange(of: selectedTab) { old, new in
            // Remember the last non-search tab so SearchResultsView can scope results.
            if old != .search {
                previousTab = old
            }
        }
        .onChange(of: chatViewModel.chatTabRequested) { _, _ in
            selectedTab = .chat
        }
    }
}

private struct SidebarView: View {
    var viewModel: ChatViewModel
    var gatewayViewModel: GatewayViewModel
    @Binding var selectedTaskID: String?
    @Binding var sidebarSelection: SidebarSelection
    @Environment(ConversationStore.self) private var conversationStore
    @Environment(GatewayStore.self) private var gatewayStore

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        List {
            Section("Current Chat") {
                Button {
                    selectedTaskID = nil
                    if let profile = gatewayStore.activeProfile {
                        viewModel.startNewConversation(gateway: profile)
                    } else {
                        viewModel.clearCurrentConversation()
                    }
                } label: {
                    Label("New Conversation", systemImage: "plus.message")
                }
            }

            Section("History") {
                if conversationStore.records.isEmpty {
                    Text("No previous conversations.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(conversationStore.records) { record in
                        let isActive  = viewModel.activeRecordID == record.id
                        let isLoading = isActive && viewModel.isLoadingHistory
                        Button {
                            guard !viewModel.isLoadingHistory else { return }
                            selectedTaskID = record.serverTaskID
                            Task { await viewModel.openRecord(record, gatewayViewModel: gatewayViewModel) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.title)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                        .foregroundStyle(isActive ? Color.accentColor : .primary)
                                    HStack(spacing: 5) {
                                        Text(record.gatewayName)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)
                                        Text("·")
                                            .font(.caption2)
                                            .foregroundStyle(.quaternary)
                                        Text(relativeTimestamp(for: record.startedAt))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if isLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                } else if isActive {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                        .font(.caption)
                                }
                            }
                        }
                        .listRowBackground(isActive ? Color.accentColor.opacity(0.08) : nil)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("NullClaw")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // Toggle between history and settings in the content column.
                    sidebarSelection = sidebarSelection == .settings ? .history : .settings
                } label: {
                    Label("Settings", systemImage: sidebarSelection == .settings ? "gear.badge.checkmark" : "gear")
                }
                .accessibilityLabel(sidebarSelection == .settings ? "Close Settings" : "Open Settings")
            }
        }
    }

    private func relativeTimestamp(for date: Date) -> String {
        let age = Date().timeIntervalSince(date)
        if age < 60 * 60 * 24 {
            return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return Self.absoluteFormatter.string(from: date)
    }
}

// MARK: - SearchResultsView

/// Content shown in the dedicated search tab (Tab role: .search).
/// Follows the Apple WishList sample pattern: .searchable is placed on the
/// NavigationStack inside this view, not on the TabView. This confines the
/// search bar to this tab only — no leakage into other tabs' nav bars.
///
/// Results are scoped to the tab the user came from:
///   • History → search conversations only
///   • Settings → search gateways only
///   • Chat (or unknown) → search both
private struct SearchResultsView: View {
    var chatViewModel: ChatViewModel
    /// The tab that was active before the user tapped Search.
    var sourceTab: AppTab

    @State private var searchText: String = ""
    @Environment(ConversationStore.self) private var conversationStore
    @Environment(GatewayStore.self) private var gatewayStore
    @Environment(GatewayViewModel.self) private var gatewayViewModel

    private var searchPrompt: String {
        switch sourceTab {
        case .history: return "Search conversations"
        case .settings: return "Search gateways"
        default: return "Search conversations & gateways"
        }
    }

    private var showConversations: Bool { sourceTab != .settings }
    private var showGateways: Bool { sourceTab != .history }

    private var filteredRecords: [ConversationRecord] {
        guard showConversations else { return [] }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return conversationStore.records }
        return conversationStore.records.filter {
            $0.title.lowercased().contains(q) || $0.gatewayName.lowercased().contains(q)
        }
    }

    private var filteredProfiles: [GatewayProfile] {
        guard showGateways else { return [] }
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
                            Section("Gateways") {
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
                                    .accessibilityLabel("Gateway: \(profile.name) at \(profile.displayHost)")
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
        case .history: return "Search your conversation history."
        case .settings: return "Search your configured gateways."
        default: return "Search conversations and gateways."
        }
    }
}
