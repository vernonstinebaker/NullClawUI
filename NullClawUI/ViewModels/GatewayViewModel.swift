import Foundation
import Observation

/// Manages connectivity to both NullHub (management) and NullClaw instances (data).
/// Creates a HubGatewayClient when the profile has a hubURL, and always maintains
/// an InstanceGatewayClient for direct A2A/streaming/agent-card access.
@Observable
@MainActor
final class GatewayViewModel {
    var appModel: AppModel
    private(set) var client: InstanceGatewayClient
    private(set) var hubClient: HubGatewayClient?

    init(appModel: AppModel) {
        self.appModel = appModel
        let url = URL(string: appModel.gatewayURL) ?? URL(string: "http://localhost:5111")!
        client = InstanceGatewayClient(baseURL: url)
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

    func switchGateway(to profile: GatewayProfile) async -> InstanceGatewayClient {
        appModel.store.activate(id: profile.id)
        appModel.agentCard = nil
        appModel.connectionStatus = .unknown

        let oldClient = client
        let instanceURLStr = profile.instanceURL ?? profile.url
        let instanceURL = URL(string: instanceURLStr) ?? URL(string: "http://localhost:5111")!
        client = InstanceGatewayClient(baseURL: instanceURL, requiresPairing: profile.requiresPairing)
        await oldClient.invalidate()

        // Restore instance token
        if
            profile.isPaired,
            let tok = try? KeychainService.retrieveToken(for: profile.url),
            !tok.isEmpty
        {
            await client.setToken(tok)
        } else {
            await client.setToken(nil)
        }

        // Set up hub client if configured
        if let hubURLStr = profile.hubURL, let hubURL = URL(string: hubURLStr) {
            await hubClient?.invalidate()
            let token = profile.hubToken
            hubClient = HubGatewayClient(baseURL: hubURL, bearerToken: token)
        } else {
            await hubClient?.invalidate()
            hubClient = nil
        }

        await connect()
        return client
    }

    func unpairActiveGateway() async {
        KeychainService.deleteToken(for: appModel.gatewayURL)
        await client.setToken(nil)
        appModel.isPaired = false
    }

    func unpairGateway(_ profile: GatewayProfile) async {
        let profileID = profile.id
        let profileURL = profile.url
        let isActive = profileID == appModel.store.activeProfileID

        KeychainService.deleteToken(for: profileURL)
        if let hub = profile.hubURL {
            KeychainService.deleteToken(for: hub)
        }
        appModel.store.setProfilePaired(profileID, isPaired: false)
        if isActive {
            await client.setToken(nil)
            appModel.isPaired = false
        }
    }
}
