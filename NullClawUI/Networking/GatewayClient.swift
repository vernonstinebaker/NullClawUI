import Foundation

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

    private let decoder: JSONDecoder = GatewayNetworking.snakeCaseDecoder()
    private let encoder: JSONEncoder = GatewayNetworking.snakeCaseEncoder()
    /// Dedicated encoder for JSON-RPC A2A methods that strictly require camelCase.
    private let a2aEncoder: JSONEncoder = GatewayNetworking.camelCaseEncoder()

    // MARK: Init

    init(
        baseURL: URL,
        token: String? = nil,
        requiresPairing: Bool = true,
        mockSessionConfig: URLSessionConfiguration? = nil
    ) {
        self.baseURL = baseURL
        bearerToken = token.flatMap { $0.isEmpty ? nil : $0 }
        // Open gateways (requiresPairing: false) never issue tokens. Setting pairingMode
        // to .notRequired here allows all API calls to proceed without a bearer token.
        pairingMode = requiresPairing ? .required : .notRequired
        session = GatewayNetworking.defaultSession(using: mockSessionConfig)
        sseSession = GatewayNetworking.sseSession(using: mockSessionConfig)
    }

    // MARK: Configuration

    func setBaseURL(_ url: URL) {
        baseURL = url
    }

    func setToken(_ token: String?) {
        bearerToken = token.flatMap { $0.isEmpty ? nil : $0 }
    }

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
        let params = MessageSendParams(message: message)
        let rpc = JSONRPCRequest(
            id: UUID().uuidString,
            method: "message/send",
            params: params
        )
        let url = baseURL.appendingPathComponent("a2a")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try a2aEncoder.encode(rpc)

        let (data, response) = try await session.data(for: req)
        try validate(response)

        let envelope = try decode(JSONRPCResponse<NullClawTask>.self, from: data)
        if let err = envelope.error { throw GatewayError.jsonRPCError(code: err.code, message: err.message) }
        guard let task = envelope.result else { throw GatewayError.decodingError(underlying: DecodingError.dataCorrupted(.init(
            codingPath: [],
            debugDescription: "Null result"
        ))) }
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
        let rpc = JSONRPCRequest(
            id: UUID().uuidString,
            method: "message/stream",
            params: params
        )
        let url = baseURL.appendingPathComponent("a2a")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try a2aEncoder.encode(rpc)

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
                    var cursor = 0 // index of the first unprocessed byte in `buffer`

                    for try await byte in asyncBytes {
                        buffer.append(byte)

                        // Guard against a runaway response with no SSE delimiter.
                        if buffer.count - cursor > Self.sseMaxBufferBytes {
                            continuation.finish(throwing: GatewayError.networkError(
                                underlying: NSError(
                                    domain: "GatewayClient",
                                    code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "SSE buffer exceeded 4 MB — aborting stream"]
                                )
                            ))
                            return
                        }

                        try Self.yieldBufferedSSEEvents(
                            buffer: buffer,
                            cursor: &cursor,
                            decoder: localDecoder,
                            continuation: continuation
                        )

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

    // MARK: - Phase 15+: Cron Jobs (REST)

    /// GET /cron — List all live scheduler jobs (legacy endpoint).
    func listCronJobsLegacy() async throws -> [CronJob] {
        let url = baseURL.appendingPathComponent("cron")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response)
        return try decode([CronJob].self, from: data)
    }

    /// POST /cron/add — Add a new cron job (legacy endpoint).
    func addCronJobLegacy(_ params: CronJobAddParams) async throws -> CronJob {
        let url = baseURL.appendingPathComponent("cron/add")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try encoder.encode(params)
        let (data, response) = try await session.data(for: req)
        try validate(response)
        return try decode(CronJob.self, from: data)
    }

    /// POST /cron/remove — Remove a cron job by id (legacy endpoint).
    func removeCronJobLegacy(id: String) async throws {
        let url = baseURL.appendingPathComponent("cron/remove")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try encoder.encode(CronJobIDParams(id: id))
        let (_, response) = try await session.data(for: req)
        try validate(response)
    }

    /// POST /cron/pause — Pause a cron job (legacy endpoint).
    func pauseCronJobLegacy(id: String) async throws {
        let url = baseURL.appendingPathComponent("cron/pause")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try encoder.encode(CronJobIDParams(id: id))
        let (_, response) = try await session.data(for: req)
        try validate(response)
    }

    /// POST /cron/resume — Resume a cron job (legacy endpoint).
    func resumeCronJobLegacy(id: String) async throws {
        let url = baseURL.appendingPathComponent("cron/resume")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try encoder.encode(CronJobIDParams(id: id))
        let (_, response) = try await session.data(for: req)
        try validate(response)
    }

    /// POST /cron/update — Partially update a cron job (legacy endpoint).
    func updateCronJobLegacy(_ params: CronJobUpdateParams) async throws {
        let url = baseURL.appendingPathComponent("cron/update")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try encoder.encode(params)
        let (_, response) = try await session.data(for: req)
        try validate(response)
    }

    // MARK: - REST Admin API (/api/*)

    /// Typed wrapper used by `apiConfigObjectValue(path:as:)` to extract the `value`
    /// field from a GET /api/config response envelope.
    private struct ConfigValueOf<T: Decodable>: Decodable {
        let value: T
    }

    /// Decodes an /api/* response envelope, throwing `GatewayError.apiError` on failure.
    private func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try GatewayNetworking.decodeEnvelope(type, from: data, using: decoder)
    }

    /// Decodes an /api/* response envelope where the data is an array.
    private func decodeArrayEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> [T] {
        try GatewayNetworking.decodeArrayEnvelope(type, from: data, using: decoder)
    }

    // MARK: Status, Doctor & Capabilities

    /// GET /api/status — System status, uptime, health components.
    func apiStatus() async throws -> ApiStatusResponse {
        let url = baseURL.appendingPathComponent("api/status")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiStatusResponse.self, from: data)
    }

    /// GET /api/doctor — Deep per-component health report with timestamps and restart counts.
    func apiDoctor() async throws -> ApiDoctorResponse {
        let url = baseURL.appendingPathComponent("api/doctor")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiDoctorResponse.self, from: data)
    }

    /// GET /api/capabilities — Runtime capability flags and channel availability matrix.
    func apiCapabilities() async throws -> ApiCapabilitiesResponse {
        let url = baseURL.appendingPathComponent("api/capabilities")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiCapabilitiesResponse.self, from: data)
    }

    // MARK: Config (cont.)

    /// GET /api/config?path=<dotted.path> — Read a single config value.
    func apiConfigValue(path: String) async throws -> ConfigValueResponse {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/config"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let url = components.url else { throw GatewayError.invalidURL }
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ConfigValueResponse.self, from: data)
    }

    /// GET /api/config?path=<dotted.path> — Decodes the 'value' field directly into T.
    /// Use this when the config value is a known struct (e.g. AgentConfigPayload, AutonomyConfigPayload).
    func apiConfigObjectValue<T: Decodable>(path: String, as type: T.Type) async throws -> T {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/config"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let url = components.url else { throw GatewayError.invalidURL }
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        // The envelope shape is: {"success":true,"data":{"path":"...","value":{...}}}
        // Peel off the outer ApiEnvelope then decode "value" as T.
        // Wrap any DecodingError (e.g. null value for unknown path) into GatewayError.decodingError.
        do {
            let inner = try decodeEnvelope(ConfigValueOf<T>.self, from: data)
            return inner.value
        } catch let e as GatewayError {
            throw e
        } catch {
            throw GatewayError.decodingError(underlying: error)
        }
    }

    /// GET /api/models — Available providers and default model.
    func apiModels() async throws -> ApiModelsResponse {
        let url = baseURL.appendingPathComponent("api/models")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiModelsResponse.self, from: data)
    }

    // MARK: Cron (REST Admin API)

    /// GET /api/cron — List all scheduled jobs (envelope-wrapped).
    func apiListCronJobs() async throws -> [CronJob] {
        let url = baseURL.appendingPathComponent("api/cron")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeArrayEnvelope(CronJob.self, from: data)
    }

    /// POST /api/cron — Create a new cron job.
    func apiCreateCronJob(_ params: CronJobAddParams) async throws -> CronJob {
        let url = baseURL.appendingPathComponent("api/cron")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try encoder.encode(params)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(CronJob.self, from: data)
    }

    /// POST /api/cron/once — Create a one-shot delayed job.
    func apiCreateCronJobOnce(_ params: CronJobAddParams) async throws -> CronJob {
        let url = baseURL.appendingPathComponent("api/cron/once")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try encoder.encode(params)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(CronJob.self, from: data)
    }

    /// POST /api/cron/:id/run — Trigger immediate run.
    func apiRunCronJob(id: String) async throws {
        let url = baseURL.appendingPathComponent("api/cron/\(id)/run")
        let req = try makeRequest(url: url, method: "POST", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
    }

    /// POST /api/cron/:id/pause — Pause a cron job.
    func apiPauseCronJob(id: String) async throws {
        let url = baseURL.appendingPathComponent("api/cron/\(id)/pause")
        let req = try makeRequest(url: url, method: "POST", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
    }

    /// POST /api/cron/:id/resume — Resume a cron job.
    func apiResumeCronJob(id: String) async throws {
        let url = baseURL.appendingPathComponent("api/cron/\(id)/resume")
        let req = try makeRequest(url: url, method: "POST", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
    }

    /// PATCH /api/cron/:id — Partially update a cron job.
    func apiUpdateCronJob(id: String, _ params: CronJobUpdateParams) async throws {
        let url = baseURL.appendingPathComponent("api/cron/\(id)")
        var req = try makeRequest(url: url, method: "PATCH", authenticated: true)
        req.httpBody = try encoder.encode(params)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
    }

    /// DELETE /api/cron/:id — Delete a cron job.
    func apiDeleteCronJob(id: String) async throws {
        let url = baseURL.appendingPathComponent("api/cron/\(id)")
        let req = try makeRequest(url: url, method: "DELETE", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
    }

    // MARK: Channels

    /// GET /api/channels — List all configured channels with status.
    func apiListChannels() async throws -> [ApiChannelInfo] {
        let url = baseURL.appendingPathComponent("api/channels")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeArrayEnvelope(ApiChannelInfo.self, from: data)
    }

    /// GET /api/channels/:name — Get detail for a specific channel type.
    func apiGetChannel(name: String) async throws -> ApiChannelDetail {
        let url = baseURL.appendingPathComponent("api/channels/\(name)")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiChannelDetail.self, from: data)
    }

    // MARK: MCP Servers

    /// GET /api/mcp — List all configured MCP servers.
    func apiListMCPServers() async throws -> [ApiMCPServerInfo] {
        let url = baseURL.appendingPathComponent("api/mcp")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeArrayEnvelope(ApiMCPServerInfo.self, from: data)
    }

    /// GET /api/mcp/:name — Get detail for a specific MCP server.
    func apiGetMCPServer(name: String) async throws -> ApiMCPServerDetail {
        let url = baseURL.appendingPathComponent("api/mcp/\(name)")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiMCPServerDetail.self, from: data)
    }

    // MARK: Config Mutation

    /// PATCH /api/config — Set a config value at a dotted path.
    func apiSetConfigValue(path: String, value: some Encodable) async throws {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/config"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let url = components.url else { throw GatewayError.invalidURL }
        var req = try makeRequest(url: url, method: "PATCH", authenticated: true)
        req.httpBody = try encoder.encode(["value": value])
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
    }

    /// DELETE /api/config — Unset a config value at a dotted path.
    func apiUnsetConfigValue(path: String) async throws {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/config"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let url = components.url else { throw GatewayError.invalidURL }
        let req = try makeRequest(url: url, method: "DELETE", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
    }

    /// POST /api/config/reload — Hot-reload config from disk.
    func apiReloadConfig() async throws -> ApiConfigReloadResponse {
        let url = baseURL.appendingPathComponent("api/config/reload")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try encoder.encode([String: String]()) // endpoint requires a body
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiConfigReloadResponse.self, from: data)
    }

    /// POST /api/config/validate — Validate config without applying.
    func apiValidateConfig() async throws -> ApiConfigReloadResponse {
        let url = baseURL.appendingPathComponent("api/config/validate")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try encoder.encode([String: String]()) // endpoint requires a body
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiConfigReloadResponse.self, from: data)
    }

    // MARK: Models (cont.)

    /// GET /api/models/:name — Get detail for a specific model.
    func apiGetModel(name: String) async throws -> ApiModelDetail {
        let url = baseURL.appendingPathComponent("api/models/\(name)")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiModelDetail.self, from: data)
    }

    // MARK: Cron (cont.)

    /// GET /api/cron/:id — Get detail for a single scheduled job.
    func apiGetCronJob(id: String) async throws -> CronJob {
        let url = baseURL.appendingPathComponent("api/cron/\(id)")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(CronJob.self, from: data)
    }

    /// GET /api/cron/:id/runs — Run history for a specific scheduled job.
    func apiCronJobRuns(id: String) async throws -> ApiCronRunsResponse {
        let url = baseURL.appendingPathComponent("api/cron/\(id)/runs")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiCronRunsResponse.self, from: data)
    }

    // MARK: Skills

    /// GET /api/skills — List installed skills and their output directory.
    func apiListSkills() async throws -> ApiSkillsResponse {
        let url = baseURL.appendingPathComponent("api/skills")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiSkillsResponse.self, from: data)
    }

    /// GET /api/skills/:name — Get detail for a specific skill.
    func apiGetSkill(name: String) async throws -> ApiSkillInfo {
        let url = baseURL.appendingPathComponent("api/skills/\(name)")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiSkillInfo.self, from: data)
    }

    /// DELETE /api/skills/:name — Uninstall a skill.
    func apiDeleteSkill(name: String) async throws {
        let url = baseURL.appendingPathComponent("api/skills/\(name)")
        let req = try makeRequest(url: url, method: "DELETE", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
    }

    // MARK: Agent Sessions

    /// GET /api/agent/sessions — List all agent conversation sessions.
    func apiListAgentSessions() async throws -> ApiAgentSessionsResponse {
        let url = baseURL.appendingPathComponent("api/agent/sessions")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiAgentSessionsResponse.self, from: data)
    }

    /// POST /api/agent — Send a blocking agent chat turn.
    func apiAgentChat(message: String, sessionId: String? = nil) async throws -> ApiAgentTurnResponse {
        let url = baseURL.appendingPathComponent("api/agent")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        var body: [String: String] = ["message": message]
        if let sid = sessionId { body["session_id"] = sid }
        req.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiAgentTurnResponse.self, from: data)
    }

    /// DELETE /api/agent/sessions/:id — Delete an agent session and its history.
    func apiDeleteAgentSession(id: String) async throws {
        let url = baseURL.appendingPathComponent("api/agent/sessions/\(id)")
        let req = try makeRequest(url: url, method: "DELETE", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
    }

    // MARK: Memory

    /// GET /api/memory — List memory entries with optional pagination.
    func apiListMemory(limit: Int? = nil, offset: Int? = nil) async throws -> ApiMemoryListResponse {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/memory"),
            resolvingAgainstBaseURL: false
        )!
        var items: [URLQueryItem] = []
        if let l = limit { items.append(URLQueryItem(name: "limit", value: String(l))) }
        if let o = offset { items.append(URLQueryItem(name: "offset", value: String(o))) }
        if !items.isEmpty { components.queryItems = items }
        guard let url = components.url else { throw GatewayError.invalidURL }
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiMemoryListResponse.self, from: data)
    }

    /// GET /api/memory/stats — Memory backend statistics (count, backend type).
    func apiMemoryStats() async throws -> ApiMemoryStatsResponse {
        let url = baseURL.appendingPathComponent("api/memory/stats")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiMemoryStatsResponse.self, from: data)
    }

    /// POST /api/memory/search — Semantic search over memory entries.
    func apiSearchMemory(query: String, limit: Int? = nil) async throws -> ApiMemorySearchResponse {
        let url = baseURL.appendingPathComponent("api/memory/search")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        var body: [String: Any] = ["query": query]
        if let l = limit { body["limit"] = l }
        req.httpBody = try encoder.encode(body.mapValues { AnyEncodable($0) })
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiMemorySearchResponse.self, from: data)
    }

    /// GET /api/memory/:key — Get a specific memory entry by key.
    func apiGetMemory(key: String) async throws -> ApiMemoryEntry {
        let url = baseURL.appendingPathComponent("api/memory/\(key)")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiMemoryEntry.self, from: data)
    }

    /// DELETE /api/memory/:key — Delete a specific memory entry by key.
    func apiDeleteMemory(key: String) async throws {
        let url = baseURL.appendingPathComponent("api/memory/\(key)")
        let req = try makeRequest(url: url, method: "DELETE", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
    }

    // MARK: History

    /// GET /api/history — List all agent conversation session summaries.
    func apiListHistory() async throws -> ApiHistoryListResponse {
        let url = baseURL.appendingPathComponent("api/history")
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiHistoryListResponse.self, from: data)
    }

    /// GET /api/history/:session_id — Get conversation history for a specific session.
    func apiGetHistory(
        sessionId: String,
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> ApiHistoryDetailResponse {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/history/\(sessionId)"),
            resolvingAgainstBaseURL: false
        )!
        var items: [URLQueryItem] = []
        if let l = limit { items.append(URLQueryItem(name: "limit", value: String(l))) }
        if let o = offset { items.append(URLQueryItem(name: "offset", value: String(o))) }
        if !items.isEmpty { components.queryItems = items }
        guard let url = components.url else { throw GatewayError.invalidURL }
        let req = try makeRequest(url: url, method: "GET", authenticated: true)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decodeEnvelope(ApiHistoryDetailResponse.self, from: data)
    }

    // MARK: - Phase 5: Task History (JSON-RPC via POST /a2a)

    // Note: All task management methods are JSON-RPC, not REST.
    // Methods: tasks/list, tasks/get, tasks/cancel — all POSTed to /a2a.

    func listTasks() async throws -> [TaskSummary] {
        guard pairingMode == .notRequired || bearerToken != nil else { throw GatewayError.unpaired }
        let rpc = JSONRPCRequest(
            id: UUID().uuidString,
            method: "tasks/list",
            params: TaskListParams()
        )
        let url = baseURL.appendingPathComponent("a2a")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try a2aEncoder.encode(rpc)
        let (data, response) = try await session.data(for: req)
        try validate(response)
        let envelope = try decode(JSONRPCResponse<TaskListResult>.self, from: data)
        if let err = envelope.error { throw GatewayError.jsonRPCError(code: err.code, message: err.message) }
        return envelope.result?.tasks ?? []
    }

    func getTask(id: String) async throws -> NullClawTask {
        guard pairingMode == .notRequired || bearerToken != nil else { throw GatewayError.unpaired }
        let rpc = JSONRPCRequest(
            id: UUID().uuidString,
            method: "tasks/get",
            params: TaskIDParams(id: id)
        )
        let url = baseURL.appendingPathComponent("a2a")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try a2aEncoder.encode(rpc)
        let (data, response) = try await session.data(for: req)
        try validate(response)
        let envelope = try decode(JSONRPCResponse<NullClawTask>.self, from: data)
        if let err = envelope.error { throw GatewayError.jsonRPCError(code: err.code, message: err.message) }
        guard let task = envelope.result else {
            throw GatewayError.decodingError(underlying: DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Null result")
            ))
        }
        return task
    }

    func cancelTask(id: String) async throws {
        guard pairingMode == .notRequired || bearerToken != nil else { throw GatewayError.unpaired }
        let rpc = JSONRPCRequest(
            id: UUID().uuidString,
            method: "tasks/cancel",
            params: TaskIDParams(id: id)
        )
        let url = baseURL.appendingPathComponent("a2a")
        var req = try makeRequest(url: url, method: "POST", authenticated: true)
        req.httpBody = try a2aEncoder.encode(rpc)
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
            if
                result.kind == "artifact-update",
                let parts = result.artifact?.parts
            {
                let chunk = parts.compactMap(\.text).joined()
                if result.append == true {
                    reply += chunk
                } else {
                    reply = chunk
                }
            }
        }
        return reply
    }

    /// Sends a one-shot user prompt via `message/send` (non-streaming) and collects
    /// the complete reply text from the returned task's artifacts.
    /// Bypasses SSE entirely — useful when `message/stream` returns garbage for
    /// certain tool calls (e.g. file_read on vdsmini).
    /// Throws if the client is unpaired or the network call fails.
    func sendOneShotNonStreaming(_ prompt: String) async throws -> String {
        guard pairingMode == .notRequired || bearerToken != nil else { throw GatewayError.unpaired }
        let message = A2AMessage(
            role: "user",
            parts: [MessagePart(text: prompt, kind: "text")],
            contextId: nil
        )
        let task = try await sendMessage(message)
        // Collect text from the task's artifacts
        var reply = ""
        if let artifacts = task.artifacts {
            for artifact in artifacts {
                reply += artifact.parts.compactMap(\.text).joined()
            }
        }
        return reply
    }

    /// Sends a `/config apply set <path> <value>` slash command to the gateway
    /// via `message/send` (non-streaming). Used for mutating agent config.
    /// Throws if the client is unpaired or the network call fails.
    func sendConfigApply(path: String, value: Any) async throws {
        guard pairingMode == .notRequired || bearerToken != nil else { throw GatewayError.unpaired }
        let prompt = "/config apply set \(path) \(value)"
        let message = A2AMessage(
            role: "user",
            parts: [MessagePart(text: prompt, kind: "text")],
            contextId: nil
        )
        _ = try await sendMessage(message)
    }

    /// Sends a `/config reload` slash command to the gateway via `message/send`
    /// (non-streaming). Used after config mutations that support hot-reload.
    /// Throws if the client is unpaired or the network call fails.
    func sendConfigReload() async throws {
        guard pairingMode == .notRequired || bearerToken != nil else { throw GatewayError.unpaired }
        let message = A2AMessage(
            role: "user",
            parts: [MessagePart(text: "/config reload", kind: "text")],
            contextId: nil
        )
        _ = try await sendMessage(message)
    }

    // MARK: - Helpers

    private func makeRequest(url: URL, method: String, authenticated: Bool = false) throws -> URLRequest {
        try GatewayNetworking.makeRequest(url: url, method: method, token: bearerToken, authenticated: authenticated)
    }

    private func validate(_ response: URLResponse, data: Data? = nil) throws {
        try GatewayNetworking.validate(response, data: data, decoder: decoder)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try GatewayNetworking.decode(type, from: data, using: decoder)
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
                .init(codingPath: [], debugDescription: "Invalid UTF-8 SSE event")
            ))
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
                .init(codingPath: [], debugDescription: "Invalid UTF-8 SSE payload")
            ))
        }
        do {
            let envelope = try decoder.decode(JSONRPCResponse<StreamEvent>.self, from: data)
            if let error = envelope.error {
                throw GatewayError.jsonRPCError(code: error.code, message: error.message)
            }
            guard envelope.result != nil else {
                throw GatewayError.decodingError(underlying: DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "SSE event missing result")
                ))
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
            for index in start ... (count - 4) {
                if
                    buffer[index] == 13,
                    buffer[index + 1] == 10,
                    buffer[index + 2] == 13,
                    buffer[index + 3] == 10
                {
                    return (eventEnd: index - start, consumedLength: index - start + 4)
                }
            }
        }
        if count - start >= 2 {
            for index in start ... (count - 2) {
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
