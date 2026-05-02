/// Represents the current step in the gateway pairing flow.
enum PairingStep: Equatable {
    case connecting
    case requiresPairing
    case notRequired
    case success
    case failed(String)
}
