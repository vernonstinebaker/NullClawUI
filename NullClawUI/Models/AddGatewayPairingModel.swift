import Foundation
import Observation
import SwiftUI

// MARK: - PairingStep

/// Represents the current step in the gateway pairing flow.
enum PairingStep: Equatable {
    case connecting
    case requiresPairing
    case notRequired
    case success
    case failed(String)
}

// MARK: - AddGatewayPairingModel

/// Drives the gateway pairing flow: connect → probe → code entry → pair.
/// Used by both the initial gateway-add sheet and the re-pair sheet for
/// already-saved-but-unpaired profiles.
@Observable
@MainActor
final class AddGatewayPairingModel {
    // MARK: State

    private(set) var step: PairingStep = .connecting
    var pairingCode: String = ""
    private(set) var isPairing: Bool = false

    private let url: URL
    private var client: GatewayClient?

    // MARK: Init

    init(url: URL) {
        self.url = url
    }

    // MARK: - Connect

    /// Probes the gateway URL to determine whether pairing is required.
    /// Sets `step` to `.requiresPairing`, `.notRequired`, or `.failed`.
    func connect() async {
        step = .connecting
        let client = GatewayClient(baseURL: url)
        self.client = client

        do {
            // First try to pair with an empty code — if the gateway returns 403,
            // it means require_pairing: false (open gateway).
            let token = try await client.pair(code: "")
            if token.isEmpty {
                // Open gateway — no pairing code required.
                step = .notRequired
            } else {
                // Already paired with empty code (shouldn't happen in practice).
                step = .success
            }
        } catch {
            // Check if it's an HTTP error that indicates the gateway is reachable
            // but requires a pairing code.
            if
                let gwError = error as? GatewayError,
                case let .httpError(code) = gwError,
                code == 401 || code == 403
            {
                step = .requiresPairing
            } else {
                step = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Pair

    /// Submits the 6-digit pairing code to the gateway.
    func pair(profileURL: String, store: GatewayStore, profile: GatewayProfile) async {
        guard let client else { return }
        isPairing = true
        defer { isPairing = false }

        do {
            let token = try await client.pair(code: pairingCode.trimmingCharacters(in: .whitespacesAndNewlines))
            // Store the token in the Keychain, keyed by the profile URL.
            try KeychainService.storeToken(token, for: profileURL)
            store.setProfilePaired(profile.id, isPaired: true)
            step = .success
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    // MARK: - Complete Open Gateway

    /// Marks an open gateway (require_pairing: false) as paired in the store.
    /// No token is stored because open gateways don't issue tokens.
    func completeOpenGateway(store: GatewayStore, profile: GatewayProfile) {
        store.setProfilePaired(profile.id, isPaired: true)
        store.activate(id: profile.id)
    }
}
