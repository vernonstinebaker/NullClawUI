import SwiftUI

/// Sheet for adding a new server — either a NullHub (management plane)
/// or a direct NullClaw instance (data plane).
enum ConnectionType: String, CaseIterable {
    case hub = "NullHub"
    case instance = "Instance"
}

struct AddGatewaySheet: View {
    let onComplete: (String, String, Bool, Bool, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(GatewayStore.self) private var store

    @State private var name: String = ""
    @State private var connectionType: ConnectionType = .hub
    @State private var hubURLString: String = ""
    @State private var hubToken: String = ""
    @State private var instanceURLString: String = ""
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
        .navigationTitle("Add Server")
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
                TextField("Server Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Server name")

                Picker("Connection Type", selection: $connectionType) {
                    ForEach(ConnectionType.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                if connectionType == .hub {
                    TextField("http://hostname:19800", text: $hubURLString)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .accessibilityLabel("NullHub URL")
                        .accessibilityHint("The base URL of your NullHub instance")

                    SecureField("Admin token (optional)", text: $hubToken)
                        .accessibilityLabel("Hub admin token")
                        .accessibilityHint("The --auth-token value if NullHub is running with authentication")
                } else {
                    TextField("http://hostname:5111", text: $instanceURLString)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Instance URL")
                        .accessibilityHint("The base URL of the NullClaw instance")
                }
            } header: {
                Text("Connection")
            } footer: {
                if connectionType == .hub {
                    Text(
                        "NullHub manages one or more NullClaw instances. Enter its URL to auto-discover configured instances."
                    )
                } else {
                    Text(
                        "Connect directly to a NullClaw instance for chat and streaming. Admin features require NullHub."
                    )
                }
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
                .disabled(isProbing || !isFormValid)
            }
        }
    }

    private var isFormValid: Bool {
        let nameOk = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if connectionType == .hub {
            return nameOk && isValidGatewayURL(hubURLString)
        }
        return nameOk && isValidGatewayURL(instanceURLString)
    }

    // MARK: - Pairing View (instance mode only)

    private var pairingView: some View {
        Form {
            Section {
                LabeledContent("Name", value: name)
                LabeledContent("URL") {
                    Text(instanceURLString)
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
                        Text("Connecting to instance…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

            case .requiresPairing:
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "number").foregroundStyle(.secondary).frame(width: 20)
                        TextField("000000", text: $pairingCode)
                            .keyboardType(.numberPad)
                            .font(.title3.monospacedDigit())
                            .accessibilityLabel("Pairing code")
                    }

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
                } header: { Text("Pair Device") }
                    footer: { Text("Enter the 6-digit code shown in the NullClaw admin interface.") }

            case .notRequired:
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Open instance — no pairing code required.")
                    }
                    Button("Complete") { completeAdd() }
                        .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                }

            case .success:
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        Text("Connected successfully.")
                    }
                }
                Section {
                    Button("Done") { completeAdd() }
                        .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                }

            case let .failed(message):
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Could not connect").font(.subheadline.weight(.semibold))
                            Text(message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button("Retry") { Task { await probeConnection() } }
                } header: { Text("Connection Error") }
            }
        }
    }

    // MARK: - Actions

    private func probeConnection() async {
        isProbing = true
        probeError = nil
        defer { isProbing = false }

        if connectionType == .hub {
            await probeHub()
        } else {
            await probeInstance()
        }
    }

    private func probeHub() async {
        guard let url = URL(string: hubURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            probeError = "Invalid URL format."
            return
        }
        let token = hubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = HubGatewayClient(baseURL: url, bearerToken: token.isEmpty ? nil : token)

        do {
            _ = try await client.fetchHubStatus()
            // Hub is reachable — auto-complete
            completeAdd()
        } catch {
            probeError = error.localizedDescription
        }
    }

    private func probeInstance() async {
        guard let url = URL(string: instanceURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
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
                case let .httpError(code) = gwError, code == 401 || code == 403
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

        let trimmedURL = instanceURLString.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let trimmedInstanceURL = instanceURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHubURL = hubURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = hubToken.trimmingCharacters(in: .whitespacesAndNewlines)

        let effectiveHubURL: String? = connectionType == .hub && !trimmedHubURL.isEmpty ? trimmedHubURL : nil
        let effectiveInstanceURL: String = connectionType == .instance && !trimmedInstanceURL.isEmpty
            ? trimmedInstanceURL : trimmedHubURL

        let isPaired: Bool
        let requiresPairing: Bool
        if connectionType == .hub {
            isPaired = !trimmedToken.isEmpty
            requiresPairing = !trimmedToken.isEmpty
        } else {
            switch step {
            case .success: (isPaired, requiresPairing) = (true, true)
            case .notRequired: (isPaired, requiresPairing) = (true, false)
            default: (isPaired, requiresPairing) = (false, true)
            }
        }

        // Store hub token if provided
        if !trimmedToken.isEmpty, let hubURL = effectiveHubURL {
            try? KeychainService.storeToken(trimmedToken, for: hubURL)
        }

        onComplete(trimmedName, effectiveInstanceURL, isPaired, requiresPairing, effectiveHubURL)
        dismiss()
    }
}
