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
    var parallelTools: Bool = false        // config: agent.parallel_tools

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
            let reply = try await client.sendOneShot(Self.loadPrompt)
            config = try parseConfig(from: reply)
            isLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Setters

    func setTemperature(_ value: Double) async {
        await applyChange(
            prompt: "Set the default temperature to \(String(format: "%.2f", value)).",
            update: { $0.temperature = value },
            confirmation: "Temperature set to \(String(format: "%.2f", value))."
        )
    }

    func setPrimaryModel(_ model: String) async {
        guard !model.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        await applyChange(
            prompt: "Update agents.defaults.model.primary to \"\(model)\" in ~/.nullclaw/config.json.",
            update: { $0.primaryModel = model },
            confirmation: "Primary model set to \"\(model)\"."
        )
    }

    func setMaxToolIterations(_ value: Int) async {
        await applyChange(
            prompt: "Update agent.max_tool_iterations to \(value) in ~/.nullclaw/config.json.",
            update: { $0.maxToolIterations = value },
            confirmation: "Max tool iterations set to \(value)."
        )
    }

    func setMessageTimeout(_ seconds: Int) async {
        await applyChange(
            prompt: "Update agent.message_timeout_secs to \(seconds) in ~/.nullclaw/config.json.",
            update: { $0.messageTimeoutSecs = seconds },
            confirmation: "Message timeout set to \(seconds)s."
        )
    }

    func setParallelTools(_ enabled: Bool) async {
        await applyChange(
            prompt: "Update agent.parallel_tools to \(enabled) in ~/.nullclaw/config.json.",
            update: { $0.parallelTools = enabled },
            confirmation: "Parallel tools \(enabled ? "enabled" : "disabled")."
        )
    }

    func setCompactContext(_ enabled: Bool) async {
        await applyChange(
            prompt: "Update agent.compact_context to \(enabled) in ~/.nullclaw/config.json.",
            update: { $0.compactContext = enabled },
            confirmation: "Compact context \(enabled ? "enabled" : "disabled")."
        )
    }

    func setCompactionThreshold(_ value: Int) async {
        await applyChange(
            prompt: "Update agent.compaction_max_source_chars to \(value) in ~/.nullclaw/config.json.",
            update: { $0.compactionThreshold = value },
            confirmation: "Compaction threshold set to \(value) chars."
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
            c.parallelTools = raw.parallel_tools ?? raw.parallel_tools_enabled ?? false
            c.compactContext = raw.compact_context ?? raw.compaction_enabled ?? false
            c.compactionThreshold = raw.compaction_max_source_chars ?? raw.compaction_threshold ?? 8000
            return c
        } catch {
            throw AgentConfigParseError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Private helpers

    private func applyChange(
        prompt: String,
        update: (inout AgentConfig) -> Void,
        confirmation: String
    ) async {
        isSaving = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isSaving = false }

        do {
            _ = try await client.sendOneShot(prompt)
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
        "parallel_tools" (boolean, from agent.parallel_tools), \
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
    var parallel_tools: Bool?
    // Limits — legacy names the agent sometimes emits
    var message_timeout_seconds: Int?
    var parallel_tools_enabled: Bool?
    // Compaction — canonical
    var compact_context: Bool?
    var compaction_max_source_chars: Int?
    // Compaction — legacy
    var compaction_enabled: Bool?
    var compaction_threshold: Int?
}
