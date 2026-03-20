import SwiftUI

// NOTE: No unit test — pure layout change for the UsageStatsView body; covered by visual inspection in Simulator.

// MARK: - UsageStatsView

/// Shows token usage and cost data for the gateway, with editable spend limits.
/// Follows the same structure as AutonomyView: constructs its own GatewayClient,
/// fetches via a single sendOneShot prompt on appear, and uses refreshable for reload.
struct UsageStatsView: View {
    let profile: GatewayProfile

    @State private var viewModel: UsageStatsViewModel

    // Draft state for numeric fields — staged locally, committed on editing end
    @State private var dailyLimitDraft: String = ""
    @State private var monthlyLimitDraft: String = ""
    @State private var warnPercentDraft: Int = 80

    // Focus tracking so we can commit on tap-outside (decimalPad has no Return key)
    private enum LimitField { case daily, monthly }
    @FocusState private var focusedLimitField: LimitField?

    init(profile: GatewayProfile) {
        self.profile = profile
        let client: GatewayClient? = {
            guard let url = URL(string: profile.url) else { return nil }
            let token = (try? KeychainService.retrieveToken(for: profile.url)) ?? ""
            return GatewayClient(baseURL: url, token: token, requiresPairing: profile.requiresPairing)
        }()
        _viewModel = State(wrappedValue: UsageStatsViewModel(client: client))
    }

