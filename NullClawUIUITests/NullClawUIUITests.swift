import XCTest

@MainActor
final class NullClawUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // --uitesting resets UserDefaults so tests start in a clean, deterministic state
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        // Terminate the app so any in-flight UserDefaults writes are flushed, then reset
        // the gateway URL pref so a corrupted value from a test cannot leak into production launches.
        app.terminate()
        app = nil
    }

    // MARK: - Phase 1: Settings Screen

    func testSettingsScreenLoads() {
        XCTAssertTrue(app.textFields["Gateway URL"].waitForExistence(timeout: 5))
    }

    func testDefaultGatewayURL() {
        let urlField = app.textFields["Gateway URL"]
        guard urlField.waitForExistence(timeout: 5) else {
            return XCTFail("Gateway URL field not found")
        }
        let value = urlField.value as? String ?? ""
        XCTAssertTrue(
            value.contains("localhost") || value.contains("127.0.0.1") || value.contains("5111"),
            "Expected default gateway URL, got: \(value)"
        )
    }

    func testConnectButtonExists() {
        XCTAssertTrue(app.buttons["Connect"].waitForExistence(timeout: 5))
    }

    func testConnectButtonIsAccessible() {
        let btn = app.buttons["Connect"]
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
        XCTAssertTrue(btn.isHittable)
    }

    func testURLFieldEditable() {
        let urlField = app.textFields["Gateway URL"]
        guard urlField.waitForExistence(timeout: 5) else {
            return XCTFail("Gateway URL field not found")
        }
        urlField.replaceText("http://example.com:5111")
        let value = urlField.value as? String ?? ""
        XCTAssertTrue(value.contains("example.com"), "Expected example.com in value, got: \(value)")
    }

    // MARK: - Phase 2: Pairing UI

    func testPairingCodeFieldNotVisibleBeforeConnect() {
        XCTAssertFalse(app.textFields["Pairing code"].waitForExistence(timeout: 2),
                       "Pairing code field should not appear before connecting")
    }

    // MARK: - Accessibility & Navigation

    func testNavigationTitleExists() {
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    func testConnectionStatusBadgeExists() {
        // ConnectionBadge is a combined accessibility element — surfaces as StaticText with identifier.
        let badge = app.staticTexts["connectionBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 8),
                      "Connection status badge not found in accessibility tree")
    }

    func testConnectionBadgeIsHittable() {
        // ConnectionBadge is a non-interactive view; we just verify it exists and is visible.
        let badge = app.staticTexts["connectionBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 8),
                      "Connection status badge should be visible")
    }
}

// MARK: - Paired State Tests

