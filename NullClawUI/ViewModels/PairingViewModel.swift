import Foundation
import Observation

/// Drives Phase 2: pairing flow.
@Observable
@MainActor
final class PairingViewModel {
    var appModel: AppModel
    var client: InstanceGatewayClient

    var pairingCode: String = ""
    var isPairing: Bool = false
    var errorMessage: String?

    init(appModel: AppModel, client: InstanceGatewayClient) {
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
            let token = try await client.pair(code: pairingCode.trimmingCharacters(in: .whitespacesAndNewlines))
            // token is empty when the gateway has require_pairing: false (returned 403).
            // In that case pairingMode is already set to .notRequired on the client; skip Keychain.
            if !token.isEmpty {
                try KeychainService.storeToken(token, for: appModel.gatewayURL)
                await client.setToken(token)
            }
            appModel.isPaired = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Probes /pair with an empty code to detect open gateways (require_pairing: false).
    /// If the gateway responds 403, auto-bypasses pairing and sets isPaired = true.
    /// Also marks requiresPairing = false so updateProfile never clobbers isPaired.
    /// No-ops if already paired or a probe is already in progress.
    func probeIfNeeded() async {
        guard !appModel.isPaired, !isPairing else { return }
        isPairing = true
        defer { isPairing = false }
        let result = try? await client.pair(code: "")
        if result?.isEmpty == true {
            // Gateway returned 403 — pairing not required.
            // Must set requiresPairing=false BEFORE isPaired=true so updateProfile
            // never re-derives isPaired from Keychain (open gateways have no token).
            if let id = appModel.store.activeProfileID ?? appModel.store.profiles.first?.id {
                appModel.store.setProfileRequiresPairing(id, requiresPairing: false)
            }
            appModel.isPaired = true
        }
    }

    func unpair() {
        KeychainService.deleteToken(for: appModel.gatewayURL)
        Task { await client.setToken(nil) }
        appModel.isPaired = false // delegates to store.setProfilePaired
        pairingCode = ""
    }
}
