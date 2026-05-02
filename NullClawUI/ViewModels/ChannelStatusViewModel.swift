import Foundation

// MARK: - ViewModel

@Observable
@MainActor
final class ChannelStatusViewModel {
    // MARK: Published state

    private(set) var channels: [ChannelInfo] = []
    private(set) var isLoading: Bool = false
    var errorMessage: String?

    // MARK: Dependencies

    var client: InstanceGatewayClient

    // MARK: Init

    init(client: InstanceGatewayClient) {
        self.client = client
    }

    /// Invalidates the underlying URLSession. Call from the view's `.onDisappear` to
    /// release the session and avoid orphaned network connections.
    func invalidate() {
        let c = client
        Task { await c.invalidate() }
    }

    // MARK: - Load

    /// Fetches channel list from the REST Admin API.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let apiChannels = try await client.apiListChannels()
            channels = apiChannels.map { apiCh in
                ChannelInfo(
                    name: apiCh.type,
                    connected: apiCh.status == "ok",
                    serverURL: nil,
                    botName: apiCh.accountId
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
