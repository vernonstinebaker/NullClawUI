import SwiftUI

// NOTE: No unit test — pure layout change for the AutonomyView body; covered by visual inspection in Simulator.

// MARK: - AutonomyView

struct AutonomyView: View {
    let profile: GatewayProfile

    @State private var viewModel: AutonomyViewModel

    // Local draft state — edits are staged here, sent on commit
    @State private var maxActionsDraft: Int = 60
    @State private var showingCommandEditor: Bool = false
    @State private var commandEditorText: String = ""

    init(profile: GatewayProfile) {
        self.profile = profile
        let url = URL(string: profile.url) ?? URL(string: "http://localhost:5111")!
        let token = (try? KeychainService.retrieveToken(for: profile.url)) ?? ""
        _viewModel = State(wrappedValue: AutonomyViewModel(
            client: GatewayClient(baseURL: url, token: token, requiresPairing: profile.requiresPairing)
        ))
    }

    var body: some View {
        List {
            if !profile.isPaired {
                Section {
                    Label("Pair this gateway to view autonomy configuration.", systemImage: "lock.fill")
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
                autonomyLevelSection
                limitsSection
                safetySection
                allowedCommandsSection
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
        .navigationTitle("Autonomy & Safety")
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
            maxActionsDraft = new.maxActionsPerHour
        }
        .sheet(isPresented: $showingCommandEditor) {
            CommandEditorSheet(
                initialText: commandEditorText,
                onSave: { newText in
                    let commands = newText
                        .components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    Task { await viewModel.setAllowedCommands(commands) }
                }
            )
        }
    }

    // MARK: - Sections

    private var autonomyLevelSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Autonomy Level", systemImage: "dial.medium")
                    Spacer()
                    riskBadge(for: viewModel.config.level)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Autonomy level: \(viewModel.config.level). Risk: \(riskLabel(for: viewModel.config.level))")

                Picker("Autonomy Level", selection: Binding(
                    get: { viewModel.config.level },
                    set: { newLevel in Task { await viewModel.setLevel(newLevel) } }
                )) {
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Autonomy level selector")
                .accessibilityHint("Low restricts agent actions; High allows broad autonomy. Change requires confirmation from the agent.")
            }
            .padding(.vertical, 4)
        } header: {
            Text("Autonomy Level")
        } footer: {
            Text(levelFooter(for: viewModel.config.level))
        }
    }

    private var limitsSection: some View {
        Section {
            Stepper(
                value: $maxActionsDraft,
                in: 1...1000,
                step: 10,
                onEditingChanged: { finished in
                    if finished {
                        Task { await viewModel.setMaxActionsPerHour(maxActionsDraft) }
                    }
                }
            ) {
                HStack {
                    Label("Max actions / hour", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    Spacer()
                    Text("\(maxActionsDraft)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Max actions per hour: \(maxActionsDraft)")
            .accessibilityHint("Maximum number of agent-initiated actions allowed per hour")
        } header: {
            Text("Limits")
        }
    }

    private var safetySection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewModel.config.blockHighRiskCommands },
                set: { newVal in Task { await viewModel.setBlockHighRiskCommands(newVal) } }
            )) {
                Label("Block high-risk commands", systemImage: "hand.raised.fill")
            }
            .accessibilityLabel("Block high-risk commands: \(viewModel.config.blockHighRiskCommands ? "enabled" : "disabled")")
            .accessibilityHint("When enabled, the agent cannot execute commands classified as high risk")

            Toggle(isOn: Binding(
                get: { viewModel.config.requireApprovalForMediumRisk },
                set: { newVal in Task { await viewModel.setRequireApprovalForMediumRisk(newVal) } }
            )) {
                Label("Require approval for medium-risk", systemImage: "checkmark.shield")
            }
            .accessibilityLabel("Require approval for medium-risk: \(viewModel.config.requireApprovalForMediumRisk ? "enabled" : "disabled")")
            .accessibilityHint("When enabled, the agent requests user approval before executing medium-risk commands")
        } header: {
            Text("Safety")
        }
    }

    private var allowedCommandsSection: some View {
        Section {
            if viewModel.config.allowedCommands.isEmpty {
                HStack {
                    Text("No commands restricted")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Spacer()
                    editCommandsButton
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.config.allowedCommands, id: \.self) { cmd in
                            Text(cmd)
                                .font(.caption.monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 6))
                                .accessibilityLabel("Allowed command: \(cmd)")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Allowed commands: \(viewModel.config.allowedCommands.joined(separator: ", "))")
                HStack {
                    Spacer()
                    editCommandsButton
                }
            }
        } header: {
            Text("Allowed Commands")
        } footer: {
            Text("Commands explicitly permitted regardless of risk level. One entry per line.")
        }
    }

    // MARK: - Helpers

    private var editCommandsButton: some View {
        Button("Edit") {
            commandEditorText = viewModel.config.allowedCommands.joined(separator: "\n")
            showingCommandEditor = true
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .accessibilityLabel("Edit allowed commands list")
        .accessibilityHint("Opens a text editor to modify the list of allowed commands")
    }

    @ViewBuilder
    private func riskBadge(for level: String) -> some View {
        Text(riskLabel(for: level))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(riskColor(for: level).opacity(0.15), in: Capsule())
            .foregroundStyle(riskColor(for: level))
    }

    private func riskColor(for level: String) -> Color {
        switch level.lowercased() {
        case "low":  return .green
        case "high": return .red
        default:     return .yellow
        }
    }

    private func riskLabel(for level: String) -> String {
        switch level.lowercased() {
        case "low":  return "Low Risk"
        case "high": return "High Risk"
        default:     return "Medium Risk"
        }
    }

    private func levelFooter(for level: String) -> String {
        switch level.lowercased() {
        case "low":
            return "The agent requires explicit approval before most actions. Safest setting."
        case "high":
            return "The agent operates with broad autonomy. Use with care on trusted gateways."
        default:
            return "The agent can act independently for routine tasks. Approval required for risky operations."
        }
    }

    private func syncDrafts() {
        maxActionsDraft = viewModel.config.maxActionsPerHour
    }
}

// MARK: - CommandEditorSheet

/// Simple text-entry sheet for editing the allowed commands list.
private struct CommandEditorSheet: View {
    let initialText: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    init(initialText: String, onSave: @escaping (String) -> Void) {
        self.initialText = initialText
        self.onSave = onSave
        _text = State(wrappedValue: initialText)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.body.monospaced())
                .padding(.horizontal, 12)
                .navigationTitle("Allowed Commands")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave(text)
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
