@testable import NullClawUI
import XCTest

final class HubGatewayClientTests: XCTestCase {
    private var hubURL: URL!
    private var mockConfig: URLSessionConfiguration!

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.setup()
        hubURL = try XCTUnwrap(URL(string: "http://localhost:19800"))
        mockConfig = URLSessionConfiguration.ephemeral
        mockConfig.protocolClasses = [MockURLProtocol.self]
    }

    override func tearDown() async throws {
        MockURLProtocol.tearDown()
        hubURL = nil
        mockConfig = nil
        try await super.tearDown()
    }

    // MARK: - Health

    func testHealthCheckSuccess() async throws {
        let client = HubGatewayClient(baseURL: hubURL, mockSessionConfig: mockConfig)
        MockURLProtocol.handle(path: "/health") { _ in
            let data = Data(#"{"status":"ok"}"#.utf8)
            let response = HTTPURLResponse(
                url: self.hubURL.appendingPathComponent("health"),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response, nil)
        }

        try await client.checkHealth()
    }

    func testHealthCheckFailure() async throws {
        let client = HubGatewayClient(baseURL: hubURL, mockSessionConfig: mockConfig)
        MockURLProtocol.handle(path: "/health") { _ in
            let response = HTTPURLResponse(
                url: self.hubURL.appendingPathComponent("health"),
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (nil, response, nil)
        }

        do {
            try await client.checkHealth()
            XCTFail("Expected error not thrown")
        } catch {
            XCTAssertTrue(error is GatewayError)
        }
    }

    // MARK: - Hub Status

    func testHubStatusSuccess() async throws {
        let client = HubGatewayClient(baseURL: hubURL, mockSessionConfig: mockConfig)
        MockURLProtocol.handle(path: "/api/status") { _ in
            let json = """
            {
              "hub": {
                "version": "dev",
                "platform": "aarch64-macos",
                "pid": 12345,
                "uptime_seconds": 10,
                "access": {
                  "browser_open_url": "http://nullhub.localhost:19800",
                  "direct_url": "http://127.0.0.1:19800",
                  "canonical_url": "http://nullhub.localhost:19800",
                  "fallback_url": "http://127.0.0.1:19800",
                  "local_alias_chain": true,
                  "public_alias_active": false,
                  "public_alias_provider": "none",
                  "public_alias_url": ""
                }
              },
              "components": {},
              "instances": {},
              "overall_status": "ok"
            }
            """
            let data = Data(json.utf8)
            let response = HTTPURLResponse(
                url: self.hubURL.appendingPathComponent("api/status"),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response, nil)
        }

        let status = try await client.fetchHubStatus()
        XCTAssertEqual(status.overallStatus, "ok")
        XCTAssertEqual(status.hub.version, "dev")
        XCTAssertEqual(status.hub.pid, 12345)
    }

    func testHubStatusUnauthorized() async throws {
        let client = HubGatewayClient(baseURL: hubURL, mockSessionConfig: mockConfig)
        MockURLProtocol.handle(path: "/api/status") { _ in
            let response = HTTPURLResponse(
                url: self.hubURL.appendingPathComponent("api/status"),
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (nil, response, nil)
        }

        do {
            _ = try await client.fetchHubStatus()
            XCTFail("Expected error not thrown")
        } catch let error as GatewayError {
            if case let .httpError(code) = error {
                XCTAssertEqual(code, 401)
            } else {
                XCTFail("Expected httpError, got \(error)")
            }
        }
    }

    // MARK: - Token Auth

    func testUnauthenticatedRequestOmitsAuthHeader() async throws {
        let client = HubGatewayClient(baseURL: hubURL, mockSessionConfig: mockConfig)
        var capturedRequest: URLRequest?
        MockURLProtocol.handle(path: "/health") { req in
            capturedRequest = req
            let data = Data(#"{"status":"ok"}"#.utf8)
            let response = HTTPURLResponse(
                url: self.hubURL.appendingPathComponent("health"),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (data, response, nil)
        }

        try await client.checkHealth()
        let authHeader = try XCTUnwrap(capturedRequest).value(forHTTPHeaderField: "Authorization")
        XCTAssertNil(authHeader)
    }

    func testAuthenticatedRequestIncludesAuthHeader() async throws {
        let client = HubGatewayClient(baseURL: hubURL, bearerToken: "test-hub-token", mockSessionConfig: mockConfig)
        var capturedRequest: URLRequest?
        MockURLProtocol.handle(path: "/api/status") { req in
            capturedRequest = req
            let data = TestFixtures.healthResponseData
            let response = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (data, response, nil)
        }

        do {
            _ = try await client.fetchHubStatus()
        } catch {
            // Decoding may fail with a minimal JSON response — that's fine.
            // We only care about the captured request.
        }

        let req = try XCTUnwrap(capturedRequest, "Mock handler was not called — request not intercepted")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-hub-token")
    }
}
