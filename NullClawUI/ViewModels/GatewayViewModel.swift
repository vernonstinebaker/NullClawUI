import Foundation
import Observation

/// Drives Phase 1: connectivity check and agent card fetch.
/// Phase 9+: supports switching between multiple gateway profiles.
@Observable
@MainActor
final class GatewayViewModel {
    var appModel: AppModel
    private(set) var client: GatewayClient

    init(appModel: AppModel) {
        self.appModel = appModel
        let url = URL(string: appModel.gatewayURL) ?? URL(string: "http://localhost:5111")!
        self.client = GatewayClient(baseURL: url)
    }

    // MARK: - Connect to active gateway

    func connect() async {
        guard let url = URL(string: appModel.gatewayURL) else {
            appModel.connectionStatus = .offline
            return
        }
        await client.setBaseURL(url)

        do {
            try await client.checkHealth()
            let card = try await client.fetchAgentCard()
            appModel.agentCard = card
            appModel.connectionStatus = .online
        } catch {
            appModel.agentCard = nil
            appModel.connectionStatus = .offline
        }
    }

    // MARK: - Switch to a different gateway profile

    /// Switches the active gateway profile, rebuilds the GatewayClient, and connects.
    /// Returns the new client so ChatViewModel can be updated.
    func switchGateway(to profile: GatewayProfile) async -> GatewayClient {
        // Activate the new profile in the store.
        appModel.store.activate(id: profile.id)

        // Reset transient connection state.
        appModel.agentCard = nil
        appModel.connectionStatus = .unknown

        // Build a fresh client for the new URL.
        let url = URL(string: profile.url) ?? URL(string: "http://localhost:5111")!
        client = GatewayClient(baseURL: url)

        // Restore token if the profile is already paired.
        if profile.isPaired,
           let tok = (try? KeychainService.retrieveToken(for: profile.url)) ?? nil,
           !tok.isEmpty {
            await client.setToken(tok)
        } else {
            await client.setToken(nil)
        }

        // Connect with the new client.
        await connect()

        return client
    }

    func unpairActiveGateway() async {
        KeychainService.deleteToken(for: appModel.gatewayURL)
        await client.setToken(nil)
        appModel.isPaired = false
    }
}
