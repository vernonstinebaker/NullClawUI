import Foundation

// MARK: - AgentConfig model

/// Live-editable agent configuration fields surfaced by the gateway's config_mutator.
/// Field names mirror the real config schema in ~/.nullclaw/config.json.
struct AgentConfig: Sendable, Equatable {
    // Model
    var primaryModel: String = ""
    var provider: String = ""

    // Sampling
    var temperature: Double = 1.0          // config: default_temperature (top-level)

    // Limits
    var maxToolIterations: Int = 25        // config: agent.max_tool_iterations
    var messageTimeoutSecs: Int = 300      // config: agent.message_timeout_secs
    // NOTE: agent.parallel_tools is a dead stub in the gateway (no runtime effect) — omitted.

    // Memory / Compaction
    var compactContext: Bool = false       // config: agent.compact_context
    var compactionThreshold: Int = 8000   // config: agent.compaction_max_source_chars (proxy)
}

// MARK: - Parse error

enum AgentConfigParseError: Error, LocalizedError, Sendable {
    case noConfigFound
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noConfigFound:
            return "No configuration data found in the agent reply."
        case .decodingFailed(let detail):
            return "Failed to parse agent configuration: \(detail)"
        }
    }
}

// MARK: - ViewModel

@Observable @MainActor
final class AgentConfigViewModel {

    // MARK: Published state

    private(set) var config: AgentConfig = AgentConfig()
    private(set) var isLoading: Bool = false
    private(set) var isSaving: Bool = false
    private(set) var isLoaded: Bool = false
    var errorMessage: String? = nil
    var confirmationMessage: String? = nil

    // MARK: Dependencies

    var client: GatewayClient

    // MARK: Init

    init(client: GatewayClient) {
        self.client = client
    }

    /// Invalidates the underlying URLSession. Call from the view's `.onDisappear` to
    /// release the session and avoid orphaned network connections.
    func invalidate() {
        let c = client
        Task { await c.invalidate() }
    }

    // MARK: - Load

    /// Asks the agent for the current configuration and parses the reply.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isLoading = false }

        do {
            let reply = try await client.sendOneShotNonStreaming(Self.loadPrompt)
            config = try parseConfig(from: reply)
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
        // Hot-reloadable: default_temperature
        await applyChange(
            path: "default_temperature",
            value: String(format: "%.2f", value),
            hotReload: true,
            update: { $0.temperature = value },
            confirmation: "Temperature set to \(String(format: "%.2f", value))."
        )
    }

    func setPrimaryModel(_ model: String) async {
        guard !model.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        // Hot-reloadable: agents.defaults.model.primary (value must be a JSON string)
        let jsonString = "\"\(model)\""
        await applyChange(
            path: "agents.defaults.model.primary",
            value: jsonString,
            hotReload: true,
            update: { $0.primaryModel = model },
            confirmation: "Primary model set to \"\(model)\"."
        )
    }

    func setMaxToolIterations(_ value: Int) async {
        // Hot-reloadable: agent.max_tool_iterations
        await applyChange(
            path: "agent.max_tool_iterations",
            value: "\(value)",
            hotReload: true,
            update: { $0.maxToolIterations = value },
            confirmation: "Max tool iterations set to \(value)."
        )
    }

    func setMessageTimeout(_ seconds: Int) async {
        // Hot-reloadable: agent.message_timeout_secs
        await applyChange(
            path: "agent.message_timeout_secs",
            value: "\(seconds)",
            hotReload: true,
            update: { $0.messageTimeoutSecs = seconds },
            confirmation: "Message timeout set to \(seconds)s."
        )
    }

    func setCompactContext(_ enabled: Bool) async {
        // NOT hot-reloadable — persisted to disk, takes effect on next gateway restart.
        await applyChange(
            path: "agent.compact_context",
            value: enabled ? "true" : "false",
            hotReload: false,
            update: { $0.compactContext = enabled },
            confirmation: "Compact context \(enabled ? "enabled" : "disabled"). Restart gateway to apply."
        )
    }

