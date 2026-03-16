import Foundation

// MARK: - ConversationRecord

/// A locally-persisted record of a single conversation session.
/// Created when a new conversation starts (app launch, new-conversation button, gateway switch).
/// Updated in place as messages are exchanged and when the bot generates a title.
struct ConversationRecord: Codable, Identifiable, Sendable {
    let id: UUID                    // local stable identity
    var serverTaskID: String?       // gateway task UUID — set on first send
    var contextID: String?          // gateway context/session ID — set on first SSE event

    // Gateway snapshot — taken at record creation so history survives profile edits.
    var gatewayProfileID: UUID
    var gatewayName: String
    var gatewayURL: String

    // Human-readable title: starts as "New Conversation", updated to first user msg,
    // then optionally replaced with an AI-generated summary once the first reply lands.
    var title: String

    var startedAt: Date             // when the record was created
    var lastMessageAt: Date         // updated on each send/stream completion
    var messageCount: Int           // total messages (user + assistant)
}

// MARK: - ConversationStore

private let conversationHistoryKey = "conversationHistory"
/// Maximum number of conversation records kept in UserDefaults.
/// The oldest records (at the end of the array) are pruned when this is exceeded.
private let maxConversationRecords = 100

/// Manages locally-persisted conversation records.
/// Parallels GatewayStore — same UserDefaults JSON approach, @Observable.
@Observable
@MainActor
final class ConversationStore {

    var records: [ConversationRecord] = []
    var currentRecordID: UUID? = nil

    // MARK: - Init

    init() {
        load()
    }

    /// Designated init for UI tests — empty store without touching UserDefaults.
    init(empty: Bool) {
        records = []
        currentRecordID = nil
    }

    // MARK: - Current record

    /// The most-recently-created record (the "active" conversation).
    var current: ConversationRecord? {
        guard let id = currentRecordID else { return records.first }
        return records.first(where: { $0.id == id }) ?? records.first
    }

    func record(id: UUID) -> ConversationRecord? {
        records.first(where: { $0.id == id })
    }

    func record(serverTaskID: String) -> ConversationRecord? {
        records.first(where: { $0.serverTaskID == serverTaskID })
    }

    func mostRecentRecord(for gatewayProfileID: UUID) -> ConversationRecord? {
        records.first(where: { $0.gatewayProfileID == gatewayProfileID })
    }

    // MARK: - Mutations

    /// Creates a new record for the given gateway profile and makes it the current one.
    /// If the current record is an unsent "New Conversation" for the same gateway, it is
    /// reused rather than creating a duplicate empty record.
    /// Returns the new (or reused) record.
    @discardableResult
    func startNewRecord(gateway: GatewayProfile) -> ConversationRecord {
        // Reuse if the current record is a blank placeholder for the same gateway.
        if let existing = current,
           existing.gatewayProfileID == gateway.id,
           existing.messageCount == 0,
           existing.title == "New Conversation" {
            return existing
        }
        let record = ConversationRecord(
            id: UUID(),
            serverTaskID: nil,
            contextID: nil,
            gatewayProfileID: gateway.id,
            gatewayName: gateway.name,
            gatewayURL: gateway.url,
            title: "New Conversation",
            startedAt: Date(),
            lastMessageAt: Date(),
            messageCount: 0
        )
        // Prepend so newest is first.
        records.insert(record, at: 0)
        currentRecordID = record.id
        // Prune oldest records beyond the cap.
        if records.count > maxConversationRecords {
            records.removeLast(records.count - maxConversationRecords)
        }
        save()
        return record
    }

    func activate(id: UUID) {
        guard records.contains(where: { $0.id == id }) else { return }
        currentRecordID = id
        save()
    }

    /// Updates the current (first) record with a server task ID and context ID.
    /// Also sets the title from the first user message if still at the default.
    func updateCurrent(
        serverTaskID: String? = nil,
        contextID: String? = nil,
        firstUserText: String? = nil,
        incrementMessages: Bool = false
    ) {
        guard let currentID = currentRecordID ?? records.first?.id,
              let index = records.firstIndex(where: { $0.id == currentID }) else { return }
        if let tid = serverTaskID, records[index].serverTaskID == nil {
            records[index].serverTaskID = tid
        }
        if let cid = contextID, records[index].contextID == nil {
            records[index].contextID = cid
        }
        if let text = firstUserText, records[index].title == "New Conversation" {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                records[index].title = String(trimmed.prefix(80))
            }
        }
        if incrementMessages {
            records[index].messageCount += 1
            records[index].lastMessageAt = Date()
        }
        save()
    }

    /// Replaces the title of the current record with an AI-generated summary.
    func setCurrentTitle(_ title: String) {
        guard !title.isEmpty,
              let currentID = currentRecordID ?? records.first?.id,
              let index = records.firstIndex(where: { $0.id == currentID }) else { return }
        records[index].title = title
        save()
    }

    /// Deletes the record with the given ID.
    func delete(id: UUID) {
        records.removeAll { $0.id == id }
        if currentRecordID == id {
            currentRecordID = records.first?.id
        }
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: conversationHistoryKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: conversationHistoryKey),
              let decoded = try? JSONDecoder().decode([ConversationRecord].self, from: data) else {
            return
        }
        // Cap on load to handle records that accumulated before the limit was introduced.
        records = Array(decoded.prefix(maxConversationRecords))
        currentRecordID = records.first?.id
    }
}
