import SwiftUI

/// Phase 6: adaptive layout (Sidebar on iPad, Stack/Tabs on iPhone).
struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(GatewayStatusViewModel.self) private var statusVM

    var gatewayViewModel: GatewayViewModel
    var chatViewModel: ChatViewModel

    // For SplitView navigation
    @State private var selectedTaskID: String? = nil
    @State private var showingSettings = false
    // For iPhone TabView — tracks the active tab so we can switch to Chat programmatically.
    @State private var selectedTab: Int = 0

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPadOS: SplitView
                NavigationSplitView {
                    SidebarView(
                        viewModel: chatViewModel,
                        gatewayViewModel: gatewayViewModel,
                        selectedTaskID: $selectedTaskID,
                        showingSettings: $showingSettings
                    )
                } detail: {
                    ChatView(viewModel: chatViewModel, gatewayViewModel: gatewayViewModel)
                }
            } else {
                // iPhone: TabView with programmatic tab selection.
                TabView(selection: $selectedTab) {
                    Tab("Chat", systemImage: "bubble.left.and.bubble.right.fill", value: 0) {
                        ChatView(viewModel: chatViewModel, gatewayViewModel: gatewayViewModel)
                    }
                    Tab("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90", value: 1) {
                        TaskHistoryView(viewModel: chatViewModel)
                    }
                    Tab("Status", systemImage: "gauge.with.dots.needle.67percent", value: 2) {
                        GatewayStatusView(statusVM: statusVM)
                    }
                    Tab("Settings", systemImage: "gear", value: 3) {
                        PairedSettingsView()
                    }
                }
                .onChange(of: chatViewModel.chatTabRequested) { _, _ in
                    // Switch to the Chat tab whenever a history task is loaded.
                    // Using an Int counter (not a Bool toggle) so rapid increments
                    // are never coalesced and dropped by SwiftUI.
                    selectedTab = 0
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            PairedSettingsView()
        }
    }
}

private struct SidebarView: View {
    var viewModel: ChatViewModel
    var gatewayViewModel: GatewayViewModel
    @Binding var selectedTaskID: String?
    @Binding var showingSettings: Bool
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
                Button { showingSettings = true } label: { Label("Settings", systemImage: "gear") }
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
