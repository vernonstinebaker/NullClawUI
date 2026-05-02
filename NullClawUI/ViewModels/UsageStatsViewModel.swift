import Foundation

// MARK: - Parse error

enum UsageStatsParseError: Error, LocalizedError {
    case noDataFound
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDataFound:
            "No usage data found in the agent reply."
        case let .decodingFailed(detail):
            "Failed to parse usage data: \(detail)"
        }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class UsageStatsViewModel {
    // MARK: Published state

    private(set) var stats: UsageStats = .init()
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

    /// Fetches cost configuration via Hub getConfig and usage via getInstanceUsage.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isLoading = false }

        do {
            async let costData = client.getConfig(instance: instance, component: component, path: "cost")
            async let usageData = client.getInstanceUsage(instance: instance, component: component)

            let (cost, usage) = try await (costData, usageData)
            stats = Self.buildStats(from: cost, usage: usage)
            isLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Setters

    func setCostEnabled(_ enabled: Bool) async {
        let value = enabled ? "true" : "false"
        await applyChange(
            path: "cost.enabled",
            value: value,
            update: { $0.costEnabled = enabled },
            confirmation: "Cost tracking \(enabled ? "enabled" : "disabled")."
        )
    }

    func setDailyLimit(_ usd: Double) async {
        await applyChange(
            path: "cost.daily_limit_usd",
            value: String(usd),
            update: { $0.dailyLimitUSD = usd },
            confirmation: String(format: "Daily limit set to $%.2f.", usd)
        )
    }

    func setMonthlyLimit(_ usd: Double) async {
        await applyChange(
            path: "cost.monthly_limit_usd",
            value: String(usd),
            update: { $0.monthlyLimitUSD = usd },
            confirmation: String(format: "Monthly limit set to $%.2f.", usd)
        )
    }

    func setWarnAtPercent(_ percent: Int) async {
        let clamped = max(1, min(100, percent))
        await applyChange(
            path: "cost.warn_at_percent",
            value: String(clamped),
            update: { $0.warnAtPercent = clamped },
            confirmation: "Warning threshold set to \(clamped)%."
        )
    }

    // MARK: - Build stats (internal — visible for tests)

    /// Builds a UsageStats from a cost config dict and a usage response dict.
    static func buildStats(from costData: Data, usage: Data) -> UsageStats {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let costDict = (try? JSONSerialization.jsonObject(with: costData) as? [String: Any])?.compactMapValues
            { $0 as? String } ?? [:]
        let usageDict = (try? JSONSerialization.jsonObject(with: usage) as? [String: Any])?.compactMapValues
            { $0 as? String } ?? [:]
        var s = UsageStats()
        s.costEnabled = costDict["enabled"] == "true" || costDict["enabled"] == "1"
        s.dailyLimitUSD = costDict["daily_limit_usd"].flatMap(Double.init) ?? 0.0
        s.monthlyLimitUSD = costDict["monthly_limit_usd"].flatMap(Double.init) ?? 0.0
        s.warnAtPercent = costDict["warn_at_percent"].flatMap(Int.init) ?? 80
        s.sessionCostUSD = usageDict["session_cost_usd"].flatMap(Double.init) ?? 0.0
        s.dailyCostUSD = usageDict["daily_cost_usd"].flatMap(Double.init) ?? 0.0
        s.monthlyCostUSD = usageDict["monthly_cost_usd"].flatMap(Double.init) ?? 0.0
        s.totalTokens = usageDict["total_tokens"].flatMap(Int.init) ?? 0
        s.requestCount = usageDict["request_count"].flatMap(Int.init) ?? 0
        return s
    }

    // MARK: - Private helpers

    private func applyChange(
        path: String,
        value: String,
        update: (inout UsageStats) -> Void,
        confirmation: String
    ) async {
        isSaving = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isSaving = false }

        do {
            try await client.setConfig(instance: instance, component: component, path: path, value: value)
            update(&stats)
            confirmationMessage = confirmation
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
