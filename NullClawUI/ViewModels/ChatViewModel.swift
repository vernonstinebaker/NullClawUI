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

// MARK: - GatewaySlot
// Captures the full conversation state for one local history record.

private struct GatewaySlot {
    var messages: [ChatMessage]
    var activeTaskID: String?
    var activeContextID: String?
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
    /// Incremented on every streaming token append so the view can reliably auto-scroll.
    var scrollTick: Int = 0
    /// Toggled each time loadTask completes — observers switch to the Chat tab.
    var chatTabRequested: Bool = false

    // MARK: - Per-record conversation slots
    // Keyed by ConversationRecord.id so reopening history restores the correct session.
    private var recordSlots: [UUID: GatewaySlot] = [:]
    private var activeRecordIDByGateway: [UUID: UUID] = [:]

    // Currently active profile ID — needed to save the slot on switch.
    private var activeProfileID: UUID? = nil

    // Handle to the in-flight stream Task so we can cancel it before switching gateways.
    private var streamTask: Task<Void, Never>? = nil

    init(appModel: AppModel, client: GatewayClient, conversationStore: ConversationStore) {
        self.appModel = appModel
        self.client = client
        self.conversationStore = conversationStore
    }

    // MARK: - Conversation session management

    /// Starts a fresh conversation: saves current state to the record and resets UI.
    /// Call this from the "New Conversation" button instead of wiping state inline.
    func startNewConversation(gateway: GatewayProfile) {
        // Cancel any in-flight stream first.
        cancelStream()

        // Create a fresh record for the new conversation.
        let record = conversationStore.startNewRecord(gateway: gateway)
        activeProfileID = gateway.id
        activeRecordIDByGateway[gateway.id] = record.id
        clearCurrentConversation()
        recordSlots[record.id] = GatewaySlot(messages: [], activeTaskID: nil, activeContextID: nil)
    }

    /// Ensures a history record exists for the current gateway before the first send/stream.
    /// Creates one lazily if absent, or if the existing current record belongs to a different gateway.
    private func ensureRecordForSend(gateway: GatewayProfile) {
        if let current = conversationStore.current, current.gatewayProfileID == gateway.id {
            activeRecordIDByGateway[gateway.id] = current.id
            return  // existing record for this gateway — reuse it
        }
        let record = conversationStore.startNewRecord(gateway: gateway)
        activeRecordIDByGateway[gateway.id] = record.id
    }

    // MARK: - Phase 3: send (non-streaming)

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        inputText = ""
        isSending = true
        errorMessage = nil
        messages.append(ChatMessage(role: "user", text: text))

