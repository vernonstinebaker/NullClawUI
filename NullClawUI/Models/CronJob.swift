import Foundation

// MARK: - CronJob Model

/// Represents a single cron job entry from the NullClaw gateway's cron.json.
/// Fields mirror the gateway schema exactly so the JSON round-trips cleanly.
struct CronJob: Codable, Identifiable, Sendable, Equatable {

    // MARK: Identity
    let id: String

    // MARK: Schedule
    /// Standard cron expression, e.g. "0 */2 * * *".
    var expression: String

    // MARK: Execution
    /// Human-readable command description (shown in the UI).
    var command: String?
    /// Agent prompt text (only present for job_type == "agent").
    var prompt: String?
    /// Optional model override; nil means gateway default.
    var model: String?
    /// "shell" or "agent".
    var jobType: String

    // MARK: Delivery
    var deliveryMode: String?
    var deliveryChannel: String?
    var deliveryTo: String?

    // MARK: State flags
    var paused: Bool
    var enabled: Bool
    var oneShot: Bool
    var deleteAfterRun: Bool

    // MARK: Runtime
    /// Unix timestamp (seconds) of when the job last ran.  Nil if never.
    var lastRunSecs: Double?
    /// Last execution outcome, e.g. "success" or "failed".
    var lastStatus: String?
    /// Unix timestamp (seconds) of the next scheduled run.
    var nextRunSecs: Double?

    // MARK: - Computed helpers

    /// Human-readable job type label.
    var jobTypeLabel: String {
        jobType == "shell" ? "Shell" : "Agent"
    }

    /// The most descriptive single-line label for the job.
    var displayTitle: String {
        if let cmd = command, !cmd.isEmpty { return cmd }
        if let p   = prompt,  !p.isEmpty  {
            let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
            let first = trimmed.components(separatedBy: "\n").first ?? trimmed
            return first.count > 80 ? String(first.prefix(77)) + "…" : first
        }
        return id
    }

    /// Date of the next scheduled run, if available.
    var nextRunDate: Date? {
        guard let secs = nextRunSecs else { return nil }
        return Date(timeIntervalSince1970: secs)
    }

    /// Date of the last run, if available.
    var lastRunDate: Date? {
        guard let secs = lastRunSecs else { return nil }
        return Date(timeIntervalSince1970: secs)
    }

    /// Human-readable countdown to next run.
    var nextRunCountdown: String {
        guard let date = nextRunDate else { return "—" }
        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return "now" }
        let mins  = Int(diff / 60)
        let hours = mins / 60
        let days  = hours / 24
        if days  > 0 { return "in \(days)d \(hours % 24)h" }
        if hours > 0 { return "in \(hours)h \(mins % 60)m" }
        if mins  > 0 { return "in \(mins)m" }
        return "in <1m"
    }
}
