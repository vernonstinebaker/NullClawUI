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

// MARK: - Pairing Mode

/// Whether the gateway requires a bearer token.
/// Set to .notRequired when the gateway responds 403 to /pair (require_pairing: false).
enum PairingMode: Sendable, Equatable {
    case required
    case notRequired
}

// MARK: - GatewayClient

/// Thread-safe, async/await client for the NullClaw Gateway.
/// All methods are safe to call from any actor; UI updates must be dispatched to @MainActor by callers.
actor GatewayClient {

    // MARK: State
    private(set) var baseURL: URL
    private var bearerToken: String?
    /// Reflects whether the gateway requires a bearer token.
    /// Flipped to .notRequired when /pair returns 403 (require_pairing: false on the gateway).
    private(set) var pairingMode: PairingMode = .required

    private var session: URLSession
    private var sseSession: URLSession

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

    init(baseURL: URL, token: String? = nil, mockSessionConfig: URLSessionConfiguration? = nil) {
        self.baseURL = baseURL
        self.bearerToken = token
        if let cfg = mockSessionConfig {
            self.session = URLSession(configuration: cfg)
            self.sseSession = URLSession(configuration: cfg)
        } else {
            let defaultCfg = URLSessionConfiguration.default
            defaultCfg.timeoutIntervalForRequest = 30
            defaultCfg.timeoutIntervalForResource = 300
            self.session = URLSession(configuration: defaultCfg)
            let sseCfg = URLSessionConfiguration.default
            sseCfg.timeoutIntervalForRequest = 90    // max wait for first byte / between tokens
            sseCfg.timeoutIntervalForResource = 600  // max total stream duration
            self.sseSession = URLSession(configuration: sseCfg)
        }
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
        // 403 means require_pairing: false on the gateway — no token is issued.
        if let http = response as? HTTPURLResponse, http.statusCode == 403 {
            pairingMode = .notRequired
            return ""
        }
        try validate(response)
        let result = try decode(PairResponse.self, from: data)
        bearerToken = result.token
        pairingMode = .required
        return result.token
    }

    // MARK: - Phase 3: message/send

    func sendMessage(_ message: A2AMessage) async throws -> NullClawTask {
        guard pairingMode == .notRequired || bearerToken != nil else { throw GatewayError.unpaired }
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
        guard pairingMode == .notRequired || bearerToken != nil else { throw GatewayError.unpaired }
        let params = MessageSendParams(message: message)
        let rpc    = JSONRPCRequest(id: UUID().uuidString,
                                    method: "message/stream",
                                    params: params)
        let url = baseURL.appendingPathComponent("a2a")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = bearerToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try encoder.encode(rpc)

        let (asyncBytes, response) = try await sseSession.bytes(for: req)
        try validate(response)
        let localDecoder = decoder

        return AsyncThrowingStream { continuation in
            let t = Task {
                do {
                    var buffer: [UInt8] = []
                    for try await byte in asyncBytes {
                        buffer.append(byte)
                        try Self.yieldBufferedSSEEvents(from: &buffer, decoder: localDecoder, continuation: continuation)
                    }
                    try Self.yieldTrailingSSEEvent(from: &buffer, decoder: localDecoder, continuation: continuation)
                    continuation.finish()
                } catch SSEControlSignal.done {
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
        guard pairingMode == .notRequired || bearerToken != nil else { throw GatewayError.unpaired }
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
        guard pairingMode == .notRequired || bearerToken != nil else { throw GatewayError.unpaired }
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
        guard pairingMode == .notRequired || bearerToken != nil else { throw GatewayError.unpaired }
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

    nonisolated static func dataPayload(fromSSELines lines: [String]) -> String? {
        let payloadLines = lines.compactMap { line -> String? in
            guard line.hasPrefix("data:") else { return nil }
            let value = line.dropFirst(5)
            return value.first == " " ? String(value.dropFirst()) : String(value)
        }
        guard !payloadLines.isEmpty else { return nil }
        return payloadLines.joined(separator: "\n")
    }

    private nonisolated static func sseEventLines(from bytes: [UInt8]) throws -> [String] {
        guard let text = String(bytes: bytes, encoding: .utf8) else {
            throw GatewayError.decodingError(underlying: DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Invalid UTF-8 SSE event")))
        }
        return text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    nonisolated static func sseEventPayloads(from bytes: [UInt8]) throws -> [String] {
        var buffer = bytes
        var payloads: [String] = []
        while let boundary = nextSSEEventBoundary(in: buffer) {
            let eventBytes = Array(buffer[..<boundary.eventEnd])
            buffer.removeFirst(boundary.consumedLength)
            let lines = try sseEventLines(from: eventBytes)
            if let payload = dataPayload(fromSSELines: lines) {
                payloads.append(payload)
            }
        }
        while let last = buffer.last, last == 10 || last == 13 {
            buffer.removeLast()
        }
        if !buffer.isEmpty {
            let lines = try sseEventLines(from: buffer)
            if let payload = dataPayload(fromSSELines: lines) {
                payloads.append(payload)
            }
        }
        return payloads
    }

    nonisolated static func decodeStreamEnvelope(
        payload: String,
        decoder: JSONDecoder
    ) throws -> TaskStatusUpdateEvent {
        if payload == "[DONE]" {
            throw SSEControlSignal.done
        }
        guard let data = payload.data(using: .utf8) else {
            throw GatewayError.decodingError(underlying: DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Invalid UTF-8 SSE payload")))
        }
        do {
            let envelope = try decoder.decode(JSONRPCResponse<StreamEvent>.self, from: data)
            if let error = envelope.error {
                throw GatewayError.jsonRPCError(code: error.code, message: error.message)
            }
            guard envelope.result != nil else {
                throw GatewayError.decodingError(underlying: DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "SSE event missing result")))
            }
            return TaskStatusUpdateEvent(id: envelope.id, result: envelope.result)
        } catch let error as GatewayError {
            throw error
        } catch {
            throw GatewayError.decodingError(underlying: error)
        }
    }

    private nonisolated static func yieldSSEEvent(
        from lines: [String],
        decoder: JSONDecoder,
        continuation: AsyncThrowingStream<TaskStatusUpdateEvent, Error>.Continuation
    ) throws {
        guard let payload = dataPayload(fromSSELines: lines) else { return }
        do {
            let event = try decodeStreamEnvelope(payload: payload, decoder: decoder)
            continuation.yield(event)
        } catch SSEControlSignal.done {
            continuation.finish()
            throw SSEControlSignal.done
        }
    }

    private nonisolated static func yieldBufferedSSEEvents(
        from buffer: inout [UInt8],
        decoder: JSONDecoder,
        continuation: AsyncThrowingStream<TaskStatusUpdateEvent, Error>.Continuation
    ) throws {
        while let boundary = nextSSEEventBoundary(in: buffer) {
            let eventBytes = Array(buffer[..<boundary.eventEnd])
            buffer.removeFirst(boundary.consumedLength)
            let lines = try sseEventLines(from: eventBytes)
            try yieldSSEEvent(from: lines, decoder: decoder, continuation: continuation)
        }
    }

    private nonisolated static func yieldTrailingSSEEvent(
        from buffer: inout [UInt8],
        decoder: JSONDecoder,
        continuation: AsyncThrowingStream<TaskStatusUpdateEvent, Error>.Continuation
    ) throws {
        while let last = buffer.last, last == 10 || last == 13 {
            buffer.removeLast()
        }
        guard !buffer.isEmpty else { return }
        let lines = try sseEventLines(from: buffer)
        buffer.removeAll(keepingCapacity: false)
        try yieldSSEEvent(from: lines, decoder: decoder, continuation: continuation)
    }

    nonisolated static func nextSSEEventBoundary(
        in buffer: [UInt8]
    ) -> (eventEnd: Int, consumedLength: Int)? {
        if buffer.count >= 4 {
            for index in 0...(buffer.count - 4) {
                if buffer[index] == 13,
                   buffer[index + 1] == 10,
                   buffer[index + 2] == 13,
                   buffer[index + 3] == 10 {
                    return (eventEnd: index, consumedLength: index + 4)
                }
            }
        }
        if buffer.count >= 2 {
            for index in 0...(buffer.count - 2) {
                if buffer[index] == 10, buffer[index + 1] == 10 {
                    return (eventEnd: index, consumedLength: index + 2)
                }
            }
        }
        return nil
    }
}

private enum SSEControlSignal: Error {
    case done
}
