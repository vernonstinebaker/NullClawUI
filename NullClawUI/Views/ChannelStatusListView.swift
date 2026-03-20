import SwiftUI

// NOTE: No unit test — pure layout change for the ChannelStatusListView body; covered by visual inspection in Simulator.

// MARK: - ChannelStatusListView

/// Phase 20: Channel Status & Management.
/// Displays all configured gateway communication channels with connection status badges
/// and a read-only detail view per channel. Includes a persistent restart-required banner.
struct ChannelStatusListView: View {
    let profile: GatewayProfile

    @State private var viewModel: ChannelStatusViewModel

    init(profile: GatewayProfile) {
        self.profile = profile
        let url = URL(string: profile.url) ?? URL(string: "http://localhost:5111")!
        let token = (try? KeychainService.retrieveToken(for: profile.url)) ?? ""
        _viewModel = State(wrappedValue: ChannelStatusViewModel(
            client: GatewayClient(baseURL: url, token: token, requiresPairing: profile.requiresPairing)
        ))
    }

    var body: some View {
        List {
            // Restart-required banner — only shown once channels have loaded (not on empty/loading state)
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
            } else if viewModel.isLoading && viewModel.channels.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Loading channels…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Loading channel status")
                }
            } else if viewModel.channels.isEmpty && !viewModel.isLoading {
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

            // Error banner
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
            if viewModel.isLoading && !viewModel.channels.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .task {
            if viewModel.channels.isEmpty && profile.isPaired {
                await viewModel.load()
            }
        }
        .onDisappear {
            viewModel.invalidate()
        }
    }

    // MARK: - Restart banner

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

    // MARK: - Channel list

    private var channelListSection: some View {
        Section {
            ForEach(viewModel.channels) { channel in
                NavigationLink {
                    ChannelDetailView(channel: channel)
                } label: {
                    channelRow(channel)
                }
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func channelRow(_ channel: ChannelInfo) -> some View {
        HStack(spacing: 12) {
            // Channel type icon
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

            // Connection status badge
            connectionBadge(for: channel.connected)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(channelAccessibilityLabel(for: channel))
        .accessibilityHint("Tap to view channel details.")
    }

    @ViewBuilder
    private func connectionBadge(for connected: Bool?) -> some View {
        let (label, color, icon) = connectionInfo(for: connected)
        Label(label, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .accessibilityLabel("Status: \(label)")
    }

    // MARK: - Helpers

    private func channelColor(for name: String) -> Color {
        switch name.lowercased() {
        case "discord":   return .purple
        case "telegram":  return .blue
        case "slack":     return .orange
        case "whatsapp":  return .green
        case "irc":       return .indigo
        case "matrix":    return .teal
        case "email":     return .gray
        default:          return Color(.systemGray2)
        }
    }

    private func connectionInfo(for connected: Bool?) -> (String, Color, String) {
        switch connected {
        case true:  return ("Connected",  .green,  "circle.fill")
        case false: return ("Offline",    .red,    "exclamationmark.circle.fill")
        case nil:   return ("Unknown",    Color(.systemGray), "circle.dotted")
        }
    }

    private func channelAccessibilityLabel(for channel: ChannelInfo) -> String {
        let status = connectionInfo(for: channel.connected).0
        return "\(channel.displayName), \(status)"
    }
}

// MARK: - ChannelDetailView

/// Read-only detail view for a single channel.
private struct ChannelDetailView: View {
    let channel: ChannelInfo

    var body: some View {
        List {
            Section("Identity") {
                LabeledContent("Channel", value: channel.displayName)
                LabeledContent("Status") {
                    HStack(spacing: 4) {
                        switch channel.connected {
                        case true:
                            Image(systemName: "circle.fill").foregroundStyle(.green)
                            Text("Connected")
                        case false:
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                            Text("Offline")
                        case nil:
                            Image(systemName: "circle.dotted").foregroundStyle(.secondary)
                            Text("Unknown")
                        }
                    }
                    .font(.subheadline)
                }
            }

            if channel.serverURL != nil || channel.botName != nil {
                Section("Configuration") {
                    if let serverURL = channel.serverURL, !serverURL.isEmpty {
                        LabeledContent("Server URL") {
                            Text(serverURL)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                        .accessibilityLabel("Server URL: \(serverURL)")
                    }
                    if let botName = channel.botName, !botName.isEmpty {
                        LabeledContent("Bot Name", value: botName)
                            .accessibilityLabel("Bot name: \(botName)")
                    }
                }
            }

            Section {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Channel configuration changes require a gateway restart.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Channel configuration changes require a gateway restart.")
            }
        }
        .navigationTitle(channel.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
