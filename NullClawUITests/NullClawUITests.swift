@testable import NullClawUI
import XCTest

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
    func testLocalizedDescriptions() throws {
        XCTAssertNotNil(GatewayError.invalidURL.errorDescription)
        XCTAssertNotNil(GatewayError.httpError(statusCode: 401).errorDescription)
        XCTAssertNotNil(GatewayError.unpaired.errorDescription)
        XCTAssertTrue(try XCTUnwrap(GatewayError.httpError(statusCode: 404).errorDescription?.contains("404")))
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
        XCTAssertEqual(DesignTokens.CornerRadius.card, 16)
        XCTAssertEqual(DesignTokens.CornerRadius.medium, 12)
        XCTAssertEqual(DesignTokens.CornerRadius.bubble, 16)
        XCTAssertEqual(DesignTokens.CornerRadius.small, 8)
        XCTAssertEqual(DesignTokens.CornerRadius.inner, 6)
        XCTAssertEqual(DesignTokens.CornerRadius.tiny, 2)
    }

    func testSpacingValues() {
        XCTAssertEqual(DesignTokens.Spacing.section, 20)
        XCTAssertEqual(DesignTokens.Spacing.card, 16)
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
            var errorDescription: String? {
                "Test error message"
            }
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

// MARK: - CronJob REST Decoding Tests

final class CronJobDecodingTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    func testDecodeShellCronJob() throws {
        let json = """
        {
            "id": "job-1",
            "expression": "*/5 * * * *",
            "command": "echo hello",
            "next_run_secs": 1712345678,
            "last_run_secs": 1712345600,
            "last_status": "ok",
            "paused": false,
            "one_shot": false,
            "job_type": "shell",
            "session_target": "isolated",
            "enabled": true,
            "delete_after_run": false,
            "prompt": null,
            "model": null,
            "delivery_mode": "none",
            "delivery_channel": null,
            "delivery_account_id": null,
            "delivery_to": null,
            "delivery_peer_kind": null,
            "delivery_peer_id": null,
            "delivery_thread_id": null,
            "delivery_best_effort": true,
            "created_at_s": 1712345000
        }
        """
        let job = try decoder.decode(CronJob.self, from: Data(json.utf8))
        XCTAssertEqual(job.id, "job-1")
        XCTAssertEqual(job.expression, "*/5 * * * *")
        XCTAssertEqual(job.command, "echo hello")
        XCTAssertEqual(job.jobType, "shell")
        XCTAssertFalse(job.paused)
        XCTAssertTrue(job.enabled)
        XCTAssertFalse(job.oneShot)
        XCTAssertFalse(job.deleteAfterRun)
        XCTAssertEqual(job.nextRunSecs, 1_712_345_678)
        XCTAssertEqual(job.lastRunSecs, 1_712_345_600)
        XCTAssertEqual(job.lastStatus, "ok")
        XCTAssertEqual(job.createdAtS, 1_712_345_000)
        XCTAssertNil(job.prompt)
        XCTAssertNil(job.model)
    }

    func testDecodeAgentCronJob() throws {
        let json = """
        {
            "id": "agent-1",
            "expression": "0 * * * *",
            "command": "Summarize alerts",
            "prompt": "Summarize alerts",
            "model": "openrouter/anthropic/claude-sonnet-4",
            "job_type": "agent",
            "session_target": "main",
            "paused": false,
            "enabled": true,
            "one_shot": false,
            "delete_after_run": false,
            "delivery_mode": "always",
            "delivery_channel": "telegram",
            "delivery_account_id": "main",
            "delivery_to": "-1001234567890",
            "delivery_peer_kind": "group",
            "delivery_peer_id": "-1001234567890",
            "delivery_thread_id": "42",
            "delivery_best_effort": true,
            "next_run_secs": 1712349200,
            "last_run_secs": null,
            "last_status": null,
            "created_at_s": 1712340000
        }
        """
        let job = try decoder.decode(CronJob.self, from: Data(json.utf8))
        XCTAssertEqual(job.id, "agent-1")
        XCTAssertEqual(job.jobType, "agent")
        XCTAssertEqual(job.prompt, "Summarize alerts")
        XCTAssertEqual(job.model, "openrouter/anthropic/claude-sonnet-4")
        XCTAssertEqual(job.sessionTarget, "main")
        XCTAssertEqual(job.deliveryMode, "always")
        XCTAssertEqual(job.deliveryChannel, "telegram")
        XCTAssertEqual(job.deliveryAccountId, "main")
        XCTAssertEqual(job.deliveryTo, "-1001234567890")
        XCTAssertEqual(job.deliveryPeerKind, "group")
        XCTAssertEqual(job.deliveryPeerId, "-1001234567890")
        XCTAssertEqual(job.deliveryThreadId, "42")
        XCTAssertTrue(job.deliveryBestEffort ?? false)
        XCTAssertNil(job.lastRunSecs)
        XCTAssertNil(job.lastStatus)
    }

    func testDecodeCronJobArray() throws {
        let json = """
        [
            {"id": "job-1", "expression": "*/5 * * * *", "command": "echo hello", "job_type": "shell", "paused": false, "enabled": true, "one_shot": false, "delete_after_run": false, "next_run_secs": 100, "last_run_secs": null, "last_status": null, "created_at_s": 0},
            {"id": "job-2", "expression": "0 * * * *", "command": "test", "prompt": "test", "job_type": "agent", "paused": true, "enabled": false, "one_shot": false, "delete_after_run": false, "next_run_secs": 200, "last_run_secs": null, "last_status": null, "created_at_s": 0}
        ]
        """
        let jobs = try decoder.decode([CronJob].self, from: Data(json.utf8))
        XCTAssertEqual(jobs.count, 2)
        XCTAssertEqual(jobs[0].id, "job-1")
        XCTAssertEqual(jobs[1].id, "job-2")
        XCTAssertTrue(jobs[1].paused)
        XCTAssertFalse(jobs[1].enabled)
    }
}

