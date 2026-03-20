import SwiftUI

// MARK: - CronJobListView

/// Phase 15: Cron Job Manager.
/// Displays all gateway cron jobs with swipe actions and an Add button.
/// Accessed via a NavigationLink inside GatewayDetailView.
struct CronJobListView: View {
    // NOTE: No unit test — pure layout change; covered by visual inspection in Simulator.

    let profile: GatewayProfile

    @State private var viewModel: CronJobViewModel
    @State private var showingAddSheet: Bool = false
    @State private var editingJob: CronJob? = nil

    init(profile: GatewayProfile) {
        self.profile = profile
        // Build a tokened GatewayClient if the profile is paired.
        let client: GatewayClient? = {
            guard let url = URL(string: profile.url) else { return nil }
            let token = try? KeychainService.retrieveToken(for: profile.url)
            return GatewayClient(baseURL: url, token: token ?? "", requiresPairing: profile.requiresPairing)
        }()
        _viewModel = State(wrappedValue: CronJobViewModel(client: client))
    }

    var body: some View {
        List {
            if !profile.isPaired {
                Section {
                    Label(
                        "This gateway is not paired. Pair it first to manage cron jobs.",
                        systemImage: "key.slash"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            } else if viewModel.isLoading && viewModel.jobs.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Loading cron jobs…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Loading cron jobs")
                }
            } else if viewModel.jobs.isEmpty && !viewModel.isLoading {
                Section {
                    ContentUnavailableView(
                        "No Cron Jobs",
                        systemImage: "clock.badge.xmark",
                        description: Text("Tap + to add a new job.")
                    )
                }
            } else {
                ForEach(viewModel.jobs) { job in
                    Button {
                        editingJob = job
                    } label: {
                        jobRow(job)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            // Delete
                            Button(role: .destructive) {
                                Task { await viewModel.delete(job) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                            .accessibilityLabel("Delete cron job \(job.id)")
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            // Pause / Resume
                            if job.paused {
                                Button {
                                    Task { await viewModel.resume(job) }
                                } label: {
                                    Label("Resume", systemImage: "play.fill")
                                }
                                .tint(.green)
                                .accessibilityLabel("Resume cron job \(job.id)")
                            } else {
                                Button {
                                    Task { await viewModel.pause(job) }
                                } label: {
                                    Label("Pause", systemImage: "pause.fill")
                                }
                                .tint(.orange)
                                .accessibilityLabel("Pause cron job \(job.id)")
                            }
                            // Run Now
                            Button {
                                Task { await viewModel.runNow(job) }
                            } label: {
                                Label("Run Now", systemImage: "bolt.fill")
                            }
                            .tint(.blue)
                            .accessibilityLabel("Run cron job \(job.id) now")
                        }
                }
            }

            if let err = viewModel.errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Cron Jobs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Job", systemImage: "plus")
                }
                .disabled(!profile.isPaired)
                .accessibilityLabel("Add a new cron job")
            }
            if viewModel.isLoading && !viewModel.jobs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .refreshable {
            await viewModel.load()
        }
        .task {
            if viewModel.jobs.isEmpty && profile.isPaired {
                await viewModel.load()
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddCronJobSheet { draft in
                Task { await viewModel.addJob(draft) }
            }
        }
        .sheet(item: $editingJob) { job in
            EditCronJobSheet(job: job) { draft in
                Task { await viewModel.editJob(job, draft: draft) }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func jobRow(_ job: CronJob) -> some View {
        let isActing = viewModel.actionInProgress == job.id

        HStack(spacing: 12) {
            // Status / type icon
            ZStack {
                Circle()
                    .fill(iconBackgroundColor(for: job))
                    .frame(width: 36, height: 36)
                if isActing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: jobIcon(for: job))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(job.id)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if job.paused {
                        Text("Paused")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange, in: Capsule())
                    }
                    if job.oneShot {
                        Text("One-shot")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.purple, in: Capsule())
                    }
                }

                Text(job.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(job.expression, systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if job.nextRunDate != nil {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                        Text(job.nextRunCountdown)
                            .font(.caption2)
                            .foregroundStyle(job.nextRunDate?.timeIntervalSinceNow ?? 0 < 300 ? .orange : .secondary)
                    }

                    if let lastStatus = job.lastStatus {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                        Label(lastStatus, systemImage: lastStatus == "success" ? "checkmark.circle" : "xmark.circle")
                            .font(.caption2)
                            .foregroundStyle(lastStatus == "success" ? .green : .red)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: job))
                    .accessibilityHint("Tap to edit. Swipe left to delete, swipe right to pause or run")
    }

    // MARK: - Helpers

    private func jobIcon(for job: CronJob) -> String {
        if job.paused  { return "pause.circle.fill" }
        return job.jobType == "shell" ? "terminal.fill" : "brain"
    }

    private func iconBackgroundColor(for job: CronJob) -> Color {
        if job.paused { return Color(.systemGray3) }
        return job.jobType == "shell" ? Color.indigo : Color.teal
    }

    private func accessibilityLabel(for job: CronJob) -> String {
        var parts = ["\(job.id), \(job.expression)"]
        if job.paused    { parts.append("Paused") }
        if !job.enabled  { parts.append("Disabled") }
        if let s = job.lastStatus { parts.append("Last status: \(s)") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - AddCronJobSheet

/// Form for creating a new cron job via the agent.
private struct AddCronJobSheet: View {
    let onAdd: (CronJobDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var draft = CronJobDraft()

    private var isValid: Bool {
        !draft.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.commandOrPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Job ID (e.g. heartbeat-1)", text: $draft.id)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Job ID")
                        .accessibilityHint("Unique identifier for this cron job")

                    TextField("Schedule (e.g. 0 */2 * * *)", text: $draft.expression)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.body.monospaced())
                        .accessibilityLabel("Cron expression")
                        .accessibilityHint("Standard cron schedule expression")
                }

                Section("Execution") {
                    Picker("Type", selection: $draft.jobType) {
                        Text("Agent Prompt").tag("agent")
                        Text("Shell Command").tag("shell")
                    }
                    .accessibilityLabel("Job type")

                    TextField(
                        draft.jobType == "shell" ? "Shell command…" : "Agent prompt…",
                        text: $draft.commandOrPrompt,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel(draft.jobType == "shell" ? "Shell command" : "Agent prompt")

                    if draft.jobType == "agent" {
                        TextField("Model override (optional)", text: $draft.model)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityLabel("Model override")
                            .accessibilityHint("Leave blank to use the gateway default model")
                    }
                }

                Section("Options") {
                    Toggle("One-shot (run once then disable)", isOn: $draft.oneShot)
                        .accessibilityLabel("One-shot job")
                        .accessibilityHint("Job runs once then is disabled automatically")

                    Toggle("Delete after run", isOn: $draft.deleteAfterRun)
                        .accessibilityLabel("Delete after run")
                        .accessibilityHint("Job is removed from the list after it runs")
                }

                Section("Delivery (optional)") {
                    TextField("Channel (e.g. mattermost)", text: $draft.deliveryChannel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Delivery channel")

                    TextField("Recipient (e.g. channel:abc123)", text: $draft.deliveryTo)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Delivery recipient")
                }
            }
            .navigationTitle("Add Cron Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(draft)
                        dismiss()
                    }
                    .disabled(!isValid)
                    .accessibilityLabel("Add cron job")
                    .accessibilityHint("Submits the new cron job to the gateway agent")
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - EditCronJobSheet

/// Form for editing an existing cron job via the agent.
/// Pre-populates all fields from the existing `CronJob`.
private struct EditCronJobSheet: View {
    let job: CronJob
    let onSave: (CronJobDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var draft: CronJobDraft

    init(job: CronJob, onSave: @escaping (CronJobDraft) -> Void) {
        self.job = job
        self.onSave = onSave
        _draft = State(wrappedValue: CronJobDraft(
            id: job.id,
            expression: job.expression,
            jobType: job.jobType,
            commandOrPrompt: job.command ?? job.prompt ?? "",
            model: job.model ?? "",
            deliveryChannel: job.deliveryChannel ?? "",
            deliveryTo: job.deliveryTo ?? "",
            oneShot: job.oneShot,
            deleteAfterRun: job.deleteAfterRun
        ))
    }

    private var isValid: Bool {
        !draft.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draft.commandOrPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Job ID (e.g. heartbeat-1)", text: $draft.id)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Job ID")
                        .accessibilityHint("Unique identifier for this cron job")

                    TextField("Schedule (e.g. 0 */2 * * *)", text: $draft.expression)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.body.monospaced())
                        .accessibilityLabel("Cron expression")
                        .accessibilityHint("Standard cron schedule expression")
                }

                Section("Execution") {
                    Picker("Type", selection: $draft.jobType) {
                        Text("Agent Prompt").tag("agent")
                        Text("Shell Command").tag("shell")
                    }
                    .accessibilityLabel("Job type")

                    TextField(
                        draft.jobType == "shell" ? "Shell command…" : "Agent prompt…",
                        text: $draft.commandOrPrompt,
                        axis: .vertical
                    )
                    .lineLimit(4...8)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel(draft.jobType == "shell" ? "Shell command" : "Agent prompt")

                    if draft.jobType == "agent" {
                        TextField("Model override (optional)", text: $draft.model)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityLabel("Model override")
                            .accessibilityHint("Leave blank to use the gateway default model")
                    }
                }

                Section("Options") {
                    Toggle("One-shot (run once then disable)", isOn: $draft.oneShot)
                        .accessibilityLabel("One-shot job")
                        .accessibilityHint("Job runs once then is disabled automatically")

                    Toggle("Delete after run", isOn: $draft.deleteAfterRun)
                        .accessibilityLabel("Delete after run")
                        .accessibilityHint("Job is removed from the list after it runs")
                }

                Section("Delivery (optional)") {
                    TextField("Channel (e.g. mattermost)", text: $draft.deliveryChannel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Delivery channel")

                    TextField("Recipient (e.g. channel:abc123)", text: $draft.deliveryTo)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Delivery recipient")
                }
            }
            .navigationTitle("Edit Cron Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!isValid)
                    .accessibilityLabel("Save cron job changes")
                    .accessibilityHint("Submits the updated cron job to the gateway agent")
                }
            }
        }
        .presentationDetents([.large])
    }
}
