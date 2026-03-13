import Foundation
import Observation

// MARK: - ChatMessage (local UI model)

struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: String   // "user" | "assistant"
    var text: String
    var isStreaming: Bool = false

    init(role: String, text: String, isStreaming: Bool = false) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
    }
}

// MARK: - ChatViewModel

/// Drives Phases 3–5: sending/streaming messages and task history.
@Observable
@MainActor
final class ChatViewModel {
    var appModel: AppModel
    var client: GatewayClient

    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isSending: Bool = false
    var isStreaming: Bool = false
    var activeTaskID: String? = nil
    var errorMessage: String? = nil

    // Phase 5
    var taskSummaries: [TaskSummary] = []

    init(appModel: AppModel, client: GatewayClient) {
        self.appModel = appModel
        self.client = client
    }

    // MARK: - Phase 3: send (non-streaming)

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        inputText = ""
        isSending = true
        errorMessage = nil
        messages.append(ChatMessage(role: "user", text: text))

        let userMessage = A2AMessage(role: "user", parts: [MessagePart(text: text, kind: "text")])
        do {
            let task = try await client.sendMessage(userMessage)
            activeTaskID = task.id
            let replyText = task.replyText
            messages.append(ChatMessage(role: "assistant", text: replyText))
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }

    // MARK: - Phase 4: stream

    func stream() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        inputText = ""
        isStreaming = true
        errorMessage = nil
        messages.append(ChatMessage(role: "user", text: text))

        var assistantIndex: Int? = nil
        var retries = 0
        let maxRetries = 3

        let userMessage = A2AMessage(role: "user", parts: [MessagePart(text: text, kind: "text")])

        while retries <= maxRetries {
            do {
                let stream = try await client.streamMessageBytes(userMessage)

                // Insert streaming placeholder on first attempt
                if assistantIndex == nil {
                    messages.append(ChatMessage(role: "assistant", text: "", isStreaming: true))
                    assistantIndex = messages.count - 1
                }

                for try await event in stream {
                    guard let result = event.result else { continue }
                    if let idx = assistantIndex {
                        switch result.kind {
                        case "artifact-update":
                            if let parts = result.artifact?.parts {
                                let text = parts.compactMap { $0.text }.joined()
                                if result.append == true {
                                    messages[idx].text += text
                                } else {
                                    messages[idx].text = text
                                }
                            }
                        case "status-update":
                            if result.final == true {
                                messages[idx].isStreaming = false
                            }
                        case "task":
                            if let taskId = result.id, activeTaskID == nil {
                                activeTaskID = taskId
                            }
                        default:
                            break
                        }
                    }
                    // Capture task ID from any event
                    if let taskId = result.taskId, activeTaskID == nil {
                        activeTaskID = taskId
                    }
                }
                // Successfully finished
                if let idx = assistantIndex { messages[idx].isStreaming = false }
                break

            } catch {
                retries += 1
                if retries > maxRetries {
                    errorMessage = "Stream failed after \(maxRetries) retries: \(error.localizedDescription)"
                    if let idx = assistantIndex { messages[idx].isStreaming = false }
                } else {
                    // Exponential backoff
                    try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retries - 1))) * 1_000_000_000)
                }
            }
        }
        isStreaming = false
    }

    // MARK: - Phase 5: abort

    func abort() async {
        guard let id = activeTaskID else { return }
        do {
            try await client.cancelTask(id: id)
            activeTaskID = nil
            isStreaming = false
            if let last = messages.indices.last { messages[last].isStreaming = false }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Phase 5: task history

    func loadTaskHistory() async {
        do {
            taskSummaries = try await client.listTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTask(id: String) async {
        do {
            let task = try await client.getTask(id: id)
            // Server returns history with role "user" and "agent" (not "assistant").
            // Map "agent" → "assistant" so the chat UI renders it correctly.
            messages = (task.history ?? task.messages ?? []).map { msg in
                let role = msg.role == "agent" ? "assistant" : msg.role
                let text = msg.parts.compactMap { $0.text }.joined()
                return ChatMessage(role: role, text: text)
            }
            activeTaskID = id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
