@testable import NullClawUI
import XCTest

/// End-to-end integration tests against a real NullHub instance.
/// All tests are skipped automatically if no hub is reachable.
///
/// To run locally: start NullHub at http://localhost:19800
///   cd ~/Programming/claw/nullhub
///   zig build -Dembed-ui=false -Doptimize=ReleaseFast
///   ./zig-out/bin/nullhub serve --port 19800
@MainActor
final class HubLiveIntegrationTests: XCTestCase {
    private static let hubURL = "http://localhost:19800"
    private var client: HubGatewayClient!

    override func setUp() async throws {
        try await super.setUp()
        guard let url = URL(string: Self.hubURL) else {
            throw XCTSkip("Invalid test hub URL")
        }
        client = HubGatewayClient(baseURL: url)
    }

    override func tearDown() async throws {
        if let c = client { await c.invalidate() }
        client = nil
        try await super.tearDown()
    }

    private func requireHub() async throws {
        do {
            try await client.checkHealth()
        } catch {
            throw XCTSkip("NullHub not reachable at \(Self.hubURL): \(error.localizedDescription)")
        }
    }

    // MARK: - Meta

    func testHubHealth() async throws {
        try await requireHub()
        try await client.checkHealth()
    }

    func testHubStatus() async throws {
        try await requireHub()
        let status = try await client.fetchHubStatus()
        XCTAssertFalse(status.overallStatus.isEmpty)
        XCTAssertFalse(status.hub.version.isEmpty)
    }

    func testHubComponents() async throws {
        try await requireHub()
        let components = try await client.listComponents()
        XCTAssertFalse(components.isEmpty)
        let nullclaw = components.first { $0.name == "nullclaw" }
        XCTAssertNotNil(nullclaw)
    }

    func testHubInstances() async throws {
        try await requireHub()
        let instances = try await client.listInstances()
        // May be empty if no instances installed; that's valid
        XCTAssertNotNil(instances)
    }

    func testHubSettings() async throws {
        try await requireHub()
        // Settings is fetched via status endpoint which includes access URLs
        let status = try await client.fetchHubStatus()
        XCTAssertNotNil(status.hub.access.browserOpenUrl)
    }
}
