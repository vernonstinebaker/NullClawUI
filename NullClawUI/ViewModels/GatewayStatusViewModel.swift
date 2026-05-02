import Foundation
import Observation

struct ProfileHealthState {
    var status: ConnectionStatus = .unknown
    var lastChecked: Date?
    var isChecking: Bool = false
    var cronJobCount: Int?
    var mcpServerCount: Int?
    var channelCount: Int?
}

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
                    let healthStatus = await Self.checkHealth(
                        urlString: urlString,
                        sessionConfig: cfg
                    )
                    guard healthStatus == .online else {
                        return HealthResult(
                            id: profileID,
                            status: healthStatus,
                            cronJobCount: nil,
                            mcpServerCount: nil,
                            channelCount: nil
                        )
                    }

                    let (cronCount, mcpCount, channelCount) = await Self.fetchCounts(
                        urlString: urlString
                    )
                    return HealthResult(
                        id: profileID,
                        status: healthStatus,
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

    func healthState(for profile: GatewayProfile) -> ProfileHealthState {
        healthStates[profile.id] ?? ProfileHealthState()
    }

    private static func checkHealth(
        urlString: String,
        sessionConfig: URLSessionConfiguration?
    ) async -> ConnectionStatus {
        guard let base = URL(string: urlString) else { return .offline }
        let url = base.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8

        let session: URLSession
        if let cfg = sessionConfig {
            session = URLSession(configuration: cfg)
        } else {
            let cfg = URLSessionConfiguration.ephemeral
            cfg.timeoutIntervalForRequest = 8
            session = URLSession(configuration: cfg)
        }
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

    private static func fetchCounts(
        urlString: String
    ) async -> (Int?, Int?, Int?) {
        guard let base = URL(string: urlString) else { return (nil, nil, nil) }
        let token = KeychainService.retrieveTokenIfAvailable(for: urlString)
        let client = InstanceGatewayClient(baseURL: base, token: token, requiresPairing: false)
        defer { Task { await client.invalidate() } }

        async let cronJobs: [CronJob]? = {
            do { return try await client.apiListCronJobs() } catch { return nil }
        }()

        async let mcpServers: [ApiMCPServerInfo]? = {
            do { return try await client.apiListMCPServers() } catch { return nil }
        }()

        async let channels: [ApiChannelInfo]? = {
            do { return try await client.apiListChannels() } catch { return nil }
        }()

        let (c, m, ch) = await (cronJobs, mcpServers, channels)
        return (c?.count, m?.count, ch?.count)
    }
}
