import Foundation

/// Thread-safe client for the NullHub management API.
/// Methods return raw `Data` — callers decode using their own JSONDecoder.
actor HubGatewayClient {
    private let baseURL: URL
    private var bearerToken: String?
    private let session: URLSession
    private let decoder: JSONDecoder = GatewayNetworking.snakeCaseDecoder()

    // MARK: Init

    init(
        baseURL: URL,
        bearerToken: String? = nil,
        mockSessionConfig: URLSessionConfiguration? = nil
    ) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken.flatMap { $0.isEmpty ? nil : $0 }
        session = GatewayNetworking.defaultSession(using: mockSessionConfig)
    }

    // MARK: Configuration

    func setToken(_ token: String?) {
        bearerToken = token.flatMap { $0.isEmpty ? nil : $0 }
    }

    func invalidate() {
        session.invalidateAndCancel()
    }

    // MARK: Health

    func checkHealth() async throws {
        let url = baseURL.appendingPathComponent("health")
        let req = try makeRequest(url: url, method: "GET", authenticated: false)
        let (_, response) = try await session.data(for: req)
        try validate(response)
    }

    // MARK: Hub Status

    func fetchHubStatus() async throws -> NullHubStatusResponse {
        let url = baseURL.appendingPathComponent("api/status")
        let req = try makeRequest(url: url, method: "GET", authenticated: bearerToken != nil)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return try decode(NullHubStatusResponse.self, from: data)
    }

    // MARK: Instance Discovery

    func listInstances() async throws -> [String: [String: NullHubInstanceSummary]] {
        let url = baseURL.appendingPathComponent("api/instances")
        let req = try makeRequest(url: url, method: "GET", authenticated: bearerToken != nil)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        let envelope = try decode(NullHubInstancesResponse.self, from: data)
        return envelope.instances
    }

    func listComponents() async throws -> [NullHubComponentInfo] {
        let url = baseURL.appendingPathComponent("api/components")
        let req = try makeRequest(url: url, method: "GET", authenticated: bearerToken != nil)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        let envelope = try decode(NullHubComponentsResponse.self, from: data)
        return envelope.components
    }

    func getComponentManifest(name: String) async throws -> Data {
        let path = "api/components/\(name)/manifest"
        let url = baseURL.appendingPathComponent(path)
        let req = try makeRequest(url: url, method: "GET", authenticated: bearerToken != nil)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return data
    }

    // MARK: Generic GET / POST helpers (return raw Data)

    func getData(instance: String, component: String, subpath: String) async throws -> Data {
        let url = instanceURL(instance: instance, component: component, subpath: subpath)
        let req = try makeRequest(url: url, method: "GET", authenticated: bearerToken != nil)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return data
    }

    func postData(instance: String, component: String, subpath: String, body: Data? = nil) async throws -> Data {
        let url = instanceURL(instance: instance, component: component, subpath: subpath)
        var req = try makeRequest(url: url, method: "POST", authenticated: bearerToken != nil)
        req.httpBody = body ?? Data("{}".utf8)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return data
    }

    func deleteData(instance: String, component: String, subpath: String) async throws {
        let url = instanceURL(instance: instance, component: component, subpath: subpath)
        let req = try makeRequest(url: url, method: "DELETE", authenticated: bearerToken != nil)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
    }

    // MARK: Config (typed for ViewModel compatibility)

    func getConfig(instance: String, component: String, path: String) async throws -> Data {
        let url = baseURL
            .appendingPathComponent("api/instances")
            .appendingPathComponent(component)
            .appendingPathComponent(instance)
            .appendingPathComponent("config")
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let finalURL = comps.url else { throw GatewayError.invalidURL }
        let req = try makeRequest(url: finalURL, method: "GET", authenticated: bearerToken != nil)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return data
    }

    func setConfig(instance: String, component: String, path: String, value: String) async throws {
        _ = try await postData(
            instance: instance, component: component, subpath: "config-set",
            body: JSONSerialization.data(withJSONObject: ["path": path, "value": value])
        )
    }

    func unsetConfig(instance: String, component: String, path: String) async throws {
        _ = try await postData(
            instance: instance, component: component, subpath: "config-unset",
            body: JSONSerialization.data(withJSONObject: ["path": path])
        )
    }

    func reloadConfig(instance: String, component: String) async throws -> Data {
        try await postData(instance: instance, component: component, subpath: "config-reload")
    }

    func validateConfig(instance: String, component: String) async throws -> Data {
        try await postData(instance: instance, component: component, subpath: "config-validate")
    }

    // MARK: - Helpers

    private func instanceURL(instance: String, component: String, subpath: String) -> URL {
        baseURL
            .appendingPathComponent("api/instances")
            .appendingPathComponent(component)
            .appendingPathComponent(instance)
            .appendingPathComponent(subpath)
    }

    // MARK: Cron (typed convenience)

    func listCronJobs(instance: String, component: String) async throws -> [CronJob] {
        let data = try await getData(instance: instance, component: component, subpath: "cron")
        struct CronList: Decodable { let jobs: [CronJob] }
        return try decode(CronList.self, from: data).jobs
    }

    func createCronJob(instance: String, component: String, body: Data) async throws -> CronJob {
        let data = try await postData(instance: instance, component: component, subpath: "cron", body: body)
        struct CronResult: Decodable { let job: CronJob }
        return try decode(CronResult.self, from: data).job
    }

    func getCronJob(instance: String, component: String, id: String) async throws -> CronJob {
        let data = try await getData(instance: instance, component: component, subpath: "cron/\(id)")
        struct CronResult: Decodable { let job: CronJob }
        return try decode(CronResult.self, from: data).job
    }

    func runCronJob(instance: String, component: String, id: String) async throws {
        _ = try await postData(instance: instance, component: component, subpath: "cron/\(id)/run")
    }

    func pauseCronJob(instance: String, component: String, id: String) async throws {
        _ = try await postData(instance: instance, component: component, subpath: "cron/\(id)/pause")
    }

    func resumeCronJob(instance: String, component: String, id: String) async throws {
        _ = try await postData(instance: instance, component: component, subpath: "cron/\(id)/resume")
    }

    func deleteCronJob(instance: String, component: String, id: String) async throws {
        try await deleteData(instance: instance, component: component, subpath: "cron/\(id)")
    }

    // MARK: Channels (typed convenience)

    func listChannels(instance: String, component: String) async throws -> Data {
        try await getData(instance: instance, component: component, subpath: "channels")
    }

    // MARK: MCP (typed convenience)

    func listMCPServers(instance: String, component: String) async throws -> [MCPServer] {
        let data = try await getData(instance: instance, component: component, subpath: "mcp")
        return try decode([MCPServer].self, from: data)
    }

    // MARK: Skills (typed convenience)

    func listSkills(instance: String, component: String) async throws -> [ApiSkillInfo] {
        let data = try await getData(instance: instance, component: component, subpath: "skills")
        return try decode([ApiSkillInfo].self, from: data)
    }

    // MARK: History

    func listHistory(instance: String, component: String) async throws -> Data {
        try await getData(instance: instance, component: component, subpath: "history")
    }

    // MARK: Doctor / Capabilities

    func getDoctor(instance: String, component: String) async throws -> Data {
        try await getData(instance: instance, component: component, subpath: "doctor")
    }

    func getCapabilities(instance: String, component: String) async throws -> Data {
        try await getData(instance: instance, component: component, subpath: "capabilities")
    }

    // MARK: Usage

    func getInstanceUsage(instance: String, component: String, window: String = "24h") async throws -> Data {
        let url = instanceURL(instance: instance, component: component, subpath: "usage")
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "window", value: window)]
        guard let finalURL = comps.url else { throw GatewayError.invalidURL }
        let req = try makeRequest(url: finalURL, method: "GET", authenticated: bearerToken != nil)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        return data
    }

    // MARK: Models

    func listModels(instance: String, component: String) async throws -> ApiModelsResponse {
        let data = try await getData(instance: instance, component: component, subpath: "models")
        return try decode(ApiModelsResponse.self, from: data)
    }

    // MARK: Agent

    func invokeAgent(instance: String, component: String, body: Data) async throws -> Data {
        try await postData(instance: instance, component: component, subpath: "agent", body: body)
    }

    private func makeRequest(url: URL, method: String, authenticated: Bool = false) throws -> URLRequest {
        try GatewayNetworking.makeRequest(url: url, method: method, token: bearerToken, authenticated: authenticated)
    }

    private func validate(_ response: URLResponse, data: Data? = nil) throws {
        try GatewayNetworking.validate(response, data: data, decoder: decoder)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try GatewayNetworking.decode(type, from: data, using: decoder)
    }
}
