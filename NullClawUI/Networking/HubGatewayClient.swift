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
