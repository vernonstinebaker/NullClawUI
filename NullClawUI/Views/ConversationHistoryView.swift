import SwiftUI

struct ConversationHistoryView: View {
    let viewModel: ChatViewModel
    let gatewayViewModel: GatewayViewModel

    @Environment(GatewayStore.self) private var store
    @Environment(ConversationStore.self) private var conversationStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var expandedRecordID: UUID?

    private var activeGatewayRecords: [ConversationRecord] {
        guard let activeID = store.activeProfile?.id else { return [] }
        let records = conversationStore.records
            .filter { $0.gatewayProfileID == activeID }
            .sorted { $0.lastMessageAt > $1.lastMessageAt }
        if searchText.isEmpty { return records }
        return records.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.lastMessagePreview ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if activeGatewayRecords.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Conversations",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(searchText.isEmpty
                            ? "Conversations will appear here after you start chatting."
                            : "No conversations match \"\(searchText)\"."
                        )
                    )
                }
            } else {
                ForEach(activeGatewayRecords) { record in
                    recordRow(record)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search conversations")
        .navigationTitle("Conversations")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func recordRow(_ record: ConversationRecord) -> some View {
        let isActive = viewModel.activeRecordID == record.id

        Button {
            guard !isActive else { return }
            Task {
                await viewModel.openRecord(record, gatewayViewModel: gatewayViewModel)
                dismiss()
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title)
                        .font(.subheadline.weight(isActive ? .bold : .regular))
                        .foregroundStyle(isActive ? Color.accentColor : .primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(record.lastMessageAt, style: .relative)
                            .font(.caption2)
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(record.messageCount) messages")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)

                    if
                        expandedRecordID == record.id,
                        let preview = record.lastMessagePreview, !preview.isEmpty
                    {
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .padding(.top, 2)
                    }
                }

                Spacer()

                if isActive {
                    Image(systemName: "text.bubble.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                viewModel.deleteRecord(id: record.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                withAnimation(.spring(duration: 0.25)) {
                    expandedRecordID = expandedRecordID == record.id ? nil : record.id
                }
            } label: {
                Label(
                    expandedRecordID == record.id ? "Collapse" : "Expand",
                    systemImage: expandedRecordID == record.id ? "chevron.up" : "chevron.down"
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(record.title), \(record.messageCount) messages, \(isActive ? "active" : record.lastMessageAt.formatted(.relative(presentation: .named)))"
        )
        .accessibilityHint(isActive ? "Currently loaded in chat" : "Tap to load this conversation")
    }
}
