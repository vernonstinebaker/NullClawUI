import XCTest
@testable import NullClawUI

// MARK: - ServerCard Unit Tests

@MainActor
final class ServerCardTests: XCTestCase {

    private func makeProfile(name: String = "TestAgent", url: String = "http://localhost:5111", isPaired: Bool = true) -> GatewayProfile {
        GatewayProfile(name: name, url: url, isPaired: isPaired)
    }

    // MARK: Tests

    func testServerCardShowsGatewayName() {
        let profile = makeProfile(name: "MyGateway")
        let card = ServerCard(
            profile: profile,
            healthStatus: .online,
            lastChecked: nil,
            taskCount: 0,
            cronJobCount: 0,
            onTap: {}
        )
        XCTAssertEqual(card.profile.name, "MyGateway")
    }

    func testServerCardShowsURL() {
        let profile = makeProfile(url: "http://gateway.local:3000")
        let card = ServerCard(
            profile: profile,
            healthStatus: .online,
            lastChecked: nil,
            taskCount: 0,
            cronJobCount: 0,
            onTap: {}
        )
        XCTAssertTrue(card.profile.displayHost.contains("gateway.local"))
    }

    func testServerCardShowsOnlineStatus() {
        let profile = makeProfile()
        let card = ServerCard(
            profile: profile,
            healthStatus: .online,
            lastChecked: nil,
            taskCount: 5,
            cronJobCount: 3,
            onTap: {}
        )
        XCTAssertEqual(card.healthStatus, .online)
    }

    func testServerCardShowsOfflineStatus() {
        let profile = makeProfile()
        let card = ServerCard(
            profile: profile,
            healthStatus: .offline,
            lastChecked: nil,
            taskCount: 0,
            cronJobCount: 0,
            onTap: {}
        )
        XCTAssertEqual(card.healthStatus, .offline)
    }

    func testServerCardShowsUnknownStatus() {
        let profile = makeProfile()
        let card = ServerCard(
            profile: profile,
            healthStatus: .unknown,
            lastChecked: nil,
            taskCount: 0,
            cronJobCount: 0,
            onTap: {}
        )
        XCTAssertEqual(card.healthStatus, .unknown)
    }

    func testServerCardTappingTriggersAction() {
        let profile = makeProfile()
        let expectation = XCTestExpectation(description: "Tap triggered")
        let card = ServerCard(
            profile: profile,
            healthStatus: .online,
            lastChecked: nil,
            taskCount: 0,
            cronJobCount: 0,
            onTap: { expectation.fulfill() }
        )
        XCTAssertNotNil(card.onTap)
        card.onTap()
        wait(for: [expectation], timeout: 1.0)
    }

    func testServerCardShowsMiniStats() {
        let profile = makeProfile()
        let card = ServerCard(
            profile: profile,
            healthStatus: .online,
            lastChecked: nil,
            taskCount: 7,
            cronJobCount: 2,
            onTap: {}
        )
        XCTAssertEqual(card.taskCount, 7)
        XCTAssertEqual(card.cronJobCount, 2)
    }

    func testServerCardShowsLastCheckedTime() {
        let profile = makeProfile()
        let now = Date()
        let card = ServerCard(
            profile: profile,
            healthStatus: .online,
            lastChecked: now,
            taskCount: 0,
            cronJobCount: 0,
            onTap: {}
        )
        XCTAssertNotNil(card.lastChecked)
    }

    func testServerCardHidesMiniStatsWhenOffline() {
        let profile = makeProfile()
        let card = ServerCard(
            profile: profile,
            healthStatus: .offline,
            lastChecked: nil,
            taskCount: 5,
            cronJobCount: 3,
            onTap: {}
        )
        XCTAssertEqual(card.healthStatus, .offline)
    }

    func testServerCardShowsPairedStatus() {
        let paired = makeProfile(isPaired: true)
        let unpaired = makeProfile(isPaired: false)
        XCTAssertTrue(paired.isPaired)
        XCTAssertFalse(unpaired.isPaired)
    }

    func testServerCardHasAccessibilityLabel() {
        let profile = makeProfile(name: "TestGateway")
        let card = ServerCard(
            profile: profile,
            healthStatus: .online,
            lastChecked: nil,
            taskCount: 0,
            cronJobCount: 0,
            onTap: {}
        )
        XCTAssertEqual(card.profile.name, "TestGateway")
    }
}
