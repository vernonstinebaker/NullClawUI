@testable import NullClawUI
import SwiftData
import XCTest

final class GatewayProfileMigrationTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: GatewayProfile.self, configurations: config)
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    @MainActor
    private func newContext() -> ModelContext {
        container.mainContext
    }

    // MARK: - Defaults

    @MainActor
    func testGatewayProfileDefaults() {
        let context = newContext()
        let profile = GatewayProfile(name: "Test", url: "http://localhost:5111")
        context.insert(profile)

        XCTAssertEqual(profile.hubURL, nil)
        XCTAssertEqual(profile.instanceName, "default")
        XCTAssertEqual(profile.component, "nullclaw")
    }

    @MainActor
    func testGatewayProfileWithHubURL() {
        let context = newContext()
        let profile = GatewayProfile(
            name: "Hub Server",
            url: "http://localhost:5111",
            hubURL: "http://localhost:19800"
        )
        context.insert(profile)

        XCTAssertEqual(profile.hubURL, "http://localhost:19800")
        XCTAssertEqual(profile.url, "http://localhost:5111")
        XCTAssertEqual(profile.instanceName, "default")
        XCTAssertEqual(profile.component, "nullclaw")
    }

    @MainActor
    func testGatewayProfileExplicitInstanceURL() {
        let context = newContext()
        let profile = GatewayProfile(
            name: "Custom",
            url: "http://localhost:5111",
            hubURL: "http://localhost:19800",
            instanceURL: "http://192.168.1.5:3000",
            instanceName: "production",
            component: "nullclaw"
        )
        context.insert(profile)

        XCTAssertEqual(profile.hubURL, "http://localhost:19800")
        XCTAssertEqual(profile.instanceURL, "http://192.168.1.5:3000")
        XCTAssertEqual(profile.instanceName, "production")
        XCTAssertEqual(profile.component, "nullclaw")
    }

    // MARK: - Backward Compatibility

    @MainActor
    func testLegacyProfileInstanceURLDefaultsToURL() {
        let context = newContext()
        // Legacy: only url set, no hubURL or instanceURL
        let profile = GatewayProfile(name: "Legacy", url: "http://old-server:5111")
        context.insert(profile)

        // instanceURL should fall back to url
        XCTAssertEqual(profile.instanceURL, "http://old-server:5111")
        XCTAssertEqual(profile.hubURL, nil)
    }

    // MARK: - Hub Token Keychain

    func testHubTokenStoreAndRetrieve() throws {
        let hubURL = "http://localhost:19800"
        let testToken = "test-hub-token-abc123"

        try KeychainService.storeToken(testToken, for: hubURL)
        defer { KeychainService.deleteToken(for: hubURL) }

        let retrieved = try KeychainService.retrieveToken(for: hubURL)
        XCTAssertEqual(retrieved, testToken)
    }

    func testHubTokenDelete() throws {
        let hubURL = "http://localhost:19999"
        try KeychainService.storeToken("delete-me", for: hubURL)

        let deleted = KeychainService.deleteToken(for: hubURL)
        XCTAssertTrue(deleted)

        let retrieved = try KeychainService.retrieveToken(for: hubURL)
        XCTAssertNil(retrieved)
    }

    func testHubTokenIsolationFromInstanceToken() throws {
        let hubURL = "http://localhost:19800"
        let instanceURL = "http://localhost:5111"

        try KeychainService.storeToken("hub-secret", for: hubURL)
        try KeychainService.storeToken("instance-secret", for: instanceURL)
        defer {
            KeychainService.deleteToken(for: hubURL)
            KeychainService.deleteToken(for: instanceURL)
        }

        let hubToken = try KeychainService.retrieveToken(for: hubURL)
        let instanceToken = try KeychainService.retrieveToken(for: instanceURL)

        XCTAssertEqual(hubToken, "hub-secret")
        XCTAssertEqual(instanceToken, "instance-secret")
        XCTAssertNotEqual(hubToken, instanceToken)
    }
}
