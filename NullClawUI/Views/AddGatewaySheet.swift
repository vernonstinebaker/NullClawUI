import SwiftUI

/// Sheet for adding a new gateway profile.
/// Guides the user through: name → URL → connect probe → pairing (if required).
struct AddGatewaySheet: View {
    let onComplete: (String, String, Bool, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(GatewayStore.self) private var store

    @State private var name: String = ""
    @State private var urlString: String = ""
    @State private var isProbing: Bool = false
    @State private var probeError: String? = nil
    @State private var step: PairingStep = .connecting
    @State private var pairingCode: String = ""
    @State private var isPairing: Bool = false
    @State private var pairingClient: InstanceGatewayClient?
    @State private var showPairing: Bool = false

    var body: some View {
        NavigationStack {
            if showPairing {
                pairingView
            } else {
                formView
            }
        }
        .presentationDetents([.medium, .large])
        .navigationTitle("Add Gateway")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    // MARK: - Form View

    private var formView: some View {
        Form {
            Section {
                TextField("Gateway Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Gateway name")
                    .accessibilityHint("A friendly name for this gateway")

                TextField("http://hostname:5111", text: $urlString)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Gateway URL")
                    .accessibilityHint("The base URL of the NullClaw gateway")
            } header: {
                Text("Connection")
            } footer: {
                Text(
                    "Enter the base URL of your NullClaw gateway. The app will probe the connection to determine if pairing is required."
                )
            }

            if let error = probeError {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Connection Error")
                }
            }

            Section {
                Button {
                    Task { await probeConnection() }
                } label: {
                    HStack {
                        Spacer()
                        if isProbing {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Label("Connect", systemImage: "network")
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isProbing || name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty || !isValidGatewayURL(urlString))
            }
        }
    }

    // MARK: - Pairing View

    private var pairingView: some View {
        Form {
            Section {
                LabeledContent("Name", value: name)
                LabeledContent("URL") {
                    Text(urlString)
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
                        Task { await submitPairingCode() }
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
                        completeAdd()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Complete gateway addition")
                    .accessibilityHint("Finalises connection to this open gateway without a pairing code")
                }

            case .success:
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Connected successfully.")
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button("Done") {
                        completeAdd()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Done")
                    .accessibilityHint("Dismisses the add gateway sheet after successful connection")
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
                        Task { await probeConnection() }
                    }
                } header: {
                    Text("Connection Error")
                }
            }
        }
    }

    // MARK: - Actions

    private func probeConnection() async {
        isProbing = true
        probeError = nil
        defer { isProbing = false }

        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            probeError = "Invalid URL format."
            return
        }

        step = .connecting
        let c = InstanceGatewayClient(baseURL: url)
        pairingClient = c
        showPairing = true

        do {
            let token = try await c.pair(code: "")
            if token.isEmpty {
                step = .notRequired
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
                probeError = error.localizedDescription
            }
        }
    }

    private func submitPairingCode() async {
        guard let c = pairingClient else { return }
        isPairing = true
        defer { isPairing = false }

        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let token = try await c.pair(code: pairingCode.trimmingCharacters(in: .whitespacesAndNewlines))
            try KeychainService.storeToken(token, for: trimmedURL)
            step = .success
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    private func completeAdd() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        let isPaired: Bool
        let requiresPairing: Bool
        switch step {
        case .success:
            isPaired = true
            requiresPairing = true
        case .notRequired:
            isPaired = true
            requiresPairing = false
        case .requiresPairing:
            isPaired = false
            requiresPairing = true
        default:
            isPaired = false
            requiresPairing = true
        }

        onComplete(trimmedName, trimmedURL, isPaired, requiresPairing)
        dismiss()
    }
}
