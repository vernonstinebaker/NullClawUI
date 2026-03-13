import XCTest

@MainActor
final class NullClawUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Inject launch argument so app starts in a clean state
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Phase 1: Settings Screen

    func testSettingsScreenLoads() {
        // Gateway URL field should exist
        let urlField = app.textFields["Gateway URL"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5))
    }

    func testDefaultGatewayURL() {
        let urlField = app.textFields["Gateway URL"]
        guard urlField.waitForExistence(timeout: 5) else {
            XCTFail("Gateway URL field not found")
            return
        }
        let value = urlField.value as? String ?? ""
        XCTAssertTrue(value.contains("localhost") || value.isEmpty,
                      "Expected default URL containing 'localhost', got: \(value)")
    }

    func testConnectButtonExists() {
        let connectBtn = app.buttons["Connect"]
        XCTAssertTrue(connectBtn.waitForExistence(timeout: 5))
    }

    func testConnectButtonIsAccessible() {
        let connectBtn = app.buttons["Connect"]
        XCTAssertTrue(connectBtn.waitForExistence(timeout: 5))
        XCTAssertTrue(connectBtn.isHittable)
    }

    func testURLFieldEditable() {
        let urlField = app.textFields["Gateway URL"]
        guard urlField.waitForExistence(timeout: 5) else {
            XCTFail("Gateway URL field not found")
            return
        }
        urlField.tap()
        urlField.clearAndEnterText("http://example.com:5111")
        XCTAssertEqual(urlField.value as? String, "http://example.com:5111")
    }

    // MARK: - Phase 2: Pairing UI

    func testPairingCodeFieldNotVisibleBeforeConnect() {
        // Pairing field should only appear after successful connect
        // Since we can't connect to a real server in UI tests, we verify
        // the field does NOT exist on initial load.
        let codeField = app.textFields["Pairing code"]
        // Wait briefly — it should NOT appear before a connection is made
        let exists = codeField.waitForExistence(timeout: 2)
        XCTAssertFalse(exists, "Pairing code field should not appear before connecting")
    }

    // MARK: - Accessibility

    func testNavigationTitleExists() {
        let nav = app.navigationBars["Settings"]
        XCTAssertTrue(nav.waitForExistence(timeout: 5))
    }

    func testConnectionStatusBadgeExists() {
        // The badge always renders with an accessibility label starting with "Connection status:"
        let badge = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Connection status'")).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
    }
}

// MARK: - XCUIElement helper

extension XCUIElement {
    func clearAndEnterText(_ text: String) {
        guard self.value is String else { return }
        tap()
        let selectAll = XCUIApplication().menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 1) {
            selectAll.tap()
            typeText(text)
        } else {
            // Fallback: triple-tap to select all
            let coordinate = self.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            coordinate.tap()
            coordinate.tap()
            coordinate.tap()
            typeText(text)
        }
    }
}
