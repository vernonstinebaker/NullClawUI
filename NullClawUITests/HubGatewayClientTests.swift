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

    // MARK: - Instance Discovery

    func testListInstancesEmpty() async throws {
        let client = HubGatewayClient(baseURL: hubURL, mockSessionConfig: mockConfig)
        MockURLProtocol.handle(path: "/api/instances") { req in
            let json = """
            {"instances":{}}
            """
            let data = Data(json.utf8)
            let response = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response, nil)
        }

        let result = try await client.listInstances()
        XCTAssertTrue(result.isEmpty)
    }

    func testListInstancesPopulated() async throws {
        let client = HubGatewayClient(baseURL: hubURL, mockSessionConfig: mockConfig)
        MockURLProtocol.handle(path: "/api/instances") { req in
            let json = """
            {
              "instances": {
                "nullclaw": {
                  "default": {
                    "version": "standalone",
                    "auto_start": false,
                    "launch_mode": "gateway",
                    "verbose": false,
                    "status": "stopped"
                  }
                }
              }
            }
            """
            let data = Data(json.utf8)
            let response = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response, nil)
        }

        let result = try await client.listInstances()
        XCTAssertEqual(result.count, 1)
        let nullclawInstances = try XCTUnwrap(result["nullclaw"])
        XCTAssertEqual(nullclawInstances.count, 1)
        let defaultInstance = try XCTUnwrap(nullclawInstances["default"])
        XCTAssertEqual(defaultInstance.version, "standalone")
        XCTAssertEqual(defaultInstance.status, "stopped")
    }

    func testListComponents() async throws {
        let client = HubGatewayClient(baseURL: hubURL, mockSessionConfig: mockConfig)
        MockURLProtocol.handle(path: "/api/components") { req in
            let json = """
            {
              "components": [
                {
                  "name": "nullclaw",
                  "display_name": "NullClaw",
                  "description": "AI agent runtime.",
                  "repo": "nullclaw/nullclaw",
                  "alpha": false,
                  "installed": true,
                  "standalone": false,
                  "instance_count": 1
                }
              ]
            }
            """
            let data = Data(json.utf8)
            let response = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response, nil)
        }

        let components = try await client.listComponents()
        XCTAssertEqual(components.count, 1)
        XCTAssertEqual(components[0].name, "nullclaw")
        XCTAssertEqual(components[0].displayName, "NullClaw")
        XCTAssertTrue(components[0].installed)
    }

    func testGetComponentManifest() async throws {
        let client = HubGatewayClient(baseURL: hubURL, mockSessionConfig: mockConfig)
        let manifestJSON = """
        {"name":"nullclaw","display_name":"NullClaw","description":"Test"}
        """
        MockURLProtocol.handle(path: "/api/components/nullclaw/manifest") { req in
            let data = Data(manifestJSON.utf8)
            let response = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response, nil)
        }

        let manifest = try await client.getComponentManifest(name: "nullclaw")
        XCTAssertFalse(manifest.isEmpty)
    }

    func testListInstancesError() async throws {
        let client = HubGatewayClient(baseURL: hubURL, mockSessionConfig: mockConfig)
        MockURLProtocol.handle(path: "/api/instances") { req in
            let response = HTTPURLResponse(
                url: req.url!,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (nil, response, nil)
        }

        do {
            _ = try await client.listInstances()
            XCTFail("Expected error not thrown")
        } catch {
            XCTAssertTrue(error is GatewayError)
        }
    }

    // MARK: - Config

    func testGetConfigValue() async throws {
        let client = HubGatewayClient(baseURL: hubURL, mockSessionConfig: mockConfig)
        let instance = "default"
        let component = "nullclaw"
        let configPath = "agent.name"
        MockURLProtocol.handle(path: "/api/instances/nullclaw/default/config") { req in
            let json = """
            {"path":"agent.name","value":"TestBot"}
            """
            let data = Data(json.utf8)
            let response = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response, nil)
        }

        let result = try await client.getConfig(instance: instance, component: component, path: configPath)
        XCTAssertEqual(result["path"], "agent.name")
        XCTAssertEqual(result["value"], "TestBot")
    }

    func testSetConfigValue() async throws {
        let client = HubGatewayClient(baseURL: hubURL, mockSessionConfig: mockConfig)
        MockURLProtocol.handle(path: "/api/instances/nullclaw/default/config-set") { req in
            let json = """
            {"status":"ok","path":"agent.name"}
            """
            let data = Data(json.utf8)
            let response = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response, nil)
        }

        try await client.setConfig(instance: "default", component: "nullclaw", path: "agent.name", value: "TestBot")
    }

    func testUnsetConfigValue() async throws {
        let client = HubGatewayClient(baseURL: hubURL, mockSessionConfig: mockConfig)
        MockURLProtocol.handle(path: "/api/instances/nullclaw/default/config-unset") { req in
            let data = Data(#"{"status":"ok"}"#.utf8)
            let response = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (data, response, nil)
        }

        try await client.unsetConfig(instance: "default", component: "nullclaw", path: "old.key")
    }

    func testReloadConfig() async throws {
        let client = HubGatewayClient(baseURL: hubURL, mockSessionConfig: mockConfig)
        MockURLProtocol.handle(path: "/api/instances/nullclaw/default/config-reload") { req in
            let json = """
            {"valid":true,"message":"config reloaded"}
            """
            let data = Data(json.utf8)
            let response = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response, nil)
        }

        let result = try await client.reloadConfig(instance: "default", component: "nullclaw")
        XCTAssertEqual(result["valid"], "1")
    }

    func testValidateConfig() async throws {
        let client = HubGatewayClient(baseURL: hubURL, mockSessionConfig: mockConfig)
        MockURLProtocol.handle(path: "/api/instances/nullclaw/default/config-validate") { req in
            let json = """
            {"valid":true}
            """
            let data = Data(json.utf8)
            let response = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (data, response, nil)
        }

        let result = try await client.validateConfig(instance: "default", component: "nullclaw")
        XCTAssertEqual(result["valid"], "1")
    }
}
