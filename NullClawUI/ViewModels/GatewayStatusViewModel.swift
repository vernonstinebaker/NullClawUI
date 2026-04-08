import Foundation
import Observation

// MARK: - Profile Health State

/// The health state for a single gateway profile, including resource counts.
struct ProfileHealthState {
    var status: ConnectionStatus = .unknown
    var lastChecked: Date?
    var isChecking: Bool = false
    var cronJobCount: Int?
    var mcpServerCount: Int?
    var channelCount: Int?
}

// MARK: - GatewayStatusViewModel

/// Lightweight multi-gateway health overview with resource counts.
/// Fires concurrent GET /health + REST API calls against every known profile.
@Observable
@MainActor
final class GatewayStatusViewModel {
    private(set) var healthStates: [UUID: ProfileHealthState] = [:]
    var isRefreshing: Bool = false

    var store: GatewayStore
    var mockSessionConfig: URLSessionConfiguration?

    init(store: GatewayStore, mockSessionConfig: URLSessionConfiguration? = nil) {
        self.store = store
        self.mockSessionConfig = mockSessionConfig
    }

    // MARK: - Public API

    func refresh() async {
        guard !isRefreshing else { return }
        let profiles = store.profiles
        guard !profiles.isEmpty else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        for profile in profiles {
            var state = healthStates[profile.id] ?? ProfileHealthState()
            state.isChecking = true
            healthStates[profile.id] = state
        }

        struct HealthResult: Sendable {
            let id: UUID
            let status: ConnectionStatus
            let cronJobCount: Int?
            let mcpServerCount: Int?
            let channelCount: Int?
        }

        await withTaskGroup(of: HealthResult.self) { group in
            for profile in profiles {
                let profileID = profile.id
                let urlString = profile.url
                let cfg = mockSessionConfig
                group.addTask {
                    let (status, cronCount, mcpCount, channelCount) = await Self.checkHealthAndCounts(
                        urlString: urlString,
                        sessionConfig: cfg
                    )
                    return HealthResult(
                        id: profileID,
                        status: status,
                        cronJobCount: cronCount,
                        mcpServerCount: mcpCount,
                        channelCount: channelCount
                    )
                }
            }
            for await result in group {
                var state = healthStates[result.id] ?? ProfileHealthState()
                state.status = result.status
                state.lastChecked = Date()
                state.isChecking = false
                state.cronJobCount = result.cronJobCount
                state.mcpServerCount = result.mcpServerCount
                state.channelCount = result.channelCount
                healthStates[result.id] = state
            }
        }
    }

    // MARK: - Convenience accessors

    func healthState(for profile: GatewayProfile) -> ProfileHealthState {
        healthStates[profile.id] ?? ProfileHealthState()
    }

    // MARK: - Private helpers

    private static func checkHealth(
        urlString: String,
        sessionConfig: URLSessionConfiguration?
    ) async -> ConnectionStatus {
        guard let base = URL(string: urlString) else { return .offline }
        let url = base.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8

        let session = makeSession(config: sessionConfig)
        defer { session.invalidateAndCancel() }
        do {
            let (_, response) = try await session.data(for: request)
            if
                let http = response as? HTTPURLResponse,
                (200 ..< 300).contains(http.statusCode)
            {
                return .online
            }
            return .offline
        } catch {
            return .offline
        }
    }

    private static func checkHealthAndCounts(
        urlString: String,
        sessionConfig: URLSessionConfiguration?
    ) async -> (ConnectionStatus, Int?, Int?, Int?) {
        let status = await checkHealth(urlString: urlString, sessionConfig: sessionConfig)
        guard status == .online else {
            return (status, nil, nil, nil)
        }

        let session = makeSession(config: sessionConfig)
        defer { session.invalidateAndCancel() }
        guard let base = URL(string: urlString) else {
            return (status, nil, nil, nil)
        }

        let token = KeychainService.retrieveTokenIfAvailable(for: urlString)

        async let cronCount = fetchCount(session: session, baseURL: base, path: "/api/cron", token: token) { data in
            if let array = try? JSONDecoder().decode([CronJob].self, from: data) {
                return array.count
            }
            return nil
        }
        async let mcpCount = fetchCount(session: session, baseURL: base, path: "/api/mcp", token: token) { data in
            if let array = try? JSONDecoder().decode([ApiMCPServerInfo].self, from: data) {
                return array.count
            }
            return nil
        }
        async let channelCount = fetchCount(
            session: session,
            baseURL: base,
            path: "/api/channels",
            token: token
        ) { data in
            if let array = try? JSONDecoder().decode([ApiChannelInfo].self, from: data) {
                return array.count
            }
            return nil
        }

        let (c, m, ch) = await (cronCount, mcpCount, channelCount)
        return (status, c, m, ch)
    }

    private static func fetchCount(
        session: URLSession,
        baseURL: URL,
        path: String,
        token: String?,
        parser: @Sendable (Data) -> Int?
    ) async -> Int? {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard
                let http = response as? HTTPURLResponse,
                (200 ..< 300).contains(http.statusCode) else
            {
                return nil
            }
            return parser(data)
        } catch {
            return nil
        }
    }

    private static func makeSession(config: URLSessionConfiguration?) -> URLSession {
        if let cfg = config {
            return URLSession(configuration: cfg)
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        return URLSession(configuration: cfg)
    }
}