// MARK: - CronJob REST Encoding Tests

final class CronJobEncodingTests: XCTestCase {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .withoutEscapingSlashes
        return e
    }()

    func testEncodeCronJobIDParams() throws {
        let params = CronJobIDParams(id: "job-1")
        let data = try encoder.encode(params)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["id"] as? String, "job-1")
    }

    func testEncodeCronJobAddParamsShell() throws {
        var params = CronJobAddParams()
        params.expression = "*/5 * * * *"
        params.command = "echo hello"

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(params)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["expression"] as? String, "*/5 * * * *")
        XCTAssertEqual(dict?["command"] as? String, "echo hello")
        XCTAssertNil(dict?["prompt"])
    }

    func testEncodeCronJobAddParamsAgent() throws {
        var params = CronJobAddParams()
        params.expression = "0 * * * *"
        params.prompt = "Summarize alerts"
        params.model = "openrouter/anthropic/claude-sonnet-4"
        params.deliveryChannel = "telegram"
        params.deliveryTo = "-1001234567890"
        params.deliveryBestEffort = true

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(params)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["expression"] as? String, "0 * * * *")
        XCTAssertEqual(dict?["prompt"] as? String, "Summarize alerts")
        XCTAssertEqual(dict?["model"] as? String, "openrouter/anthropic/claude-sonnet-4")
        XCTAssertEqual(dict?["delivery_channel"] as? String, "telegram")
        XCTAssertEqual(dict?["delivery_to"] as? String, "-1001234567890")
        XCTAssertEqual(dict?["delivery_best_effort"] as? Bool, true)
    }

    func testEncodeCronJobAddParamsOneShot() throws {
        var params = CronJobAddParams()
        params.delay = "30m"
        params.command = "echo later"

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(params)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["delay"] as? String, "30m")
        XCTAssertEqual(dict?["command"] as? String, "echo later")
        XCTAssertNil(dict?["expression"])
    }

    func testEncodeCronJobUpdateParams() throws {
        let params = CronJobUpdateParams(
            id: "job-1",
            expression: "*/10 * * * *",
            command: "echo updated",
            prompt: nil,
            model: "gpt-4",
            sessionTarget: nil,
            paused: false,
            enabled: true
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(params)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(dict?["id"] as? String, "job-1")
        XCTAssertEqual(dict?["expression"] as? String, "*/10 * * * *")
        XCTAssertEqual(dict?["command"] as? String, "echo updated")
        XCTAssertEqual(dict?["model"] as? String, "gpt-4")
        XCTAssertEqual(dict?["paused"] as? Bool, false)
        XCTAssertEqual(dict?["enabled"] as? Bool, true)
    }
}

// MARK: - CronJobDraft REST Conversion Tests

final class CronJobDraftRESTConversionTests: XCTestCase {
    func testDraftToRESTParamsShell() {
        var draft = CronJobDraft()
        draft.id = "job-1"
        draft.expression = "*/5 * * * *"
        draft.jobType = "shell"
        draft.commandOrPrompt = "echo hello"
        draft.model = ""
        draft.deliveryChannel = ""
        draft.deliveryTo = ""

        let params = draft.toRESTParams()
        XCTAssertEqual(params.expression, "*/5 * * * *")
        XCTAssertEqual(params.command, "echo hello")
        XCTAssertNil(params.prompt)
        XCTAssertNil(params.model)
        XCTAssertNil(params.deliveryChannel)
        XCTAssertNil(params.delay)
    }

    func testDraftToRESTParamsAgent() {
        var draft = CronJobDraft()
        draft.id = "agent-1"
        draft.expression = "0 * * * *"
        draft.jobType = "agent"
        draft.commandOrPrompt = "Summarize alerts"
        draft.model = "gpt-4"
        draft.deliveryChannel = "telegram"
        draft.deliveryTo = "-1001234567890"

        let params = draft.toRESTParams()
        XCTAssertEqual(params.expression, "0 * * * *")
        XCTAssertEqual(params.prompt, "Summarize alerts")
        XCTAssertNil(params.command)
        XCTAssertEqual(params.model, "gpt-4")
        XCTAssertEqual(params.deliveryChannel, "telegram")
        XCTAssertEqual(params.deliveryTo, "-1001234567890")
    }

