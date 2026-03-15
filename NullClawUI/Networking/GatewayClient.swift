import Foundation

// MARK: - Gateway Errors

enum GatewayError: Error, LocalizedError, Sendable {
    case invalidURL
    case httpError(statusCode: Int)
    case decodingError(underlying: Error)
    case networkError(underlying: Error)
    case jsonRPCError(code: Int, message: String)
    case unpaired

    var errorDescription: String? {
        switch self {
        case .invalidURL:            return "Invalid gateway URL."
        case .httpError(let code):   return "HTTP error \(code)."
        case .decodingError:         return "Failed to decode server response."
        case .networkError(let e):   return e.localizedDescription
        case .jsonRPCError(_, let m):return "RPC error: \(m)"
        case .unpaired:              return "Not paired with gateway."
        }
    }
}

// MARK: - GatewayClient

/// Thread-safe, async/await client for the NullClaw Gateway.
/// All methods are safe to call from any actor; UI updates must be dispatched to @MainActor by callers.
actor GatewayClient {

    // MARK: State
    private(set) var baseURL: URL
    private var bearerToken: String?

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 300 // long enough for SSE streams
        return URLSession(configuration: cfg)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = .withoutEscapingSlashes
        return e
    }()

    // MARK: Init

    init(baseURL: URL, token: String? = nil) {
        self.baseURL = baseURL
        self.bearerToken = token
    }

    // MARK: Configuration

    func setBaseURL(_ url: URL) { self.baseURL = url }
    func setToken(_ token: String?) { self.bearerToken = token.flatMap { $0.isEmpty ? nil : $0 } }

    // MARK: - Phase 1: Health & Agent Card

    /// GET /health  → HTTP 200 means online.
    func checkHealth() async throws {
        let url = baseURL.appendingPathComponent("health")
        let req = try makeRequest(url: url, method: "GET")
        let (_, response) = try await session.data(for: req)
        try validate(response)
    }

    /// GET /.well-known/agent-card.json
    func fetchAgentCard() async throws -> AgentCard {
        let url = baseURL.appendingPathComponent(".well-known/agent-card.json")
        let req = try makeRequest(url: url, method: "GET")
        let (data, response) = try await session.data(for: req)
        try validate(response)
        return try decode(AgentCard.self, from: data)
    }

    // MARK: - Phase 2: Pairing

    struct PairResponse: Decodable { let token: String }

    func pair(code: String) async throws -> String {
        let url = baseURL.appendingPathComponent("pair")
        var req = try makeRequest(url: url, method: "POST")
        req.setValue(code, forHTTPHeaderField: "X-Pairing-Code")
        let (data, response) = try await session.data(for: req)
        try validate(response)
        let result = try decode(PairResponse.self, from: data)
        bearerToken = result.token
        return result.token
    }

    // MARK: - Phase 3: message/send

    func sendMessage(_ message: A2AMessage) async throws -> NullClawTask {
        guard bearerToken != nil else { throw GatewayError.unpaired }
        let params  = MessageSendParams(message: message)
        let rpc     = JSONRPCRequest(id: UUID().uuidString,
                                     method: "message/send",
                                     params: params)
        let url = baseURL.appendingPathComponent("a2a")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try encoder.encode(rpc)

        let (data, response) = try await session.data(for: req)
        try validate(response)

        let envelope = try decode(JSONRPCResponse<NullClawTask>.self, from: data)
        if let err = envelope.error { throw GatewayError.jsonRPCError(code: err.code, message: err.message) }
        guard let task = envelope.result else { throw GatewayError.decodingError(underlying: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Null result"))) }
        return task
    }

    // MARK: - Phase 4: message/stream (SSE via AsyncBytes)

    /// Streams a message via SSE (method: message/stream) using URLSession.bytes.
    /// Each yielded SSEEnvelope wraps a StreamEvent (kind: task | artifact-update | status-update).
    func streamMessage(_ message: A2AMessage) async throws -> AsyncThrowingStream<TaskStatusUpdateEvent, Error> {
        guard let token = bearerToken else { throw GatewayError.unpaired }
        let params = MessageSendParams(message: message)
        let rpc    = JSONRPCRequest(id: UUID().uuidString,
                                    method: "message/stream",
                                    params: params)
        let url = baseURL.appendingPathComponent("a2a")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try encoder.encode(rpc)

        let (asyncBytes, response) = try await session.bytes(for: req)
        try validate(response)
        let localDecoder = decoder

        return AsyncThrowingStream { continuation in
            let t = Task {
                do {
                    var buffer = ""
                    for try await byte in asyncBytes {
                        guard let char = String(bytes: [byte], encoding: .utf8) else { continue }
                        buffer += char
                        while let range = buffer.range(of: "\n\n") {
                            let chunk = String(buffer[buffer.startIndex..<range.lowerBound])
                            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                            // Strip the "data: " SSE prefix
                            let dataLines = chunk.split(separator: "\n", omittingEmptySubsequences: true)
                            for dataLine in dataLines {
                                let stripped = dataLine.hasPrefix("data: ") ? String(dataLine.dropFirst(6)) : String(dataLine)
                                if stripped == "[DONE]" { continuation.finish(); return }
                                guard let data = stripped.data(using: .utf8) else { continue }
                                if let event = try? localDecoder.decode(TaskStatusUpdateEvent.self, from: data) {
                                    continuation.yield(event)
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in t.cancel() }
        }
    }

    // MARK: - Phase 5: Task History (JSON-RPC via POST /a2a)
    // Note: All task management methods are JSON-RPC, not REST.
    // Methods: tasks/list, tasks/get, tasks/cancel — all POSTed to /a2a.

    func listTasks() async throws -> [TaskSummary] {
        guard bearerToken != nil else { throw GatewayError.unpaired }
        let rpc = JSONRPCRequest(id: UUID().uuidString,
                                 method: "tasks/list",
                                 params: TaskListParams())
        let url = baseURL.appendingPathComponent("a2a")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try encoder.encode(rpc)
        let (data, response) = try await session.data(for: req)
        try validate(response)
        let envelope = try decode(JSONRPCResponse<TaskListResult>.self, from: data)
        if let err = envelope.error { throw GatewayError.jsonRPCError(code: err.code, message: err.message) }
        return envelope.result?.tasks ?? []
    }

    func getTask(id: String) async throws -> NullClawTask {
        guard bearerToken != nil else { throw GatewayError.unpaired }
        let rpc = JSONRPCRequest(id: UUID().uuidString,
                                 method: "tasks/get",
                                 params: TaskIDParams(id: id))
        let url = baseURL.appendingPathComponent("a2a")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try encoder.encode(rpc)
        let (data, response) = try await session.data(for: req)
        try validate(response)
        let envelope = try decode(JSONRPCResponse<NullClawTask>.self, from: data)
        if let err = envelope.error { throw GatewayError.jsonRPCError(code: err.code, message: err.message) }
        guard let task = envelope.result else {
            throw GatewayError.decodingError(underlying: DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Null result")))
        }
        return task
    }

    func cancelTask(id: String) async throws {
        guard bearerToken != nil else { throw GatewayError.unpaired }
        let rpc = JSONRPCRequest(id: UUID().uuidString,
                                 method: "tasks/cancel",
                                 params: TaskIDParams(id: id))
        let url = baseURL.appendingPathComponent("a2a")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try encoder.encode(rpc)
        let (_, response) = try await session.data(for: req)
        try validate(response)
    }

    // MARK: - Helpers

    private func makeRequest(url: URL, method: String, authenticated: Bool = false) throws -> URLRequest {
        guard url.scheme != nil else { throw GatewayError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let token = bearerToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw GatewayError.httpError(statusCode: http.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw GatewayError.decodingError(underlying: error)
        }
    }
}
