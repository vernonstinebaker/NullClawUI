import Foundation
import Observation

// MARK: - CronJobViewModel

/// Phase 15: Cron Job Manager.
///
/// Communicates with the NullClaw Gateway via dedicated REST endpoints
/// (GET /cron, POST /cron/add, /cron/remove, /cron/pause, /cron/resume, /cron/update)
/// instead of A2A natural-language prompts. This makes cron operations fast,
/// deterministic, and reliable.
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

    private(set) var jobs: [CronJob] = []
    private(set) var isLoading: Bool = false
    var errorMessage: String? = nil
    private(set) var actionInProgress: String? = nil

    // MARK: Dependencies

    var client: GatewayClient

    // MARK: Init

    init(client: GatewayClient) {
        self.client = client
    }

    func invalidate() {
        let c = client
        Task { await c.invalidate() }
    }

    // MARK: - Public API

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            jobs = try await client.listCronJobs()
        } catch {
            errorMessage = "Failed to load cron jobs: \(error.localizedDescription)"
        }
    }

    /// Pauses the given job and refreshes the list.
    func pause(_ job: CronJob) async {
        await performMutation(
            action: { try await self.client.pauseCronJob(id: job.id) },
            jobID: job.id,
            errorPrefix: "Failed to pause job"
        )
    }

    /// Resumes (un-pauses) the given job and refreshes the list.
    func resume(_ job: CronJob) async {
        await performMutation(
            action: { try await self.client.resumeCronJob(id: job.id) },
            jobID: job.id,
            errorPrefix: "Failed to resume job"
        )
    }

    /// Triggers an immediate run of the given job and refreshes the list.
    /// Note: The gateway doesn't expose a REST endpoint for "run now", so this
    /// falls back to the A2A one-shot prompt.
    func runNow(_ job: CronJob) async {
        await performActionViaA2A(
            "Run the cron job with id \"\(job.id)\" immediately.",
            jobID: job.id
        )
    }

    /// Deletes the given job and refreshes the list.
    func delete(_ job: CronJob) async {
        await performMutation(
            action: { try await self.client.removeCronJob(id: job.id) },
            jobID: job.id,
            errorPrefix: "Failed to delete job"
        )
    }

    /// Submits a new cron job creation request, then refreshes the list.
    func addJob(_ draft: CronJobDraft) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let params = draft.toRESTParams()
            _ = try await client.addCronJob(params)
            jobs = try await client.listCronJobs()
        } catch {
            errorMessage = "Failed to add cron job: \(error.localizedDescription)"
        }
    }

    /// Updates an existing cron job, then refreshes the list.
    func editJob(_ job: CronJob, draft: CronJobDraft) async {
        guard actionInProgress == nil else { return }
        actionInProgress = job.id
        errorMessage = nil
        defer { actionInProgress = nil }

        do {
            let params = draft.toUpdateRESTParams(existingID: job.id)
            try await client.updateCronJob(params)
            jobs = try await client.listCronJobs()
        } catch {
            errorMessage = "Failed to update cron job: \(error.localizedDescription)"
        }
    }

    // MARK: - Private

    /// Performs a REST mutation then refreshes the job list.
    private func performMutation(
        action: () async throws -> Void,
        jobID: String,
        errorPrefix: String
    ) async {
        guard actionInProgress == nil else { return }
        actionInProgress = jobID
        errorMessage = nil
        defer { actionInProgress = nil }

        do {
            try await action()
            jobs = try await client.listCronJobs()
        } catch {
            errorMessage = "\(errorPrefix): \(error.localizedDescription)"
        }
    }

    /// Falls back to A2A for operations without dedicated REST endpoints (e.g. run now).
    private func performActionViaA2A(_ prompt: String, jobID: String) async {
        guard actionInProgress == nil else { return }
        actionInProgress = jobID
        errorMessage = nil
        defer { actionInProgress = nil }

        do {
            _ = try await client.sendOneShot(prompt)
            jobs = try await client.listCronJobs()
        } catch {
            errorMessage = "\(prompt) failed: \(error.localizedDescription)"
        }
    }
}
