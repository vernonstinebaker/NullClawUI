import Foundation
import Observation

/// Drives Phase 1: connectivity check and agent card fetch.
@Observable
@MainActor
final class GatewayViewModel {
    var appModel: AppModel
    var client: GatewayClient

    init(appModel: AppModel) {
        self.appModel = appModel
        let url = URL(string: appModel.gatewayURL) ?? URL(string: "http://localhost:5111")!
        self.client = GatewayClient(baseURL: url)
    }

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
}
