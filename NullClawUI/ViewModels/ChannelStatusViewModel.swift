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
            let data = try await client.listChannels(instance: instance, component: component)
            channels = Self.parseChannels(from: data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private struct HubChannelEntry: Decodable {
        let type: String
        let status: String?
        let configured: Bool?
    }

    private static func parseChannels(from data: Data) -> [ChannelInfo] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let entries = try? decoder.decode([HubChannelEntry].self, from: data) else { return [] }
        return entries.map { entry in
            ChannelInfo(
                name: entry.type,
                connected: entry.status == "ok" || entry.status == "connected",
                serverURL: nil,
                botName: nil
            )
        }
    }
}
