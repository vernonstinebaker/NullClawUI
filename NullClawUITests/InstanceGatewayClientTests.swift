@testable import NullClawUI
import XCTest

/// Unit tests for `InstanceGatewayClient` using `MockURLProtocol`.
final class InstanceGatewayClientTests: XCTestCase {
    private var client: InstanceGatewayClient!
    private var mockConfig: URLSessionConfiguration!

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.setup()
        mockConfig = URLSessionConfiguration.ephemeral
        mockConfig.protocolClasses = [MockURLProtocol.self]

        let url = try XCTUnwrap(URL(string: "http://localhost:5111"))
        client = InstanceGatewayClient(baseURL: url, requiresPairing: false, mockSessionConfig: mockConfig)
    }

    override func tearDown() async throws {
        MockURLProtocol.tearDown()
        client = nil
        mockConfig = nil
        try await super.tearDown()
    }

    func testHealthCheckSuccess() async throws {
        let url = try XCTUnwrap(URL(string: "http://localhost:5111"))
        MockURLProtocol.handle(path: "/health") { _ in
            let data = TestFixtures.healthResponseData
            let response = TestFixtures.healthResponse(url: url)
            return (data, response, nil)
        }

        try await client.checkHealth()
        // No error thrown means success
    }

    func testHealthCheckFailure() async throws {
        let url = try XCTUnwrap(URL(string: "http://localhost:5111"))
        MockURLProtocol.handle(path: "/health") { _ in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            ))
            return (nil, response, nil)
        }

        do {
            try await client.checkHealth()
            XCTFail("Expected health check to throw")
        } catch {
            // Expected
            XCTAssertTrue(error is GatewayError)
        }
    }

    func testFetchAgentCardSuccess() async throws {
        let url = try XCTUnwrap(URL(string: "http://localhost:5111"))
        MockURLProtocol.handle(path: "/.well-known/agent-card.json") { _ in
            let data = TestFixtures.agentCardData
            let response = TestFixtures.httpResponse(for: url)
            return (data, response, nil)
        }
        let card = try await client.fetchAgentCard()
        XCTAssertEqual(card.name, "TestAgent")
        XCTAssertEqual(card.version, "1.0.0")
        XCTAssertEqual(card.capabilities?.streaming, true)
    }

    func testFetchAgentCardNotFound() async throws {
        let url = try XCTUnwrap(URL(string: "http://localhost:5111"))
        MockURLProtocol.handle(path: "/.well-known/agent-card.json") { _ in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url,
                statusCode: 404,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            ))
            return (nil, response, nil)
        }
        do {
            _ = try await client.fetchAgentCard()
            XCTFail("Expected fetchAgentCard to throw")
        } catch {
            XCTAssertTrue(error is GatewayError)
        }
    }

    func testPairingRequired() async throws {
        let url = try XCTUnwrap(URL(string: "http://localhost:5111"))
        MockURLProtocol.handle(path: "/pair") { _ in
            // Gateway requires pairing → returns 200 with token
            let data = TestFixtures.pairingResponseData
            let response = TestFixtures.httpResponse(for: url)
            return (data, response, nil)
        }
        let token = try await client.pair(code: "123456")
        XCTAssertEqual(token, "test-bearer-token-abc123")
    }

    func testPairingNotRequired() async throws {
        let url = try XCTUnwrap(URL(string: "http://localhost:5111"))
        MockURLProtocol.handle(path: "/pair") { _ in
            // Gateway returns 403 → pairing not required
            let response = TestFixtures.pairingNotRequiredResponse(url: url)
            return (nil, response, nil)
        }

        let token = try await client.pair(code: "")
        XCTAssertEqual(token, "")
    }
}
