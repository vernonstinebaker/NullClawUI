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

    let client: HubGatewayClient
    let instance: String
    let component: String

    // MARK: Init

    init(client: HubGatewayClient, instance: String = "default", component: String = "nullclaw") {
        self.client = client
        self.instance = instance
        self.component = component
    }

    /// Invalidates the underlying URLSession. Call from the view's `.onDisappear` to
    /// release the session and avoid orphaned network connections.
    func invalidate() {
        let c = client
        Task { await c.invalidate() }
    }

    // MARK: - Load

    /// Fetches autonomy configuration via Hub management API.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isLoading = false }

        do {
            let data = try await client.getConfig(instance: instance, component: component, path: "autonomy")
            config = Self.buildConfig(from: data)
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
        let valueString: String = if
            let data = try? JSONEncoder().encode(commands), let json = String(
                data: data,
                encoding: .utf8
            )
        {
            json
        } else {
            String(describing: commands)
        }
        await applyChange(
            path: "autonomy.allowed_commands",
            value: valueString,
            update: { $0.allowedCommands = commands },
            confirmation: "Allowed commands list updated. Restart gateway to apply."
        )
    }

    // MARK: - Build config (internal — visible for tests)

    /// Converts decoded autonomy config data into an AutonomyConfig.
    static func buildConfig(from configData: Data) -> AutonomyConfig {
        var c = AutonomyConfig()

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard
            let envelope = try? decoder.decode(ConfigValueResponse.self, from: configData),
            let raw = envelope.value?.value as? [String: Any] else { return c }

        c.level = raw["level"] as? String ?? "medium"
        c.maxActionsPerHour = raw["max_actions_per_hour"] as? Int ?? 60
        c.blockHighRiskCommands = raw["block_high_risk_commands"] as? Bool ?? true
        c.requireApprovalForMediumRisk = raw["require_approval_for_medium_risk"] as? Bool ?? false
        c.allowedCommands = raw["allowed_commands"] as? [String] ?? []
        return c
    }

    // MARK: - Private helpers

    /// Applies a config change via Hub setConfig.
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
            try await client.setConfig(
                instance: instance,
                component: component,
                path: path,
                value: String(describing: value)
            )
            update(&config)
            confirmationMessage = confirmation
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
