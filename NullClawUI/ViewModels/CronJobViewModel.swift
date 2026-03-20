import Foundation
import Observation

// MARK: - CronJobViewModel

/// Phase 15: Cron Job Manager.
///
/// Communicates with the active gateway exclusively through A2A natural-language prompts
/// (message/stream) — there is no dedicated REST endpoint for cron management.
///
/// Lifecycle:
///   • Call load() to fetch the current job list.
///   • Call pause(_:), resume(_:), runNow(_:), delete(_:) for row-level actions.
///   • Call addJob(_:) to create a new job.
///   Each mutating call re-fetches the list afterward so the UI stays in sync.
@Observable
@MainActor
final class CronJobViewModel {

    // MARK: Published state

    /// Current list of cron jobs, ordered as returned by the agent.
    private(set) var jobs: [CronJob] = []
    /// True while an A2A round-trip is in flight.
    private(set) var isLoading: Bool = false
    /// Non-nil when the last operation failed.
    var errorMessage: String? = nil
    /// Non-nil while a one-shot command (pause/resume/run/delete) is executing.
    /// Contains the job id being acted upon.
    private(set) var actionInProgress: String? = nil

    // MARK: Dependencies

    /// The client to use for all A2A calls.
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

    // MARK: - Public API

    /// Fetches the current cron job list from the agent.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        await loadInternal(client: client)
    }

    // MARK: - Private load helper

    /// Performs the actual network fetch without touching `isLoading`.
    /// Called internally by mutating operations that already own `isLoading`.
    private func loadInternal(client: GatewayClient) async {
        do {
            let reply = try await client.sendOneShot(Self.loadPrompt)
            jobs = try parseCronJobs(from: reply)
        } catch {
            errorMessage = "Failed to load cron jobs: \(error.localizedDescription)"
        }
    }

    /// Pauses the given job and refreshes the list.
    func pause(_ job: CronJob) async {
        await performAction("Pause the cron job with id \"\(job.id)\" in ~/.nullclaw/cron.json.", jobID: job.id)
    }

    /// Resumes (un-pauses) the given job and refreshes the list.
    func resume(_ job: CronJob) async {
        await performAction("Resume the cron job with id \"\(job.id)\" in ~/.nullclaw/cron.json.", jobID: job.id)
    }

    /// Triggers an immediate run of the given job and refreshes the list.
    func runNow(_ job: CronJob) async {
        await performAction("Run the cron job with id \"\(job.id)\" immediately.", jobID: job.id)
    }

    /// Deletes the given job and refreshes the list.
    func delete(_ job: CronJob) async {
        await performAction("Delete the cron job with id \"\(job.id)\" from ~/.nullclaw/cron.json.", jobID: job.id)
    }

    /// Submits a new cron job creation request to the agent, then refreshes the list.
    func addJob(_ draft: CronJobDraft) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let prompt = draft.toPrompt()
        do {
            _ = try await client.sendOneShot(prompt)
            await loadInternal(client: client)
        } catch {
            errorMessage = "Failed to add cron job: \(error.localizedDescription)"
        }
    }

    /// Updates an existing cron job by replacing it with the provided draft, then refreshes the list.
    func editJob(_ job: CronJob, draft: CronJobDraft) async {
        guard actionInProgress == nil else { return }
        actionInProgress = job.id
        errorMessage = nil
        defer { actionInProgress = nil }

        let prompt = draft.toEditPrompt(replacing: job.id)
        do {
            _ = try await client.sendOneShot(prompt)
            await loadInternal(client: client)
        } catch {
            errorMessage = "Failed to update cron job: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers (internal/package-visible for tests)

    /// Parses a raw agent reply string into a `[CronJob]` array.
    /// Locates the first `[` … `]` substring and decodes it as JSON.
    func parseCronJobs(from text: String) throws -> [CronJob] {
        guard let start = text.firstIndex(of: "["),
              let end   = text.lastIndex(of: "]") else {
            // Agent returned no JSON array — treat as empty list.
            return []
        }
        let jsonSubstring = String(text[start...end])
        guard let data = jsonSubstring.data(using: .utf8) else {
            throw CronJobParseError.invalidUTF8
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode([CronJob].self, from: data)
        } catch {
            throw CronJobParseError.decodingFailed(underlying: error)
        }
    }

    // MARK: - Private

    private func performAction(_ prompt: String, jobID: String) async {
        guard actionInProgress == nil else { return }
        actionInProgress = jobID
        errorMessage = nil
        defer { actionInProgress = nil }

        do {
            _ = try await client.sendOneShot(prompt)
            await loadInternal(client: client)
        } catch {
            errorMessage = "\(prompt) failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Prompt constants (visible for tests)

    /// Instructs the agent to read cron.json directly rather than relying on
    /// in-memory state, which has proven unreliable (agent returns [] when asked
    /// to "list cron jobs" without a direct file-read instruction).
    static let loadPrompt = """
        Read ~/.nullclaw/cron.json and respond with ONLY its raw contents as a valid \
        JSON array, no extra text before or after.
        """
}

// MARK: - CronJobParseError

enum CronJobParseError: Error, LocalizedError {
    case invalidUTF8
    case decodingFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "Agent response contained invalid UTF-8."
        case .decodingFailed(let e):
            return "Could not decode cron job JSON: \(e.localizedDescription)"
        }
    }
}

// MARK: - CronJobDraft

/// Value type used by AddCronJobSheet to collect user input before submission.
struct CronJobDraft: Sendable {
    var id: String = ""
    var expression: String = ""
    var jobType: String = "agent"   // "agent" | "shell"
    var commandOrPrompt: String = ""
    var model: String = ""
    var deliveryChannel: String = ""
    var deliveryTo: String = ""
    var oneShot: Bool = false
    var deleteAfterRun: Bool = false

    /// Composes the natural-language prompt sent to the agent.
    func toPrompt() -> String {
        let typeLabel   = jobType == "shell" ? "shell command" : "agent prompt"
        let modelPart   = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "" : ", model \(model.trimmingCharacters(in: .whitespacesAndNewlines))"
        let delivPart   = deliveryChannel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "" : ", delivery channel \(deliveryChannel.trimmingCharacters(in: .whitespacesAndNewlines)) to \(deliveryTo.trimmingCharacters(in: .whitespacesAndNewlines))"
        let oneShotPart = oneShot ? ", one_shot true" : ""
        let delPart     = deleteAfterRun ? ", delete_after_run true" : ""
        return """
        Add a new cron job with the following settings:
        id: \(id.trimmingCharacters(in: .whitespacesAndNewlines))
        expression: \(expression.trimmingCharacters(in: .whitespacesAndNewlines))
        type: \(typeLabel)
        \(jobType == "shell" ? "command" : "prompt"): \(commandOrPrompt.trimmingCharacters(in: .whitespacesAndNewlines))\(modelPart)\(delivPart)\(oneShotPart)\(delPart)
        Confirm the job was added by replying with: "Cron job added."
        """
    }

    /// Composes the natural-language prompt to update an existing cron job.
    /// The agent should replace the job identified by `existingID` with the new settings.
    func toEditPrompt(replacing existingID: String) -> String {
        let typeLabel   = jobType == "shell" ? "shell command" : "agent prompt"
        let modelPart   = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "" : ", model \(model.trimmingCharacters(in: .whitespacesAndNewlines))"
        let delivPart   = deliveryChannel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "" : ", delivery channel \(deliveryChannel.trimmingCharacters(in: .whitespacesAndNewlines)) to \(deliveryTo.trimmingCharacters(in: .whitespacesAndNewlines))"
        let oneShotPart = oneShot ? ", one_shot true" : ", one_shot false"
        let delPart     = deleteAfterRun ? ", delete_after_run true" : ", delete_after_run false"
        return """
        Update the cron job with id "\(existingID)" in ~/.nullclaw/cron.json with the following new settings:
        id: \(id.trimmingCharacters(in: .whitespacesAndNewlines))
        expression: \(expression.trimmingCharacters(in: .whitespacesAndNewlines))
        type: \(typeLabel)
        \(jobType == "shell" ? "command" : "prompt"): \(commandOrPrompt.trimmingCharacters(in: .whitespacesAndNewlines))\(modelPart)\(delivPart)\(oneShotPart)\(delPart)
        Confirm the job was updated by replying with: "Cron job updated."
        """
    }
}
