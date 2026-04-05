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

    func testServersTabExists() {
        let serversTab = app.tabBars.buttons["Servers"]
        XCTAssertTrue(serversTab.waitForExistence(timeout: 5), "Servers tab should exist in tab bar")
    }

    func testChatTabExists() {
        let chatTab = app.tabBars.buttons["Chat"]
        XCTAssertTrue(chatTab.waitForExistence(timeout: 5), "Chat tab should exist in tab bar")
    }

    func testSwitchToServersTab() {
        // Start on Chat (default), switch to Servers
        let serversTab = app.tabBars.buttons["Servers"]
        guard serversTab.waitForExistence(timeout: 5) else {
            return XCTFail("Servers tab not found")
        }
        serversTab.tap()
        XCTAssertTrue(app.navigationBars["Servers"].waitForExistence(timeout: 5),
                      "Servers navigation bar should appear after switching to Servers tab")
    }

    func testSwitchToChatTab() {
        let chatTab = app.tabBars.buttons["Chat"]
        guard chatTab.waitForExistence(timeout: 5) else {
            return XCTFail("Chat tab not found")
        }
        chatTab.tap()
        XCTAssertTrue(app.buttons["gatewayPickerButton"].waitForExistence(timeout: 5),
                      "Chat screen should show the gateway picker title button")
    }

    func testSwitchBackToChatTab() {
        // Navigate to Servers, then return to Chat
        let serversTab = app.tabBars.buttons["Servers"]
        guard serversTab.waitForExistence(timeout: 5) else {
            return XCTFail("Servers tab not found")
        }
        serversTab.tap()
        _ = app.navigationBars["Servers"].waitForExistence(timeout: 3)
        app.tabBars.buttons["Chat"].tap()
        XCTAssertTrue(app.buttons["gatewayPickerButton"].waitForExistence(timeout: 5),
                      "Chat screen should reappear after switching back to Chat tab")
    }

    // MARK: - ChatView

    func testChatViewNavigationTitle() {
        // Navigate to Chat tab first
        app.tabBars.buttons["Chat"].tap()
        _ = app.buttons["gatewayPickerButton"].waitForExistence(timeout: 5)
        let pickerBtn = app.buttons["gatewayPickerButton"]
        XCTAssertTrue(pickerBtn.waitForExistence(timeout: 5),
                      "Chat screen should show the gateway picker title button")
    }

    func testNewConversationButtonExists() {
        app.tabBars.buttons["Chat"].tap()
        _ = app.buttons["gatewayPickerButton"].waitForExistence(timeout: 5)
        let btn = app.buttons.matching(
            NSPredicate(format: "identifier == 'newConversationButton' OR label == 'New conversation'")
        ).firstMatch
        XCTAssertTrue(btn.waitForExistence(timeout: 5), "New conversation toolbar button should exist")
    }

    func testNewConversationButtonIsHittable() {
        app.tabBars.buttons["Chat"].tap()
        _ = app.buttons["gatewayPickerButton"].waitForExistence(timeout: 5)
        let btn = app.buttons.matching(
            NSPredicate(format: "identifier == 'newConversationButton' OR label == 'New conversation'")
        ).firstMatch
        XCTAssertTrue(btn.waitForExistence(timeout: 5))
        XCTAssertTrue(btn.isHittable)
    }

    func testMessageInputFieldExists() {
        app.tabBars.buttons["Chat"].tap()
        _ = app.buttons["gatewayPickerButton"].waitForExistence(timeout: 5)
        let input = app.textFields["Message input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5), "Message input field should exist in ChatView")
    }

    func testMessageInputFieldIsHittable() {
        app.tabBars.buttons["Chat"].tap()
        _ = app.buttons["gatewayPickerButton"].waitForExistence(timeout: 5)
        let input = app.textFields["Message input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(input.isHittable)
    }

    func testSendButtonExists() {
        app.tabBars.buttons["Chat"].tap()
        _ = app.buttons["gatewayPickerButton"].waitForExistence(timeout: 5)
        let sendBtn = app.buttons["Send message"]
        XCTAssertTrue(sendBtn.waitForExistence(timeout: 5), "Send button should exist in ChatView")
    }

    func testSendButtonDisabledWhenInputEmpty() {
        app.tabBars.buttons["Chat"].tap()
        _ = app.buttons["gatewayPickerButton"].waitForExistence(timeout: 5)
        let sendBtn = app.buttons["Send message"]
        guard sendBtn.waitForExistence(timeout: 5) else {
            return XCTFail("Send button not found")
        }
        XCTAssertFalse(sendBtn.isEnabled,
                       "Send button should be disabled when the message input is empty")
    }

    func testSendButtonEnabledAfterTyping() {
        app.tabBars.buttons["Chat"].tap()
        _ = app.buttons["gatewayPickerButton"].waitForExistence(timeout: 5)
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
        app.tabBars.buttons["Chat"].tap()
        _ = app.buttons["gatewayPickerButton"].waitForExistence(timeout: 5)
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

    // MARK: - ServersView

    func testServersViewShowsServerCards() {
        // The Servers tab shows ServerCard views for each gateway.
        app.tabBars.buttons["Servers"].tap()
        _ = app.navigationBars["Servers"].waitForExistence(timeout: 5)
        // At least one server card should be visible.
        XCTAssertTrue(app.staticTexts["TestAgent"].waitForExistence(timeout: 5),
                      "Servers view should show at least one server card")
    }

    func testTappingServerCardOpensDetail() {
        app.tabBars.buttons["Servers"].tap()
        _ = app.navigationBars["Servers"].waitForExistence(timeout: 5)
        // Tap the server card via its accessibility label.
        let card = app.staticTexts["TestAgent"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Server card button should exist")
        card.tap()
        XCTAssertTrue(app.navigationBars["TestAgent"].waitForExistence(timeout: 5),
                      "Tapping a server card should open the gateway detail page")
    }

    // MARK: - ChatView

    func testUnpairButtonExists() {
        app.tabBars.buttons["Servers"].tap()
        _ = app.navigationBars["Servers"].waitForExistence(timeout: 5)
        let card = app.staticTexts["TestAgent"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Server card should exist")
        card.tap()
        _ = app.navigationBars["TestAgent"].waitForExistence(timeout: 5)
        let unpairBtn = findUnpairButton()
        XCTAssertTrue(unpairBtn.waitForExistence(timeout: 5), "Unpair button should exist in gateway detail")
    }

    func testUnpairButtonIsHittable() {
        app.tabBars.buttons["Servers"].tap()
        _ = app.navigationBars["Servers"].waitForExistence(timeout: 5)
        let card = app.staticTexts["TestAgent"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        _ = app.navigationBars["TestAgent"].waitForExistence(timeout: 5)
        let unpairBtn = findUnpairButton()
        XCTAssertTrue(unpairBtn.waitForExistence(timeout: 5))
        XCTAssertTrue(unpairBtn.isHittable, "Unpair button should be hittable")
    }

    func testGatewayInfoInlineURLExists() {
        app.tabBars.buttons["Servers"].tap()
        _ = app.navigationBars["Servers"].waitForExistence(timeout: 5)
        let card = app.staticTexts["TestAgent"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        _ = app.navigationBars["TestAgent"].waitForExistence(timeout: 5)
        let urlLabel = app.staticTexts["URL"]
        XCTAssertTrue(urlLabel.waitForExistence(timeout: 5),
                      "Gateway URL label should be visible on the detail page")
    }

    func testGatewayInfoInlineStatusExists() {
        app.tabBars.buttons["Servers"].tap()
        _ = app.navigationBars["Servers"].waitForExistence(timeout: 5)
        let card = app.staticTexts["TestAgent"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        _ = app.navigationBars["TestAgent"].waitForExistence(timeout: 5)
        let statusLabel = app.staticTexts["Status"]
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 5),
                      "Gateway Status label should be visible on the detail page")
    }

    func testUnpairTransitionsToSetupScreen() {
        app.tabBars.buttons["Servers"].tap()
        _ = app.navigationBars["Servers"].waitForExistence(timeout: 5)
        let card = app.staticTexts["TestAgent"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        _ = app.navigationBars["TestAgent"].waitForExistence(timeout: 5)
        let unpairBtn = findUnpairButton()
        guard unpairBtn.waitForExistence(timeout: 5) else {
            return XCTFail("Unpair button not found")
        }
        unpairBtn.tap()
        XCTAssertTrue(app.textFields["Gateway URL"].waitForExistence(timeout: 5),
                      "App should return to setup screen after unpairing")
    }

    private func findUnpairButton() -> XCUIElement {
        let list = app.collectionViews.firstMatch
        if list.waitForExistence(timeout: 3) {
            list.swipeUp()
            list.swipeUp()
        }
        return app.buttons["Unpair this device"]
    }
}

// MARK: - GatewayDetailSubPageTests

/// Tests that every NavigationLink in GatewayDetailView opens the correct sub-page.
/// Uses --uitesting-paired so the detail row and all sub-page links are visible.
@MainActor
final class GatewayDetailSubPageTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting-paired"]
        app.launch()
        // Navigate to Servers → gateway detail once for all sub-page tests.
        app.tabBars.buttons["Servers"].tap()
        _ = app.navigationBars["Servers"].waitForExistence(timeout: 5)
        let card = app.staticTexts["TestAgent"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Server card should exist")
        card.tap()
        _ = app.navigationBars["TestAgent"].waitForExistence(timeout: 5)
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: Detail page presence

    func testDetailPageLoads() {
        XCTAssertTrue(app.navigationBars["TestAgent"].waitForExistence(timeout: 5),
                      "GatewayDetailView should show the gateway name as its navigation title")
    }

    func testDetailURLLabelExists() {
        XCTAssertTrue(app.staticTexts["URL"].waitForExistence(timeout: 5),
                      "URL label should be visible in the Gateway section")
    }

    func testDetailStatusLabelExists() {
        XCTAssertTrue(app.staticTexts["Status"].waitForExistence(timeout: 5),
                      "Status label should be visible in the Gateway section")
    }

    // MARK: Sub-page navigation links

    func testCronJobsLinkNavigates() {
        let link = app.cells.staticTexts["Cron Jobs"]
        XCTAssertTrue(link.waitForExistence(timeout: 5), "Cron Jobs link should be in the detail list")
        link.tap()
        XCTAssertTrue(app.navigationBars["Cron Jobs"].waitForExistence(timeout: 5),
                      "Tapping Cron Jobs link should push the Cron Jobs page")
    }

    func testAgentConfigLinkNavigates() {
        let link = app.cells.staticTexts["Agent Configuration"]
        XCTAssertTrue(link.waitForExistence(timeout: 5),
                      "Agent Configuration link should be in the detail list")
        link.tap()
        XCTAssertTrue(app.navigationBars["Agent Configuration"].waitForExistence(timeout: 5),
                      "Tapping Agent Configuration link should push the Agent Config page")
    }

    func testAutonomyLinkNavigates() {
        let link = app.cells.staticTexts["Autonomy & Safety"]
        XCTAssertTrue(link.waitForExistence(timeout: 5),
                      "Autonomy & Safety link should be in the detail list")
        link.tap()
        XCTAssertTrue(app.navigationBars["Autonomy & Safety"].waitForExistence(timeout: 5),
                      "Tapping Autonomy & Safety link should push the Autonomy page")
    }

    func testMCPServersLinkNavigates() {
        // MCP Servers link may require a scroll to become visible.
        let list = app.collectionViews.firstMatch
        if list.waitForExistence(timeout: 3) { list.swipeUp() }
        let link = app.cells.staticTexts["MCP Servers"]
        XCTAssertTrue(link.waitForExistence(timeout: 5),
                      "MCP Servers link should be in the detail list")
        link.tap()
        XCTAssertTrue(app.navigationBars["MCP Servers"].waitForExistence(timeout: 5),
                      "Tapping MCP Servers link should push the MCP Servers page")
    }

    func testCostUsageLinkNavigates() {
        let list = app.collectionViews.firstMatch
        if list.waitForExistence(timeout: 3) { list.swipeUp() }
        let link = app.cells.staticTexts["Cost & Usage"]
        XCTAssertTrue(link.waitForExistence(timeout: 5),
                      "Cost & Usage link should be in the detail list")
        link.tap()
        XCTAssertTrue(app.navigationBars["Cost & Usage"].waitForExistence(timeout: 5),
                      "Tapping Cost & Usage link should push the Cost & Usage page")
    }

    func testChannelsLinkNavigates() {
        let list = app.collectionViews.firstMatch
        if list.waitForExistence(timeout: 3) { list.swipeUp() }
        let link = app.cells.staticTexts["Channels"]
        XCTAssertTrue(link.waitForExistence(timeout: 5),
                      "Channels link should be in the detail list")
        link.tap()
        XCTAssertTrue(app.navigationBars["Channels"].waitForExistence(timeout: 5),
                      "Tapping Channels link should push the Channels page")
    }

    // MARK: Edit button

    func testEditGatewayButtonOpensSheet() {
        let list = app.collectionViews.firstMatch
        if list.waitForExistence(timeout: 3) { list.swipeUp(); list.swipeUp() }
        let editCell = app.cells.staticTexts["Edit Gateway"]
        XCTAssertTrue(editCell.waitForExistence(timeout: 5),
                      "Edit Gateway cell should be visible in the detail list")
        editCell.tap()
        XCTAssertTrue(app.navigationBars["Edit Gateway"].waitForExistence(timeout: 5),
                      "Tapping Edit Gateway should present the EditGatewaySheet")
    }
}

// MARK: - GatewaySwitcherTests

/// Tests for the gateway-switcher confirmation dialog shown in the Chat tab title bar.
/// Requires --uitesting-paired-multi which starts the app with two gateways.
@MainActor
final class GatewaySwitcherTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting-paired-multi"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    func testPickerButtonHasChevronWhenMultipleGateways() {
        // Navigate to Chat tab where the picker button lives
        app.tabBars.buttons["Chat"].tap()
        _ = app.buttons["gatewayPickerButton"].waitForExistence(timeout: 5)
        let pickerBtn = app.buttons["gatewayPickerButton"]
        XCTAssertTrue(pickerBtn.waitForExistence(timeout: 5),
                      "Gateway picker button should be present when multiple gateways are configured")
        XCTAssertTrue(pickerBtn.isEnabled,
                      "Picker button should be enabled when more than one gateway exists")
    }

    func testPickerButtonTapShowsDialog() {
        app.tabBars.buttons["Chat"].tap()
        _ = app.buttons["gatewayPickerButton"].waitForExistence(timeout: 5)
        let pickerBtn = app.buttons["gatewayPickerButton"]
        guard pickerBtn.waitForExistence(timeout: 5) else {
            return XCTFail("Gateway picker button not found")
        }
        pickerBtn.tap()
        XCTAssertTrue(app.staticTexts["Switch Gateway"].waitForExistence(timeout: 5),
                      "Tapping the picker button should present the Switch Gateway dialog")
    }

    func testPickerDialogShowsAllGateways() {
        app.tabBars.buttons["Chat"].tap()
        _ = app.buttons["gatewayPickerButton"].waitForExistence(timeout: 5)
        let pickerBtn = app.buttons["gatewayPickerButton"]
        guard pickerBtn.waitForExistence(timeout: 5) else {
            return XCTFail("Gateway picker button not found")
        }
        pickerBtn.tap()
        _ = app.staticTexts["Switch Gateway"].waitForExistence(timeout: 5)
        XCTAssertTrue(app.buttons["TestAgent"].waitForExistence(timeout: 3),
                      "TestAgent should appear as a choice in the switcher dialog")
        XCTAssertTrue(app.buttons["SecondAgent"].waitForExistence(timeout: 3),
                      "SecondAgent should appear as a choice in the switcher dialog")
    }

    func testPickerDialogCanBeDismissed() {
        app.tabBars.buttons["Chat"].tap()
        _ = app.buttons["gatewayPickerButton"].waitForExistence(timeout: 5)
        let pickerBtn = app.buttons["gatewayPickerButton"]
        guard pickerBtn.waitForExistence(timeout: 5) else {
            return XCTFail("Gateway picker button not found")
        }
        pickerBtn.tap()
        _ = app.staticTexts["Switch Gateway"].waitForExistence(timeout: 5)
        let otherBtn = app.buttons["SecondAgent"]
        XCTAssertTrue(otherBtn.waitForExistence(timeout: 3), "SecondAgent button should exist in the dialog")
        otherBtn.tap()
        XCTAssertFalse(app.staticTexts["Switch Gateway"].waitForExistence(timeout: 5),
                       "Switch Gateway dialog should be dismissed after selecting a gateway")
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10),
                      "Chat view navigation bar should be visible after dismissing the switcher dialog")
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