        // Lazily create a history record on the first send of a session.
        if let gateway = appModel.store.activeProfile {
            ensureRecordForSend(gateway: gateway)
        }

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
            saveCurrentSlot()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
    }

    // MARK: - Phase 4: stream

    /// Spawns the stream as a cancellable Task and stores the handle.
    /// Call this from the view instead of `Task { await stream() }`.
    func beginStream() {
        let task = Task { await stream() }
        streamTask = task
    }

    func stream() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        inputText = ""
        isStreaming = true
        errorMessage = nil
        messages.append(ChatMessage(role: "user", text: text))

        // Lazily create a history record on the first stream of a session.
        if let gateway = appModel.store.activeProfile {
            ensureRecordForSend(gateway: gateway)
        }

        // Update record title from first user message.
        conversationStore.updateCurrent(firstUserText: text, incrementMessages: true)

        var assistantIndex: Int? = nil
        var retries = 0
        let maxRetries = 3
        var receivedAnyStreamEvent = false

        let userMessage = A2AMessage(role: "user",
                                     parts: [MessagePart(text: text, kind: "text")],
                                     contextId: activeContextID)

        while retries <= maxRetries {
            // Check for cancellation (e.g. gateway switch mid-stream).
            if Task.isCancelled { break }

            do {
                let stream = try await client.streamMessage(userMessage)

                // Insert streaming placeholder on first attempt; clear text on retries to
                // avoid showing corrupted concatenated output from the failed attempt.
                if assistantIndex == nil {
                    messages.append(ChatMessage(role: "assistant", text: "", isStreaming: true))
                    assistantIndex = messages.count - 1
                } else if let idx = assistantIndex, idx < messages.count {
                    messages[idx].text = ""
                    messages[idx].isStreaming = true
                }

                for try await event in stream {
                    // Gateway switch may have wiped messages — stop processing.
                    if Task.isCancelled { break }

                    guard let result = event.result else { continue }
                    receivedAnyStreamEvent = true

                    // Always capture / update the context ID — some gateways
                    // only send it on the first event, others on every event.
                    if let cid = result.contextId {
                        if activeContextID != cid {
                            activeContextID = cid
                            conversationStore.updateCurrent(contextID: cid)
                        }
                    }

                    // Guard index in case messages were cleared by a gateway switch.
                    if let idx = assistantIndex, idx < messages.count {
                        switch result.kind {
                        case "artifact-update":
                            if let parts = result.artifact?.parts {
                                let chunk = parts.compactMap { $0.text }.joined()
                                if result.append == true {
                                    messages[idx].text += chunk
                                } else {
                                    messages[idx].text = chunk
                                }
                                // Notify the view to scroll for each new chunk of text.
                                scrollTick &+= 1
                            }
                        case "status-update":
                            // Mark streaming done on the final status event.
                            // Also handle the case where final is absent but the
                            // stream ended (loop exits below).
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

                if Task.isCancelled { break }

                // Stream ended (server closed connection). Ensure the placeholder
                // is no longer marked as streaming regardless of whether a
                // final=true status-update was received — some gateways omit it.
                if let idx = assistantIndex, idx < messages.count {
                    messages[idx].isStreaming = false
                }
                conversationStore.updateCurrent(incrementMessages: true)
                // After first assistant reply, upgrade title to a summary derived from the reply.
                if messages.filter({ $0.role == "assistant" }).count == 1,
                   let idx = assistantIndex,
                   idx < messages.count,
                   let derived = derivedTitle(from: messages[idx].text) {
                    conversationStore.setCurrentTitle(derived)
                }
                saveCurrentSlot()
                break

            } catch {
                if Task.isCancelled { break }
                // 401 is a permanent auth failure — retrying won't help.
                if case GatewayError.httpError(let code) = error, code == 401 {
                    errorMessage = "Authentication failed (401). Please re-pair the device in Settings."
                    appModel.isPaired = false
                    if let idx = assistantIndex, idx < messages.count {
                        messages[idx].isStreaming = false
                    }
                    break
                }
                if receivedAnyStreamEvent || activeTaskID != nil || activeContextID != nil {
                    errorMessage = "Stream interrupted: \(error.localizedDescription)"
                    if let idx = assistantIndex, idx < messages.count {
                        messages[idx].isStreaming = false
                    }
                    saveCurrentSlot()
                    break
                }
                retries += 1
                if retries > maxRetries {
                    errorMessage = "Stream failed after \(maxRetries) retries: \(error.localizedDescription)"
                    if let idx = assistantIndex, idx < messages.count {
                        messages[idx].isStreaming = false
                    }
                } else {
                    // Exponential backoff
                    try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retries - 1))) * 1_000_000_000)
                }
            }
        }
        // Always clear the ViewModel-level streaming flag, and make sure any
        // in-flight placeholder bubble is also cleaned up (belt-and-suspenders).
        if let idx = assistantIndex, idx < messages.count, messages[idx].isStreaming {
            messages[idx].isStreaming = false
        }
        isStreaming = false
    }

    // MARK: - Phase 9: gateway switch

    /// Called when the user switches to a different gateway profile.
    /// Saves current conversation state, cancels any in-flight stream,
    /// then restores (or starts fresh) the destination gateway's conversation.
    func resetForNewGateway(client newClient: GatewayClient, gateway: GatewayProfile) {
        // 1. Persist the current conversation into its slot before wiping anything.
        saveCurrentSlot()

        // 2. Cancel any in-flight stream — this sets Task.isCancelled on the
        //    stream() task, so the SSE loop will exit cleanly without touching
        //    the now-replaced messages array.
        cancelStream()

        // 3. Switch client and clear transient send/stream flags.
        client = newClient
        inputText = ""
        isSending = false
        isStreaming = false
        errorMessage = nil

        // 4. Restore the destination gateway's conversation slot (if any).
        activeProfileID = gateway.id
        if let recordID = activeRecordIDByGateway[gateway.id] ?? conversationStore.mostRecentRecord(for: gateway.id)?.id {
            activeRecordIDByGateway[gateway.id] = recordID
            conversationStore.activate(id: recordID)
            restoreConversation(for: recordID)
        } else {
            clearCurrentConversation()
        }

        // No record creation here — records are created lazily on the first send/stream
        // for this gateway. startNewConversation() remains the only explicit creator.
    }

    // MARK: - History opening

    func openRecord(_ record: ConversationRecord, gatewayViewModel: GatewayViewModel) async {
        saveCurrentSlot()

        if let profile = appModel.store.profiles.first(where: { $0.id == record.gatewayProfileID }),
           profile.id != appModel.store.activeProfile?.id {
            let newClient = await gatewayViewModel.switchGateway(to: profile)
            resetForNewGateway(client: newClient, gateway: profile)
        }

        activeProfileID = record.gatewayProfileID
        activeRecordIDByGateway[record.gatewayProfileID] = record.id
        conversationStore.activate(id: record.id)

        if let taskID = record.serverTaskID {
            await loadTask(id: taskID, recordID: record.id)
        } else {
            restoreConversation(for: record.id)
            chatTabRequested.toggle()
        }
    }

    // MARK: - Per-record slot helpers

    private func saveCurrentSlot() {
        guard let recordID = conversationStore.current?.id else { return }
        recordSlots[recordID] = GatewaySlot(
            messages: messages,
            activeTaskID: activeTaskID,
            activeContextID: activeContextID
        )
        if let profileID = conversationStore.current?.gatewayProfileID {
            activeRecordIDByGateway[profileID] = recordID
        }
    }

    /// Set the active profile ID on first connection (app launch / initial gateway).
    func setActiveProfile(_ profile: GatewayProfile) {
        guard activeProfileID == nil else { return }
        activeProfileID = profile.id
        if let recordID = conversationStore.current?.id,
           conversationStore.current?.gatewayProfileID == profile.id {
            activeRecordIDByGateway[profile.id] = recordID
        }
    }

    // MARK: - Cancel in-flight stream

    private func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
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

    private func loadTask(id: String, recordID: UUID? = nil) async {
        // Save the current slot so we can restore it if loadTask fails.
        let priorCurrentID = conversationStore.current?.id
        saveCurrentSlot()

        do {
            if let recordID {
                conversationStore.activate(id: recordID)
            } else if let record = conversationStore.record(serverTaskID: id) {
                conversationStore.activate(id: record.id)
                activeRecordIDByGateway[record.gatewayProfileID] = record.id
                activeProfileID = record.gatewayProfileID
            }
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

            saveCurrentSlot()

            // Signal iPhone TabView to switch to the Chat tab.
            chatTabRequested.toggle()
        } catch {
            // Restore the previous conversation on failure so the UI stays coherent.
            if let priorID = priorCurrentID {
                conversationStore.activate(id: priorID)
            }
            errorMessage = error.localizedDescription
        }
    }

    func clearCurrentConversation() {
        messages.removeAll()
        activeTaskID = nil
        activeContextID = nil
        inputText = ""
        errorMessage = nil
        isSending = false
        isStreaming = false
    }

    private func restoreConversation(for recordID: UUID) {
        if let slot = recordSlots[recordID] {
            messages = slot.messages
            activeTaskID = slot.activeTaskID
            activeContextID = slot.activeContextID
        } else if let record = conversationStore.record(id: recordID) {
            messages.removeAll()
            activeTaskID = record.serverTaskID
            activeContextID = record.contextID
        } else {
            clearCurrentConversation()
        }
        isSending = false
        isStreaming = false
        errorMessage = nil
    }
}
