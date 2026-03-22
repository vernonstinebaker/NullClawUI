import Foundation
import Observation
import UIKit

// MARK: - ChatAttachment (local UI model)

/// Represents a user-selected image or file that will be sent as an inlineData part.
struct ChatAttachment: Identifiable, Sendable {
    let id: UUID
    let mimeType: String
    let data: Data          // raw bytes; base64-encoded when building MessagePart

    init(mimeType: String, data: Data) {
        self.id = UUID()
        self.mimeType = mimeType
        self.data = data
    }

    /// Convenience: build the corresponding A2A MessagePart.
    var messagePart: MessagePart {
        MessagePart(inlineData: InlineData(mimeType: mimeType, data: data.base64EncodedString()))
    }
}

// MARK: - ChatMessage (local UI model)

struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: String   // "user" | "assistant"
    var text: String
    var isStreaming: Bool = false
    /// Image/file attachments carried by this message (user-sent or inbound inlineData parts).
    var attachments: [ChatAttachment] = []

    init(role: String, text: String, isStreaming: Bool = false, attachments: [ChatAttachment] = []) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
        self.attachments = attachments
    }
}

// MARK: - GatewaySlot
// Captures the full conversation state for one local history record.

private struct GatewaySlot {
    var messages: [ChatMessage]
    var activeTaskID: String?
    var activeContextID: String?
}

// MARK: - LRU slot cache
// Keeps at most maxSlots full conversation transcripts in memory.
// When the cap is reached, the least-recently-used entry is evicted.
private struct SlotCache {
    static let maxSlots = 10
    /// Ordered from most-recently-used (index 0) to least (last).
    private var order: [UUID] = []
    private var dict:  [UUID: GatewaySlot] = [:]

    subscript(id: UUID) -> GatewaySlot? {
        get { dict[id] }
    }

    mutating func store(_ slot: GatewaySlot, for id: UUID) {
        // Move to front (or insert).
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        dict[id] = slot
        // Evict LRU entries beyond the cap.
        while order.count > Self.maxSlots {
            let evicted = order.removeLast()
            dict.removeValue(forKey: evicted)
        }
    }

    mutating func remove(_ id: UUID) {
        order.removeAll { $0 == id }
        dict.removeValue(forKey: id)
    }

