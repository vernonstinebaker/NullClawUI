import Foundation

// MARK: - CronJob Model

/// Represents a single cron job entry from the NullClaw gateway's cron.json.
/// Fields mirror the gateway schema exactly so the JSON round-trips cleanly.
struct CronJob: Codable, Identifiable, Equatable {
    // MARK: Identity

    let id: String

    // MARK: Schedule

    /// Standard cron expression, e.g. "0 */2 * * *".
    var expression: String

    // MARK: Execution

    var command: String?
    var prompt: String?
    var model: String?
    var jobType: String
    var sessionTarget: String?

    // MARK: Delivery

    var deliveryMode: String?
    var deliveryChannel: String?
    var deliveryAccountId: String?
    var deliveryTo: String?
    var deliveryPeerKind: String?
    var deliveryPeerId: String?
    var deliveryThreadId: String?
    var deliveryBestEffort: Bool?

    // MARK: State flags

    var paused: Bool
    var enabled: Bool
    var oneShot: Bool
    var deleteAfterRun: Bool

    // MARK: Runtime

    var lastRunSecs: Double?
    var lastStatus: String?
    var nextRunSecs: Double?
    var createdAtS: Double?

    // MARK: - Computed helpers

    /// Human-readable job type label.
    var jobTypeLabel: String {
        jobType == "shell" ? "Shell" : "Agent"
    }

    /// The most descriptive single-line label for the job.
    var displayTitle: String {
        if let cmd = command, !cmd.isEmpty { return cmd }
        if let p = prompt, !p.isEmpty {
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

    /// Date the job was created, if available.
    var createdDate: Date? {
        guard let secs = createdAtS else { return nil }
        return Date(timeIntervalSince1970: secs)
    }

    /// Human-readable countdown to next run.
    var nextRunCountdown: String {
        guard let date = nextRunDate else { return "—" }
        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return "now" }
        let mins = Int(diff / 60)
        let hours = mins / 60
        let days = hours / 24
        if days > 0 { return "in \(days)d \(hours % 24)h" }
        if hours > 0 { return "in \(hours)h \(mins % 60)m" }
        if mins > 0 { return "in \(mins)m" }
        return "in <1m"
    }
}

// MARK: - Cron REST API Request Types

/// Request body for POST /cron/add.
struct CronJobAddParams: Encodable {
    var expression: String?
    var delay: String?
    var command: String?
    var prompt: String?
    var model: String?
    var sessionTarget: String?
    var deliveryMode: String?
    var deliveryChannel: String?
    var deliveryAccountId: String?
    var deliveryTo: String?
    var deliveryPeerKind: String?
    var deliveryPeerId: String?
    var deliveryThreadId: String?
    var deliveryBestEffort: Bool?
}

/// Request body for POST /cron/remove, /cron/pause, /cron/resume.
struct CronJobIDParams: Encodable {
    let id: String
}

/// Request body for POST /cron/update.
struct CronJobUpdateParams: Encodable {
    let id: String
    var expression: String?
    var command: String?
    var prompt: String?
    var model: String?
    var sessionTarget: String?
    var paused: Bool?
    var enabled: Bool?
}

// MARK: - CronJobDraft

/// Value type used by AddCronJobSheet to collect user input before submission.
struct CronJobDraft {
    var id: String = ""
    var expression: String = ""
    var jobType: String = "agent"
    var commandOrPrompt: String = ""
    var model: String = ""
    var deliveryChannel: String = ""
    var deliveryTo: String = ""
    var oneShot: Bool = false
    var deleteAfterRun: Bool = false

    /// Converts to REST API params for POST /cron/add.
    func toRESTParams() -> CronJobAddParams {
        var params = CronJobAddParams()
        params.expression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        params.model = model.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        params.deliveryChannel = deliveryChannel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        params.deliveryTo = deliveryTo.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        params.deliveryBestEffort = true

        if jobType == "shell" {
            params.command = commandOrPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            params.prompt = commandOrPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if oneShot {
            params.expression = nil
            params.delay = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return params
    }

    /// Converts to REST API params for POST /cron/update.
    func toUpdateRESTParams(existingID: String) -> CronJobUpdateParams {
        var params = CronJobUpdateParams(id: existingID)
        params.expression = expression.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        params.model = model.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        if jobType == "shell" {
            params.command = commandOrPrompt.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        } else {
            params.prompt = commandOrPrompt.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }

        return params
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
