import SwiftUI

/// Settings tab shown when already paired.
struct PairedSettingsView: View {
    @Environment(AppModel.self) private var appModel
    var pairingVM: PairingViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemBackground), Color.accentColor.opacity(0.10)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        // Agent info
                        if let card = appModel.agentCard {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("Gateway Info", systemImage: "info.circle")
                                        .font(.headline)
                                    AgentCardView(card: card)
                                    Divider()
                                    HStack {
                                        Label("URL", systemImage: "link")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(appModel.gatewayURL)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    ConnectionBadge(status: appModel.connectionStatus)
                                }
                            }
                        }

                        // Unpair
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Authentication", systemImage: "key.fill")
                                    .font(.headline)
                                Text("Paired with \(appModel.gatewayURL)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button(role: .destructive) {
                                    pairingVM.unpair()
                                } label: {
                                    Label("Unpair Device", systemImage: "trash")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .accessibilityLabel("Unpair this device")
                                .accessibilityHint("Removes stored credentials and returns to the setup screen")
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 28)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
