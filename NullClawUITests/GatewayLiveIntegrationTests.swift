import XCTest
@testable import NullClawUI

/// Integration tests that run against a real NullClaw Gateway instance.
/// Tests are skipped if no server is available at the configured URL.
///
/// To run locally: start a NullClaw Gateway at http://localhost:5111
/// (see NullClaw repository README → "Running Locally").
@MainActor
final class GatewayLiveIntegrationTests: XCTestCase {

    // MARK: - Configuration

    private static let gatewayURL = "http://localhost:5111"
    private var client: GatewayClient!

    override func setUp() async throws {
        try await super.setUp()
        guard let url = URL(string: Self.gatewayURL) else {
            throw XCTSkip("Invalid test gateway URL")
        }
        client = GatewayClient(baseURL: url)
    }

    override func tearDown() async throws {
        if let c = client {
            await c.invalidate()
        }
        client = nil
        try await super.tearDown()
    }

    // MARK: - Health

    func testHealthEndpoint() async throws {
        do {
            try await client.checkHealth()
        } catch {
            throw XCTSkip("Gateway not available at \(Self.gatewayURL): \(error.localizedDescription)")
        }
    }

    // MARK: - Agent Card

    func testFetchAgentCard() async throws {
        do {
            let card = try await client.fetchAgentCard()
            XCTAssertFalse(card.name.isEmpty, "Agent card should have a name")
            XCTAssertFalse(card.version.isEmpty, "Agent card should have a version")
        } catch {
            throw XCTSkip("Gateway not available: \(error.localizedDescription)")
        }
    }

    // MARK: - Pairing (requires running gateway with require_pairing: true)

    func testPairWithInvalidCode() async throws {
        do {
            try await client.checkHealth()
        } catch {
            throw XCTSkip("Gateway not available")
        }

        // An invalid 6-digit code should fail with an HTTP error.
        do {
            _ = try await client.pair(code: "000000")
            // If it succeeds, the gateway has require_pairing: false.
            // That's fine — just verify the pairingMode was updated.
            let mode = await client.pairingMode
            XCTAssertEqual(mode, .notRequired)
        } catch let error as GatewayError {
            if case .httpError = error {
                // Expected — invalid code rejected.
                XCTAssertTrue(true)
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Message Send (requires paired gateway)

    func testSendMessageRequiresPairing() async throws {
        do {
            try await client.checkHealth()
        } catch {
            throw XCTSkip("Gateway not available")
        }

        let mode = await client.pairingMode
        guard mode == .required else {
            throw XCTSkip("Gateway does not require pairing — skipping auth test")
        }

        // Without a token, sendMessage should throw .unpaired.
        let message = A2AMessage(
            role: "user",
            parts: [MessagePart(text: "ping")]
        )
        do {
            _ = try await client.sendMessage(message)
            XCTFail("Expected .unpaired error")
        } catch GatewayError.unpaired {
            // Expected.
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected .unpaired but got: \(error)")
        }
    }

    // MARK: - Task Operations (requires paired gateway)

    func testGetTaskNotFound() async throws {
        do {
            try await client.checkHealth()
        } catch {
            throw XCTSkip("Gateway not available")
        }

        let mode = await client.pairingMode
        guard mode == .required else {
            throw XCTSkip("Gateway does not require pairing")
        }

        // Without pairing, getTask should throw .unpaired.
        do {
            _ = try await client.getTask(id: "nonexistent-task-id")
            XCTFail("Expected .unpaired error")
        } catch GatewayError.unpaired {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected .unpaired but got: \(error)")
        }
    }

    // MARK: - sendOneShotNonStreaming

    func testSendOneShotNonStreamingRequiresPairing() async throws {
        do {
            try await client.checkHealth()
        } catch {
            throw XCTSkip("Gateway not available")
        }

        let mode = await client.pairingMode
        guard mode == .required else {
            throw XCTSkip("Gateway does not require pairing")
        }

        do {
            _ = try await client.sendOneShotNonStreaming("ping")
            XCTFail("Expected .unpaired error")
        } catch GatewayError.unpaired {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Expected .unpaired but got: \(error)")
        }
    }
}
