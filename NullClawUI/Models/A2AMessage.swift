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
    let kind: String?   // "text" | "file" etc — present in server responses

    init(text: String? = nil, kind: String? = nil) {
        self.text = text
        self.kind = kind
    }

    enum CodingKeys: String, CodingKey {
        case text
        case kind
    }
}

struct A2AMessage: Codable, Sendable {
    let role: String          // "user" | "assistant"
    var parts: [MessagePart]
    var contextId: String? = nil    // Optional: ties messages to the same conversation session

    // Explicit CodingKeys to prevent JSONEncoder's .convertToSnakeCase strategy
    // from turning "contextId" into "context_id". The gateway looks for "contextId"
    // (camelCase) in a2a.zig:extractMessageContextId — snake_case silently breaks
    // context continuity, causing a fresh agent session on every message.
    enum CodingKeys: String, CodingKey {
        case role
        case parts
        case contextId
    }
}

struct MessageSendParams: Encodable, Sendable {
    let message: A2AMessage
}

// MARK: - Task

struct TaskArtifact: Codable, Sendable {
    let artifactId: String?
    let parts: [MessagePart]

    var text: String {
        parts.compactMap { $0.text }.joined()
    }
}

struct NullClawTask: Codable, Sendable, Identifiable {
    let id: String
    let contextId: String?      // conversation session ID; pass on subsequent messages
    let status: TaskStatus
    let messages: [A2AMessage]?
    let artifacts: [TaskArtifact]?
    let history: [A2AMessage]?

    /// Best-effort reply text: prefer artifacts, fall back to status.message.
    var replyText: String {
        if let art = artifacts, !art.isEmpty {
            return art.map(\.text).joined(separator: "\n")
        }
        return status.message?.parts.compactMap(\.text).joined() ?? ""
    }

    struct TaskStatus: Codable, Sendable {
        let state: String    // "working" | "completed" | "cancelled" | "failed"
        let message: A2AMessage?
    }
}

/// Lightweight summary used for the task list (Phase 5).
/// The server returns the full task shape; we extract id + status.state.
struct TaskSummary: Codable, Sendable, Identifiable {
    let id: String
    let status: TaskSummaryStatus

    struct TaskSummaryStatus: Codable, Sendable {
        let state: String
    }

    /// Display string for the status row.
    var statusLabel: String { status.state }
}

// MARK: - JSON-RPC params for task management (Phase 5)

/// Params for tasks/list (no required fields; server defaults to pageSize 50).
struct TaskListParams: Encodable, Sendable {}

/// Params for tasks/get and tasks/cancel.
struct TaskIDParams: Encodable, Sendable {
    let id: String
}

/// Result shape for the tasks/list JSON-RPC response.
struct TaskListResult: Decodable, Sendable {
    let tasks: [TaskSummary]
    let totalSize: Int?
    let nextPageToken: String?
}

// MARK: - SSE Event (Phase 4)

/// Wraps a streaming JSON-RPC result from method "message/stream".
/// Each SSE line is: data: {"jsonrpc":"2.0","id":"...","result": <StreamEvent>}
struct SSEEnvelope: Decodable, Sendable {
    let id: String?
    let result: StreamEvent?
}

struct StreamEvent: Decodable, Sendable {
    let kind: String            // "task" | "artifact-update" | "status-update"
    let taskId: String?
    let contextId: String?      // returned on every event; use to continue the conversation
    let artifact: TaskArtifact? // present when kind == "artifact-update"
    let append: Bool?           // true = delta, false = replace
    let lastChunk: Bool?
    let status: NullClawTask.TaskStatus? // present when kind == "status-update"
    let final: Bool?            // true on the terminal event

    // kind == "task": initial task snapshot
    let id: String?             // task id when kind == "task"
}

/// Alias kept for compatibility — callers use StreamEvent directly now.
typealias TaskStatusUpdateEvent = SSEEnvelope
