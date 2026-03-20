import Foundation

// MARK: - AutonomyConfig model

/// Live-editable autonomy and safety configuration fields from the gateway's autonomy block.
/// Field names mirror the real config schema in ~/.nullclaw/config.json under `autonomy`.
struct AutonomyConfig: Sendable, Equatable {
    var level: String = "medium"                           // "low" | "medium" | "high"
    var maxActionsPerHour: Int = 60                        // autonomy.max_actions_per_hour
    var blockHighRiskCommands: Bool = true                 // autonomy.block_high_risk_commands
    var requireApprovalForMediumRisk: Bool = false         // autonomy.require_approval_for_medium_risk
    var allowedCommands: [String] = []                     // autonomy.allowed_commands
}

// MARK: - Parse error

enum AutonomyConfigParseError: Error, LocalizedError, Sendable {
    case noConfigFound
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noConfigFound:
            return "No autonomy configuration data found in the agent reply."
        case .decodingFailed(let detail):
            return "Failed to parse autonomy configuration: \(detail)"
        }
    }
}

// MARK: - ViewModel

@Observable @MainActor
final class AutonomyViewModel {

    // MARK: Published state

    private(set) var config: AutonomyConfig = AutonomyConfig()
    private(set) var isLoading: Bool = false
    private(set) var isSaving: Bool = false
    private(set) var isLoaded: Bool = false
    var errorMessage: String? = nil
    var confirmationMessage: String? = nil

    // MARK: Dependencies

    var client: GatewayClient?

    // MARK: Init

    init(client: GatewayClient? = nil) {
        self.client = client
    }

    /// Invalidates the underlying URLSession. Call from the view's `.onDisappear` to
    /// release the session and avoid orphaned network connections.
    func invalidate() {
        let c = client
        Task { await c?.invalidate() }
    }

    // MARK: - Load

    /// Asks the agent for the current autonomy configuration and parses the reply.
    func load() async {
        guard !isLoading else { return }
        guard let c = client else {
            errorMessage = "No gateway client available."
            return
        }
        isLoading = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isLoading = false }

        do {
            let reply = try await c.sendOneShot(Self.loadPrompt)
            config = try parseConfig(from: reply)
            isLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Setters

    func setLevel(_ level: String) async {
        await applyChange(
            prompt: "Update autonomy.level to \"\(level)\" in ~/.nullclaw/config.json.",
            update: { $0.level = level },
            confirmation: "Autonomy level set to \"\(level)\"."
        )
    }

    func setMaxActionsPerHour(_ value: Int) async {
        await applyChange(
            prompt: "Update autonomy.max_actions_per_hour to \(value) in ~/.nullclaw/config.json.",
            update: { $0.maxActionsPerHour = value },
            confirmation: "Max actions per hour set to \(value)."
        )
    }

    func setBlockHighRiskCommands(_ enabled: Bool) async {
        await applyChange(
            prompt: "Update autonomy.block_high_risk_commands to \(enabled) in ~/.nullclaw/config.json.",
            update: { $0.blockHighRiskCommands = enabled },
            confirmation: "Block high-risk commands \(enabled ? "enabled" : "disabled")."
        )
    }

    func setRequireApprovalForMediumRisk(_ enabled: Bool) async {
        await applyChange(
            prompt: "Update autonomy.require_approval_for_medium_risk to \(enabled) in ~/.nullclaw/config.json.",
            update: { $0.requireApprovalForMediumRisk = enabled },
            confirmation: "Require approval for medium-risk \(enabled ? "enabled" : "disabled")."
        )
    }

    func setAllowedCommands(_ commands: [String]) async {
        let jsonArray = "[" + commands.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
        await applyChange(
            prompt: "Update autonomy.allowed_commands to \(jsonArray) in ~/.nullclaw/config.json.",
            update: { $0.allowedCommands = commands },
            confirmation: "Allowed commands list updated."
        )
    }

    // MARK: - Parse (internal — visible for tests)

    /// Parses an `AutonomyConfig` from an agent reply that contains a JSON object.
    /// The parser is lenient: it extracts the first `{…}` block found in `text`.
    func parseConfig(from text: String) throws -> AutonomyConfig {
        guard
            let start = text.firstIndex(of: "{"),
            let end = text.lastIndex(of: "}")
        else {
            throw AutonomyConfigParseError.noConfigFound
        }

        let jsonString = String(text[start...end])
        guard let data = jsonString.data(using: .utf8) else {
            throw AutonomyConfigParseError.decodingFailed("UTF-8 encoding failed")
        }

        do {
            let raw = try JSONDecoder().decode(AutonomyConfigRaw.self, from: data)
            var c = AutonomyConfig()
            c.level = raw.level ?? "medium"
            c.maxActionsPerHour = raw.max_actions_per_hour ?? 60
            c.blockHighRiskCommands = raw.block_high_risk_commands ?? true
            c.requireApprovalForMediumRisk = raw.require_approval_for_medium_risk ?? false
            c.allowedCommands = raw.allowed_commands ?? []
            return c
        } catch {
            throw AutonomyConfigParseError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Private helpers

    private func applyChange(
        prompt: String,
        update: (inout AutonomyConfig) -> Void,
        confirmation: String
    ) async {
        guard let c = client else {
            errorMessage = "No gateway client available."
            return
        }
        isSaving = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isSaving = false }

        do {
            _ = try await c.sendOneShot(prompt)
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
        "level" (string, from autonomy.level, e.g. "low", "medium", or "high"), \
        "max_actions_per_hour" (integer, from autonomy.max_actions_per_hour), \
        "block_high_risk_commands" (boolean, from autonomy.block_high_risk_commands), \
        "require_approval_for_medium_risk" (boolean, from autonomy.require_approval_for_medium_risk), \
        "allowed_commands" (array of strings, from autonomy.allowed_commands).
        """
}

// MARK: - Private decoding shim

/// Intermediate Decodable used only by `parseConfig(from:)`.
/// Accepts the canonical autonomy config key names from the gateway config.
private struct AutonomyConfigRaw: Decodable {
    var level: String?
    var max_actions_per_hour: Int?
    var block_high_risk_commands: Bool?
    var require_approval_for_medium_risk: Bool?
    var allowed_commands: [String]?
}
