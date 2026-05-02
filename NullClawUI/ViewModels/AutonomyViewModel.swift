import Foundation

// MARK: - AutonomyConfig model

/// Live-editable autonomy and safety configuration fields from the gateway's autonomy block.
/// Field names mirror the real config schema in ~/.nullclaw/config.json under `autonomy`.
struct AutonomyConfig: Equatable {
    var level: String = "medium" // "low" | "medium" | "high"
    var maxActionsPerHour: Int = 60 // autonomy.max_actions_per_hour
    var blockHighRiskCommands: Bool = true // autonomy.block_high_risk_commands
    var requireApprovalForMediumRisk: Bool = false // autonomy.require_approval_for_medium_risk
    var allowedCommands: [String] = [] // autonomy.allowed_commands
}

// MARK: - REST payload struct

/// Decoded from GET /api/config?path=autonomy → data.value
/// Keys use camelCase to match the InstanceGatewayClient decoder's convertFromSnakeCase strategy.
struct AutonomyConfigPayload: Decodable {
    var level: String?
    var maxActionsPerHour: Int?
    var blockHighRiskCommands: Bool?
    var requireApprovalForMediumRisk: Bool?
    var allowedCommands: [String]?
    /// Additional fields present in the live gateway response (not exposed in the UI):
    var workspaceOnly: Bool?
}

// MARK: - ViewModel

@Observable
@MainActor
final class AutonomyViewModel {
    // MARK: Published state

    private(set) var config: AutonomyConfig = .init()
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

    /// Fetches autonomy configuration via REST (GET /api/config?path=autonomy).
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isLoading = false }

        do {
            let payload = try await client.apiConfigObjectValue(path: "autonomy", as: AutonomyConfigPayload.self)
            config = Self.buildConfig(from: payload)
            isLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Setters

    //
    // autonomy.* paths are NOT in the gateway's hot_reload_paths list.
    // Changes are persisted to disk via PATCH /api/config and take effect on next restart.

    func setLevel(_ level: String) async {
        await applyChange(
            path: "autonomy.level",
            value: level,
            update: { $0.level = level },
            confirmation: "Autonomy level set to \"\(level)\". Restart gateway to apply."
        )
    }

    func setMaxActionsPerHour(_ value: Int) async {
        await applyChange(
            path: "autonomy.max_actions_per_hour",
            value: value,
            update: { $0.maxActionsPerHour = value },
            confirmation: "Max actions per hour set to \(value). Restart gateway to apply."
        )
    }

    func setBlockHighRiskCommands(_ enabled: Bool) async {
        await applyChange(
            path: "autonomy.block_high_risk_commands",
            value: enabled,
            update: { $0.blockHighRiskCommands = enabled },
            confirmation: "Block high-risk commands \(enabled ? "enabled" : "disabled"). Restart gateway to apply."
        )
    }

    func setRequireApprovalForMediumRisk(_ enabled: Bool) async {
        await applyChange(
            path: "autonomy.require_approval_for_medium_risk",
            value: enabled,
            update: { $0.requireApprovalForMediumRisk = enabled },
            confirmation: "Require approval for medium-risk \(enabled ? "enabled" : "disabled"). Restart gateway to apply."
        )
    }

    func setAllowedCommands(_ commands: [String]) async {
        await applyChange(
            path: "autonomy.allowed_commands",
            value: commands,
            update: { $0.allowedCommands = commands },
            confirmation: "Allowed commands list updated. Restart gateway to apply."
        )
    }

    // MARK: - Build config (internal — visible for tests)

    /// Converts a decoded AutonomyConfigPayload into an AutonomyConfig.
    static func buildConfig(from payload: AutonomyConfigPayload) -> AutonomyConfig {
        var c = AutonomyConfig()
        c.level = payload.level ?? "medium"
        c.maxActionsPerHour = payload.maxActionsPerHour ?? 60
        c.blockHighRiskCommands = payload.blockHighRiskCommands ?? true
        c.requireApprovalForMediumRisk = payload.requireApprovalForMediumRisk ?? false
        c.allowedCommands = payload.allowedCommands ?? []
        return c
    }

    // MARK: - Private helpers

    /// Applies a config change via the REST Admin API PATCH /api/config.
    /// Autonomy paths are not hot-reloadable — changes take effect on next gateway restart.
    private func applyChange(
        path: String,
        value: some Encodable & Sendable,
        update: (inout AutonomyConfig) -> Void,
        confirmation: String
    ) async {
        isSaving = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isSaving = false }

        do {
            try await client.apiSetConfigValue(path: path, value: value)
            update(&config)
            confirmationMessage = confirmation
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
