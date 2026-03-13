import Foundation
import Observation

/// Drives Phase 2: pairing flow.
@Observable
@MainActor
final class PairingViewModel {
    var appModel: AppModel
    var client: GatewayClient

    var pairingCode: String = ""
    var isPairing: Bool = false
    var errorMessage: String? = nil

    init(appModel: AppModel, client: GatewayClient) {
        self.appModel = appModel
        self.client = client
    }

    func pair() async {
        guard pairingCode.count == 6 else {
            errorMessage = "Enter a valid 6-digit code."
            return
        }
        isPairing = true
        errorMessage = nil
        defer { isPairing = false }

        do {
            let token = try await client.pair(code: pairingCode)
            try KeychainService.storeToken(token, for: appModel.gatewayURL)
            await client.setToken(token)
            appModel.isPaired = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unpair() {
        KeychainService.deleteToken(for: appModel.gatewayURL)
        Task { await client.setToken(nil) }
        appModel.isPaired = false
        pairingCode = ""
    }
}
