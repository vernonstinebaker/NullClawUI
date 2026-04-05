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

    // MARK: - Cron REST Endpoints

    func testListCronJobsReturnsArray() async throws {
        do {
            try await client.checkHealth()
        } catch {
            throw XCTSkip("Gateway not available")
        }

        // When the gateway doesn't require pairing, listCronJobs succeeds without auth.
        // When it does require pairing (and we're not paired), it returns an HTTP error.
        // Either outcome is valid — we just verify the endpoint is reachable.
        do {
            let jobs = try await client.listCronJobs()
            // Gateway doesn't require pairing — we got the list.
            XCTAssert(jobs.count >= 0, "Should return an array (possibly empty)")
        } catch let error as GatewayError {
            if case .httpError(let code) = error {
                // Gateway requires pairing and we're not paired — expected.
                XCTAssertTrue(code == 401 || code == 403, "Expected 401/403, got \(code)")
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAddCronJobRequiresAuth() async throws {
        do {
            try await client.checkHealth()
        } catch {
            throw XCTSkip("Gateway not available")
        }

        var params = CronJobAddParams()
        params.expression = "*/5 * * * *"
        params.command = "echo test"

        do {
            _ = try await client.addCronJob(params)
            // Gateway doesn't require pairing — job was added.
            XCTAssertTrue(true)
        } catch let error as GatewayError {
            if case .httpError(let code) = error {
                XCTAssertTrue(code == 401 || code == 403 || code == 400, "Expected auth or validation error, got \(code)")
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPauseCronJobRequiresAuth() async throws {
        do {
            try await client.checkHealth()
        } catch {
            throw XCTSkip("Gateway not available")
        }

        do {
            try await client.pauseCronJob(id: "nonexistent-job")
            // Gateway doesn't require pairing.
            XCTAssertTrue(true)
        } catch let error as GatewayError {
            if case .httpError(let code) = error {
                XCTAssertTrue(code == 401 || code == 403 || code == 404, "Expected auth or not-found error, got \(code)")
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRemoveCronJobRequiresAuth() async throws {
        do {
            try await client.checkHealth()
        } catch {
            throw XCTSkip("Gateway not available")
        }

        do {
            try await client.removeCronJob(id: "nonexistent-job")
            // Gateway doesn't require pairing.
            XCTAssertTrue(true)
        } catch let error as GatewayError {
            if case .httpError(let code) = error {
                XCTAssertTrue(code == 401 || code == 403 || code == 404, "Expected auth or not-found error, got \(code)")
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