    var body: some View {
        List {
            if !profile.isPaired {
                Section {
                    Label("Pair this gateway to view cost and usage data.", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.isLoading && !viewModel.isLoaded {
                Section {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Loading usage data…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                usageSummarySection
                limitsSection
                settingsSection
            }

            // Confirmation banner
            if let msg = viewModel.confirmationMessage {
                Section {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Saved: \(msg)")
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
        .navigationTitle("Cost & Usage")
        .refreshable { await viewModel.load() }
        .toolbar {
            if viewModel.isLoading || viewModel.isSaving {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                        .accessibilityLabel("Loading")
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
        .onChange(of: viewModel.stats) { _, new in
            syncDrafts(from: new)
        }
        // Commit limit fields when focus leaves (decimalPad has no Return key on iPhone)
        .onChange(of: focusedLimitField) { old, _ in
            switch old {
            case .daily:   commitDailyLimit()
            case .monthly: commitMonthlyLimit()
            case nil:      break
            }
        }
    }

    // MARK: - Sections

    private var usageSummarySection: some View {
        Section {
            // Session
            LabeledContent {
                Text(formatCost(viewModel.stats.sessionCostUSD))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            } label: {
                Label("Session cost", systemImage: "bolt.fill")
            }
            .accessibilityLabel("Session cost: \(formatCost(viewModel.stats.sessionCostUSD))")

            // Daily — with optional progress bar
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent {
                    HStack(spacing: 6) {
                        if viewModel.stats.isDailyWarning {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .imageScale(.small)
                        }
                        Text(formatCost(viewModel.stats.dailyCostUSD))
                            .monospacedDigit()
                            .foregroundStyle(viewModel.stats.isDailyWarning ? .orange : .primary)
                    }
                } label: {
                    Label("Today", systemImage: "sun.max.fill")
                }

                if let progress = viewModel.stats.dailyProgress {
                    ProgressView(value: progress)
                        .tint(progressColor(for: progress))
                        .accessibilityLabel(String(format: "Daily usage: %.0f%% of $%.2f limit",
                                                   progress * 100, viewModel.stats.dailyLimitUSD))
                }
            }
            .accessibilityElement(children: .combine)

            // Monthly — with optional progress bar
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent {
                    HStack(spacing: 6) {
                        if viewModel.stats.isMonthlyWarning {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .imageScale(.small)
                        }
                        Text(formatCost(viewModel.stats.monthlyCostUSD))
                            .monospacedDigit()
                            .foregroundStyle(viewModel.stats.isMonthlyWarning ? .orange : .primary)
                    }
                } label: {
                    Label("This month", systemImage: "calendar")
                }

                if let progress = viewModel.stats.monthlyProgress {
                    ProgressView(value: progress)
                        .tint(progressColor(for: progress))
                        .accessibilityLabel(String(format: "Monthly usage: %.0f%% of $%.2f limit",
                                                   progress * 100, viewModel.stats.monthlyLimitUSD))
                }
            }
            .accessibilityElement(children: .combine)

            // Token & request counts
            LabeledContent {
                Text("\(viewModel.stats.totalTokens.formatted())")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } label: {
                Label("Total tokens", systemImage: "text.word.spacing")
            }
            .accessibilityLabel("Total tokens used: \(viewModel.stats.totalTokens.formatted())")

            LabeledContent {
                Text("\(viewModel.stats.requestCount.formatted())")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } label: {
                Label("API requests", systemImage: "arrow.triangle.2.circlepath")
            }
            .accessibilityLabel("API requests made: \(viewModel.stats.requestCount.formatted())")

        } header: {
            Text("Usage Summary")
        } footer: {
            Text("Session stats reflect the current gateway session. Daily and monthly figures are read from the gateway's cost log.")
        }
    }

    private var limitsSection: some View {
        Section {
            // Daily limit text field
            HStack {
                Label("Daily limit (USD)", systemImage: "sun.max")
                Spacer()
                TextField("0.00", text: $dailyLimitDraft)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .foregroundStyle(.secondary)
                    .focused($focusedLimitField, equals: .daily)
                    .onSubmit { commitDailyLimit() }
            }
            .accessibilityLabel("Daily spend limit in US dollars")
            .accessibilityHint("Enter 0 to disable the daily limit")

            // Monthly limit text field
            HStack {
                Label("Monthly limit (USD)", systemImage: "calendar.badge.clock")
                Spacer()
                TextField("0.00", text: $monthlyLimitDraft)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .foregroundStyle(.secondary)
                    .focused($focusedLimitField, equals: .monthly)
                    .onSubmit { commitMonthlyLimit() }
            }
            .accessibilityLabel("Monthly spend limit in US dollars")
            .accessibilityHint("Enter 0 to disable the monthly limit")

            // Warn-at percent stepper
            Stepper(
                value: $warnPercentDraft,
                in: 1...100,
                step: 5,
                onEditingChanged: { finished in
                    if finished {
                        Task { await viewModel.setWarnAtPercent(warnPercentDraft) }
                    }
                }
            ) {
                HStack {
                    Label("Warn at", systemImage: "bell.badge.fill")
                    Spacer()
                    Text("\(warnPercentDraft)%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Warn at \(warnPercentDraft)% of limit")
            .accessibilityHint("Gateway emits a warning when spend reaches this percentage of the limit")

        } header: {
            Text("Spend Limits")
        } footer: {
            Text("Set to 0 to disable a limit. Changes are written to the gateway's config.json immediately.")
        }
    }

    private var settingsSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewModel.stats.costEnabled },
                set: { newVal in Task { await viewModel.setCostEnabled(newVal) } }
            )) {
                Label("Enable cost tracking", systemImage: "chart.bar.fill")
            }
            .accessibilityLabel("Cost tracking: \(viewModel.stats.costEnabled ? "enabled" : "disabled")")
            .accessibilityHint("When enabled, the gateway records token usage and enforces spend limits")
        } header: {
            Text("Settings")
        } footer: {
            Text("When disabled, usage is not logged and spend limits are not enforced.")
        }
    }

    // MARK: - Helpers

    private func formatCost(_ usd: Double) -> String {
        if usd == 0 { return "$0.00" }
        return String(format: "$%.4f", usd)
    }

    private func progressColor(for progress: Double) -> Color {
        if progress >= 1.0 { return .red }
        if progress >= Double(viewModel.stats.warnAtPercent) / 100.0 { return .orange }
        return .blue
    }

    private func syncDrafts(from s: UsageStats? = nil) {
        let source = s ?? viewModel.stats
        dailyLimitDraft = String(format: "%.2f", source.dailyLimitUSD)
        monthlyLimitDraft = String(format: "%.2f", source.monthlyLimitUSD)
        warnPercentDraft = source.warnAtPercent
    }

    private func commitDailyLimit() {
        guard let value = Double(dailyLimitDraft) else {
            dailyLimitDraft = String(format: "%.2f", viewModel.stats.dailyLimitUSD)
            return
        }
        Task { await viewModel.setDailyLimit(value) }
    }

    private func commitMonthlyLimit() {
        guard let value = Double(monthlyLimitDraft) else {
            monthlyLimitDraft = String(format: "%.2f", viewModel.stats.monthlyLimitUSD)
            return
        }
        Task { await viewModel.setMonthlyLimit(value) }
    }
}
