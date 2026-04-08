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

    /// Asks the agent for the current cost configuration and usage summary,
    /// parses the combined JSON reply into a `UsageStats` value.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isLoading = false }

        do {
            let reply = try await client.sendOneShotNonStreaming(Self.loadPrompt)
            stats = try parseStats(from: reply)
            isLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Setters

    func setCostEnabled(_ enabled: Bool) async {
        await applyChange(
            prompt: "Update cost.enabled to \(enabled) in ~/.nullclaw/config.json.",
            update: { $0.costEnabled = enabled },
            confirmation: "Cost tracking \(enabled ? "enabled" : "disabled")."
        )
    }

    func setDailyLimit(_ usd: Double) async {
        await applyChange(
            prompt: "Update cost.daily_limit_usd to \(usd) in ~/.nullclaw/config.json.",
            update: { $0.dailyLimitUSD = usd },
            confirmation: String(format: "Daily limit set to $%.2f.", usd)
        )
    }

    func setMonthlyLimit(_ usd: Double) async {
        await applyChange(
            prompt: "Update cost.monthly_limit_usd to \(usd) in ~/.nullclaw/config.json.",
            update: { $0.monthlyLimitUSD = usd },
            confirmation: String(format: "Monthly limit set to $%.2f.", usd)
        )
    }

    func setWarnAtPercent(_ percent: Int) async {
        let clamped = max(1, min(100, percent))
        await applyChange(
            prompt: "Update cost.warn_at_percent to \(clamped) in ~/.nullclaw/config.json.",
            update: { $0.warnAtPercent = clamped },
            confirmation: "Warning threshold set to \(clamped)%."
        )
    }

    // MARK: - Parse (internal — visible for tests)

    /// Parses a `UsageStats` from an agent reply containing a JSON object.
    /// Lenient: extracts the first `{…}` block found in `text`.
    func parseStats(from text: String) throws -> UsageStats {
        guard
            let start = text.firstIndex(of: "{"),
            let end = text.lastIndex(of: "}") else
        {
            throw UsageStatsParseError.noDataFound
        }

        let jsonString = String(text[start ... end])
        guard let data = jsonString.data(using: .utf8) else {
            throw UsageStatsParseError.decodingFailed("UTF-8 encoding failed")
        }

        do {
            let raw = try JSONDecoder().decode(UsageStatsRaw.self, from: data)
            var s = UsageStats()
            s.sessionCostUSD = raw.session_cost_usd ?? 0.0
            s.dailyCostUSD = raw.daily_cost_usd ?? 0.0
            s.monthlyCostUSD = raw.monthly_cost_usd ?? 0.0
            s.totalTokens = raw.total_tokens ?? 0
            s.requestCount = raw.request_count ?? 0
            s.costEnabled = raw.cost_enabled ?? false
            s.dailyLimitUSD = raw.daily_limit_usd ?? 0.0
            s.monthlyLimitUSD = raw.monthly_limit_usd ?? 0.0
            s.warnAtPercent = raw.warn_at_percent ?? 80
            return s
        } catch {
            throw UsageStatsParseError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Private helpers

    private func applyChange(
        prompt: String,
        update: (inout UsageStats) -> Void,
        confirmation: String
    ) async {
        isSaving = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isSaving = false }

        do {
            _ = try await client.sendOneShot(prompt)
            update(&stats)
            confirmationMessage = confirmation
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Prompt constants (visible for tests)

    /// Single prompt that fetches both config limits and live usage in one round-trip.
    /// The agent reads `config.json` for the cost settings and `state/costs.jsonl` for
    /// the usage summary, then returns a merged JSON object.
    static let loadPrompt = """
    Read ~/.nullclaw/config.json and ~/.nullclaw/state/costs.jsonl (if it exists). \
    Respond with ONLY a valid JSON object, no extra text. \
    The JSON must have exactly these keys: \
    "cost_enabled" (boolean, from config.json cost.enabled), \
    "daily_limit_usd" (number, from config.json cost.daily_limit_usd), \
    "monthly_limit_usd" (number, from config.json cost.monthly_limit_usd), \
    "warn_at_percent" (integer, from config.json cost.warn_at_percent), \
    "session_cost_usd" (number, sum of cost_usd from all records in the current session in costs.jsonl; 0.0 if file absent), \
    "daily_cost_usd" (number, sum of cost_usd for records with a timestamp on today's date in costs.jsonl; 0.0 if file absent), \
    "monthly_cost_usd" (number, sum of cost_usd for records with a timestamp in the current calendar month in costs.jsonl; 0.0 if file absent), \
    "total_tokens" (integer, sum of total_tokens across all records in costs.jsonl; 0 if file absent), \
    "request_count" (integer, total number of records in costs.jsonl; 0 if file absent).
    """
}

// MARK: - Private decoding shim

/// Intermediate Decodable used only by `parseStats(from:)`.
/// All fields are optional so a partial reply never throws.
private struct UsageStatsRaw: Decodable {
    var cost_enabled: Bool?
    var daily_limit_usd: Double?
    var monthly_limit_usd: Double?
    var warn_at_percent: Int?
    var session_cost_usd: Double?
    var daily_cost_usd: Double?
    var monthly_cost_usd: Double?
    var total_tokens: Int?
    var request_count: Int?
}
