import Foundation

// MARK: - JSON-RPC 2.0 Envelope

struct JSONRPCRequest<P: Encodable & Sendable>: Encodable, Sendable {
    let jsonrpc: String = "2.0"
    let id: String
    let method: String
    let params: P
}

struct JSONRPCResponse<R: Decodable>: Decodable {
    let id: String?
    let result: R?
    let error: JSONRPCError?
}

struct JSONRPCError: Decodable {
    let code: Int
    let message: String
}

// MARK: - A2A Core Types

struct MessagePart: Codable, Sendable {
    let text: String?
    // Phase 6: file parts will be added here

    enum CodingKeys: String, CodingKey {
        case text
    }
}

struct A2AMessage: Codable, Sendable {
    let role: String          // "user" | "assistant"
    var parts: [MessagePart]
}

struct MessageSendParams: Encodable, Sendable {
    let message: A2AMessage
}

// MARK: - Task

struct NullClawTask: Codable, Sendable, Identifiable {
    let id: String
    let status: TaskStatus
    let messages: [A2AMessage]?

    struct TaskStatus: Codable, Sendable {
        let state: String    // "working" | "completed" | "cancelled" | "failed"
        let message: A2AMessage?
    }
}

/// Lightweight summary used for the task list (Phase 5)
struct TaskSummary: Codable, Sendable, Identifiable {
    let id: String
    let status: String
}

// MARK: - SSE Event (Phase 4)

struct TaskStatusUpdateEvent: Decodable, Sendable {
    let id: String
    let status: NullClawTask.TaskStatus?
    let delta: MessagePart?
    let final: Bool?
}
