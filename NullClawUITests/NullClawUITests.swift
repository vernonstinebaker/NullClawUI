import XCTest
@testable import NullClawUI

// MARK: - Keychain Tests

final class KeychainServiceTests: XCTestCase {
    private let testURL = "http://localhost:5111"
    private let testToken = "test-bearer-token-abc123"

    override func tearDown() {
        KeychainService.deleteToken(for: testURL)
        super.tearDown()
    }

    func testStoreAndRetrieveToken() throws {
        try KeychainService.storeToken(testToken, for: testURL)
        let retrieved = try KeychainService.retrieveToken(for: testURL)
        XCTAssertEqual(retrieved, testToken)
    }

    func testDeleteToken() throws {
        try KeychainService.storeToken(testToken, for: testURL)
        KeychainService.deleteToken(for: testURL)
        let retrieved = try KeychainService.retrieveToken(for: testURL)
        XCTAssertNil(retrieved)
    }

    func testOverwriteToken() throws {
        try KeychainService.storeToken(testToken, for: testURL)
        let newToken = "new-token-xyz"
        try KeychainService.storeToken(newToken, for: testURL)
        let retrieved = try KeychainService.retrieveToken(for: testURL)
        XCTAssertEqual(retrieved, newToken)
    }

    func testRetrieveMissingToken() throws {
        let result = try KeychainService.retrieveToken(for: "http://notexist:9999")
        XCTAssertNil(result)
    }

    func testDifferentGatewaysIsolated() throws {
        let url1 = "http://gateway1:5111"
        let url2 = "http://gateway2:5111"
        defer {
            KeychainService.deleteToken(for: url1)
            KeychainService.deleteToken(for: url2)
        }
        try KeychainService.storeToken("token1", for: url1)
        try KeychainService.storeToken("token2", for: url2)
        XCTAssertEqual(try KeychainService.retrieveToken(for: url1), "token1")
        XCTAssertEqual(try KeychainService.retrieveToken(for: url2), "token2")
    }
}

// MARK: - AgentCard Decoding Tests

final class AgentCardDecodingTests: XCTestCase {
    func testDecodeFullAgentCard() throws {
        let json = """
        {
            "name": "NullClaw",
            "version": "1.2.0",
            "description": "An AI gateway.",
            "capabilities": {
                "streaming": true,
                "multi_modal": false,
                "history": true
            },
            "accentColor": "#7B5EA7"
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let card = try decoder.decode(AgentCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.name, "NullClaw")
        XCTAssertEqual(card.version, "1.2.0")
        XCTAssertEqual(card.description, "An AI gateway.")
        XCTAssertEqual(card.capabilities?.streaming, true)
        XCTAssertEqual(card.capabilities?.multiModal, false)
        XCTAssertEqual(card.capabilities?.history, true)
        XCTAssertEqual(card.accentColor, "#7B5EA7")
    }

    func testDecodeMinimalAgentCard() throws {
        let json = "{ \"name\": \"NullClaw\", \"version\": \"1.0.0\" }"
        let card = try JSONDecoder().decode(AgentCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.name, "NullClaw")
        XCTAssertNil(card.description)
        XCTAssertNil(card.capabilities)
        XCTAssertNil(card.accentColor)
    }
}

// MARK: - JSONRPCRequest Encoding Tests

final class JSONRPCEncodingTests: XCTestCase {
    func testEncodeMessageSendRequest() throws {
        let params = MessageSendParams(message: A2AMessage(role: "user", parts: [MessagePart(text: "Hello")]))
        let rpc = JSONRPCRequest(id: "test-id", method: "message/send", params: params)

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(rpc)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(dict?["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(dict?["method"] as? String, "message/send")
        XCTAssertEqual(dict?["id"] as? String, "test-id")
        XCTAssertNotNil(dict?["params"])
    }
}

// MARK: - NullClawTask Decoding Tests

final class NullClawTaskDecodingTests: XCTestCase {
    func testDecodeCompletedTask() throws {
        let json = """
        {
            "id": "task-001",
            "status": {
                "state": "completed",
                "message": {
                    "role": "assistant",
                    "parts": [{ "text": "Hello, I am NullClaw!" }]
                }
            }
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let task = try decoder.decode(NullClawTask.self, from: Data(json.utf8))
        XCTAssertEqual(task.id, "task-001")
        XCTAssertEqual(task.status.state, "completed")
        XCTAssertEqual(task.status.message?.parts.first?.text, "Hello, I am NullClaw!")
    }
}

// MARK: - SSE Parsing Tests

final class SSEParsingTests: XCTestCase {
    func testParseStatusUpdateEvent() throws {
        let json = """
        {
            "id": "task-001",
            "result": {
                "kind": "status-update",
                "task_id": "task-001",
                "context_id": "ctx-1",
                "status": {
                    "state": "completed",
                    "message": {
                        "role": "assistant",
                        "parts": [{ "text": "Done." }]
                    }
                },
                "final": true
            }
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let event = try decoder.decode(TaskStatusUpdateEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.id, "task-001")
        XCTAssertEqual(event.result?.final, true)
        XCTAssertEqual(event.result?.status?.state, "completed")
    }

    func testParseArtifactUpdateEvent() throws {
        let json = """
        {
            "id": "task-002",
            "result": {
                "kind": "artifact-update",
                "task_id": "task-002",
                "context_id": "ctx-2",
                "artifact": {
                    "artifact_id": "art-1",
                    "parts": [{ "text": "Hello" }]
                },
                "append": true,
                "final": false
            }
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let event = try decoder.decode(TaskStatusUpdateEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.result?.kind, "artifact-update")
        XCTAssertEqual(event.result?.append, true)
        XCTAssertEqual(event.result?.artifact?.parts.first?.text, "Hello")
        XCTAssertEqual(event.result?.final, false)
    }
}

// MARK: - GatewayError Tests

final class GatewayErrorTests: XCTestCase {
    func testLocalizedDescriptions() {
        XCTAssertNotNil(GatewayError.invalidURL.errorDescription)
        XCTAssertNotNil(GatewayError.httpError(statusCode: 401).errorDescription)
        XCTAssertNotNil(GatewayError.unpaired.errorDescription)
        XCTAssertTrue(GatewayError.httpError(statusCode: 404).errorDescription!.contains("404"))
    }
}

// MARK: - HealthIndicator Tests

final class HealthIndicatorTests: XCTestCase {
    func testHealthyColor() {
        XCTAssertEqual(HealthIndicator.healthy.color, .green)
    }