    func testDraftToRESTParamsOneShot() {
        var draft = CronJobDraft()
        draft.expression = "30m"
        draft.jobType = "shell"
        draft.commandOrPrompt = "echo later"
        draft.oneShot = true

        let params = draft.toRESTParams()
        XCTAssertNil(params.expression)
        XCTAssertEqual(params.delay, "30m")
        XCTAssertEqual(params.command, "echo later")
    }

    func testDraftToUpdateRESTParams() {
        var draft = CronJobDraft()
        draft.expression = "*/10 * * * *"
        draft.jobType = "agent"
        draft.commandOrPrompt = "New prompt"
        draft.model = "gpt-4"

        let params = draft.toUpdateRESTParams(existingID: "job-1")
        XCTAssertEqual(params.id, "job-1")
        XCTAssertEqual(params.expression, "*/10 * * * *")
        XCTAssertEqual(params.prompt, "New prompt")
        XCTAssertNil(params.command)
        XCTAssertEqual(params.model, "gpt-4")
    }

    func testDraftToRESTParamsTrimsWhitespace() {
        var draft = CronJobDraft()
        draft.expression = "  */5 * * * *  \n"
        draft.jobType = "shell"
        draft.commandOrPrompt = "  echo hello  "
        draft.model = "  gpt-4  "

        let params = draft.toRESTParams()
        XCTAssertEqual(params.expression, "*/5 * * * *")
        XCTAssertEqual(params.command, "echo hello")
        XCTAssertEqual(params.model, "gpt-4")
    }
}

// NOTE: CronJobViewModel REST migration tests are in GatewayLiveIntegrationTests.swift.

// MARK: - AgentConfigViewModel buildConfig Tests

final class AgentConfigViewModelTests: XCTestCase {
    @MainActor
    func testBuildConfigHappyPath() {
        let agent: [String: String] = [
            "compactContext": "1",
            "maxToolIterations": "40",
            "maxHistoryMessages": "100",
            "parallelTools": "1",
            "sessionIdleTimeoutSecs": "600",
            "compactionKeepRecent": "20",
            "compactionMaxSummaryChars": "2000",
            "compactionMaxSourceChars": "13000",
            "messageTimeoutSecs": "300"
        ]
        let models: [String: String] = [
            "defaultProvider": "openrouter",
            "defaultModel": "anthropic/claude-sonnet-4"
        ]
        let config = AgentConfigViewModel.buildConfig(from: agent, modelsDict: models)
        XCTAssertEqual(config.primaryModel, "anthropic/claude-sonnet-4")
        XCTAssertEqual(config.provider, "openrouter")
        XCTAssertEqual(config.maxToolIterations, 40)
        XCTAssertEqual(config.messageTimeoutSecs, 300)
        XCTAssertTrue(config.compactContext)
        XCTAssertEqual(config.compactionThreshold, 13000)
    }

    @MainActor
    func testBuildConfigUsesDefaults() {
        let agent: [String: String] = [:]
        let models = [
            "defaultProvider": "infini-ai"
        ]
        let config = AgentConfigViewModel.buildConfig(from: agent, modelsDict: models)
        XCTAssertEqual(config.primaryModel, "")
        XCTAssertEqual(config.provider, "infini-ai")
        XCTAssertEqual(config.maxToolIterations, 25)
        XCTAssertEqual(config.messageTimeoutSecs, 300)
        XCTAssertFalse(config.compactContext)
        XCTAssertEqual(config.compactionThreshold, 8000)
    }
}

// MARK: - AutonomyViewModel buildConfig Tests

final class AutonomyViewModelTests: XCTestCase {
    @MainActor
    func testBuildConfigHappyPath() {
        let dict: [String: String] = [
            "level": "high",
            "maxActionsPerHour": "200",
            "blockHighRiskCommands": "0",
            "requireApprovalForMediumRisk": "1",
            "allowedCommands": #"["sh","bash","date"]"#,
            "workspaceOnly": "1"
        ]
        let config = AutonomyViewModel.buildConfig(from: dict)
        XCTAssertEqual(config.level, "high")
        XCTAssertEqual(config.maxActionsPerHour, 200)
        XCTAssertFalse(config.blockHighRiskCommands)
        XCTAssertTrue(config.requireApprovalForMediumRisk)
        XCTAssertEqual(config.allowedCommands, ["sh", "bash", "date"])
    }

    @MainActor
    func testBuildConfigUsesDefaults() {
        let dict: [String: String] = [:]
        let config = AutonomyViewModel.buildConfig(from: dict)
        XCTAssertEqual(config.level, "medium")
        XCTAssertEqual(config.maxActionsPerHour, 60)
        XCTAssertTrue(config.blockHighRiskCommands)
        XCTAssertFalse(config.requireApprovalForMediumRisk)
        XCTAssertEqual(config.allowedCommands, [])
    }
}
