import SwiftUI

// NOTE: No unit test — pure layout change for the AgentConfigView body; covered by visual inspection in Simulator.

// MARK: - AgentConfigView

struct AgentConfigView: View {
    let profile: GatewayProfile

    @State private var viewModel: AgentConfigViewModel

    // Local draft state — edits are staged here, sent on commit (Return / stepper tap)
    @State private var modelDraft: String = ""
    @State private var tempDraft: Double = 1.0
    @State private var iterDraft: Int = 20
    @State private var timeoutDraft: Int = 300
    @FocusState private var modelFieldFocused: Bool

    init(profile: GatewayProfile) {
        self.profile = profile
        let url = URL(string: profile.url) ?? URL(string: "http://localhost:5111")!
        let token = (try? KeychainService.retrieveToken(for: profile.url)) ?? ""
        _viewModel = State(wrappedValue: AgentConfigViewModel(
            client: GatewayClient(baseURL: url, token: token, requiresPairing: profile.requiresPairing)
        ))
    }

    var body: some View {
        List {
            if !profile.isPaired {
                Section {
                    Label("Pair this gateway to view agent configuration.", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.isLoading && !viewModel.isLoaded {
                Section {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Loading configuration…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                modelSection
                samplingSection
                limitsSection
                memorySection
            }

            // Confirmation banner
            if let msg = viewModel.confirmationMessage {
                Section {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Configuration saved: \(msg)")
                }
            }

            // Error banner
            if let err = viewModel.errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Error: \(err)")
                }
            }
        }
        .navigationTitle("Agent Configuration")
        .refreshable { await viewModel.load() }
        .toolbar {
            if viewModel.isLoading || viewModel.isSaving {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                        .accessibilityLabel("Saving")
                }
            }
        }
        .task {
            guard profile.isPaired else { return }
            if !viewModel.isLoaded {
                await viewModel.load()
                syncDrafts()
            }
        }
        .onDisappear {
            viewModel.invalidate()
        }
        .onChange(of: viewModel.config) { _, new in
            // Only sync when the user is NOT currently editing the model field
            if !modelFieldFocused {
                modelDraft = new.primaryModel
            }
            tempDraft = new.temperature
            iterDraft = new.maxToolIterations
            timeoutDraft = new.messageTimeoutSecs
        }
    }

    // MARK: - Sections

    private var modelSection: some View {
        Section {
            // Model name text field — commits on Return key
            TextField("Primary model", text: $modelDraft)
                .focused($modelFieldFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    Task { await viewModel.setPrimaryModel(modelDraft) }
                }
                .accessibilityLabel("Primary model")
                .accessibilityHint("Type a model name and press Return to apply")

            // Provider — read-only (requires restart to change)
            HStack {
                Label("Provider", systemImage: "server.rack")
                Spacer()
                Text(viewModel.config.provider.isEmpty ? "—" : viewModel.config.provider)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Label("Requires restart", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Provider: \(viewModel.config.provider.isEmpty ? "unknown" : viewModel.config.provider). Requires gateway restart to change.")
        } header: {
            Text("Model")
        }
    }

    private var samplingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Temperature", systemImage: "thermometer.medium")
                    Spacer()
                    Text(String(format: "%.2f", tempDraft))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $tempDraft, in: 0.0...2.0, step: 0.05) {
                    Text("Temperature")
                } minimumValueLabel: {
                    Text("0")
                        .font(.caption)
                } maximumValueLabel: {
                    Text("2")
                        .font(.caption)
                }
                .onChange(of: tempDraft) { _, _ in
                    // Debounce: commit when the user lifts their finger (onEditingChanged
                    // is not available on Slider in SwiftUI; we commit on task submit instead)
                }
                .accessibilityLabel("Temperature slider")
                .accessibilityValue(String(format: "%.2f", tempDraft))
                .accessibilityHint("Adjust between 0 (deterministic) and 2 (creative). Double-tap then swipe to change.")

                Button("Apply") {
                    Task { await viewModel.setTemperature(tempDraft) }
                }
                .buttonStyle(.bordered)
                .font(.callout)
                .accessibilityLabel("Apply temperature \(String(format: "%.2f", tempDraft))")
            }
        } header: {
            Text("Sampling")
        }
    }

    private var limitsSection: some View {
        Section {
            // Max tool iterations
            Stepper(
                value: $iterDraft,
                in: 1...100,
                step: 1,
                onEditingChanged: { finished in
                    if finished {
                        Task { await viewModel.setMaxToolIterations(iterDraft) }
                    }
                }
            ) {
                HStack {
                    Label("Max tool iterations", systemImage: "arrow.trianglehead.2.clockwise")
                    Spacer()
                    Text("\(iterDraft)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Max tool iterations: \(iterDraft)")
            .accessibilityHint("Adjust the maximum number of tool calls per agent turn")

            // Message timeout
            Stepper(
                value: $timeoutDraft,
                in: 30...3600,
                step: 30,
                onEditingChanged: { finished in
                    if finished {
                        Task { await viewModel.setMessageTimeout(timeoutDraft) }
                    }
                }
            ) {
                HStack {
                    Label("Message timeout", systemImage: "timer")
                    Spacer()
                    Text("\(timeoutDraft)s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Message timeout: \(timeoutDraft) seconds")
            .accessibilityHint("Adjust the timeout for a single agent message in seconds")

            // Parallel tools toggle
            Toggle(isOn: Binding(
                get: { viewModel.config.parallelTools },
                set: { newVal in Task { await viewModel.setParallelTools(newVal) } }
            )) {
                Label("Parallel tools", systemImage: "square.stack.3d.forward.dottedline")
            }
            .accessibilityLabel("Parallel tools: \(viewModel.config.parallelTools ? "enabled" : "disabled")")
            .accessibilityHint("When enabled, the agent may call multiple tools simultaneously")
        } header: {
            Text("Limits")
        }
    }

    private var memorySection: some View {
        Section {
            // Compaction enabled toggle
            Toggle(isOn: Binding(
                get: { viewModel.config.compactContext },
                set: { newVal in Task { await viewModel.setCompactContext(newVal) } }
            )) {
                Label("Auto-compact conversation", systemImage: "arrow.down.left.and.arrow.up.right")
            }
            .accessibilityLabel("Auto-compact conversation: \(viewModel.config.compactContext ? "enabled" : "disabled")")
            .accessibilityHint("When enabled, long conversations are automatically summarised to save context")

            // Compaction threshold stepper
            Stepper(
                value: Binding(
                    get: { viewModel.config.compactionThreshold },
                    set: { newVal in Task { await viewModel.setCompactionThreshold(newVal) } }
                ),
                in: 1000...128_000,
                step: 1000
            ) {
                HStack {
                    Label("Compaction threshold", systemImage: "chart.bar.fill")
                    Spacer()
                    Text("\(viewModel.config.compactionThreshold) tokens")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .disabled(!viewModel.config.compactContext)
            .accessibilityLabel("Compaction threshold: \(viewModel.config.compactionThreshold) tokens")
            .accessibilityHint("The token count at which automatic compaction triggers")
        } header: {
            Text("Memory / Compaction")
        }
    }

    // MARK: - Helpers

    private func syncDrafts() {
        modelDraft = viewModel.config.primaryModel
        tempDraft = viewModel.config.temperature
        iterDraft = viewModel.config.maxToolIterations
        timeoutDraft = viewModel.config.messageTimeoutSecs
    }
}
