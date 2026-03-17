import Foundation
import Observation

// MARK: - Profile Health State

/// The health state for a single gateway profile, used by the Status tab.
struct ProfileHealthState: Sendable {
    var status: ConnectionStatus = .unknown
    var lastChecked: Date? = nil
    var isChecking: Bool = false
}

// MARK: - GatewayStatusViewModel

/// Phase 14 (redesigned): lightweight multi-gateway health overview.
/// Fires concurrent GET /health checks against every known profile — no A2A prompts,
/// no tokens required.  Results are nearly instant (<1 s on LAN).
@Observable
@MainActor
final class GatewayStatusViewModel {

    // MARK: Published state

    /// Health state keyed by profile ID.  Ordered to match GatewayStore.profiles.
    private(set) var healthStates: [UUID: ProfileHealthState] = [:]
    /// True while at least one profile is being checked.
    /// Internal (not private) so tests can inspect and simulate concurrent-refresh scenarios.
    var isRefreshing: Bool = false

    // MARK: Dependencies

    /// Provides all known profiles in display order.
    var store: GatewayStore
    /// Optional: if a custom session config is injected (for tests), use it.
    var mockSessionConfig: URLSessionConfiguration?

    // MARK: Init

    init(store: GatewayStore, mockSessionConfig: URLSessionConfiguration? = nil) {
        self.store = store
        self.mockSessionConfig = mockSessionConfig
    }

    // MARK: - Public API

    /// Fires concurrent GET /health checks for all profiles and updates healthStates.
    /// Calling again while already refreshing is a no-op.
    func refresh() async {
        guard !isRefreshing else { return }
        let profiles = store.profiles
        guard !profiles.isEmpty else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        // Mark all profiles as currently checking.
        for profile in profiles {
            var state = healthStates[profile.id] ?? ProfileHealthState()
            state.isChecking = true
            healthStates[profile.id] = state
        }

        // Collect results from concurrent health checks.
        // TaskGroup needs a concrete result type; wrap in a named struct to avoid
        // inference issues with tuples in strict-concurrency mode.
        struct HealthResult: Sendable {
            let id: UUID
            let status: ConnectionStatus
        }

        await withTaskGroup(of: HealthResult.self) { group in
            for profile in profiles {
                let profileID = profile.id
                let urlString = profile.url
                let cfg = mockSessionConfig
                group.addTask {
                    let status = await Self.checkHealth(urlString: urlString, sessionConfig: cfg)
                    return HealthResult(id: profileID, status: status)
                }
            }
            for await result in group {
                var state = healthStates[result.id] ?? ProfileHealthState()
                state.status = result.status
                state.lastChecked = Date()
                state.isChecking = false
                healthStates[result.id] = state
            }
        }
    }

    // MARK: - Convenience accessors

    func healthState(for profile: GatewayProfile) -> ProfileHealthState {
        healthStates[profile.id] ?? ProfileHealthState()
    }

    // MARK: - Private helpers

    /// Performs a single GET /health and returns the resulting ConnectionStatus.
    /// Never throws — always returns .online or .offline.
    private static func checkHealth(
        urlString: String,
        sessionConfig: URLSessionConfiguration?
    ) async -> ConnectionStatus {
        guard let base = URL(string: urlString) else { return .offline }
        let url = base.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8   // fast timeout for a health check

        let session: URLSession
        if let cfg = sessionConfig {
            session = URLSession(configuration: cfg)
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 8
            session = URLSession(configuration: cfg)
        }

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode) {
                return .online
            }
            return .offline
        } catch {
            return .offline
        }
    }
}
