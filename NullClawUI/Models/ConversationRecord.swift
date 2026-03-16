import Foundation
import SwiftData

// MARK: - ConversationRecord

/// A locally-persisted record of a single conversation session.
/// Migrated from a Codable struct + UserDefaults (Phase 9) to a SwiftData @Model (Phase 11).
@Model
final class ConversationRecord {
    // MARK: - Identity
    @Attribute(.unique) var id: UUID

    /// Gateway task UUID — set on first send. `nil` for records that were never sent.
    var serverTaskID: String?
    /// Gateway context / session ID — set on first SSE event.
    var contextID: String?

    // MARK: - Gateway snapshot
    // Denormalized at record creation so history survives profile edits / deletions.
    var gatewayProfileID: UUID
    var gatewayName: String
    var gatewayURL: String

    // MARK: - Display

    /// Human-readable title: starts as "New Conversation", then set to the first user
    /// message text, optionally replaced with an AI-generated summary.
    var title: String

    /// Short preview of the last message — shown in the history list without a network call.
    var lastMessagePreview: String?

    var startedAt: Date
    var lastMessageAt: Date
    var messageCount: Int   // total messages (user + assistant)

    // MARK: - Relationship

    /// Owning gateway profile — optional so records survive profile deletion
    /// (deleteRule is set on the GatewayProfile side as .cascade).
    var gateway: GatewayProfile?

    // MARK: - Init

    init(
        id: UUID = UUID(),
        serverTaskID: String? = nil,
        contextID: String? = nil,
        gatewayProfileID: UUID,
        gatewayName: String,
        gatewayURL: String,
        title: String = "New Conversation",
        lastMessagePreview: String? = nil,
        startedAt: Date = Date(),
        lastMessageAt: Date = Date(),
        messageCount: Int = 0,
        gateway: GatewayProfile? = nil
    ) {
        self.id = id
        self.serverTaskID = serverTaskID
        self.contextID = contextID
        self.gatewayProfileID = gatewayProfileID
        self.gatewayName = gatewayName
        self.gatewayURL = gatewayURL
        self.title = title
        self.lastMessagePreview = lastMessagePreview
        self.startedAt = startedAt
        self.lastMessageAt = lastMessageAt
        self.messageCount = messageCount
        self.gateway = gateway
    }
}

// MARK: - ConversationStore

/// Maximum number of conversation records kept in the SwiftData store.
/// Oldest records are pruned on insert when this is exceeded.
private let maxConversationRecords = 100

/// Manages locally-persisted conversation records via SwiftData.
/// Replaces the UserDefaults-backed store from Phase 9.
@Observable
@MainActor
final class ConversationStore {

    // MARK: - Public state

    /// All records, sorted newest-first. Refreshed from the ModelContext on every mutation.
    var records: [ConversationRecord] = []

    /// The ID of the record that is currently considered "active" (the one in the chat view).
    var currentRecordID: UUID? = nil

    // MARK: - Private

    private var context: ModelContext

    // MARK: - Init

    /// Normal init — takes the shared ModelContext from the app container.
    init(context: ModelContext) {
        self.context = context
        loadRecords()
    }

