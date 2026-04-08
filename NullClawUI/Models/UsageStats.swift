import Foundation

// MARK: - UsageStats Model

/// Token usage and cost data retrieved from the NullClaw gateway.
/// Values reflect the current session and historical rollups from
/// `~/.nullclaw/state/costs.jsonl`.
struct UsageStats: Equatable {
    // MARK: Cost (USD)

    /// Cost incurred in the current gateway session.
    var sessionCostUSD: Double = 0.0
    /// Cost incurred today (calendar day in the gateway's local timezone).
    var dailyCostUSD: Double = 0.0
    /// Cost incurred this calendar month.
    var monthlyCostUSD: Double = 0.0

    // MARK: Tokens

    /// Total tokens consumed this session (input + output).
    var totalTokens: Int = 0
    /// Number of LLM API calls made this session.
    var requestCount: Int = 0

    // MARK: Limits & Settings (from cost config block)

    /// Whether cost tracking is enabled on the gateway.
    var costEnabled: Bool = false
    /// Daily spend cap in USD. 0 means no limit.
    var dailyLimitUSD: Double = 0.0
    /// Monthly spend cap in USD. 0 means no limit.
    var monthlyLimitUSD: Double = 0.0
    /// Warn-at percentage (0–100). Gateway emits a warning when
    /// `daily_cost / daily_limit` exceeds this threshold.
    var warnAtPercent: Int = 80

    // MARK: - Computed helpers

    /// Progress toward the daily limit (0.0 – 1.0).
    /// Returns nil when the daily limit is zero (no limit set).
    var dailyProgress: Double? {
        guard dailyLimitUSD > 0 else { return nil }
        return min(dailyCostUSD / dailyLimitUSD, 1.0)
    }

    /// Progress toward the monthly limit (0.0 – 1.0).
    /// Returns nil when the monthly limit is zero (no limit set).
    var monthlyProgress: Double? {
        guard monthlyLimitUSD > 0 else { return nil }
        return min(monthlyCostUSD / monthlyLimitUSD, 1.0)
    }

    /// True when daily spend has crossed the warn threshold.
    var isDailyWarning: Bool {
        guard dailyLimitUSD > 0 else { return false }
        let threshold = dailyLimitUSD * Double(warnAtPercent) / 100.0
        return dailyCostUSD >= threshold
    }

    /// True when monthly spend has crossed the warn threshold.
    var isMonthlyWarning: Bool {
        guard monthlyLimitUSD > 0 else { return false }
        let threshold = monthlyLimitUSD * Double(warnAtPercent) / 100.0
        return monthlyCostUSD >= threshold
    }
}