    func testDegradedColor() {
        XCTAssertEqual(HealthIndicator.degraded.color, .yellow)
    }

    func testUnhealthyColor() {
        XCTAssertEqual(HealthIndicator.unhealthy.color, .red)
    }

    func testUnknownColor() {
        XCTAssertEqual(HealthIndicator.unknown.color, .orange)
    }

    func testEquatable() {
        XCTAssertEqual(HealthIndicator.healthy, HealthIndicator.healthy)
        XCTAssertNotEqual(HealthIndicator.healthy, HealthIndicator.unhealthy)
    }
}

// MARK: - DesignTokens Tests

final class DesignTokensTests: XCTestCase {
    func testCornerRadiusValues() {
        XCTAssertEqual(DesignTokens.CornerRadius.card, 20)
        XCTAssertEqual(DesignTokens.CornerRadius.medium, 12)
        XCTAssertEqual(DesignTokens.CornerRadius.bubble, 10)
        XCTAssertEqual(DesignTokens.CornerRadius.small, 8)
        XCTAssertEqual(DesignTokens.CornerRadius.inner, 6)
        XCTAssertEqual(DesignTokens.CornerRadius.tiny, 2)
    }

    func testSpacingValues() {
        XCTAssertEqual(DesignTokens.Spacing.section, 24)
        XCTAssertEqual(DesignTokens.Spacing.card, 20)
        XCTAssertEqual(DesignTokens.Spacing.standard, 16)
        XCTAssertEqual(DesignTokens.Spacing.tight, 12)
        XCTAssertEqual(DesignTokens.Spacing.minimal, 8)
        XCTAssertEqual(DesignTokens.Spacing.tiny, 4)
    }

    func testFontSizeValues() {
        XCTAssertEqual(DesignTokens.FontSize.title, 28)
        XCTAssertEqual(DesignTokens.FontSize.headline, 17)
        XCTAssertEqual(DesignTokens.FontSize.body, 17)
        XCTAssertEqual(DesignTokens.FontSize.callout, 16)
        XCTAssertEqual(DesignTokens.FontSize.subheadline, 15)
        XCTAssertEqual(DesignTokens.FontSize.footnote, 13)
        XCTAssertEqual(DesignTokens.FontSize.caption, 12)
        XCTAssertEqual(DesignTokens.FontSize.caption2, 11)
    }

    func testAnimationSpringReturnsNonNil() {
        _ = DesignTokens.Animation.spring()
        _ = DesignTokens.Animation.quick()
    }

    func testTransitionsReturnNonNil() {
        _ = DesignTokens.Animation.fade()
        _ = DesignTokens.Animation.expand()
    }
}

// MARK: - AppModel Error Handling Tests

final class AppModelErrorHandlingTests: XCTestCase {
    @MainActor
    func testPresentErrorWithLocalizedError() {
        let store = GatewayStore(inMemory: true)
        let appModel = AppModel(store: store)
        XCTAssertNil(appModel.presentedErrorMessage)

        struct TestError: LocalizedError {
            var errorDescription: String? { "Test error message" }
        }
        appModel.presentError(TestError())
        XCTAssertEqual(appModel.presentedErrorMessage, "Test error message")
    }

    @MainActor
    func testPresentErrorWithStandardError() {
        let store = GatewayStore(inMemory: true)
        let appModel = AppModel(store: store)

        appModel.presentError(NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Standard error"]))
        XCTAssertNotNil(appModel.presentedErrorMessage)
    }

    @MainActor
    func testPresentErrorWithGatewayError() {
        let store = GatewayStore(inMemory: true)
        let appModel = AppModel(store: store)

        appModel.presentError(GatewayError.unpaired)
        XCTAssertEqual(appModel.presentedErrorMessage, GatewayError.unpaired.errorDescription)
    }

    @MainActor
    func testDismissError() {
        let store = GatewayStore(inMemory: true)
        let appModel = AppModel(store: store)

        appModel.presentedErrorMessage = "Some error"
        XCTAssertNotNil(appModel.presentedErrorMessage)

        appModel.dismissError()
        XCTAssertNil(appModel.presentedErrorMessage)
    }
}
