import SwiftUI

// MARK: - GatewayPairSheet

/// Sheet for pairing an already-saved-but-unpaired gateway profile.
/// Reuses AddGatewayPairingModel (connect probe → auto or code entry).
struct GatewayPairSheet: View {
    let profile: GatewayProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(GatewayStore.self) private var store

    @State private var pairingModel: AddGatewayPairingModel? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let pm = pairingModel {
                    pairForm(pm: pm)
                } else {
                    ProgressView("Connecting…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Pair Gateway")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            if let url = URL(string: profile.url) {
                let pm = AddGatewayPairingModel(url: url)
                pairingModel = pm
                await pm.connect()
                // Auto-complete open gateways — no user action needed.
                if pm.step == .notRequired {
                    pm.completeOpenGateway(store: store, profile: profile)
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func pairForm(pm: AddGatewayPairingModel) -> some View {
        Form {
            Section {
                LabeledContent("Name", value: profile.name)
                LabeledContent("URL") {
                    Text(profile.url)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            switch pm.step {
            case .connecting:
                Section {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Connecting to gateway…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

            case .requiresPairing:
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "number")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        @Bindable var bpm = pm
                        TextField("000000", text: $bpm.pairingCode)
                            .keyboardType(.numberPad)
                            .font(.title3.monospacedDigit())
                            .accessibilityLabel("Pairing code")
                            .accessibilityHint("6-digit code from the NullClaw admin interface")
                    }
                    .padding(.vertical, 4)

                    Button {
                        Task { await pm.pair(profileURL: profile.url, store: store, profile: profile) }
                    } label: {
                        HStack {
                            Spacer()
                            if pm.isPairing {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Label("Pair", systemImage: "checkmark.seal.fill")
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(pm.isPairing || pm.pairingCode.count != 6)
                } header: {
                    Text("Pair Device")
                } footer: {
                    Text("Enter the 6-digit code shown in the NullClaw admin interface.")
                }

            case .notRequired:
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Gateway is open — no pairing code required.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    Button("Complete") {
                        pm.completeOpenGateway(store: store, profile: profile)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }

            case .success:
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Paired successfully.")
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }

            case .failed(let message):
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Could not connect")
                                .font(.subheadline.weight(.semibold))
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    Button("Retry") {
                        Task { await pm.connect() }
                    }
                } header: {
                    Text("Connection Error")
                }
            }
        }
    }
}

// MARK: - URL Validation

/// Returns true if the string is a well-formed http/https URL with a non-empty host.
func isValidGatewayURL(_ string: String) -> Bool {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed),
          let scheme = url.scheme,
          scheme == "http" || scheme == "https",
          let host = url.host,
          !host.isEmpty else { return false }
    return true
}