    /// UI-test init — creates an in-memory store that never touches disk.
    init(inMemory: Bool = false) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: ConversationRecord.self, GatewayProfile.self, configurations: config)
        self.context = container.mainContext
        // records stays empty — no load needed for tests
    }

    // MARK: - Current record

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

    /// Creates a new record for the given gateway profile and makes it current.
    /// Reuses the current record if it is a blank "New Conversation" for the same gateway.
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
            gatewayProfileID: gateway.id,
            gatewayName: gateway.name,
            gatewayURL: gateway.url,
            gateway: gateway
        )
        context.insert(record)

        // Prune oldest records beyond cap.
        pruneIfNeeded()
        save()

        // Refresh the in-memory array.
        loadRecords()
        currentRecordID = record.id
        return record
    }

    func activate(id: UUID) {
        guard records.contains(where: { $0.id == id }) else { return }
        currentRecordID = id
    }

    func updateCurrent(
        serverTaskID: String? = nil,
        contextID: String? = nil,
        firstUserText: String? = nil,
        incrementMessages: Bool = false,
        lastMessagePreview: String? = nil
    ) {
        guard let rec = current else { return }

        if let tid = serverTaskID, rec.serverTaskID == nil {
            rec.serverTaskID = tid
        }
        if let cid = contextID, rec.contextID == nil {
            rec.contextID = cid
        }
        if let text = firstUserText, rec.title == "New Conversation" {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                rec.title = String(trimmed.prefix(80))
            }
        }
        if incrementMessages {
            rec.messageCount += 1
            rec.lastMessageAt = Date()
        }
        if let preview = lastMessagePreview {
            rec.lastMessagePreview = String(preview.prefix(120))
        }
        save()
        loadRecords()
    }

    func setCurrentTitle(_ title: String) {
        guard !title.isEmpty, let rec = current else { return }
        rec.title = title
        save()
        loadRecords()
    }

    func delete(id: UUID) {
        if let rec = records.first(where: { $0.id == id }) {
            context.delete(rec)
            save()
        }
        if currentRecordID == id {
            currentRecordID = records.first(where: { $0.id != id })?.id
        }
        loadRecords()
    }

    // MARK: - Persistence

    private func save() {
        try? context.save()
    }

    private func loadRecords() {
        let descriptor = FetchDescriptor<ConversationRecord>(
            sortBy: [SortDescriptor(\.lastMessageAt, order: .reverse)]
        )
        records = (try? context.fetch(descriptor)) ?? []
    }

    private func pruneIfNeeded() {
        // Fetch all sorted oldest-last so we can delete the tail.
        let descriptor = FetchDescriptor<ConversationRecord>(
            sortBy: [SortDescriptor(\.lastMessageAt, order: .reverse)]
        )
        guard var all = try? context.fetch(descriptor),
              all.count >= maxConversationRecords else { return }
        let toDelete = all.dropFirst(maxConversationRecords - 1)
        for rec in toDelete { context.delete(rec) }
    }
}

// MARK: - UserDefaults Migration (Phase 11)

/// Legacy Codable struct used only during one-time migration from UserDefaults.
private struct LegacyConversationRecord: Codable {
    let id: UUID
    var serverTaskID: String?
    var contextID: String?
    var gatewayProfileID: UUID
    var gatewayName: String
    var gatewayURL: String
    var title: String
    var startedAt: Date
    var lastMessageAt: Date
    var messageCount: Int
}

extension ConversationStore {
    /// One-time migration: reads the old UserDefaults JSON blob and inserts records into
    /// SwiftData. Safe to call on every launch — it checks for the key first.
    func migrateFromUserDefaultsIfNeeded() {
        let key = "conversationHistory"
        guard let data = UserDefaults.standard.data(forKey: key),
              let legacyRecords = try? JSONDecoder().decode([LegacyConversationRecord].self, from: data)
        else { return }

        // Don't migrate if we already have data in SwiftData (idempotent).
        if !records.isEmpty { return }

        for legacy in legacyRecords.prefix(maxConversationRecords) {
            let rec = ConversationRecord(
                id: legacy.id,
                serverTaskID: legacy.serverTaskID,
                contextID: legacy.contextID,
                gatewayProfileID: legacy.gatewayProfileID,
                gatewayName: legacy.gatewayName,
                gatewayURL: legacy.gatewayURL,
                title: legacy.title,
                startedAt: legacy.startedAt,
                lastMessageAt: legacy.lastMessageAt,
                messageCount: legacy.messageCount
            )
            context.insert(rec)
        }
        save()
        loadRecords()

        // Remove the legacy key so this runs only once.
        UserDefaults.standard.removeObject(forKey: key)
    }
}
