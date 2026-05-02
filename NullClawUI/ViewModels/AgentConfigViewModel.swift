import Foundation

// MARK: - AgentConfig model

/// Live-editable agent configuration fields surfaced by the gateway's config_mutator.
/// Field names mirror the real config schema in ~/.nullclaw/config.json.
struct AgentConfig: Equatable {
    // Model
    var primaryModel: String = ""
    var provider: String = ""

    /// Sampling
    var temperature: Double = 1.0 // config: default_temperature (top-level)

    // Limits
    var maxToolIterations: Int = 25 // config: agent.max_tool_iterations
    var messageTimeoutSecs: Int = 300 // config: agent.message_timeout_secs
    // NOTE: agent.parallel_tools is a dead stub in the gateway (no runtime effect) — omitted.

    // Memory / Compaction
    var compactContext: Bool = false // config: agent.compact_context
    var compactionThreshold: Int = 8000 // config: agent.compaction_max_source_chars (proxy)
}

// MARK: - REST payload structs

/// Decoded from GET /api/config?path=agent → data.value
/// Keys use camelCase to match the InstanceGatewayClient decoder's convertFromSnakeCase strategy.
struct AgentConfigPayload: Decodable {
    var compactContext: Bool?
    var maxToolIterations: Int?
    var maxHistoryMessages: Int?
    var parallelTools: Bool?
    var sessionIdleTimeoutSecs: Int?
    var compactionKeepRecent: Int?
    var compactionMaxSummaryChars: Int?
    var compactionMaxSourceChars: Int?
    var messageTimeoutSecs: Int?
}

// MARK: - ViewModel

@Observable
@MainActor
final class AgentConfigViewModel {
    // MARK: Published state

    private(set) var config: AgentConfig = .init()
    private(set) var isLoading: Bool = false
    private(set) var isSaving: Bool = false
    private(set) var isLoaded: Bool = false
    var errorMessage: String?
    var confirmationMessage: String?

    // MARK: Dependencies

    var client: InstanceGatewayClient

    // MARK: Init

    init(client: InstanceGatewayClient) {
        self.client = client
    }

    /// Invalidates the underlying URLSession. Call from the view's `.onDisappear` to
    /// release the session and avoid orphaned network connections.
    func invalidate() {
        let c = client
        Task { await c.invalidate() }
    }

    // MARK: - Load

    /// Fetches agent configuration via REST (GET /api/config?path=agent and GET /api/models).
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isLoading = false }

        do {
            async let agentPayload = client.apiConfigObjectValue(path: "agent", as: AgentConfigPayload.self)
            async let modelsPayload = client.apiModels()

            let (agent, models) = try await (agentPayload, modelsPayload)
            config = Self.buildConfig(from: agent, models: models)
            isLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Setters

    //
    // Hot-reloadable paths (gateway applies changes to the running process without restart):
    //   agents.defaults.model.primary, default_temperature,
    //   agent.max_tool_iterations, agent.message_timeout_secs
    //
    // Non-hot-reloadable paths (persisted to disk, take effect on next gateway restart):
    //   agent.compact_context, agent.compaction_max_source_chars

    func setTemperature(_ value: Double) async {
        await applyChange(
            path: "default_temperature",
            value: value,
            hotReload: true,
            update: { $0.temperature = value },
            confirmation: "Temperature set to \(String(format: "%.2f", value))."
        )
    }

    func setPrimaryModel(_ model: String) async {
        guard !model.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        await applyChange(
            path: "agents.defaults.model.primary",
            value: model,
            hotReload: true,
            update: { $0.primaryModel = model },
            confirmation: "Primary model set to \"\(model)\"."
        )
    }

    func setMaxToolIterations(_ value: Int) async {
        await applyChange(
            path: "agent.max_tool_iterations",
            value: value,
            hotReload: true,
            update: { $0.maxToolIterations = value },
            confirmation: "Max tool iterations set to \(value)."
        )
    }

    func setMessageTimeout(_ seconds: Int) async {
        await applyChange(
            path: "agent.message_timeout_secs",
            value: seconds,
            hotReload: true,
            update: { $0.messageTimeoutSecs = seconds },
            confirmation: "Message timeout set to \(seconds)s."
        )
    }

    func setCompactContext(_ enabled: Bool) async {
        await applyChange(
            path: "agent.compact_context",
            value: enabled,
            hotReload: false,
            update: { $0.compactContext = enabled },
            confirmation: "Compact context \(enabled ? "enabled" : "disabled"). Restart gateway to apply."
        )
    }

    func setCompactionThreshold(_ value: Int) async {
        await applyChange(
            path: "agent.compaction_max_source_chars",
            value: value,
            hotReload: false,
            update: { $0.compactionThreshold = value },
            confirmation: "Compaction threshold set to \(value) chars. Restart gateway to apply."
        )
    }

    // MARK: - Build config (internal — visible for tests)

    /// Combines a decoded AgentConfigPayload and ApiModelsResponse into an AgentConfig.
    static func buildConfig(from agent: AgentConfigPayload, models: ApiModelsResponse) -> AgentConfig {
        var c = AgentConfig()
        c.primaryModel = models.defaultModel ?? ""
        c.provider = models.defaultProvider
        c.temperature = 1.0 // default_temperature is a top-level scalar; fetched separately if needed
        c.maxToolIterations = agent.maxToolIterations ?? 25
        c.messageTimeoutSecs = agent.messageTimeoutSecs ?? 300
        c.compactContext = agent.compactContext ?? false
        c.compactionThreshold = agent.compactionMaxSourceChars ?? 8000
        return c
    }

    // MARK: - Private helpers

    /// Applies a config change via the REST Admin API PATCH /api/config, optionally
    /// followed by POST /api/config/reload for hot-reloadable fields.
    private func applyChange(
        path: String,
        value: some Encodable & Sendable,
        hotReload: Bool,
        update: @MainActor (inout AgentConfig) -> Void,
        confirmation: String
    ) async {
        isSaving = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isSaving = false }

        do {
            let c = client
            try await c.apiSetConfigValue(path: path, value: value)
            if hotReload {
                _ = try await c.apiReloadConfig()
            }
            update(&config)
            confirmationMessage = confirmation
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
