@testable import NullClawUI
import XCTest

final class NullHubModelsTests: XCTestCase {
    private var decoder: JSONDecoder!

    override func setUp() async throws {
        try await super.setUp()
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    override func tearDown() async throws {
        decoder = nil
        try await super.tearDown()
    }

    // MARK: - Status

    func testDecodeStatusResponse() throws {
        let json = """
        {
          "hub": {
            "version": "dev",
            "platform": "aarch64-macos",
            "pid": 24448,
            "uptime_seconds": 3,
            "access": {
              "browser_open_url": "http://nullhub.localhost:19800",
              "direct_url": "http://127.0.0.1:19800",
              "canonical_url": "http://nullhub.localhost:19800",
              "fallback_url": "http://127.0.0.1:19800",
              "local_alias_chain": true,
              "public_alias_active": true,
              "public_alias_provider": "dns-sd",
              "public_alias_url": "http://nullhub.local:19800"
            }
          },
          "components": {
            "nullclaw": {
              "total": 1,
              "running": 0,
              "starting": 0,
              "restarting": 0,
              "failed": 0,
              "stopped": 1,
              "auto_start": 0,
              "status": "idle"
            }
          },
          "instances": {
            "nullclaw": {
              "default": {
                "version": "standalone",
                "auto_start": false,
                "launch_mode": "gateway",
                "verbose": false,
                "status": "stopped"
              }
            }
          },
          "overall_status": "idle"
        }
        """
        let data = try XCTUnwrap(Data(json.utf8) as Data?)
        let status = try decoder.decode(NullHubStatusResponse.self, from: data)

        XCTAssertEqual(status.overallStatus, "idle")
        XCTAssertEqual(status.hub.version, "dev")
        XCTAssertEqual(status.hub.platform, "aarch64-macos")
        XCTAssertEqual(status.hub.pid, 24448)
        XCTAssertEqual(status.hub.uptimeSeconds, 3)
        XCTAssertEqual(status.hub.access.browserOpenUrl, "http://nullhub.localhost:19800")
        XCTAssertEqual(status.components.count, 1)
        XCTAssertEqual(status.instances.count, 1)
    }

    // MARK: - Components

    func testDecodeComponentsResponse() throws {
        let json = """
        {
          "components": [
            {
              "name": "nullclaw",
              "display_name": "NullClaw",
              "description": "Autonomous AI agent runtime.",
              "repo": "nullclaw/nullclaw",
              "alpha": false,
              "installed": true,
              "standalone": false,
              "instance_count": 1
            },
            {
              "name": "nullboiler",
              "display_name": "NullBoiler",
              "description": "Workflow orchestrator.",
              "repo": "nullclaw/NullBoiler",
              "alpha": true,
              "installed": false,
              "standalone": false,
              "instance_count": 0
            }
          ]
        }
        """
        let data = try XCTUnwrap(Data(json.utf8) as Data?)
        let response = try decoder.decode(NullHubComponentsResponse.self, from: data)

        XCTAssertEqual(response.components.count, 2)
        XCTAssertEqual(response.components[0].name, "nullclaw")
        XCTAssertEqual(response.components[0].displayName, "NullClaw")
        XCTAssertEqual(response.components[0].installed, true)
        XCTAssertEqual(response.components[0].instanceCount, 1)
        XCTAssertEqual(response.components[1].name, "nullboiler")
        XCTAssertEqual(response.components[1].alpha, true)
    }

    // MARK: - Instances

    func testDecodeInstancesResponse() throws {
        let json = """
        {
          "instances": {
            "nullclaw": {
              "default": {
                "version": "standalone",
                "auto_start": false,
                "launch_mode": "gateway",
                "verbose": false,
                "status": "stopped"
              }
            }
          }
        }
        """
        let data = try XCTUnwrap(Data(json.utf8) as Data?)
        let response = try decoder.decode(NullHubInstancesResponse.self, from: data)

        XCTAssertEqual(response.instances.count, 1)
        let nullclawInstances = try XCTUnwrap(response.instances["nullclaw"])
        XCTAssertEqual(nullclawInstances.count, 1)
        let defaultInstance = try XCTUnwrap(nullclawInstances["default"])
        XCTAssertEqual(defaultInstance.version, "standalone")
        XCTAssertEqual(defaultInstance.status, "stopped")
        XCTAssertEqual(defaultInstance.autoStart, false)
        XCTAssertEqual(defaultInstance.launchMode, "gateway")
    }

    func testDecodeInstancesResponseEmpty() throws {
        let json = """
        {"instances":{}}
        """
        let data = try XCTUnwrap(Data(json.utf8) as Data?)
        let response = try decoder.decode(NullHubInstancesResponse.self, from: data)

        XCTAssertTrue(response.instances.isEmpty)
    }

    // MARK: - Settings

    func testDecodeSettingsResponse() throws {
        let json = """
        {
          "port": 19800,
          "host": "127.0.0.1",
          "auth_token": null,
          "auto_update_check": true,
          "access": {
            "browser_open_url": "http://nullhub.localhost:19800",
            "direct_url": "http://127.0.0.1:19800",
            "canonical_url": "http://nullhub.localhost:19800",
            "fallback_url": "http://127.0.0.1:19800",
            "local_alias_chain": true,
            "public_alias_active": true,
            "public_alias_provider": "dns-sd",
            "public_alias_url": "http://nullhub.local:19800"
          }
        }
        """
        let data = try XCTUnwrap(Data(json.utf8) as Data?)
        let settings = try decoder.decode(NullHubSettings.self, from: data)

        XCTAssertEqual(settings.port, 19800)
        XCTAssertEqual(settings.host, "127.0.0.1")
        XCTAssertNil(settings.authToken)
        XCTAssertEqual(settings.autoUpdateCheck, true)
        XCTAssertEqual(settings.access.browserOpenUrl, "http://nullhub.localhost:19800")
    }

    // MARK: - Service Status

    func testDecodeServiceStatusResponse() throws {
        let json = """
        {
          "status": "ok",
          "message": "Service status loaded",
          "registered": false,
          "running": false,
          "service_type": "launchd",
          "unit_path": "/Users/vds/Library/LaunchAgents/com.nullhub.server.plist"
        }
        """
        let data = try XCTUnwrap(Data(json.utf8) as Data?)
        let serviceStatus = try decoder.decode(NullHubServiceStatus.self, from: data)

        XCTAssertEqual(serviceStatus.status, "ok")
        XCTAssertEqual(serviceStatus.registered, false)
        XCTAssertEqual(serviceStatus.running, false)
        XCTAssertEqual(serviceStatus.serviceType, "launchd")
    }

    // MARK: - Providers

    func testDecodeProvidersResponseEmpty() throws {
        let json = """
        {"providers":[]}
        """
        let data = try XCTUnwrap(Data(json.utf8) as Data?)
        let response = try decoder.decode(NullHubProvidersResponse.self, from: data)

        XCTAssertTrue(response.providers.isEmpty)
    }

    func testDecodeProvidersResponsePopulated() throws {
        let json = """
        {
          "providers": [
            {
              "id": "sp_1",
              "name": "My OpenRouter",
              "provider": "openrouter",
              "api_key": "masked_sk-or-***",
              "model": "anthropic/claude-sonnet-4",
              "validated_at": "2026-05-01T10:00:00Z",
              "validated_with": "openrouter",
              "last_validation_at": "2026-05-01T10:00:00Z",
              "last_validation_ok": true
            }
          ]
        }
        """
        let data = try XCTUnwrap(Data(json.utf8) as Data?)
        let response = try decoder.decode(NullHubProvidersResponse.self, from: data)

        XCTAssertEqual(response.providers.count, 1)
        XCTAssertEqual(response.providers[0].id, "sp_1")
        XCTAssertEqual(response.providers[0].name, "My OpenRouter")
        XCTAssertEqual(response.providers[0].provider, "openrouter")
        XCTAssertEqual(response.providers[0].lastValidationOk, true)
    }

    // MARK: - Updates

    func testDecodeUpdatesResponse() throws {
        let json = """
        {
          "updates": [
            {
              "component": "nullclaw",
              "instance": "default",
              "current_version": "standalone",
              "latest_version": "v2026.4.17",
              "update_available": true
            }
          ]
        }
        """
        let data = try XCTUnwrap(Data(json.utf8) as Data?)
        let response = try decoder.decode(NullHubUpdatesResponse.self, from: data)

        XCTAssertEqual(response.updates.count, 1)
        XCTAssertEqual(response.updates[0].component, "nullclaw")
        XCTAssertEqual(response.updates[0].instance, "default")
        XCTAssertEqual(response.updates[0].currentVersion, "standalone")
        XCTAssertEqual(response.updates[0].latestVersion, "v2026.4.17")
        XCTAssertEqual(response.updates[0].updateAvailable, true)
    }

    // MARK: - Usage

    func testDecodeUsageResponse() throws {
        let json = """
        {
          "window": "24h",
          "generated_at": 1777701266,
          "totals": {
            "prompt_tokens": 100,
            "completion_tokens": 50,
            "total_tokens": 150,
            "requests": 3
          },
          "by_model": [
            {
              "model": "anthropic/claude-sonnet-4",
              "prompt_tokens": 100,
              "completion_tokens": 50,
              "total_tokens": 150,
              "requests": 3
            }
          ],
          "by_instance": [],
          "timeseries": []
        }
        """
        let data = try XCTUnwrap(Data(json.utf8) as Data?)
        let response = try decoder.decode(NullHubUsageResponse.self, from: data)

        XCTAssertEqual(response.window, "24h")
        XCTAssertEqual(response.generatedAt, 1_777_701_266)
        XCTAssertEqual(response.totals.promptTokens, 100)
        XCTAssertEqual(response.totals.completionTokens, 50)
        XCTAssertEqual(response.totals.totalTokens, 150)
        XCTAssertEqual(response.totals.requests, 3)
        XCTAssertEqual(response.byModel.count, 1)
        XCTAssertEqual(response.byModel[0].model, "anthropic/claude-sonnet-4")
    }

    // MARK: - Channels (hub-level)

    func testDecodeChannelsResponse() throws {
        let json = """
        {"channels":[]}
        """
        let data = try XCTUnwrap(Data(json.utf8) as Data?)
        let response = try decoder.decode(NullHubChannelsResponse.self, from: data)

        XCTAssertTrue(response.channels.isEmpty)
    }

    // MARK: - Meta Routes

    func testDecodeMetaRoutesResponse() throws {
        let json = """
        {
          "version": 1,
          "routes": [
            {
              "id": "health",
              "method": "GET",
              "path_template": "/health",
              "category": "meta",
              "summary": "Lightweight liveness probe.",
              "destructive": false,
              "auth_required": false,
              "auth_mode": "public",
              "path_params": [],
              "query_params": [],
              "response": "Returns status ok.",
              "examples": []
            }
          ]
        }
        """
        let data = try XCTUnwrap(Data(json.utf8) as Data?)
        let response = try decoder.decode(NullHubMetaRoutesResponse.self, from: data)

        XCTAssertEqual(response.version, 1)
        XCTAssertEqual(response.routes.count, 1)
        XCTAssertEqual(response.routes[0].id, "health")
        XCTAssertEqual(response.routes[0].method, "GET")
        XCTAssertEqual(response.routes[0].pathTemplate, "/health")
        XCTAssertEqual(response.routes[0].category, "meta")
    }
}
