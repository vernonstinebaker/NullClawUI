import Foundation
@testable import NullClawUI

/// Test fixture data for unit and integration tests.
/// All JSON strings are valid and match the actual NullClaw Gateway API responses.
enum TestFixtures {
    // MARK: - Agent Card

    static let agentCardJSON = """
    {
      "name": "TestAgent",
      "version": "1.0.0",
      "description": "A test agent for unit testing.",
      "capabilities": {
        "streaming": true,
        "multiModal": true,
        "history": true
      },
      "accentColor": "#007AFF"
    }
    """

    static var agentCardData: Data {
        Data(agentCardJSON.utf8)
    }

    static func decodeAgentCard() throws -> AgentCard {
        try JSONDecoder().decode(AgentCard.self, from: agentCardData)
    }

    // MARK: - Health Response

    static let healthResponseJSON = """
    {
      "status": "healthy",
      "timestamp": "2026-04-07T12:00:00Z",
      "version": "1.0.0"
    }
    """

    static var healthResponseData: Data {
        Data(healthResponseJSON.utf8)
    }

    // MARK: - Pairing Response (Bearer Token)

    static let pairingResponseJSON = """
    {
      "token": "test-bearer-token-abc123",
      "expires_at": "2026-04-08T12:00:00Z"
    }
    """

    static var pairingResponseData: Data {
        Data(pairingResponseJSON.utf8)
    }

    // MARK: - Empty Response (for void endpoints)

    static let emptyResponseData = Data("{}".utf8)

    // MARK: - JSON-RPC 2.0 A2A Message

    static let a2aMessageRequestJSON = """
    {
      "jsonrpc": "2.0",
      "id": "test-id-123",
      "method": "message/send",
      "params": {
        "message": {
          "role": "user",
          "parts": [
            { "text": "Hello, agent!" }
          ]
        }
      }
    }
    """

    static var a2aMessageRequestData: Data {
        Data(a2aMessageRequestJSON.utf8)
    }

    // MARK: - SSE Streaming Envelope

    static let sseEnvelopeJSON = """
    data: {"type":"TaskStatusUpdateEvent","task_id":"task-123","status":"running"}
    """

    static var sseEnvelopeData: Data {
        Data(sseEnvelopeJSON.utf8)
    }

    // MARK: - Gateway Profile

    static let gatewayProfileJSON = """
    {
      "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
      "name": "Test Gateway",
      "url": "http://localhost:5111",
      "isPaired": true,
      "requiresPairing": false
    }
    """

    static var gatewayProfileData: Data {
        Data(gatewayProfileJSON.utf8)
    }

    // MARK: - Helpers

    /// Returns a valid HTTPURLResponse for a given path and status code.
    static func httpResponse(
        for url: URL,
        statusCode: Int = 200,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    /// Returns a valid HTTPURLResponse for a health check endpoint.
    static func healthResponse(url: URL) -> HTTPURLResponse {
        httpResponse(for: url, statusCode: 200)
    }

    /// Returns a 403 response indicating pairing not required.
    static func pairingNotRequiredResponse(url: URL) -> HTTPURLResponse {
        httpResponse(for: url, statusCode: 403)
    }

    /// Returns a 401 response indicating missing/invalid token.
    static func unauthorizedResponse(url: URL) -> HTTPURLResponse {
        httpResponse(for: url, statusCode: 401)
    }
}
