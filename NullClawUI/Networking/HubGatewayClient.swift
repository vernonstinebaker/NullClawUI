import Foundation

/// Thread-safe client for the NullHub management API.
/// All admin/management operations go through this client.
/// Chat, streaming, agent card, and pairing remain on `GatewayClient`
/// (which connects directly to the NullClaw instance).
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

    // MARK: Config

    func getConfig(
        instance: String,
        component: String,
        path: String
    ) async throws -> [String: String] {
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
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GatewayError.decodingError(underlying: NSError(domain: "HubGateway", code: -1))
        }
        return dict.mapValues { String(describing: $0) }
    }

    func setConfig(
        instance: String,
        component: String,
        path: String,
        value: String
    ) async throws {
        let url = baseURL
            .appendingPathComponent("api/instances")
            .appendingPathComponent(component)
            .appendingPathComponent(instance)
            .appendingPathComponent("config-set")
        var req = try makeRequest(url: url, method: "POST", authenticated: bearerToken != nil)
        let body: [String: String] = ["path": path, "value": value]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
    }

    func unsetConfig(
        instance: String,
        component: String,
        path: String
    ) async throws {
        let url = baseURL
            .appendingPathComponent("api/instances")
            .appendingPathComponent(component)
            .appendingPathComponent(instance)
            .appendingPathComponent("config-unset")
        var req = try makeRequest(url: url, method: "POST", authenticated: bearerToken != nil)
        req.httpBody = try JSONSerialization.data(withJSONObject: ["path": path])
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
    }

    func reloadConfig(
        instance: String,
        component: String
    ) async throws -> [String: String] {
        let url = baseURL
            .appendingPathComponent("api/instances")
            .appendingPathComponent(component)
            .appendingPathComponent(instance)
            .appendingPathComponent("config-reload")
        var req = try makeRequest(url: url, method: "POST", authenticated: bearerToken != nil)
        req.httpBody = Data("{}".utf8)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GatewayError.decodingError(underlying: NSError(domain: "HubGateway", code: -1))
        }
        return dict.mapValues { String(describing: $0) }
    }

    func validateConfig(
        instance: String,
        component: String
    ) async throws -> [String: String] {
        let url = baseURL
            .appendingPathComponent("api/instances")
            .appendingPathComponent(component)
            .appendingPathComponent(instance)
            .appendingPathComponent("config-validate")
        var req = try makeRequest(url: url, method: "POST", authenticated: bearerToken != nil)
        req.httpBody = Data("{}".utf8)
        let (data, response) = try await session.data(for: req)
        try validate(response, data: data)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GatewayError.decodingError(underlying: NSError(domain: "HubGateway", code: -1))
        }
        return dict.mapValues { String(describing: $0) }
    }

    // MARK: - Helpers

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
