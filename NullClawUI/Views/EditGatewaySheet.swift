import SwiftUI

// MARK: - EditGatewaySheet

struct EditGatewaySheet: View {
    let profile: GatewayProfile
    let onSave: (GatewayProfile) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var url: String
    /// True once the user has edited the URL field at least once, so we don't
    /// show an error on a field the user hasn't touched yet.
    @State private var urlTouched: Bool = false

    init(profile: GatewayProfile, onSave: @escaping (GatewayProfile) -> Void) {
        self.profile = profile
        self.onSave = onSave
        _name = State(wrappedValue: profile.name)
        _url  = State(wrappedValue: profile.url)
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
                        // GatewayProfile is a class (reference type), so `updated` is an
                        // alias for the same object — mutations below are intentional and correct.
                        let updated = profile
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.url  = url.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(updated)
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
