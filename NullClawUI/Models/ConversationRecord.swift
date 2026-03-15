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

/// Manages locally-persisted conversation records.
/// Parallels GatewayStore — same UserDefaults JSON approach, @Observable.
@Observable
@MainActor
final class ConversationStore {

    var records: [ConversationRecord] = []

    // MARK: - Init

    init() {
        load()
    }

    /// Designated init for UI tests — empty store without touching UserDefaults.
    init(empty: Bool) {
        records = []
    }

    // MARK: - Current record

    /// The most-recently-created record (the "active" conversation).
    var current: ConversationRecord? {
        records.first
    }

    // MARK: - Mutations

    /// Creates a new record for the given gateway profile and makes it the current one.
    /// Returns the new record.
    @discardableResult
    func startNewRecord(gateway: GatewayProfile) -> ConversationRecord {
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
        save()
        return record
    }

    /// Updates the current (first) record with a server task ID and context ID.
    /// Also sets the title from the first user message if still at the default.
    func updateCurrent(
        serverTaskID: String? = nil,
        contextID: String? = nil,
        firstUserText: String? = nil,
        incrementMessages: Bool = false
    ) {
        guard !records.isEmpty else { return }
        if let tid = serverTaskID, records[0].serverTaskID == nil {
            records[0].serverTaskID = tid
        }
        if let cid = contextID, records[0].contextID == nil {
            records[0].contextID = cid
        }
        if let text = firstUserText, records[0].title == "New Conversation" {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                records[0].title = String(trimmed.prefix(80))
            }
        }
        if incrementMessages {
            records[0].messageCount += 1
            records[0].lastMessageAt = Date()
        }
        save()
    }

    /// Replaces the title of the current record with an AI-generated summary.
    func setCurrentTitle(_ title: String) {
        guard !records.isEmpty, !title.isEmpty else { return }
        records[0].title = title
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
        records = decoded
    }
}
