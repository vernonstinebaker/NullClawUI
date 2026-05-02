import Foundation
import Network
import Observation

// MARK: - DiscoveredGateway

/// A NullClaw gateway found on the local network via Bonjour.
struct DiscoveredGateway: Identifiable, Equatable {
    /// Stable identity — derived from the Bonjour service name so that re-discoveries
    /// of the same host produce the same ID and SwiftUI can diff the list correctly.
    let id: String // service name (unique on the LAN)
    let name: String // human-readable service name (same as id here)
    let url: String // "http://host:port" ready to paste into the URL field

    static func == (lhs: DiscoveredGateway, rhs: DiscoveredGateway) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url
    }
}

// MARK: - GatewayDiscoveryModel

/// Discovers NullClaw gateways (`_nullclaw._tcp`) and NullHub hubs (`_nullhub._tcp`)
/// on the local network.
///
/// Lifecycle:
///   - Call `start()` when the "Add Gateway" sheet appears.
///   - Call `stop()` when it is dismissed.
///   - Observe `discovered` for the live list of gateways.
///   - `isScanning` is true while any browser is running.
///
/// All public state is on `@MainActor`. `NWBrowser` callbacks arrive on its own
/// internal queue and are dispatched back to `@MainActor` via `Task { @MainActor in }`.
@Observable
@MainActor
final class GatewayDiscoveryModel {
    // MARK: - Public state

    /// Live list of discovered gateways/hubs. Updated as services appear/disappear.
    var discovered: [DiscoveredGateway] = []

    /// True while any `NWBrowser` is running.
    var isScanning: Bool = false

    // MARK: - Private

    private var browser: NWBrowser?
    private var hubBrowser: NWBrowser?

    // MARK: - Control

    /// Start browsing for `_nullclaw._tcp` and `_nullhub._tcp` services.
    /// Safe to call multiple times — running browsers are stopped first.
    func start() {
        stop()
        discovered = []

        let params = NWParameters()
        params.includePeerToPeer = false

        let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_nullclaw._tcp", domain: nil), using: params)
        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.updateScanningState(state)
            }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                discovered = results.compactMap { Self.gateway(from: $0, defaultPort: 5111) }
                    .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            }
        }
        b.start(queue: .global(qos: .utility))
        browser = b

        // Also browse for NullHub services
        let hb = NWBrowser(for: .bonjourWithTXTRecord(type: "_nullhub._tcp", domain: nil), using: params)
        hb.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.updateScanningState(state)
            }
        }
        hb.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let hubResults = results.compactMap { Self.gateway(from: $0, defaultPort: 19800) }
                // Merge hub results into the discovered list
                let existing = discovered.filter { gw in
                    !hubResults.contains(where: { $0.url == gw.url })
                }
                discovered = (existing + hubResults)
                    .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            }
        }
        hb.start(queue: .global(qos: .utility))
        hubBrowser = hb

        isScanning = true
    }

    private func updateScanningState(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            isScanning = true
        case .failed, .cancelled:
            if browser?.state != .ready, hubBrowser?.state != .ready {
                isScanning = false
            }
        default:
            break
        }
    }

    /// Stop all browsers and clear results.
    func stop() {
        browser?.cancel()
        browser = nil
        hubBrowser?.cancel()
        hubBrowser = nil
        isScanning = false
    }

    // MARK: - Helpers

    /// Convert an `NWBrowser.Result` into a `DiscoveredGateway`.
    /// Returns `nil` for results whose endpoint cannot be resolved to an http URL.
    nonisolated static func gateway(from result: NWBrowser.Result, defaultPort: Int = 5111) -> DiscoveredGateway? {
        switch result.endpoint {
        case let .service(serviceName, _, _, _):
            // Extract host and port from the metadata TXT record if available,
            // then fall back to the resolved address once NWConnection resolves it.
            // For discovery purposes we construct the URL from the endpoint directly;
            // the resolved host is filled in by NWEndpoint.debugDescription when available.
            //
            // The canonical approach: build a URL from the service name as a placeholder.
            // The user sees the name and can tap to fill — connection details are confirmed
            // when `InstanceGatewayClient.checkHealth()` is called after they tap Add.
            //
            // TXT-record key "port" is used if the server advertises it.
            var port = defaultPort
            if
                case let .bonjour(txt) = result.metadata,
                let portValue = txt.dictionary["port"],
                let parsedPort = Int(portValue)
            {
                port = parsedPort
            }
            // Use the service name as a hostname placeholder — NWBrowser resolves the
            // actual IP lazily; we store the .local mDNS name which is resolvable on LAN.
            let host = "\(serviceName).local"
            let url = "http://\(host):\(port)"
            return DiscoveredGateway(id: serviceName, name: serviceName, url: url)

        default:
            return nil
        }
    }

    /// Build a `DiscoveredGateway` directly from its components.
    /// Used in tests to bypass `NWBrowser.Result` construction.
    nonisolated static func makeGateway(id: String, name: String, host: String, port: Int) -> DiscoveredGateway {
        DiscoveredGateway(id: id, name: name, url: "http://\(host):\(port)")
    }

    /// Validate that a URL string produced by discovery is well-formed.
    /// Returns the URL unchanged if valid; nil otherwise.
    nonisolated static func validatedURL(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmed),
            let scheme = url.scheme,
            scheme == "http" || scheme == "https",
            let host = url.host,
            !host.isEmpty else { return nil }
        return trimmed
    }
}
