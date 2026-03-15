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
    private var conversationStore: ConversationStore

    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isSending: Bool = false
    var isStreaming: Bool = false
    var activeTaskID: String? = nil
    /// The conversation context ID returned by the gateway on the first message.
    /// Passed on every subsequent send/stream so the gateway routes to the same session.
    var activeContextID: String? = nil
    var errorMessage: String? = nil

    // Phase 5
    var taskSummaries: [TaskSummary] = []
    /// Derived titles keyed by task ID: first N chars of the first user message.
    var taskTitles: [String: String] = [:]
    /// Toggled each time loadTask completes — observers switch to the Chat tab.
    var chatTabRequested: Bool = false

    init(appModel: AppModel, client: GatewayClient, conversationStore: ConversationStore) {
        self.appModel = appModel
        self.client = client
        self.conversationStore = conversationStore
    }

    // MARK: - Conversation session management

    /// Ensures a session record exists for the current launch / gateway.
    /// Call on app launch (after isPaired is confirmed) and after a gateway switch.
    func ensureSessionRecord(gateway: GatewayProfile) {
        // Only create a new record if the most recent one has no messages yet
        // (avoids double-creating on repeated foreground cycles).
        if let current = conversationStore.current,
           current.gatewayProfileID == gateway.id,
           current.messageCount == 0 {
            return
        }
        conversationStore.startNewRecord(gateway: gateway)
    }

    /// Starts a fresh conversation: saves current state to the record and resets UI.
    /// Call this from the "New Conversation" button instead of wiping state inline.
    func startNewConversation(gateway: GatewayProfile) {
        // Create a fresh record for the new conversation.
        conversationStore.startNewRecord(gateway: gateway)

        // Wipe in-memory chat state.
        messages.removeAll()
        activeTaskID = nil
        activeContextID = nil
        inputText = ""
        errorMessage = nil
    }

    // MARK: - Phase 3: send (non-streaming)

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        inputText = ""
        isSending = true
        errorMessage = nil
        messages.append(ChatMessage(role: "user", text: text))

        // Update record title from first user message.
        conversationStore.updateCurrent(firstUserText: text, incrementMessages: true)

        let userMessage = A2AMessage(role: "user",
                                     parts: [MessagePart(text: text, kind: "text")],
                                     contextId: activeContextID)
        do {
            let task = try await client.sendMessage(userMessage)
            activeTaskID = task.id
            if let cid = task.contextId { activeContextID = cid }
            conversationStore.updateCurrent(serverTaskID: task.id, contextID: task.contextId)
            let replyText = task.replyText
            messages.append(ChatMessage(role: "assistant", text: replyText))
            conversationStore.updateCurrent(incrementMessages: true)
            // After first assistant reply, upgrade title to a summary derived from the reply.
            if messages.filter({ $0.role == "assistant" }).count == 1 {
                if let derived = derivedTitle(from: replyText) {
                    conversationStore.setCurrentTitle(derived)
                }
            }
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

        // Update record title from first user message.
        conversationStore.updateCurrent(firstUserText: text, incrementMessages: true)

        var assistantIndex: Int? = nil
        var retries = 0
        let maxRetries = 3

        let userMessage = A2AMessage(role: "user",
                                     parts: [MessagePart(text: text, kind: "text")],
                                     contextId: activeContextID)

        while retries <= maxRetries {
            do {
                let stream = try await client.streamMessage(userMessage)

                // Insert streaming placeholder on first attempt
                if assistantIndex == nil {
                    messages.append(ChatMessage(role: "assistant", text: "", isStreaming: true))
                    assistantIndex = messages.count - 1
                }

                for try await event in stream {
                    guard let result = event.result else { continue }
                    // Capture context ID as soon as it appears (first event)
                    if let cid = result.contextId, activeContextID == nil {
                        activeContextID = cid
                        conversationStore.updateCurrent(contextID: cid)
                    }
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
                                conversationStore.updateCurrent(serverTaskID: taskId)
                            }
                        default:
                            break
                        }
                    }
                    // Capture task ID from any event
                    if let taskId = result.taskId, activeTaskID == nil {
                        activeTaskID = taskId
                        conversationStore.updateCurrent(serverTaskID: taskId)
                    }
                }
                // Successfully finished — count the assistant reply
                if let idx = assistantIndex { messages[idx].isStreaming = false }
                conversationStore.updateCurrent(incrementMessages: true)
                // After first assistant reply, upgrade title to a summary derived from the reply.
                if messages.filter({ $0.role == "assistant" }).count == 1,
                   let idx = assistantIndex,
                   let derived = derivedTitle(from: messages[idx].text) {
                    conversationStore.setCurrentTitle(derived)
                }
                break

            } catch {
                // 401 is a permanent auth failure — retrying won't help.
                if case GatewayError.httpError(let code) = error, code == 401 {
                    errorMessage = "Authentication failed (401). Please re-pair the device in Settings."
                    appModel.isPaired = false
                    if let idx = assistantIndex { messages[idx].isStreaming = false }
                    break
                }
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

    // MARK: - Phase 9: gateway switch

    /// Called when the user switches to a different gateway profile.
    /// Clears all in-memory chat and task state and points the view model at the new client.
    func resetForNewGateway(client newClient: GatewayClient, gateway: GatewayProfile) {
        client = newClient
        messages.removeAll()
        taskSummaries.removeAll()
        taskTitles.removeAll()
        activeTaskID = nil
        activeContextID = nil
        inputText = ""
        isSending = false
        isStreaming = false
        errorMessage = nil
        // Start a new local record for the newly-selected gateway.
        conversationStore.startNewRecord(gateway: gateway)
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
            // Silently ignore history load errors — they are non-critical background refreshes.
            // Errors during send/stream are reported via errorMessage.
        }
    }

    // MARK: - Title derivation

    /// Derives a short, meaningful title from an assistant reply.
    /// Takes the first sentence (up to 80 chars), stripping markdown noise.
    /// Returns nil if the text is too short to be useful.
    private func derivedTitle(from text: String) -> String? {
        // Strip markdown headers, bullets, bold, italic markers
        let stripped = text
            .replacingOccurrences(of: #"#{1,6}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[*_`]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard stripped.count > 12 else { return nil }
        // Split on sentence-ending punctuation; take the first non-trivial sentence.
        let sentences = stripped.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        let first = sentences.first(where: { $0.trimmingCharacters(in: .whitespaces).count > 8 })
            ?? String(stripped.prefix(80))
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 8 else { return nil }
        return String(trimmed.prefix(80))
    }

    func loadTask(id: String) async {        do {
            let task = try await client.getTask(id: id)
            // Server returns history with role "user" and "agent" (not "assistant").
            // Map "agent" → "assistant" so the chat UI renders it correctly.
            let allMessages = (task.history ?? task.messages ?? [])
            messages = allMessages.map { msg in
                let role = msg.role == "agent" ? "assistant" : msg.role
                let text = msg.parts.compactMap { $0.text }.joined()
                return ChatMessage(role: role, text: text)
            }
            activeTaskID = id
            // Restore the context ID so follow-up messages continue the same conversation.
            activeContextID = task.contextId ?? allMessages.first?.contextId

            // Derive a human-readable title from the first user message.
            if taskTitles[id] == nil {
                let firstUserText = allMessages.first(where: { $0.role == "user" })?
                    .parts.compactMap { $0.text }.joined() ?? id
                let title = String(firstUserText.prefix(60))
                taskTitles[id] = title.isEmpty ? id : title
            }

            // Signal iPhone TabView to switch to the Chat tab.
            chatTabRequested.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
