import SwiftUI

/// Phase 5: Task history list.
struct TaskHistoryView: View {
    var viewModel: ChatViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.taskSummaries.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        description: Text("Previous conversations will appear here.")
                    )
                } else {
                    List(viewModel.taskSummaries) { summary in
                        Button {
                            Task { await viewModel.loadTask(id: summary.id) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(summary.id)
                                        .font(.caption.monospaced())
                                        .lineLimit(1)
                                    Text(summary.status.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .accessibilityLabel("Task \(summary.id), status: \(summary.status)")
                        .accessibilityHint("Tap to reload this conversation in Chat")
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.loadTaskHistory() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh task history")
                }
            }
            .task {
                await viewModel.loadTaskHistory()
            }
        }
    }
}
