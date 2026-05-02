import SwiftUI

struct ChannelStatusListView: View {
    let profile: GatewayProfile

    @State private var viewModel: ChannelStatusViewModel

    init(profile: GatewayProfile) {
        self.profile = profile
        let url = URL(string: profile.url) ?? URL(string: "http://localhost:5111")!
        let token = (try? KeychainService.retrieveToken(for: profile.url)) ?? ""
        _viewModel = State(wrappedValue: ChannelStatusViewModel(
            client: InstanceGatewayClient(baseURL: url, token: token, requiresPairing: profile.requiresPairing)
        ))
    }

    var body: some View {
        List {
            if !viewModel.channels.isEmpty {
                restartBanner
            }

            if !profile.isPaired {
                Section {
                    Label(
                        "Pair this gateway to view channel status.",
                        systemImage: "lock.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            } else if viewModel.isLoading, viewModel.channels.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Loading channels…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Loading channel status")
                }
            } else if viewModel.channels.isEmpty, !viewModel.isLoading {
                Section {
                    ContentUnavailableView(
                        "No Channels Configured",
                        systemImage: "antenna.radiowaves.left.and.right.slash",
                        description: Text("No communication channels are configured on this gateway.")
                    )
                }
            } else {
                channelListSection
            }

            if let err = viewModel.errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Error: \(err)")
                }
            }
        }
        .navigationTitle("Channels")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .toolbar {
            if viewModel.isLoading, !viewModel.channels.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .task {
            if viewModel.channels.isEmpty, profile.isPaired {
                await viewModel.load()
            }
        }
        .onDisappear {
            viewModel.invalidate()
        }
    }

    private var restartBanner: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                    .accessibilityHidden(true)
                Text("Channel configuration changes require a gateway restart.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Warning: Channel configuration changes require a gateway restart.")
        }
    }

    private var channelListSection: some View {
        Section {
            ForEach(viewModel.channels) { channel in
                channelRow(channel)
            }
        }
    }

    private func channelRow(_ channel: ChannelInfo) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(channelColor(for: channel.name))
                    .frame(width: 36, height: 36)
                Image(systemName: channel.iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(channel.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let serverURL = channel.serverURL, !serverURL.isEmpty {
                    Text(serverURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let botName = channel.botName, !botName.isEmpty {
                    Text(botName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            connectionBadge(for: channel.connected)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(channelAccessibilityLabel(for: channel))
    }

    @ViewBuilder
    private func connectionBadge(for connected: Bool?) -> some View {
        let (label, color, icon) = connectionInfo(for: connected)
        Label(label, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .accessibilityLabel("Status: \(label)")
    }

    private func channelColor(for name: String) -> Color {
        switch name.lowercased() {
        case "discord": .purple
        case "telegram": .blue
        case "slack": .orange
        case "whatsapp": .green
        case "irc": .indigo
        case "matrix": .teal
        case "email": .gray
        default: Color(.systemGray2)
        }
    }

    private func connectionInfo(for connected: Bool?) -> (String, Color, String) {
        switch connected {
        case true: ("Connected", .green, "circle.fill")
        case false: ("Offline", .red, "exclamationmark.circle.fill")
        case nil: ("Unknown", Color(.systemGray), "circle.dotted")
        }
    }

    private func channelAccessibilityLabel(for channel: ChannelInfo) -> String {
        let status = connectionInfo(for: channel.connected).0
        return "\(channel.displayName), \(status)"
    }
}
