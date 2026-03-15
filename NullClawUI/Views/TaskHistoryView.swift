import SwiftUI

// MARK: - TaskHistoryView

/// Shows locally-persisted conversation records with timestamps, gateway name, and title.
/// Each record may link to a server-side task; tapping one reloads the conversation.
struct TaskHistoryView: View {
    var viewModel: ChatViewModel
    @Environment(ConversationStore.self) private var conversationStore

    var body: some View {
        NavigationStack {
            Group {
                if conversationStore.records.isEmpty {
                    emptyState
                } else {
                    recordList
                }
            }
            .navigationTitle("History")
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

    // MARK: - Record list

    private var recordList: some View {
        List(conversationStore.records) { record in
            Button {
                if let taskID = record.serverTaskID {
                    Task { await viewModel.loadTask(id: taskID) }
                } else {
                    // Empty session — just clear the chat to let the user start fresh
                    viewModel.messages.removeAll()
                    viewModel.activeTaskID = nil
                    viewModel.activeContextID = nil
                    viewModel.chatTabRequested.toggle()
                }
            } label: {
                ConversationRow(record: record)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .accessibilityLabel("Conversation with \(record.gatewayName): \(record.title)")
            .accessibilityHint(record.serverTaskID != nil ? "Tap to reload this conversation in Chat" : "Tap to start a new conversation")
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - ConversationRow

private struct ConversationRow: View {
    let record: ConversationRecord

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

                HStack(spacing: 6) {
                    // Gateway badge
                    Text(record.gatewayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                        .foregroundStyle(Color.accentColor)

                    // Timestamp
                    Text(timestamp(for: record.startedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // Message count (if any)
                    if record.messageCount > 0 {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("\(record.messageCount) msg\(record.messageCount == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.quaternary)
        }
    }

    private func timestamp(for date: Date) -> String {
        let age = Date().timeIntervalSince(date)
        if age < 60 * 60 * 24 {
            // Within 24 h — relative
            return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
        } else {
            // Older — absolute
            return Self.absoluteFormatter.string(from: date)
        }
    }
}
