import SwiftUI

// MARK: - TaskHistoryView

/// Shows locally-persisted conversation records with timestamps, gateway name, and title.
/// Supports search/filter (pull-to-reveal), swipe-to-delete, and dual-format timestamps.
struct TaskHistoryView: View {
    var viewModel: ChatViewModel
    @Environment(ConversationStore.self) private var conversationStore
    @Environment(GatewayViewModel.self) private var gatewayViewModel

    @State private var searchText: String = ""

    private var filteredRecords: [ConversationRecord] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return conversationStore.records
        }
        let query = searchText.lowercased()
        return conversationStore.records.filter {
            $0.title.lowercased().contains(query) ||
            $0.gatewayName.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if conversationStore.records.isEmpty {
                    emptyState
                } else if filteredRecords.isEmpty {
                    noResultsState
                } else {
                    recordList
                }
            }
            .navigationTitle("History")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search conversations")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.quaternary)
                .symbolRenderingMode(.hierarchical)
            Text("No History Yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Previous conversations will appear here\nafter you send your first message.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - No search results state

    private var noResultsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.quaternary)
            Text("No Results")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("No conversations match \"\(searchText)\".")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Record list

    private var recordList: some View {
        List {
            ForEach(filteredRecords) { record in
                let isActive = viewModel.activeRecordID == record.id
                let isLoading = isActive && viewModel.isLoadingHistory

                Button {
                    guard !viewModel.isLoadingHistory else { return }
                    Task { await viewModel.openRecord(record, gatewayViewModel: gatewayViewModel) }
                } label: {
                    ConversationRow(record: record, isActive: isActive, isLoading: isLoading)
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
                .accessibilityLabel("Conversation with \(record.gatewayName): \(record.title)")
                .accessibilityHint(record.serverTaskID != nil ? "Tap to reload this conversation in Chat" : "Tap to start a new conversation")
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        // Use ChatViewModel.deleteRecord so the in-memory slot is
                        // also evicted, not just the persisted ConversationStore entry.
                        viewModel.deleteRecord(id: record.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - ConversationRow

private struct ConversationRow: View {
    let record: ConversationRecord
    var isActive: Bool = false
    var isLoading: Bool = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: record.serverTaskID != nil ? "bubble.left.and.bubble.right.fill" : "plus.bubble.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                // Gateway badge + message count
                HStack(spacing: 6) {
                    Text(record.gatewayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                        .foregroundStyle(Color.accentColor)

                    if record.messageCount > 0 {
                        Text("\(record.messageCount) msg\(record.messageCount == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Dual timestamp: relative + absolute
                Text(dualTimestamp(for: record.startedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            // Trailing indicator: spinner while loading, accent dot when active, chevron otherwise
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(width: 20)
        }
    }

    /// Returns "5 min ago · Mar 15, 2026, 3:45 PM" (both relative and absolute).
    /// For very recent items (< 60 s) just shows "Just now · <absolute>".
    private func dualTimestamp(for date: Date) -> String {
        let relative = Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
        let absolute = Self.absoluteFormatter.string(from: date)
        return "\(relative) · \(absolute)"
    }
}
