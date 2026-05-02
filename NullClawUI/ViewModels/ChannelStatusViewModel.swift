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

    let client: HubGatewayClient
    let instance: String
    let component: String

    // MARK: Init

    init(client: HubGatewayClient, instance: String = "default", component: String = "nullclaw") {
        self.client = client
        self.instance = instance
        self.component = component
    }

    func invalidate() {
        let c = client
        Task { await c.invalidate() }
    }

    // MARK: - Load

    /// Fetches channel list from the Hub management API.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let dict = try await client.listChannels(instance: instance, component: component)
            channels = Self.parseChannels(from: dict)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Parses a `[String: String]` from Hub's listChannels into `[ChannelInfo]`.
    static func parseChannels(from dict: [String: String]) -> [ChannelInfo] {
        dict.map { type, status in
            ChannelInfo(
                name: type,
                connected: status == "ok" || status == "1",
                serverURL: nil,
                botName: nil
            )
        }
    }
}
