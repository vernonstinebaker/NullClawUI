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

    init(baseURL: URL, token: String? = nil, requiresPairing: Bool = true, mockSessionConfig: URLSessionConfiguration? = nil) {
        self.baseURL = baseURL
        self.bearerToken = token.flatMap { $0.isEmpty ? nil : $0 }
        // Open gateways (requiresPairing: false) never issue tokens. Setting pairingMode
        // to .notRequired here allows all API calls to proceed without a bearer token.
        self.pairingMode = requiresPairing ? .required : .notRequired
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

    /// Cancels all in-flight requests and invalidates both URLSessions.
    /// Call this on the old client before replacing it with a new one on gateway switch.
    func invalidate() {
        session.invalidateAndCancel()
        sseSession.invalidateAndCancel()
    }

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

    /// Maximum SSE byte-buffer size (4 MB). If a single response body exceeds this
    /// without an SSE event boundary, the stream is aborted to prevent OOM.
    private static let sseMaxBufferBytes = 4 * 1024 * 1024

    /// Streams a message via SSE (method: message/stream) using URLSession.bytes.
    /// Each yielded SSEEnvelope wraps a StreamEvent (kind: task | artifact-update | status-update).
    func streamMessage(_ message: A2AMessage) async throws -> AsyncThrowingStream<TaskStatusUpdateEvent, Error> {
        guard pairingMode == .notRequired || bearerToken != nil else { throw GatewayError.unpaired }
        let params = MessageSendParams(message: message)
        let rpc    = JSONRPCRequest(id: UUID().uuidString,
                                    method: "message/stream",
                                    params: params)
        let url = baseURL.appendingPathComponent("a2a")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try encoder.encode(rpc)

        let (asyncBytes, response) = try await sseSession.bytes(for: req)
        try validate(response)
        let localDecoder = decoder

        return AsyncThrowingStream { continuation in
            let t = Task {
                do {
                    // Use a Data buffer with pre-reserved capacity for O(1) append.
                    // An index cursor advances instead of removeFirst (which is O(n)).
                    var buffer = Data()
                    buffer.reserveCapacity(4096)
                    var cursor = 0   // index of the first unprocessed byte in `buffer`

                    for try await byte in asyncBytes {
                        buffer.append(byte)

                        // Guard against a runaway response with no SSE delimiter.
                        if buffer.count - cursor > Self.sseMaxBufferBytes {
                            continuation.finish(throwing: GatewayError.networkError(
                                underlying: NSError(domain: "GatewayClient", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "SSE buffer exceeded 4 MB — aborting stream"])))
                            return
                        }

                        try Self.yieldBufferedSSEEvents(buffer: buffer, cursor: &cursor, decoder: localDecoder, continuation: continuation)

                        // Compact the buffer periodically to reclaim memory consumed
                        // by already-processed bytes, without doing it on every byte.
                        if cursor > 65536 {
                            buffer = buffer.subdata(in: cursor ..< buffer.count)
                            cursor = 0
                        }
                    }

                    // Compact any remaining processed bytes before the trailing-event pass.
                    if cursor > 0 {
                        buffer = buffer.subdata(in: cursor ..< buffer.count)
                        cursor = 0
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

    // MARK: - Phase 16+: sendOneShot helper (used by config/status/cron ViewModels)

    /// Sends a one-shot user prompt via `message/stream` and collects the complete reply text.
    /// Assembles `artifact-update` chunks in order; non-artifact events are ignored.
    /// Throws if the client is unpaired or the network call fails.
    func sendOneShot(_ prompt: String) async throws -> String {
        let message = A2AMessage(
            role: "user",
            parts: [MessagePart(text: prompt, kind: "text")],
            contextId: nil
        )
        let stream = try await streamMessage(message)
        var reply = ""
        for try await event in stream {
            guard let result = event.result else { continue }
            if result.kind == "artifact-update",
               let parts = result.artifact?.parts {
                let chunk = parts.compactMap { $0.text }.joined()
                if result.append == true {
                    reply += chunk
                } else {
                    reply = chunk
                }
            }
        }
        return reply
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
        buffer: Data,
        cursor: inout Int,
        decoder: JSONDecoder,
        continuation: AsyncThrowingStream<TaskStatusUpdateEvent, Error>.Continuation
    ) throws {
        while let boundary = nextSSEEventBoundary(in: buffer, from: cursor) {
            let eventBytes = Array(buffer[cursor ..< (cursor + boundary.eventEnd)])
            cursor += boundary.consumedLength
            let lines = try sseEventLines(from: eventBytes)
            try yieldSSEEvent(from: lines, decoder: decoder, continuation: continuation)
        }
    }

    private nonisolated static func yieldTrailingSSEEvent(
        from buffer: inout Data,
        decoder: JSONDecoder,
        continuation: AsyncThrowingStream<TaskStatusUpdateEvent, Error>.Continuation
    ) throws {
        while let last = buffer.last, last == 10 || last == 13 {
            buffer.removeLast()
        }
        guard !buffer.isEmpty else { return }
        let bytes = Array(buffer)
        let lines = try sseEventLines(from: bytes)
        buffer.removeAll(keepingCapacity: false)
        try yieldSSEEvent(from: lines, decoder: decoder, continuation: continuation)
    }

    nonisolated static func nextSSEEventBoundary(
        in buffer: [UInt8]
    ) -> (eventEnd: Int, consumedLength: Int)? {
        nextSSEEventBoundary(in: buffer, from: 0)
    }

    nonisolated static func nextSSEEventBoundary(
        in buffer: [UInt8],
        from start: Int
    ) -> (eventEnd: Int, consumedLength: Int)? {
        let count = buffer.count
        if count - start >= 4 {
            for index in start...(count - 4) {
                if buffer[index] == 13,
                   buffer[index + 1] == 10,
                   buffer[index + 2] == 13,
                   buffer[index + 3] == 10 {
                    return (eventEnd: index - start, consumedLength: index - start + 4)
                }
            }
        }
        if count - start >= 2 {
            for index in start...(count - 2) {
                if buffer[index] == 10, buffer[index + 1] == 10 {
                    return (eventEnd: index - start, consumedLength: index - start + 2)
                }
            }
        }
        return nil
    }

    /// Cursor-based boundary search for use with `Data` buffers.
    /// Delegates to the `[UInt8]` overload to avoid duplicating the search logic.
    private nonisolated static func nextSSEEventBoundary(
        in buffer: Data,
        from start: Int
    ) -> (eventEnd: Int, consumedLength: Int)? {
        // Convert only the unprocessed suffix so that the [UInt8] overload's
        // index arithmetic (which is always relative to the slice start) is correct.
        let slice = Array(buffer[start...])
        return nextSSEEventBoundary(in: slice, from: 0)
    }
}

private enum SSEControlSignal: Error {
    case done
}