    mutating func removeAll() {
        order.removeAll()
        dict.removeAll()
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
    /// Attachments staged by the user but not yet sent. Cleared after each send/stream.
    var pendingAttachments: [ChatAttachment] = []
    var isSending: Bool = false
    var isStreaming: Bool = false
    var activeTaskID: String? = nil
    /// The conversation context ID returned by the gateway on the first message.
    /// Passed on every subsequent send/stream so the gateway routes to the same session.
    var activeContextID: String? = nil
    var errorMessage: String? = nil
    /// Incremented on every streaming token append so the view can reliably auto-scroll.
    var scrollTick: Int = 0
    /// Incremented each time loadTask completes — observers switch to the Chat tab.
    /// Using an Int counter instead of a Bool toggle avoids SwiftUI missing rapid
    /// back-to-back changes when the value is set and reset in the same run-loop tick.
    var chatTabRequested: Int = 0
    /// True while a history record is being fetched from the server (openRecord → loadTask).
    var isLoadingHistory: Bool = false
    /// The record ID that is currently loaded in the chat — used to highlight the active row.
    var activeRecordID: UUID? = nil

    // MARK: - Per-record conversation slots
    // Keyed by ConversationRecord.id so reopening history restores the correct session.
    // Bounded to SlotCache.maxSlots (10) most-recently-used entries to cap memory use.
    private var recordSlots: SlotCache = SlotCache()
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
        recordSlots.store(GatewaySlot(messages: [], activeTaskID: nil, activeContextID: nil), for: record.id)
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
        let attachments = pendingAttachments
        guard (!text.isEmpty || !attachments.isEmpty), !isSending else { return }
        inputText = ""
        pendingAttachments = []
        isSending = true
        errorMessage = nil
        messages.append(ChatMessage(role: "user", text: text, attachments: attachments))

        // Lazily create a history record on the first send of a session.
        if let gateway = appModel.store.activeProfile {
            ensureRecordForSend(gateway: gateway)
        }

        // Update record title from first user message.
        conversationStore.updateCurrent(firstUserText: text, incrementMessages: true)

        // Build parts: text first (if non-empty), then one part per attachment.
        var parts: [MessagePart] = []
        if !text.isEmpty { parts.append(MessagePart(text: text, kind: "text")) }
        parts.append(contentsOf: attachments.map(\.messagePart))

        let userMessage = A2AMessage(role: "user",
                                     parts: parts,
                                     contextId: activeContextID)
        do {
            let task = try await client.sendMessage(userMessage)
            activeTaskID = task.id
            if let cid = task.contextId { activeContextID = cid }
            conversationStore.updateCurrent(serverTaskID: task.id, contextID: task.contextId)
            let replyText = task.replyText
            messages.append(ChatMessage(role: "assistant", text: replyText))
            conversationStore.updateCurrent(incrementMessages: true,
                                            lastMessagePreview: String(replyText.prefix(120)))
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
        // Cancel any orphaned task before spawning a new one.
        cancelStream()
        let task = Task { await stream() }
        streamTask = task
    }

    func stream() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard (!text.isEmpty || !attachments.isEmpty), !isStreaming else { return }
        inputText = ""
        pendingAttachments = []
        isStreaming = true
        errorMessage = nil
        messages.append(ChatMessage(role: "user", text: text, attachments: attachments))

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

        // Build parts: text first (if non-empty), then one part per attachment.
        var parts: [MessagePart] = []
        if !text.isEmpty { parts.append(MessagePart(text: text, kind: "text")) }
        parts.append(contentsOf: attachments.map(\.messagePart))

        let userMessage = A2AMessage(role: "user",
                                     parts: parts,
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
                let preview = assistantIndex.flatMap { $0 < messages.count ? messages[$0].text : nil }
                conversationStore.updateCurrent(incrementMessages: true,
                                                lastMessagePreview: preview.map { String($0.prefix(120)) })
                // After first assistant reply, upgrade title to a summary derived from the reply.
                if messages.filter({ $0.role == "assistant" }).count == 1,
                   let idx = assistantIndex,
                   idx < messages.count,
                   let derived = derivedTitle(from: messages[idx].text) {
                    conversationStore.setCurrentTitle(derived)
                }
                saveCurrentSlot()
                trimMessagesIfNeeded()
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
                // 413 means the upstream model rejected the payload — either the image
                // is too large for the provider, or the model does not support vision.
                // Retrying won't help; prompt the user to try a smaller image or a
                // different model. (The gateway body limit is now 20 MB so a 413 from
                // the gateway itself would only occur for very large files.)
                if case GatewayError.httpError(let code) = error, code == 413 {
                    errorMessage = "The model rejected this message (HTTP 413). "
                        + "Try a smaller image, or use a model that supports image attachments."
                    if let idx = assistantIndex, idx < messages.count {
                        messages[idx].isStreaming = false
                    }
                    break
                }
                // unpaired means no token is set — retrying will never succeed.
                if case GatewayError.unpaired = error {
                    errorMessage = "Not paired. Please configure and pair a gateway in Settings."
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
        pendingAttachments = []
        isSending = false
        isStreaming = false
        errorMessage = nil

        // 4. Restore the destination gateway's conversation slot (if any).
        activeProfileID = gateway.id
        if let recordID = activeRecordIDByGateway[gateway.id] ?? conversationStore.mostRecentRecord(for: gateway.id)?.id {
            activeRecordIDByGateway[gateway.id] = recordID
            activeRecordID = recordID
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
        activeRecordID = record.id

        if let taskID = record.serverTaskID {
            isLoadingHistory = true
            await loadTask(id: taskID, recordID: record.id)
            isLoadingHistory = false
        } else {
            restoreConversation(for: record.id)
            chatTabRequested += 1
        }
    }

    // MARK: - Per-record slot helpers

    private func saveCurrentSlot() {
        guard let recordID = conversationStore.current?.id else { return }
        recordSlots.store(GatewaySlot(
            messages: messages,
            activeTaskID: activeTaskID,
            activeContextID: activeContextID
        ), for: recordID)
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

    /// Maximum number of messages kept in memory for any single conversation.
    /// Older messages (from the top) are dropped when this limit is exceeded.
    static let maxMessages = 200

    /// Trims `messages` to `maxMessages`, dropping the oldest entries from the front.
    private func trimMessagesIfNeeded() {
        if messages.count > Self.maxMessages {
            messages.removeFirst(messages.count - Self.maxMessages)
        }
    }

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
                let attachments: [ChatAttachment] = msg.parts.compactMap { part in
                    guard let inline = part.inlineData,
                          let bytes = Data(base64Encoded: inline.data) else { return nil }
                    return ChatAttachment(mimeType: inline.mimeType, data: bytes)
                }
                return ChatMessage(role: role, text: text, attachments: attachments)
            }
            // Cap to maxMessages — server history may be very long.
            trimMessagesIfNeeded()
            activeTaskID = id
            // Restore the context ID so follow-up messages continue the same conversation.
            activeContextID = task.contextId ?? allMessages.first?.contextId

            saveCurrentSlot()

            // Signal iPhone TabView to switch to the Chat tab.
            chatTabRequested += 1
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
        activeRecordID = nil
        inputText = ""
        pendingAttachments = []
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

    // MARK: - Memory management

    /// Called when the user deletes a history record from the list.
    /// Evicts the in-memory slot and the gateway-lookup entry so stale data is released.
    func deleteRecord(id: UUID) {
        recordSlots.remove(id)
        // Remove the gateway pointer if it was pointing to this record.
        for (profileID, recordID) in activeRecordIDByGateway where recordID == id {
            activeRecordIDByGateway.removeValue(forKey: profileID)
        }
        conversationStore.delete(id: id)
        if activeRecordID == id {
            activeRecordID = nil
        }
    }

    /// Drops all cached slots to reclaim memory on app background / memory pressure.
    /// The current conversation's messages are preserved; all others are released.
    func handleMemoryPressure() {
        let currentID = conversationStore.current?.id
        // Persist the live conversation so it can be restored.
        saveCurrentSlot()
        // Wipe everything, then restore only the current slot.
        recordSlots.removeAll()
        if let id = currentID {
            recordSlots.store(GatewaySlot(
                messages: messages,
                activeTaskID: activeTaskID,
                activeContextID: activeContextID
            ), for: id)
        }
    }
}
