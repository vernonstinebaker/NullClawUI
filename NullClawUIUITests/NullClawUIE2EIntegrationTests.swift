import XCTest

/// End-to-end UI tests that run against a real NullClaw Gateway at http://localhost:5111.
/// No mocks — uses the actual gateway for full integration testing.
///
/// These tests require:
/// 1. A NullClaw Gateway running at http://localhost:5111
/// 2. The gateway should have require_pairing: false (open gateway)
/// 3. Or have a valid pairing code if require_pairing: true
@MainActor
final class NullClawUIE2EIntegrationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Use in-memory storage but connect to real gateway
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Add Gateway (no mocking)

    func testAddOpenGatewayAndNavigateToCronJobs() {
        // Wait for settings screen
        XCTAssertTrue(
            app.textFields["Gateway URL"].waitForExistence(timeout: 10),
            "Settings screen should load"
        )

        // Tap "Add Gateway" or equivalent - navigate to Agents tab first
        // Since we're in unpaired state, we need to add a gateway
        let addButton = app.buttons["Add Gateway"]
        if addButton.waitForExistence(timeout: 3) {
            addButton.tap()
        }
        // For now, let's try entering the gateway URL directly on the settings screen
        let urlField = app.textFields["Gateway URL"]
        urlField.tap()
        urlField.typeText("http://localhost:5111")

        // Tap Connect
        let connectBtn = app.buttons["Connect"]
        XCTAssertTrue(connectBtn.waitForExistence(timeout: 5), "Connect button should exist")
        connectBtn.tap()

        // Wait for either pairing screen or success
        // For open gateway (require_pairing: false), it should connect directly
        let pairedState = app.staticTexts["Chat"].waitForExistence(timeout: 15) ||
            app.buttons["Unpair this device"].waitForExistence(timeout: 15)

        if pairedState {
            // Connected! Navigate to Agents tab
            let agentsTab = app.tabBars.buttons["Servers"]
            XCTAssertTrue(agentsTab.waitForExistence(timeout: 5), "Agents tab should exist")
            agentsTab.tap()

            // Wait for agents list
            XCTAssertTrue(app.navigationBars["Servers"].waitForExistence(timeout: 5))

            // Tap on the first agent
            let agentCard = app.staticTexts["localhost"].firstMatch
            if !agentCard.waitForExistence(timeout: 5) {
                // Try "Local" which is the default test name
                XCTAssertTrue(app.staticTexts["Local"].waitForExistence(timeout: 5))
            }

            // Navigate to Cron Jobs
            let cronLink = app.cells.staticTexts["Cron Jobs"]
            XCTAssertTrue(cronLink.waitForExistence(timeout: 5), "Cron Jobs link should exist")
            cronLink.tap()

            // Check that we got past any auth errors
            let cronNavBar = app.navigationBars["Cron Jobs"]
            let loaded = cronNavBar.waitForExistence(timeout: 10)

            if !loaded {
                // Check for error message
                let errorText = app.staticTexts["HTTP error"].exists ||
                    app.staticTexts["403"].exists ||
                    app.staticTexts["401"].exists
                XCTAssertFalse(errorText, "Should not show HTTP auth error")
            }

            XCTAssertTrue(loaded, "Cron Jobs page should load without auth error")
        } else {
            // Check if we need to pair
            let pairingField = app.textFields["Pairing code"]
            if pairingField.waitForExistence(timeout: 5) {
                XCTSkip("Gateway requires pairing - enter a valid code to test")
            }
        }
    }

    func testGatewayWithAuthTokenCanAccessCronJobs() {
        // This test expects a valid token to be stored
        // For open gateways, no token is needed
        // For paired gateways, the token should be retrieved from Keychain

        // Start at settings
        XCTAssertTrue(app.textFields["Gateway URL"].waitForExistence(timeout: 10))

        // Enter gateway URL
        let urlField = app.textFields["Gateway URL"]
        urlField.tap()
        urlField.typeText("http://localhost:5111")

        // Connect
        app.buttons["Connect"].tap()

        // Wait to see if we're paired or need pairing
        let needPairing = app.textFields["Pairing code"].waitForExistence(timeout: 8)

        if !needPairing {
            // Go to Agents -> agent detail -> Cron Jobs
            app.tabBars.buttons["Servers"].tap()

            // Find and tap agent card
            let agentCell = app.cells.firstMatch
            agentCell.tap()

            // Navigate to Cron Jobs
            let cronLink = app.cells.staticTexts["Cron Jobs"]
            XCTAssertTrue(cronLink.waitForExistence(timeout: 5))
            cronLink.tap()

            // Should not see auth error
            let cronNav = app.navigationBars["Cron Jobs"]
            XCTAssertTrue(
                cronNav.waitForExistence(timeout: 10),
                "Cron Jobs should load without 403/401 error"
            )
        } else {
            XCTSkip("Gateway requires pairing code")
        }
    }

    func testMCPServersAccessible() {
        // Same pattern - navigate to MCP Servers
        // Setup same as above
        XCTAssertTrue(app.textFields["Gateway URL"].waitForExistence(timeout: 10))

        let urlField = app.textFields["Gateway URL"]
        urlField.tap()
        urlField.typeText("http://localhost:5111")

        app.buttons["Connect"].tap()

        let needPairing = app.textFields["Pairing code"].waitForExistence(timeout: 8)

        if !needPairing {
            app.tabBars.buttons["Servers"].tap()

            let agentCell = app.cells.firstMatch
            agentCell.tap()

            // Scroll to MCP Servers
            let list = app.collectionViews.firstMatch
            list.swipeUp()

            let mcpLink = app.cells.staticTexts["MCP Servers"]
            XCTAssertTrue(mcpLink.waitForExistence(timeout: 5))
            mcpLink.tap()

            let mcpNav = app.navigationBars["MCP Servers"]
            XCTAssertTrue(
                mcpNav.waitForExistence(timeout: 10),
                "MCP Servers should load without 403/401 error"
            )
        } else {
            XCTSkip("Gateway requires pairing code")
        }
    }

    func testChannelsAccessible() {
        // Same pattern - navigate to Channels
        XCTAssertTrue(app.textFields["Gateway URL"].waitForExistence(timeout: 10))

        let urlField = app.textFields["Gateway URL"]
        urlField.tap()
        urlField.typeText("http://localhost:5111")

        app.buttons["Connect"].tap()

        let needPairing = app.textFields["Pairing code"].waitForExistence(timeout: 8)

        if !needPairing {
            app.tabBars.buttons["Servers"].tap()

            let agentCell = app.cells.firstMatch
            agentCell.tap()

            let list = app.collectionViews.firstMatch
            list.swipeUp()

            let channelsLink = app.cells.staticTexts["Channels"]
            XCTAssertTrue(channelsLink.waitForExistence(timeout: 5))
            channelsLink.tap()

            let channelsNav = app.navigationBars["Channels"]
            XCTAssertTrue(
                channelsNav.waitForExistence(timeout: 10),
                "Channels should load without 401 error"
            )
        } else {
            XCTSkip("Gateway requires pairing code")
        }
    }
}