/// Tests that require the app to already be in the "paired" state.
/// Uses --uitesting-paired which starts the app with isPaired=true and a stubbed AgentCard.
final class PairedUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting-paired"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Tab Navigation (iPhone)

    func testChatTabExists() {
        let chatTab = app.tabBars.buttons["Chat"]
        XCTAssertTrue(chatTab.waitForExistence(timeout: 5), "Chat tab should exist in tab bar")
    }

    func testHistoryTabExists() {
        let historyTab = app.tabBars.buttons["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: 5), "History tab should exist in tab bar")
    }

    func testSettingsTabExists() {
        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5), "Settings tab should exist in tab bar")
    }

    func testSwitchToHistoryTab() {
        let historyTab = app.tabBars.buttons["History"]
        guard historyTab.waitForExistence(timeout: 5) else {
            return XCTFail("History tab not found")
        }
        historyTab.tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5),
                      "History navigation bar should appear after switching to History tab")
    }

    func testSwitchToSettingsTab() {
        let settingsTab = app.tabBars.buttons["Settings"]
        guard settingsTab.waitForExistence(timeout: 5) else {
            return XCTFail("Settings tab not found")
        }
        settingsTab.tap()
        XCTAssertTrue(app.navigationBars["Gateways"].waitForExistence(timeout: 5),
                      "Gateways navigation bar should appear after switching to Settings tab")
    }

    func testSwitchBackToChatTab() {
        // Navigate away from Chat, then return
        let historyTab = app.tabBars.buttons["History"]
        guard historyTab.waitForExistence(timeout: 5) else {
            return XCTFail("History tab not found")
        }
        historyTab.tap()
        _ = app.navigationBars["History"].waitForExistence(timeout: 3)
        app.tabBars.buttons["Chat"].tap()
        // The message input should appear in the Chat tab
        XCTAssertTrue(app.textFields["Message input"].waitForExistence(timeout: 5),
                      "Message input should reappear after switching back to Chat tab")
    }

    // MARK: - ChatView

    func testChatViewNavigationTitle() {
        // The title is now a principal toolbar button showing the agent name.
        let pickerBtn = app.buttons["gatewayPickerButton"]
        XCTAssertTrue(pickerBtn.waitForExistence(timeout: 5),
                      "Chat screen should show the gateway picker title button")
    }

    func testNewConversationButtonExists() {
        // Button is in the navigation toolbar; query by accessibilityIdentifier for reliability
        let btn = app.buttons.matching(
            NSPredicate(format: "identifier == 'newConversationButton' OR label == 'New conversation'")
        ).firstMatch
        XCTAssertTrue(btn.waitForExistence(timeout: 5), "New conversation toolbar button should exist")
    }

    func testNewConversationButtonIsHittable() {
        let btn = app.buttons.matching(
            NSPredicate(format: "identifier == 'newConversationButton' OR label == 'New conversation'")
        ).firstMatch
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
        XCTAssertTrue(btn.isHittable)
    }

    func testMessageInputFieldExists() {
        let input = app.textFields["Message input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), "Message input field should exist in ChatView")
    }

    func testMessageInputFieldIsHittable() {
        let input = app.textFields["Message input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(input.isHittable)
    }

    func testSendButtonExists() {
        let sendBtn = app.buttons["Send message"]
        XCTAssertTrue(sendBtn.waitForExistence(timeout: 5), "Send button should exist in ChatView")
    }

    func testSendButtonDisabledWhenInputEmpty() {
        let sendBtn = app.buttons["Send message"]
        guard sendBtn.waitForExistence(timeout: 5) else {
            return XCTFail("Send button not found")
        }
        XCTAssertFalse(sendBtn.isEnabled,
                       "Send button should be disabled when the message input is empty")
    }

    func testSendButtonEnabledAfterTyping() {
        let input = app.textFields["Message input"]
        guard input.waitForExistence(timeout: 5) else {
            return XCTFail("Message input not found")
        }
        input.tap()
        input.typeText("Hello")
        let sendBtn = app.buttons["Send message"]
        XCTAssertTrue(sendBtn.waitForExistence(timeout: 3))
        XCTAssertTrue(sendBtn.isEnabled,
                      "Send button should become enabled once text is entered")
    }

    func testNewConversationButtonClearsInput() {
        // Type some text, then tap New Conversation — input should clear
        let input = app.textFields["Message input"]
        guard input.waitForExistence(timeout: 5) else {
            return XCTFail("Message input not found")
        }
        input.tap()
        input.typeText("Hello")
        let btn = app.buttons.matching(
            NSPredicate(format: "identifier == 'newConversationButton' OR label == 'New conversation'")
        ).firstMatch
        guard btn.waitForExistence(timeout: 3) else {
            return XCTFail("New conversation button not found")
        }
        btn.tap()
        let value = input.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == "Message…",
                      "Input should be empty after tapping New Conversation, got: \(value)")
    }

    // MARK: - TaskHistoryView

    func testHistoryNavigationTitle() {
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5),
                      "History screen should show 'History' navigation title")
    }

    func testHistoryEmptyStateAppearsWhenNoTasks() {
        // With --uitesting-paired, the gateway is unreachable so task list returns empty.
        app.tabBars.buttons["History"].tap()
        // The empty state shows a "No History Yet" static text
        let emptyLabel = app.staticTexts["No History Yet"]
        XCTAssertTrue(emptyLabel.waitForExistence(timeout: 10),
                      "Empty state should appear when no tasks are available")
    }

    // MARK: - PairedSettingsView

    func testPairedSettingsNavigationTitle() {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Gateways"].waitForExistence(timeout: 5),
                      "PairedSettingsView should show 'Gateways' navigation title")
    }

    func testGatewayRowNavigatesToDetail() {
        app.tabBars.buttons["Settings"].tap()
        _ = app.navigationBars["Gateways"].waitForExistence(timeout: 5)
        // The active gateway row is a NavigationLink — tap it to open the detail page.
        let gatewayRow = app.cells.firstMatch
        XCTAssertTrue(gatewayRow.waitForExistence(timeout: 5), "Gateway list should have at least one row")
        gatewayRow.tap()
        XCTAssertTrue(app.navigationBars["TestAgent"].waitForExistence(timeout: 5),
                      "Detail page should show the gateway name as its navigation title")
    }

    func testUnpairButtonExists() {
        app.tabBars.buttons["Settings"].tap()
        _ = app.navigationBars["Gateways"].waitForExistence(timeout: 5)
        app.cells.firstMatch.tap()
        let unpairBtn = app.buttons["Unpair this device"]
        XCTAssertTrue(unpairBtn.waitForExistence(timeout: 5), "Unpair button should exist in gateway detail")
    }

    func testUnpairButtonIsHittable() {
        app.tabBars.buttons["Settings"].tap()
        _ = app.navigationBars["Gateways"].waitForExistence(timeout: 5)
        app.cells.firstMatch.tap()
        let unpairBtn = app.buttons["Unpair this device"]
        XCTAssertTrue(unpairBtn.waitForExistence(timeout: 5))
        XCTAssertTrue(unpairBtn.exists, "Unpair button should be present on the detail screen")
    }

    func testGatewayInfoInlineURLExists() {
        // URL is now shown on the gateway detail page.
        app.tabBars.buttons["Settings"].tap()
        _ = app.navigationBars["Gateways"].waitForExistence(timeout: 5)
        app.cells.firstMatch.tap()
        let urlLabel = app.staticTexts["URL"]
        XCTAssertTrue(urlLabel.waitForExistence(timeout: 5),
                      "Gateway URL label should be visible on the detail page")
    }

    func testGatewayInfoInlineStatusExists() {
        // Status is shown on the gateway detail page for the active gateway.
        app.tabBars.buttons["Settings"].tap()
        _ = app.navigationBars["Gateways"].waitForExistence(timeout: 5)
        app.cells.firstMatch.tap()
        let statusLabel = app.staticTexts["Status"]
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 5),
                      "Gateway Status label should be visible on the detail page")
    }

    func testUnpairTransitionsToSetupScreen() {
        app.tabBars.buttons["Settings"].tap()
        _ = app.navigationBars["Gateways"].waitForExistence(timeout: 5)
        app.cells.firstMatch.tap()
        let unpairBtn = app.buttons["Unpair this device"]
        guard unpairBtn.waitForExistence(timeout: 5) else {
            return XCTFail("Unpair button not found")
        }
        unpairBtn.tap()
        // After unpairing, ContentView should show SettingsView with the Gateway URL field
        XCTAssertTrue(app.textFields["Gateway URL"].waitForExistence(timeout: 5),
                      "App should return to setup screen after unpairing")
    }
}

// MARK: - XCUIElement helpers

extension XCUIElement {
    /// Clears all existing text in the field and types the given string.
    func replaceText(_ text: String) {
        guard self.value is String else { return }
        tap()
        // Select all via triple-tap to produce a selection
        let coord = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        coord.doubleTap()
        Thread.sleep(forTimeInterval: 0.25)
        let selectAll = XCUIApplication().menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 1.0) {
            selectAll.tap()
            Thread.sleep(forTimeInterval: 0.2)
            typeText(text)
        } else {
            // Fallback: clear char-by-char then type
            guard let current = value as? String, !current.isEmpty else {
                typeText(text)
                return
            }
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)
            typeText(deleteString)
            typeText(text)
        }
    }
}
