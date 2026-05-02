import SwiftUI

/// Sheet for pairing an already-saved-but-unpaired gateway profile.
struct GatewayPairSheet: View {
    let profile: GatewayProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(GatewayStore.self) private var store

    @State private var step: PairingStep = .connecting
    @State private var pairingCode: String = ""
    @State private var isPairing: Bool = false
    @State private var client: InstanceGatewayClient?

    var body: some View {
        NavigationStack {
            pairForm
                .navigationTitle("Pair Gateway")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .task { await probe() }
    }

    // MARK: - Pair Form

    private var pairForm: some View {
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

            switch step {
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
                        TextField("000000", text: $pairingCode)
                            .keyboardType(.numberPad)
                            .font(.title3.monospacedDigit())
                            .accessibilityLabel("Pairing code")
                            .accessibilityHint("6-digit code from the NullClaw admin interface")
                    }
                    .padding(.vertical, 4)

                    Button {
                        Task { await submitCode() }
                    } label: {
                        HStack {
                            Spacer()
                            if isPairing {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Label("Pair", systemImage: "checkmark.seal.fill")
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isPairing || pairingCode.count != 6)
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
                        completeOpenGateway()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Complete pairing")
                    .accessibilityHint("Finalises connection to this open gateway without a pairing code")
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
                        .accessibilityLabel("Done")
                        .accessibilityHint("Dismisses the pairing sheet after successful pairing")
                }

            case let .failed(message):
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
                        Task { await probe() }
                    }
                } header: {
                    Text("Connection Error")
                }
            }
        }
    }

    // MARK: - Actions

    private func probe() async {
        step = .connecting
        guard let url = URL(string: profile.url) else {
            step = .failed("Invalid URL")
            return
        }
        let c = InstanceGatewayClient(baseURL: url)
        client = c

        do {
            let token = try await c.pair(code: "")
            if token.isEmpty {
                step = .notRequired
                completeOpenGateway()
            } else {
                step = .success
            }
        } catch {
            if
                let gwError = error as? GatewayError,
                case let .httpError(code) = gwError,
                code == 401 || code == 403
            {
                step = .requiresPairing
            } else {
                step = .failed(error.localizedDescription)
            }
        }
    }

    private func submitCode() async {
        guard let c = client else { return }
        isPairing = true
        defer { isPairing = false }

        do {
            let token = try await c.pair(code: pairingCode.trimmingCharacters(in: .whitespacesAndNewlines))
            try KeychainService.storeToken(token, for: profile.url)
            store.setProfilePaired(profile.id, isPaired: true)
            step = .success
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    private func completeOpenGateway() {
        store.setProfilePaired(profile.id, isPaired: true)
        store.activate(id: profile.id)
    }
}

/// Returns true if the string is a well-formed http/https URL with a non-empty host.
func isValidGatewayURL(_ string: String) -> Bool {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
        let url = URL(string: trimmed),
        let scheme = url.scheme,
        scheme == "http" || scheme == "https",
        let host = url.host,
        !host.isEmpty else { return false }
    return true
}
