# NullHub Migration Plan — NullClawUI

## Verified Findings (Live Probe — 2026-05-02)

### NullHub (port 19800, `optional_bearer` auth)
- `GET /health` → `{"status":"ok"}`
- `GET /api/status` → hub version, platform, pid, uptime, access URLs, overall_status
- `GET /api/components` → nullclaw (installed), nullboiler, nulltickets with display names, repos
- `GET /api/instances` → `{"instances":{}}` (empty until imported)
- `GET /api/settings` → port, host, auth_token (null), auto_update_check
- `GET /api/meta/routes` → **95 documented routes** covering all management APIs
- `GET /api/wizard/nullclaw` → component manifest with wizard steps
- `GET /api/providers` → `{"providers":[]}`
- `GET /api/channels` → `{"channels":[]}`
- `GET /api/updates` → `{"updates":[]}`
- `GET /api/usage` → aggregated token/cost usage

### NullClaw Instance HTTP Gateway (port 5111)
- `GET /health` ✅
- `GET /.well-known/agent-card.json` ✅ (name, version, capabilities, security schemes)
- `POST /a2a` (JSON-RPC: message/send, message/stream, tasks/*) ✅
- `POST /pair` ✅
- `GET /api/*` admin endpoints → **HTTP 404** (PRs closed; admin API not merged into gateway)

### Key Insight
**Admin API was closed as PRs on NullClaw.** All admin operations (config, cron, MCP, channels,
memory, history, providers) must go through NullHub, which delegates to the NullClaw CLI.
The NullClaw HTTP gateway only serves A2A, health, agent-card, and pairing.

### Hybrid Architecture
```
NullClawUI App
├── Admin/Mgmt ────→ NullHub (:19800)          ← config, cron, MCP, channels, memory, history, logs, updates
├── Chat/Streaming → NullClaw Instance (:5111)  ← POST /a2a (message/stream SSE, message/send)
├── Agent Card ───→ NullClaw Instance (:5111)  ← GET /.well-known/agent-card.json
├── Health ───────→ Both                        ← GET /health on either
└── Pairing ──────→ NullClaw Instance (:5111)  ← POST /pair (preserved!)
```

---

## Implementation Strategy

- **TDD only**: every change starts with a failing test, then implementation
- **Incremental**: each step builds on the previous, app is always buildable
- **Quality gates** per step: `swiftlint --strict`, `swiftformat --lint .`, `xcodebuild build-for-testing`
- **Git safety**: commit after every step that passes gates; push after each logical group
- **Preserved code**: A2A, SSE, AgentCard, ChatView, ChatViewModel, PairingViewModel, KeychainService — all unchanged

### Quality Gate Command
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild build-for-testing -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

---

## Step 1: Add NullHub Response Models (Models Only, No Behavior)

**Goal**: Define `NullHubStatusResponse`, `NullHubComponentInfo`, `NullHubInstanceSummary`,
`NullHubSettings`, `NullHubServiceStatus`, `NullHubProviderInfo`, `NullHubUpdateInfo`
as `Codable` structs matching verified response shapes. No new behavior — just decodable types.

### 1a: Write Tests (RED)

**New file**: `NullClawUITests/NullHubModelsTests.swift`

Test methods to add:
1. `testDecodeNullHubStatusResponse()` — decode live-captured `GET /api/status` JSON
2. `testDecodeNullHubComponentsResponse()` — decode `GET /api/components` JSON
3. `testDecodeNullHubInstancesResponse()` — decode `GET /api/instances` JSON (empty and populated)
4. `testDecodeNullHubSettingsResponse()` — decode `GET /api/settings` JSON
5. `testDecodeNullHubServiceStatusResponse()` — decode `GET /api/service/status` JSON
6. `testDecodeNullHubProvidersResponse()` — decode `GET /api/providers` JSON
7. `testDecodeNullHubUpdatesResponse()` — decode `GET /api/updates` JSON
8. `testDecodeNullHubUsageResponse()` — decode `GET /api/usage` JSON
9. `testDecodeNullHubMetaRoutesResponse()` — decode `GET /api/meta/routes` JSON

Register the new test file in `project.yml` under `NullClawUITests` sources.

### 1b: Implement (GREEN)

**New file**: `NullClawUI/Models/NullHubModels.swift`

Define each struct with `Codable` conformance and `convertFromSnakeCase` key strategy.
Include captured JSON as doc comments or inline `static let sampleJSON` for reference.

### 1c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild build-for-testing -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 1d: Commit
```bash
git add -A && git commit -m "add NullHub response models with decoding tests"
git push
```

---

## Step 2: Update GatewayProfile for Dual-URL Model

**Goal**: Extend `GatewayProfile` SwiftData model to carry both `hubURL` and `instanceURL`.
The old `url` field remains as the instance URL for backward compatibility during transition.
Add `hubURL: String?`, `hubToken` (Keychain-keyed), `instanceName: String`, `component: String`.
Drop `requiresPairing: Bool` (no longer relevant for hub auth).

### 2a: Write Tests (RED)

**New file**: `NullClawUITests/GatewayProfileMigrationTests.swift`

Test methods:
1. `testGatewayProfileDualURLDefaults()` — new profile with just hubURL, default instanceName/component
2. `testGatewayProfileKeychainTokenKeying()` — hub token stored/retrieved via Keychain keyed by hubURL
3. `testGatewayProfileBackwardCompat()` — old profile with only `url` still works (instance URL)
4. `testGatewayProfileInstanceURLDiscoveredFromHub()` — instanceURL set from hub discovery

### 2b: Implement (GREEN)

In `NullClawUI/Models/GatewayProfile.swift`:
- Add `var hubURL: String? = nil`
- Add `var instanceURL: String? = nil` (defaults to `url` for backward compat)
- Add `var instanceName: String = "default"`
- Add `var component: String = "nullclaw"`
- Remove `var requiresPairing: Bool = false`
- Add computed property `var hubToken: String?` with Keychain get/set using `hubURL`

### 2c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild build-for-testing -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 2d: Commit
```bash
git add -A && git commit -m "extend GatewayProfile for dual hub/instance URL model"
git push
```

---

## Step 3: Extract Shared Networking Base

**Goal**: Create a shared `GatewayNetworking` utility (actor-safe HTTP helpers) that both
the existing `GatewayClient` and the new `HubGatewayClient` will use. Extract common
code: `URLSession` config, error types, JSON encoder/decoder creation, request building,
response validation. This is a pure refactor — zero behavior change.

### 3a: Write Tests (RED)

**Update**: `NullClawUITests/GatewayClientTests.swift`

Add test methods:
1. `testSharedSessionConfiguration()` — verify timeout/resource values
2. `testSharedDecoderUsesSnakeCase()` — decode snake_case JSON
3. `testSharedRequestBuilding()` — verify Authorization header, Content-Type, HTTP method
4. `testSharedResponseValidation()` — 200 passes, 401/404/500 throw correct GatewayError

### 3b: Implement (GREEN)

**New file**: `NullClawUI/Networking/GatewayNetworking.swift`

Move from `GatewayClient`:
- `session`, `sseSession` creation → static factory methods
- `decoder`, `encoder`, `a2aEncoder` → static factory methods
- `buildRequest(url:method:body:token:)` → static method
- `validateResponse(data:response:)` → static method returning `Data` or throwing `GatewayError`
- `GatewayError` enum → stays here

Update `GatewayClient` to use `GatewayNetworking` internally. All existing tests must still pass.

### 3c: Quality Gate (must pass existing + new tests)
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild test -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 3d: Commit
```bash
git add -A && git commit -m "extract shared GatewayNetworking utilities from GatewayClient"
git push
```

---

## Step 4: Create HubGatewayClient (Skeleton + Health Check)

**Goal**: New `HubGatewayClient` actor that connects to NullHub. Start with minimal
implementation: `init`, `checkHealth()`, `fetchHubStatus()`. Reuse `GatewayNetworking`.

### 4a: Write Tests (RED)

**New file**: `NullClawUITests/HubGatewayClientTests.swift`

Test methods:
1. `testHubHealthCheckSuccess()` — mock `GET /health` → 200 `{"status":"ok"}`
2. `testHubHealthCheckFailure()` — mock `GET /health` → 500 → throws `GatewayError`
3. `testHubStatusSuccess()` — mock `GET /api/status` → 200 with live-captured JSON
4. `testHubStatusUnauthorized()` — mock → 401 → throws `GatewayError`
5. `testHubClientUnauthenticatedRequest()` — no token set → request still includes no Authorization header

### 4b: Implement (GREEN)

**New file**: `NullClawUI/Networking/HubGatewayClient.swift`

```swift
actor HubGatewayClient {
    let baseURL: URL
    var bearerToken: String?
    private let networking: GatewayNetworking

    init(baseURL: URL, bearerToken: String? = nil) { ... }
    func setToken(_ token: String?) { ... }
    func checkHealth() async throws { ... }
    func fetchHubStatus() async throws -> NullHubStatusResponse { ... }
}
```

### 4c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild test -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 4d: Commit
```bash
git add -A && git commit -m "add HubGatewayClient with health check and hub status endpoints"
git push
```

---

## Step 5: HubGatewayClient — Instance Discovery

**Goal**: Add methods for listing instances and components from NullHub.
This enables the app to discover managed NullClaw instances and their ports.

### 5a: Write Tests (RED)

**Add to**: `NullClawUITests/HubGatewayClientTests.swift`

Test methods:
1. `testListInstancesEmpty()` — mock `GET /api/instances` → `{"instances":{}}`
2. `testListInstancesPopulated()` — mock with multiple components/instances including port info
3. `testListComponents()` — mock `GET /api/components` → 3 known components
4. `testGetComponentManifest()` — mock `GET /api/components/nullclaw/manifest`
5. `testListInstancesError()` — mock → 500 → throws `GatewayError`

### 5b: Implement (GREEN)

**Add to**: `HubGatewayClient`:
```swift
func listInstances() async throws -> [String: [String: NullHubInstanceSummary]] { ... }
func listComponents() async throws -> [NullHubComponentInfo] { ... }
func getComponentManifest(name: String) async throws -> Data { ... }
```

The `listInstances` response shape is `{"instances":{"component":{"name":{...}}}}`.
The instance summary includes `port` — use this to construct the direct instance URL.

### 5c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild test -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 5d: Commit
```bash
git add -A && git commit -m "add HubGatewayClient instance/component discovery endpoints"
git push
```

---

## Step 6: HubGatewayClient — Config Endpoints

**Goal**: Port all `/api/config*` methods from `GatewayClient` to `HubGatewayClient`,
remapped to `/api/instances/{component}/{name}/config*` paths.

### 6a: Write Tests (RED)

**Add to**: `NullClawUITests/HubGatewayClientTests.swift`

Test methods:
1. `testGetConfigValue()` — mock `GET /api/instances/nullclaw/default/config?path=agent.name` → value
2. `testGetConfigValueNotFound()` — mock → 404 → throws
3. `testSetConfigValue()` — mock `POST /api/instances/nullclaw/default/config-set` with body
4. `testUnsetConfigValue()` — mock `POST /api/instances/nullclaw/default/config-unset`
5. `testReloadConfig()` — mock `POST /api/instances/nullclaw/default/config-reload`
6. `testValidateConfig()` — mock `POST /api/instances/nullclaw/default/config-validate`
7. `testGetFullConfig()` — mock `GET /api/instances/nullclaw/default/config`
8. `testPutFullConfig()` — mock `PUT /api/instances/nullclaw/default/config`

### 6b: Implement (GREEN)

**Add to**: `HubGatewayClient`:
```swift
func getConfig(instance: String, component: String, path: String?) async throws -> AnyCodable { ... }
func setConfig(instance: String, component: String, path: String, value: AnyEncodable) async throws { ... }
func unsetConfig(instance: String, component: String, path: String) async throws { ... }
func reloadConfig(instance: String, component: String) async throws -> ApiConfigReloadResponse { ... }
func validateConfig(instance: String, component: String) async throws -> ApiConfigReloadResponse { ... }
func getFullConfig(instance: String, component: String) async throws -> Data { ... }
func putFullConfig(instance: String, component: String, config: Data) async throws { ... }
```

### 6c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild test -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 6d: Commit
```bash
git add -A && git commit -m "add HubGatewayClient config CRUD endpoints"
git push
```

---

## Step 7: HubGatewayClient — Cron Endpoints

**Goal**: Port all cron job endpoints, remapped to `/api/instances/{c}/{n}/cron*` paths.

### 7a: Write Tests (RED)

**Add to**: `NullClawUITests/HubGatewayClientTests.swift`

Test methods:
1. `testListCronJobs()` — mock `GET .../cron` → `{"jobs":[...]}`
2. `testCreateCronJob()` — mock `POST .../cron` with expression + command
3. `testCreateCronJobOnce()` — mock `POST .../cron/once` with delay
4. `testGetCronJob()` — mock `GET .../cron/{id}` → single job
5. `testRunCronJob()` — mock `POST .../cron/{id}/run`
6. `testPauseCronJob()` — mock `POST .../cron/{id}/pause`
7. `testResumeCronJob()` — mock `POST .../cron/{id}/resume`
8. `testUpdateCronJob()` — mock `PATCH .../cron/{id}` with partial fields
9. `testDeleteCronJob()` — mock `DELETE .../cron/{id}` → `{"status":"deleted"}`
10. `testCronJobRuns()` — mock `GET .../cron/{id}/runs` → `{"runs":[...]}`

### 7b: Implement (GREEN)

**Add to**: `HubGatewayClient`:
```swift
func listCronJobs(instance: String, component: String) async throws -> [CronJob] { ... }
func createCronJob(instance: String, component: String, params: CronJobAddParams) async throws -> CronJob { ... }
func createCronJobOnce(instance: String, component: String, params: CronJobAddParams) async throws -> CronJob { ... }
func getCronJob(instance: String, component: String, id: String) async throws -> CronJob { ... }
func runCronJob(instance: String, component: String, id: String) async throws { ... }
func pauseCronJob(instance: String, component: String, id: String) async throws { ... }
func resumeCronJob(instance: String, component: String, id: String) async throws { ... }
func updateCronJob(instance: String, component: String, id: String, params: CronJobUpdateParams) async throws { ... }
func deleteCronJob(instance: String, component: String, id: String) async throws { ... }
func cronJobRuns(instance: String, component: String, id: String) async throws -> ApiCronRunsResponse { ... }
```

### 7c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild test -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 7d: Commit
```bash
git add -A && git commit -m "add HubGatewayClient cron job management endpoints"
git push
```

---

## Step 8: HubGatewayClient — Channels, MCP, Skills, Memory, History, Agent Endpoints

**Goal**: Port remaining admin endpoints. This is a bulk step since they follow the same pattern.

### 8a: Write Tests (RED)

**Add to**: `NullClawUITests/HubGatewayClientTests.swift`

Test methods (one per endpoint, 20+ tests):
1. Channels: `testListChannels`, `testGetChannel`
2. MCP: `testListMCPServers`, `testGetMCPServer`
3. Skills: `testListSkills`, `testGetSkill`, `testDeleteSkill`
4. Memory: `testListMemory`, `testMemoryStats`, `testSearchMemory`, `testGetMemory`, `testDeleteMemory`
5. History: `testListHistory`, `testGetHistory`
6. Agent: `testAgentInvoke`, `testListAgentSessions`, `testDeleteAgentSession`
7. Doctor: `testDoctor`
8. Capabilities: `testCapabilities`
9. Models: `testListModels`, `testGetModel`
10. ProviderHealth: `testProviderHealth`
11. Onboarding: `testOnboarding`
12. Usage: `testInstanceUsage`

### 8b: Implement (GREEN)

**Add to**: `HubGatewayClient` — methods for each endpoint above, all following the
`/api/instances/{c}/{n}/{resource}` pattern.

### 8c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild test -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 8d: Commit
```bash
git add -A && git commit -m "add HubGatewayClient channels, MCP, skills, memory, history, agent endpoints"
git push
```

---

## Step 9: Remove Legacy Endpoints from GatewayClient

**Goal**: Strip admin API methods (`api*`) and legacy cron methods from the old `GatewayClient`.
The old client becomes purely the **instance client** (A2A, agent card, pairing, SSE).
Ensure all preserved tests pass.

### 9a: Write Tests (RED)

**No new tests** — this is removal. All existing tests for preserved functionality must pass.
The **gating criterion** is: old tests for removed methods must be deleted/updated;
remaining tests for A2A, SSE, agent card, pairing must pass.

### 9b: Implement (GREEN)

**Remove from** `GatewayClient`:
- `apiStatus()`, `apiDoctor()`, `apiCapabilities()`
- `apiConfigValue()`, `apiConfigObjectValue()`, `apiSetConfigValue()`, `apiUnsetConfigValue()`
- `apiReloadConfig()`, `apiValidateConfig()`
- `apiModels()`, `apiGetModel()`
- `apiListCronJobs()`, `apiCreateCronJob()`, `apiCreateCronJobOnce()`, `apiRunCronJob()`
- `apiPauseCronJob()`, `apiResumeCronJob()`, `apiUpdateCronJob()`, `apiDeleteCronJob()`
- `apiGetCronJob()`, `apiCronJobRuns()`
- `apiListChannels()`, `apiGetChannel()`
- `apiListMCPServers()`, `apiGetMCPServer()`
- `apiListSkills()`, `apiGetSkill()`, `apiDeleteSkill()`
- `apiListAgentSessions()`, `apiAgentChat()`, `apiDeleteAgentSession()`
- `apiListMemory()`, `apiMemoryStats()`, `apiSearchMemory()`, `apiGetMemory()`, `apiDeleteMemory()`
- `apiListHistory()`, `apiGetHistory()`
- `listCronJobsLegacy()`, `addCronJobLegacy()`, `removeCronJobLegacy()`, `pauseCronJobLegacy()`, `resumeCronJobLegacy()`, `updateCronJobLegacy()`

**Remove from** `GatewayClientTests`:
- All test methods that tested the above methods

**Remove test fixtures** for admin API paths from `TestFixtures.swift`.

**Preserved** (must still pass):
- `checkHealth()`, `fetchAgentCard()`, `pair(code:)`, `sendMessage()`, `streamMessage()`
- `listTasks()`, `getTask()`, `cancelTask()`
- All SSE parsing methods
- `sendOneShot()`, `sendOneShotNonStreaming()`

### 9c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild test -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 9d: Commit
```bash
git add -A && git commit -m "remove admin API endpoints from GatewayClient (migrated to HubGatewayClient)"
git push
```

---

## Step 10: Rename GatewayClient → InstanceGatewayClient

**Goal**: Rename to clarify role. This is a mechanical rename with no logic change.

### 10a: Write Tests (RED)

**No behavioral tests** — this is a rename. All existing tests must pass after rename.

### 10b: Implement (GREEN)

Rename:
- `GatewayClient.swift` → `InstanceGatewayClient.swift`
- Class `GatewayClient` → `InstanceGatewayClient`
- Update all references in ViewModels: `ChatViewModel`, `PairingViewModel`, `GatewayViewModel`
- Update all test references

### 10c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild test -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 10d: Commit
```bash
git add -A && git commit -m "rename GatewayClient to InstanceGatewayClient for clarity"
git push
```

---

## Step 11: Update GatewayViewModel for Dual-Client Architecture

**Goal**: `GatewayViewModel` manages both `HubGatewayClient` and `InstanceGatewayClient`.
When a hub is connected, it auto-discovers instances. When an instance is discovered,
it constructs the instance client. The old `PairingMode` state is removed — instance
pairing remains via `InstanceGatewayClient.pair(code:)`.

### 11a: Write Tests (RED)

**New file**: `NullClawUITests/GatewayViewModelTests.swift`

Test methods:
1. `testConnectToHub_withoutToken_succeeds()` — hub with no auth
2. `testConnectToHub_withToken_succeeds()` — hub with bearer token
3. `testHubDiscoveryYieldsInstanceClient()` — after hub status returns, instance client created
4. `testGatewayStatusReflectsHubAndInstance()` — both health checks contribute to status
5. `testPairInstanceFromHub()` — pairing flow preserved, token stored in Keychain for instance URL
6. `testUnpairClearsBothClients()` — unlink clears hub token and instance token

### 11b: Implement (GREEN)

**Rewrite**: `NullClawUI/ViewModels/GatewayViewModel.swift`

Key changes:
- Properties: `hubClient: HubGatewayClient?`, `instanceClient: InstanceGatewayClient?`
- `connect(url:hubToken:)` → creates hub client, fetches status, discovers instances
- `discoverInstance(hubStatus:)` → extracts port from hub status response,
  constructs `instanceURL`, creates `InstanceGatewayClient`
- Status computed from both clients' health
- Preserve pairing flow through `instanceClient.pair(code:)`

### 11c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild test -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 11d: Commit
```bash
git add -A && git commit -m "update GatewayViewModel for dual-client hub/instance architecture"
git push
```

---

## Step 12: Update AgentConfigViewModel & AutonomyViewModel

**Goal**: Point config reads/writes at `HubGatewayClient` instead of old `GatewayClient`.

### 12a: Write Tests (RED)

**Update**: `NullClawUITests/NullClawUITests.swift` (AgentConfigViewModelTests section)

Update existing tests:
1. `testBuildConfigHappyPath()` — now uses mock `HubGatewayClient`
2. `testBuildConfigDefaults()` — same

Add tests:
3. `testLoadConfigFromHub()` — fetches config path from hub, decodes
4. `testSaveConfigToHub()` — posts config-set to hub

### 12b: Implement (GREEN)

**Update**: `AgentConfigViewModel`, `AutonomyViewModel`
- Replace `GatewayClient` with `HubGatewayClient`
- Add `instance` and `component` parameters to methods
- Config get/set now goes through hub's instance-scoped endpoints

### 12c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild test -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 12d: Commit
```bash
git add -A && git commit -m "update AgentConfig and Autonomy ViewModels for HubGatewayClient"
git push
```

---

## Step 13: Update CronJob, MCPServer, ChannelStatus, UsageStats ViewModels

**Goal**: Point all remaining management ViewModels at `HubGatewayClient`.

### 13a: Write Tests (RED)

**Update**: Existing test files for each ViewModel

Update each ViewModel's tests to mock `HubGatewayClient` paths instead of old `GatewayClient` paths.
Add test for new hub-level channel management if applicable.

### 13b: Implement (GREEN)

**Update**: `CronJobViewModel`, `MCPServerViewModel`, `ChannelStatusViewModel`, `UsageStatsViewModel`
- Replace `GatewayClient` references with `HubGatewayClient`
- Add `instance`/`component` parameters

### 13c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild test -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 13d: Commit
```bash
git add -A && git commit -m "update cron, MCP, channel, usage ViewModels for HubGatewayClient"
git push
```

---

## Step 14: Update GatewayStatusViewModel

**Goal**: Status now reflects both hub health and instance health.

### 14a: Write Tests (RED)

**Add tests** to existing GatewayStatusViewModel test section:
1. `testStatusOnlineWhenHubAndInstanceHealthy()`
2. `testStatusDegradedWhenInstanceDown()`
3. `testStatusOfflineWhenHubDown()`
4. `testStatusOfflineWhenBothDown()`

### 14b: Implement (GREEN)

**Update**: `GatewayStatusViewModel`
- Accept both hub and instance health
- Compute aggregate status from both

### 14c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild test -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 14d: Commit
```bash
git add -A && git commit -m "update GatewayStatusViewModel for dual health monitoring"
git push
```

---

## Step 15: Update AddGatewaySheet for Hub URL + Instance Discovery

**Goal**: The add-server UI accepts a hub URL (with optional admin token).
Upon connection, instances are auto-discovered. Instance pairing uses the existing flow.

### 15a: Write Tests (RED) — UI Tests

**Add to**: `NullClawUIUITests/NullClawUIUITests.swift` or new test file

UI test methods:
1. `testAddHubByURL()` — enter hub URL, tap connect, verify hub appears in list
2. `testAddHubWithToken()` — enter hub URL + token, verify 401 error shown if wrong token
3. `testAutoDiscoverInstance()` — after hub connects, instance appears automatically
4. `testPairDiscoveredInstance()` — tap pair, enter code, verify paired state

### 15b: Implement (GREEN)

**Update**: `NullClawUI/Views/AddGatewaySheet.swift`
- URL field accepts hub URL
- Optional token field (secure text, "Hub admin token (optional)")
- On connect: creates `GatewayViewModel`, connects to hub
- If hub has instances: show discovered instances, allow pairing
- Preserve existing instance-only flow for non-hub connections

### 15c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild build-for-testing -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 15d: Commit
```bash
git add -A && git commit -m "update AddGatewaySheet for hub URL entry and instance discovery"
git push
```

---

## Step 16: Update ServerCard & ServersView

**Goal**: Server cards display hub name, instance count, dual health status.

### 16a: Write Tests (RED) — Component Tests

**Update**: `NullClawUITests/ServerCardTests.swift`

Add tests:
1. `testServerCardShowsHubNameAndInstanceCount()`
2. `testServerCardShowsDualHealthStatus()`
3. `testServerCardShowsPairingStatus()`

### 16b: Implement (GREEN)

**Update**: `ServerCard.swift`, `ServersView.swift`
- Display hub URL + instance count
- Health indicator aggregates hub + instance health
- Paired/unpaired badge reflects instance pairing state

### 16c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild build-for-testing -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 16d: Commit
```bash
git add -A && git commit -m "update ServerCard and ServersView for hub-aware display"
git push
```

---

## Step 17: Update GatewayDetailView Navigation

**Goal**: Detail view shows hub info + instance management links. All sub-page
navigation points to correct endpoints through hub client.

### 17a: Write Tests (RED) — UI Tests

**Update**: `NullClawUIUITests/GatewayDetailSubPageTests`

Ensure all sub-page navigation tests pass with new endpoint routing:
- Agent Config → hub config endpoint
- Cron Jobs → hub cron endpoint
- MCP Servers → hub MCP endpoint
- Channels → hub channels endpoint
- Usage Stats → hub usage endpoint

### 17b: Implement (GREEN)

**Update**: `GatewayDetailView.swift`
- Add hub info section (version, uptime, component count)
- Add instance management section (list instances, start/stop)
- Update navigation destinations to pass correct client references

### 17c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild build-for-testing -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 17d: Commit
```bash
git add -A && git commit -m "update GatewayDetailView for hub-aware navigation"
git push
```

---

## Step 18: Update Discovery (mDNS)

**Goal**: `NWBrowser` discovers `_nullhub._tcp` in addition to `_nullclaw._tcp`.
Upon discovering a NullHub, automatically query for instances.

### 18a: Write Tests (RED)

**Add tests** to discovery-related tests:
1. `testDiscoversNullHubService()` — mock `_nullhub._tcp` Bonjour record
2. `testDiscoversNullClawService()` — mock `_nullclaw._tcp` Bonjour record
3. `testHubDiscoveryTriggersInstanceQuery()` — on hub found, auto-queries `/api/instances`

### 18b: Implement (GREEN)

**Update**: `GatewayDiscoveryModel.swift`
- Add `NWBrowser` descriptor for `_nullhub._tcp`
- On hub discovery: create `HubGatewayClient`, call `listInstances()`
- Merge discovered instances into the server list
- Default hub port: 19800 (from mDNS TXT or fallback)

### 18c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild build-for-testing -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 18d: Commit
```bash
git add -A && git commit -m "add NullHub mDNS discovery with auto instance query"
git push
```

---

## Step 19: Update Health Monitor

**Goal**: `GatewayHealthMonitor` polls both hub health and instance health.

### 19a: Write Tests (RED)

**Add tests**:
1. `testHealthMonitorPollsHubAndInstance()`
2. `testHealthMonitorReportsHubDown()`
3. `testHealthMonitorReportsInstanceDown()`
4. `testHealthMonitorRecoversOnReconnect()`

### 19b: Implement (GREEN)

**Update**: `GatewayHealthMonitor.swift`
- Accept optional `HubGatewayClient` and `InstanceGatewayClient`
- Poll both every 30s
- Report aggregate status

### 19c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild build-for-testing -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 19d: Commit
```bash
git add -A && git commit -m "update HealthMonitor for dual hub/instance polling"
git push
```

---

## Step 20: Update Live Integration Tests

**Goal**: `GatewayLiveIntegrationTests` targets live NullHub instead of NullClaw admin API.
Instance-level A2A/SSE/agent-card tests preserved targeting instance directly.

### 20a: Write Tests (RED)

**New file**: `NullClawUITests/HubLiveIntegrationTests.swift`

Tests against live NullHub (requires running hub):
1. `testLiveHubHealth()` — GET /health
2. `testLiveHubStatus()` — GET /api/status
3. `testLiveHubComponents()` — GET /api/components
4. `testLiveHubInstances()` — GET /api/instances
5. `testLiveHubSettings()` — GET /api/settings
6. `testLiveHubMetaRoutes()` — GET /api/meta/routes
7. `testLiveHubProviders()` — GET /api/providers
8. `testLiveHubChannels()` — GET /api/channels
9. `testLiveHubUsage()` — GET /api/usage

**Update**: Existing `GatewayLiveIntegrationTests` — remove admin API tests,
preserve A2A/SSE/agent-card/pairing tests against instance directly.

### 20b: Implement (GREEN)

Integration tests are self-verifying. Just ensure they compile and run.

### 20c: Quality Gate
```bash
# Skip live tests in CI; run manually:
swiftlint --strict && swiftformat --lint . && \
  xcodebuild build-for-testing -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 20d: Commit
```bash
git add -A && git commit -m "update live integration tests for NullHub endpoints"
git push
```

---

## Step 21: Remove AddGatewayPairingModel (Deprecated)

**Goal**: `AddGatewayPairingModel` was tied to the old single-gateway pairing flow.
It's no longer used — the pairing flow goes through `InstanceGatewayClient.pair(code:)`.

### 21a: Verify No References (GREEN)

Confirm no code references `AddGatewayPairingModel`:
```bash
rg "AddGatewayPairingModel" NullClawUI/
```

### 21b: Remove

Delete `NullClawUI/Models/AddGatewayPairingModel.swift`.
Remove any test fixtures referencing it.

### 21c: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild build-for-testing -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 21d: Commit
```bash
git add -A && git commit -m "remove deprecated AddGatewayPairingModel"
git push
```

---

## Step 22: Full Integration Verification

**Goal**: Run the entire test suite against live services to confirm end-to-end functionality.

### 22a: Verification Steps (Manual)

1. Start NullHub: `~/Programming/claw/nullhub/zig-out/bin/nullhub serve --port 19800`
2. Start or verify NullClaw instance on port 5111
3. Run full test suite:
   ```bash
   xcodebuild test -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
   ```
4. Run live integration tests:
   ```bash
   xcodebuild test -only-testing:NullClawUITests/HubLiveIntegrationTests \
     -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
   ```
5. Launch app in Simulator, verify:
   - Add hub by URL
   - Instance auto-discovered
   - Chat/streaming works via direct instance connection
   - Agent card displays correctly
   - Config editing works through hub
   - Cron management works through hub

### 22b: Quality Gate
```bash
swiftlint --strict && swiftformat --lint . && \
  xcodebuild test -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
```

### 22c: Commit
```bash
git add -A && git commit -m "final integration verification — all tests passing"
git push
```

---

## Phase 8 (Post-Migration): New NullHub Features (Deferred)

These can be added incrementally after core migration is complete and stable:

| Feature | Priority | New Files |
|---|---|---|
| Instance lifecycle (start/stop/restart) | High | `InstanceControlView`, `InstanceControlViewModel` |
| Instance log viewing | Medium | `InstanceLogView`, `InstanceLogViewModel` |
| Hub-level provider management | Medium | `ProviderManagementView`, `HubProviderViewModel` |
| Hub settings management | Low | `HubSettingsView`, `HubSettingsViewModel` |
| Update checking | Low | `UpdateCheckView`, `InstanceUpdateViewModel` |
| OS service management | Low | `ServiceControlView` |
| Wizard/install flow | Low | `WizardInstallView` |
| Orchestration proxy | Low | `OrchestrationView` |

---

## Summary: Files Changed

| Action | Count | Files |
|---|---|---|
| **New** | ~5 | `NullHubModels.swift`, `HubGatewayClient.swift`, `GatewayNetworking.swift`, `HubLiveIntegrationTests.swift`, view model/view tests |
| **Removed** | 1 | `AddGatewayPairingModel.swift` |
| **Renamed** | 1 | `GatewayClient.swift` → `InstanceGatewayClient.swift` |
| **Heavily modified** | ~6 | `GatewayProfile.swift`, `GatewayViewModel.swift`, `AddGatewaySheet.swift`, `GatewayDetailView.swift`, `ServersView.swift`, `ServerCard.swift` |
| **Updated** | ~10 | All management ViewModels, `GatewayDiscoveryModel`, `GatewayHealthMonitor`, tests |
| **Preserved (zero changes)** | ~6 | `A2AMessage.swift`, `AgentCard.swift`, `ChatViewModel.swift`, `ChatView.swift`, `PairingViewModel.swift`, `KeychainService.swift` |
