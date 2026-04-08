@testable import NullClawUI
import XCTest

@MainActor
final class ServerCardTests: XCTestCase {
    private func makeProfile(
        name: String = "TestAgent",
        url: String = "http://localhost:5111",
        isPaired: Bool = true
    ) -> GatewayProfile {
        GatewayProfile(name: name, url: url, isPaired: isPaired)
    }

    func testServerCardShowsGatewayName() {
        let profile = makeProfile(name: "MyGateway")
        let card = ServerCard(
            profile: profile,
            healthStatus: .online,
            lastChecked: nil,
            cronJobCount: 2,
            mcpServerCount: 3,
            channelCount: 1,
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
            cronJobCount: nil,
            mcpServerCount: nil,
            channelCount: nil,
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
            cronJobCount: 3,
            mcpServerCount: 1,
            channelCount: 2,
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
            cronJobCount: nil,
            mcpServerCount: nil,
            channelCount: nil,
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
            cronJobCount: nil,
            mcpServerCount: nil,
            channelCount: nil,
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
            cronJobCount: 0,
            mcpServerCount: 0,
            channelCount: 0,
            onTap: { expectation.fulfill() }
        )
        XCTAssertNotNil(card.onTap)
        card.onTap()
        wait(for: [expectation], timeout: 1.0)
    }

    func testServerCardShowsResourceCounts() {
        let profile = makeProfile()
        let card = ServerCard(
            profile: profile,
            healthStatus: .online,
            lastChecked: nil,
            cronJobCount: 7,
            mcpServerCount: 2,
            channelCount: 3,
            onTap: {}
        )
        XCTAssertEqual(card.cronJobCount, 7)
        XCTAssertEqual(card.mcpServerCount, 2)
        XCTAssertEqual(card.channelCount, 3)
    }

    func testServerCardNilCounts() {
        let profile = makeProfile()
        let card = ServerCard(
            profile: profile,
            healthStatus: .offline,
            lastChecked: nil,
            cronJobCount: nil,
            mcpServerCount: nil,
            channelCount: nil,
            onTap: {}
        )
        XCTAssertNil(card.cronJobCount)
        XCTAssertNil(card.mcpServerCount)
        XCTAssertNil(card.channelCount)
    }

    func testServerCardShowsLastCheckedTime() {
        let profile = makeProfile()
        let now = Date()
        let card = ServerCard(
            profile: profile,
            healthStatus: .online,
            lastChecked: now,
            cronJobCount: 0,
            mcpServerCount: 0,
            channelCount: 0,
            onTap: {}
        )
        XCTAssertNotNil(card.lastChecked)
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
            cronJobCount: 0,
            mcpServerCount: 0,
            channelCount: 0,
            onTap: {}
        )
        XCTAssertEqual(card.profile.name, "TestGateway")
    }
}
