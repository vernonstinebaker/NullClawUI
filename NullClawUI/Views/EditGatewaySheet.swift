import SwiftUI

// MARK: - EditGatewaySheet

struct EditGatewaySheet: View {
    let profile: GatewayProfile
    /// Receives the updated profile AND the URL it had before editing (needed by
    /// GatewayStore.updateProfile to migrate the Keychain token from the old key).
    let onSave: (_ updated: GatewayProfile, _ previousURL: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var url: String
    /// True once the user has edited the URL field at least once, so we don't
    /// show an error on a field the user hasn't touched yet.
    @State private var urlTouched: Bool = false

    init(profile: GatewayProfile, onSave: @escaping (_ updated: GatewayProfile, _ previousURL: String) -> Void) {
        self.profile = profile
        self.onSave = onSave
        _name = State(wrappedValue: profile.name)
        _url = State(wrappedValue: profile.url)
    }

    private var urlErrorMessage: String? {
        guard urlTouched, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard isValidGatewayURL(url) else {
            return "URL must start with http:// or https:// and include a host."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Gateway Details") {
                    TextField("Name", text: $name)
                        .autocorrectionDisabled()

                    VStack(alignment: .leading, spacing: 4) {
                        TextField("URL", text: $url)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .onChange(of: url) { _, _ in urlTouched = true }
                        if let msg = urlErrorMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.red)
                            // NOTE: No unit test — pure layout change; covered by visual inspection in Simulator.
                        }
                    }
                }
            }
            .navigationTitle("Edit Gateway")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Snapshot the old URL BEFORE mutating the profile (reference type).
                        // GatewayStore.updateProfile uses previousURL to migrate the Keychain
                        // token from the old key to the new one; if we snapshot after mutation
                        // the old and new URLs are the same and the move is silently skipped.
                        let previousURL = profile.url
                        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        profile.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(profile, previousURL)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        !isValidGatewayURL(url))
                }
            }
        }
        .presentationDetents([.medium])
    }
}