    func setCompactionThreshold(_ value: Int) async {
        // NOT hot-reloadable — persisted to disk, takes effect on next gateway restart.
        await applyChange(
            path: "agent.compaction_max_source_chars",
            value: "\(value)",
            hotReload: false,
            update: { $0.compactionThreshold = value },
            confirmation: "Compaction threshold set to \(value) chars. Restart gateway to apply."
        )
    }

    // MARK: - Parse (internal — visible for tests)

    /// Parses an `AgentConfig` from an agent reply that contains a JSON object.
    /// The parser is lenient: it extracts the first `{…}` block found in `text`.
    func parseConfig(from text: String) throws -> AgentConfig {
        guard
            let start = text.firstIndex(of: "{"),
            let end = text.lastIndex(of: "}")
        else {
            throw AgentConfigParseError.noConfigFound
        }

        let jsonString = String(text[start...end])
        guard let data = jsonString.data(using: .utf8) else {
            throw AgentConfigParseError.decodingFailed("UTF-8 encoding failed")
        }

        do {
            let raw = try JSONDecoder().decode(AgentConfigRaw.self, from: data)
            var c = AgentConfig()
            c.primaryModel = raw.primary_model ?? ""
            c.provider = raw.provider ?? ""
            c.temperature = raw.temperature ?? 1.0
            c.maxToolIterations = raw.max_tool_iterations ?? 25
            // Accept both key variants the agent may emit
            c.messageTimeoutSecs = raw.message_timeout_secs ?? raw.message_timeout_seconds ?? 300
            c.compactContext = raw.compact_context ?? raw.compaction_enabled ?? false
            c.compactionThreshold = raw.compaction_max_source_chars ?? raw.compaction_threshold ?? 8000
            return c
        } catch {
            throw AgentConfigParseError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Private helpers

    /// Applies a config change via `/config apply set <path> <value>`, optionally
    /// followed by `/config reload` for hot-reloadable fields.
    private func applyChange(
        path: String,
        value: String,
        hotReload: Bool,
        update: (inout AgentConfig) -> Void,
        confirmation: String
    ) async {
        isSaving = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isSaving = false }

        do {
            try await client.sendConfigApply(path: path, value: value)
            if hotReload {
                try await client.sendConfigReload()
            }
            update(&config)
            confirmationMessage = confirmation
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Prompt constants (visible for tests)

    static let loadPrompt = """
        Read ~/.nullclaw/config.json and respond with ONLY a valid JSON object, no extra text. \
        The JSON must have exactly these keys: \
        "primary_model" (string, from agents.defaults.model.primary), \
        "provider" (string, infer from primary_model prefix or models.providers), \
        "temperature" (number, from default_temperature), \
        "max_tool_iterations" (integer, from agent.max_tool_iterations), \
        "message_timeout_secs" (integer, from agent.message_timeout_secs), \
        "compact_context" (boolean, from agent.compact_context), \
        "compaction_max_source_chars" (integer, from agent.compaction_max_source_chars).
        """
}

// MARK: - Private decoding shim

/// Intermediate Decodable used only by `parseConfig(from:)`.
/// Accepts both the canonical config key names and legacy/alternate names
/// the agent may emit when constructing the reply from its own reasoning.
private struct AgentConfigRaw: Decodable {
    // Model
    var primary_model: String?
    var provider: String?
    // Sampling
    var temperature: Double?
    // Limits — canonical
    var max_tool_iterations: Int?
    var message_timeout_secs: Int?
    // Limits — legacy names the agent sometimes emits
    var message_timeout_seconds: Int?
    // Compaction — canonical
    var compact_context: Bool?
    var compaction_max_source_chars: Int?
    // Compaction — legacy
    var compaction_enabled: Bool?
    var compaction_threshold: Int?
}
