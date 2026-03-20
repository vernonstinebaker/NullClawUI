# NullClawUI — Development Plan

A Swift/SwiftUI app for interacting with a NullClaw AI Gateway using the A2A (Agent-to-Agent) protocol.

## Platform & Tech Stack

| Property | Value |
|---|---|
| **iOS / iPadOS Target** | 26.0 (no backward compatibility) |
| **macOS Target** | 26.0 Tahoe (future — see Phase 24) |
| **Swift Version** | Swift 6 (strict concurrency) |
| **UI Paradigm** | Liquid Glass (iOS 26 material system) |
| **State Management** | `@Observable` macro (Swift 6) |
| **Networking** | URLSession + AsyncSequence for SSE |
| **Persistence** | SwiftData + CloudKit (Phase 11) + System Keychain |
| **Markdown** | swift-markdown-ui |
| **Xcode** | 26+ |
| **Preferred Simulator** | iPhone 17 Pro Max, iOS 26.2, UDID `C0F9071A-AC90-42B7-9083-219DB8CD8297` |

---

## Status Legend

| Symbol | Meaning |
|---|---|
| ✅ | Complete and verified (tests pass) |
| ⚠️ | Partial — implemented but has known gaps |
| 🔜 | In progress / uncommitted work from current session |
| ❌ | Not started |

---

## Phase 0: Project Setup ✅

- **Goal**: Establish the Xcode project structure, dependencies, entitlements, and version control.
- **What exists**:
  - Xcode project with targets: `NullClawUI` (app), `NullClawUITests`, `NullClawUIUITests`.
  - Swift 6 strict concurrency enabled (`-strict-concurrency=complete`).
  - `NSAllowsLocalNetworking: true` in `Info.plist`.
  - Keychain Sharing entitlement: `com.nullclaw.nullclawui`.
  - `swift-markdown-ui` SPM dependency added.
  - Folder structure: `App/`, `Views/`, `ViewModels/`, `Networking/`, `Security/`, `Models/`, `Resources/`.
  - `Assets.xcassets` with `AccentColor` and `AppIcon` stub sets.

---

## Phase 1: Foundation & Discovery ✅

- **Goal**: Confirm the app can "see" a NullClaw instance.
- **What exists**:
  - Settings screen with a URL input field (default: `http://localhost:5111`).
  - `GET /health` connectivity check on launch and foreground transitions (`scenePhase` observer).
  - `GET /.well-known/agent-card.json` — displays agent name, version, capabilities.
  - Liquid Glass status badge: green "Online" / red "Offline".

---

## Phase 2: Secure Pairing ✅

- **Goal**: Establish a trusted connection and persist credentials.
- **What exists**:
  - 6-digit numeric code entry UI (`PairingViewModel`, `SettingsView`).
  - `POST /pair` with `{ "code": "123456" }` → stores returned Bearer token in Keychain.
  - Keychain key format: `nullclaw.token.<normalized-gateway-url>`.
  - `kSecAttrAccessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
  - Auto-load token on launch; "Paired" status shown in settings.
  - "Unpair" action deletes Keychain item and resets to pairing screen.

---

## Phase 3: Simple Interaction ✅

- **Goal**: Send a prompt and receive a complete (non-streaming) response.
- **What exists**:
  - Chat UI with message bubbles and a `TextEditor` input bar.
  - `POST /a2a` with JSON-RPC `message/send`.
  - Decodes the response `Task` object and displays the assistant's reply.
  - Loading indicator while awaiting response.

---

## Phase 4: Real-time Streaming ✅

- **Goal**: Update the UI token-by-token as the agent generates a response.
- **What exists**:
  - `POST /a2a` with JSON-RPC `message/stream`.
  - `AsyncBytes`-based SSE parser in `GatewayClient`.
  - Dedicated `sseSession` (90 s request timeout, 600 s resource timeout) for streaming.
  - Partial token rendering — each chunk appended to the in-progress bubble.
  - Exponential-backoff reconnect: 1 s → 2 s → 4 s, max 3 retries.
  - Auto-scroll on every token chunk via `scrollTick` counter observed in `ChatView`.
  - 401 response detected as non-retriable — surfaces auth-failure alert and forces re-pair.

---

## Phase 5: Task Management & History ✅

- **Goal**: Allow users to browse and manage previous interactions.
- **What exists**:
  - `TaskHistoryView`: list of locally-persisted `ConversationRecord` objects (see Phase 9).
  - Tapping a record with a `serverTaskID` calls JSON-RPC `tasks/get` and re-populates chat.
  - "Abort" button (shown while streaming) calls JSON-RPC `tasks/cancel`.
  - `role: "agent"` from server remapped to `"assistant"` in `ChatViewModel.loadTask`.
  - Human-readable titles: first user message (≤ 80 chars), then optionally overwritten with a derived summary from the first assistant reply.
- **Note**: All task operations are `POST /a2a` JSON-RPC — REST `GET /tasks` endpoints do not exist on the server.

---

## Phase 6: Polish & Native Integration ✅

- **Goal**: Make it feel like a first-class Apple application.
- **What exists**:
  - **Markdown rendering**: `swift-markdown-ui` with `.gitHub` theme.
  - **Adaptive accent color**: parsed from `agent-card.json`; falls back to system tint.
  - **iPadOS layout**: three-column `NavigationSplitView` — sidebar (history + gear toggle), content column (Settings when gear is active, `Color.clear` otherwise), detail (chat). Gear icon toggles to `gear.badge.checkmark` while Settings is open; no sheet or dismiss button needed.
  - **iPhone layout**: `TabView` with Chat / History / Settings / Search (role: `.search`) tabs. `SearchResultsView` uses `Tab(role: .search)` pattern; `.searchable` is confined to that tab only and scopes results based on which tab was previously active.
  - **Accessibility**: `accessibilityLabel` and `accessibilityHint` throughout.
  - **Liquid Glass materials**: `GlassCard` uses `.glassEffect(.regular, in: RoundedRectangle(...))`.
  - **Contrast-safe user bubble**: `Color+Extensions.swift` computes `contrastingForeground`.

---

## Phase 7: Code Quality, UX Bugs & Test Fixes ✅

- **Goal**: Eliminate broken code, dead code, non-conformant patterns, and UX showstoppers.
- **What exists**:
  - Chat reset bug fixed: `GatewayViewModel` and `ChatViewModel` hoisted to `@State` on `NullClawUIApp`.
  - Token double-unwrap bug in `SettingsView.swift` fixed.
  - `TypingIndicator` rewritten with per-dot `@State var isUp` + `.repeatForever` animations.
  - `ConnectionBadge` demoted to non-interactive static status display.
  - 174 unit tests passing (now 421+ with Phases 16-20 and regression coverage).

---

## Phase 8: UI Polish & New Chat ✅

- **Goal**: Elevate visual quality; ship "New Conversation" feature.
- **What exists**:
  - **SettingsView** (unpaired): large SF Symbol hero, animated pulse, cleaner card hierarchy.
  - **ChatView**: asymmetric bubble corners, per-role avatar dots, `ultraThinMaterial` input bar.
  - **PairedSettingsView**: hero header with agent avatar, `ConnectionBadge` inline.
  - **New Conversation**: pencil icon in `ChatView` navbar; sidebar button on iPad.
  - `--uitesting-paired` launch mode for UI tests; 37 UI tests (3 skipped), 0 failures.

---

## Phase 9: Multiple Gateways ✅

- **Goal**: Connect to and switch between multiple NullClaw gateway instances.
- **What exists**:
  - `GatewayProfile` `@Model` class (`id`, `name`, `url`, `isPaired`, `requiresPairing`, `normalizedURL`, `displayHost`).
  - `GatewayStore`: add, edit, delete, activate profiles; SwiftData-backed (Phase 11).
  - `requiresPairing: Bool` (default `true`) — set to `false` by `completeOpenGateway` when the gateway responds 403 to `/pair`. Persisted so that `updateProfile` does not re-derive `isPaired` from the Keychain for open gateways (which never issue a token). Migration `migrateOpenGatewayFlagsIfNeeded` fixes pre-existing profiles on first launch after upgrade.
  - One Keychain token per gateway, keyed by `normalizedURL`. Open gateways (requiresPairing=false) never store a token.
  - **Open gateway `requiresPairing` invariant** (critical — see Appendix): `requiresPairing` MUST be set to `false` before `isPaired` is set to `true` for any open gateway. If `requiresPairing` is still `true` when `updateProfile` is called, it will re-derive `isPaired` from the Keychain, find no token, and set `isPaired = false` — causing the app to drop back to the pairing screen.
  - Legacy migration: pre-Phase-9 single `"gatewayURL"` UserDefaults key → first `GatewayProfile`.
  - Gateway switcher in `ChatView` toolbar (confirmation dialog when > 1 profile).
  - `GatewaySlot` in `ChatViewModel`: saves/restores `messages`, `activeTaskID`, `activeContextID` per gateway — switching away and back preserves full context.
  - `resetForNewGateway` cancels any in-flight SSE stream before switching.
  - `GatewayViewModel.switchGateway(to:)` rebuilds the `GatewayClient` and reconnects.

---

## Phase 10: UX Hardening & Settings Redesign ✅

- **Goal**: Fix accumulated UX issues and complete the Settings redesign.
- **What exists**:

  ### Bug fixes
  - **Chat title flicker**: `AppModel` now caches the last-known `AgentCard` per gateway URL in `agentCardCache: [String: AgentCard]`. `effectiveAgentCard` returns the live card or the cached one during reconnect. Title no longer drops to the profile name while the gateway is connecting.
  - **Spurious history records**: `startNewRecord` removed from `ensureSessionRecord` and `resetForNewGateway`. Records are now created lazily at the moment the user sends their first message in a session (`ensureRecordForSend` called inside `send()` / `stream()`). Gateway switching no longer creates blank history entries.
  - **Stream task lifecycle**: `beginStream()` stores the `Task` handle; `resetForNewGateway` cancels it before clearing `messages`; all `messages[idx]` accesses are bounds-checked; `isStreaming` cleared unconditionally after stream loop exits.

  ### History improvements (`TaskHistoryView`)
  - **Delete**: swipe-to-delete (full swipe allowed) calls `ConversationStore.delete(id:)`.
  - **Dual timestamps**: every row now shows both relative ("5 min ago") and absolute ("Mar 15, 2026, 3:45 PM") time, separated by `·`.
  - **Search / filter**: `.searchable` with `placement: .navigationBarDrawer(displayMode: .automatic)` — hidden until pull-down. Filters on title and gateway name.
  - **No-results state**: dedicated empty state when search returns nothing.

  ### Settings redesign (`PairedSettingsView`)
  - **Flat list**: gateway profiles are a plain `List` — no hero header, no inline expansion.
  - **Search**: `.searchable` on the gateway list (pull-to-reveal), filters on name and host.
  - **Navigation**: each row is a `NavigationLink` → `GatewayDetailView` (new). No more in-place expansion.
  - **`GatewayDetailView`**: shows agent card (name, version, description, capabilities — only when this is the active gateway and card is available), gateway URL, connection status, Edit button, Switch button (inactive gateways only), and Unpair button (active + paired only).
  - **`EditGatewaySheet`** promoted from `private` to `internal` so `GatewayDetailView` can use it.

  ### Test updates
  - Settings tests updated for new navigation title (`"Gateways"`) and detail-page flow.
  - New test: `testGatewayRowNavigatesToDetail` — verifies `NavigationLink` pushes detail with correct title.
  - All 37 UI tests pass (3 skipped), 0 failures.

---

## Phase 11: SwiftData Migration & iCloud Sync ✅

- **Goal**: Replace UserDefaults JSON persistence with SwiftData + CloudKit so that gateway configuration and conversation history sync automatically across devices (iOS app ↔ future macOS menubar app).
- **What exists**:
  - `GatewayProfile` and `ConversationRecord` converted to `@Model` classes.
  - `GatewayStore` and `ConversationStore` backed by SwiftData `ModelContext`.
  - `NullClawUIApp` configures `ModelContainer` with `cloudKitDatabase: .automatic`; falls back to local-only if CloudKit is unavailable (e.g., simulator without signed-in iCloud account).
  - One-time migration: reads legacy UserDefaults JSON blobs on first post-upgrade launch and inserts them as SwiftData records.
  - Unit tests use an in-memory `ModelContainer` (no disk or CloudKit access).
  - Keychain items are per-device and explicitly excluded from CloudKit sync.
- **Dependencies**: iCloud-capable App ID and provisioning profile; Apple Developer account with CloudKit enabled.
- **Note**: Cross-device sync validation requires two physical devices sharing the same iCloud account.

---

## Phase 12: LAN Gateway Discovery ✅

- **Goal**: Auto-discover NullClaw gateways on the local network without manual URL entry.
- **What exists**:
  - `GatewayDiscoveryModel` using `Network.framework` (`NWBrowser`) — browses for `_nullclaw._tcp` Bonjour services, resolves host/port from TXT records, falls back to `.local` mDNS name.
  - Discovered gateways surface in the "Add Gateway" sheet above the manual URL field.
  - Scanning indicator shown while browser is running.
  - Falls back gracefully to manual URL entry if no gateways are found.
  - `NSBonjourServices` key in `Info.plist`.

---

## Phase 13: Health Monitoring & Reconnect ✅

- **Goal**: Robust real-time gateway health tracking with automatic reconnect.
- **Tasks**:
  1. Implement `GatewayHealthMonitor` — periodic `GET /health` polling (default 30 s).
  2. Pause polling in background; resume on foreground (`scenePhase` observer already in place).
  3. Surface health failure as a non-intrusive banner (not a modal alert).
  4. On reconnect success, automatically resume any interrupted SSE stream.
- **Validation**: Killing and restarting NullClaw while the app is open causes the status badge to go red then green automatically.

---

## Phase 14: Gateway Status Dashboard ✅

- **Goal**: Multi-gateway health overview + on-demand live status in Settings detail.
- **What exists**:
  - **Gateway list in `PairedSettingsView`**: each row shows a coloured status dot (green/red/grey), name, host, last-checked time. Health is polled via concurrent `GET /health` against all profiles simultaneously on appear and on pull-to-refresh. Driven by `GatewayStatusViewModel`.
  - **Live Status** in `GatewayDetailView` (Settings → tap a gateway → "Live Status"): `GatewayLiveStatusView` sends an A2A prompt to the gateway asking for MCP server and channel status, parses the structured JSON reply, and renders connected/failed rows. Pull-to-refresh reloads. Available for all gateways (paired **and** open — not gated on `isPaired`).

### Live Status prompt strategy

- **`loadPrompt`** (static constant, visible for tests): instructs the agent to read `~/.nullclaw/config.json` and reply with a JSON object containing `"mcp_servers"` and `"channels"` arrays derived directly from the config structure. Stored as `GatewayLiveStatusView.loadPrompt`.
  - **Do not use** a vague NL introspection prompt like `"List your actual runtime status"` — this causes a full LLM round-trip (20+ seconds) and is unreliable; the agent may report wrong status or fail with `GatewayError.jsonRPCError` on retry.
- **Parser**: `parseJSONStatus(from:)` (internal static, testable) extracts the first `{…}` block, decodes via `LiveStatusRaw`, and maps to `[MCPServerStatus]` / `[ChannelStatus]`. `"connected"` defaults to `true` when the key is absent (channel entries in the config have no status — they are always configured).
- **Legacy fallback**: `parseMCP` and `parseChannels` fall back to the old `MCP: <name> connected/failed` / `Channel: <name> connected/failed` line format if no JSON block is found.
- **Known limitation**: HTTP-transport MCP servers (e.g. `mcp_mattermost` on Mac, `mattermost` on OrangePi) are not listed by the agent because they have no `"command"` field in the config. The prompt explicitly filters for subprocess-type MCPs. This is correct/expected.
- **OrangePi hostname caveat**: if the gateway profile URL uses a hostname (e.g. `http://orangepi:5111`), the iOS device may not be able to resolve it via mDNS. Use an IP address in the profile URL if the gateway is unreachable by name.

- **Files**:
  - `GatewayStatusViewModel.swift` — per-profile `/health` poller using `TaskGroup`; holds `[UUID: ProfileHealthState]`
  - `PairedSettingsView.swift` — gateway list with health dots; `GatewayDetailView` with `GatewayLiveStatusView`, `GatewayLiveStatus`, `MCPServerStatus`, `ChannelStatus` models, `LiveStatusRaw` JSON decoding shim
- **Note**: There is no separate `GatewayStatusView.swift` or dedicated Status tab. Health status is integrated directly into the Settings gateway list.

---

## Phase 15: Cron Job Manager ✅

- **Goal**: Let users view, pause/resume, trigger, add, edit, and delete gateway cron jobs from native UI.

### Prompt strategy (verified against live gateway)

- **`load()`**: `"Read ~/.nullclaw/cron.json and respond with ONLY its raw contents as a valid JSON array, no extra text before or after."` — agent reads the file directly and returns clean JSON. Reliable. Stored as `CronJobViewModel.loadPrompt` static constant.
  - **Do not use** a vague NL prompt like `"List all cron jobs as a JSON array"` — this causes the agent to invoke the `schedule` tool with `{"action":"list"}` which returns `success=false`, causing the agent to return `[]`.
- **`pause` / `resume`**: `"Pause/Resume the cron job with id \"X\" in ~/.nullclaw/cron.json."` — explicit file path required.
- **`runNow`**: `"Run the cron job with id \"X\" immediately."` — triggers the scheduler.
- **`delete`**: `"Delete the cron job with id \"X\" from ~/.nullclaw/cron.json."` — explicit file path required.
- **`addJob`**: constructed from `CronJobDraft.toPrompt()` — describes all fields.
- **`editJob`**: constructed from `CronJobDraft.toEditPrompt(replacing:)` — specifies the existing job ID and all new field values explicitly, including `one_shot` and `delete_after_run` as `true`/`false` even when false (unlike `toPrompt()` which omits them).

### What exists

  - `CronJob` model (`Models/CronJob.swift`) — `Codable, Identifiable, Sendable` struct matching the gateway `cron.json` schema; computed helpers for `displayTitle`, `nextRunCountdown`, timestamps.
  - `CronJobViewModel` (`ViewModels/CronJobViewModel.swift`) — `@Observable @MainActor`; `load()` uses `Self.loadPrompt` (direct file-read) and parses the `[…]` array from the reply; `pause`, `resume`, `runNow`, `delete`, `addJob`, `editJob` each send the appropriate natural-language command then re-fetch.
  - `CronJobListView` (`Views/CronJobListView.swift`) — colour-coded rows (teal = agent, indigo = shell, grey = paused), badge pills, cron expression + next-run countdown + last status; leading swipe: **Pause/Resume** + **Run Now**; trailing swipe: **Delete** (red); tap row to edit; pull-to-refresh; Add toolbar button.
  - `AddCronJobSheet` — Form with all fields: id, expression, type picker, command/prompt, model override, one-shot / delete-after-run toggles, delivery channel + recipient.
  - `EditCronJobSheet` — Same form layout as `AddCronJobSheet`, pre-populated from the tapped `CronJob`; "Save" sends `toEditPrompt(replacing:)` via `editJob(_:draft:)`; navigation title "Edit Cron Job".
  - Entry point: `NavigationLink → CronJobListView` inside `GatewayDetailView` in `PairedSettingsView`.
  - 28 unit tests covering model decode, `parseCronJobs`, `toPrompt`, `toEditPrompt`, `editJob` ViewModel state, and regression tests for `loadPrompt` content and explicit boolean encoding.

---

## Phase 16: Agent Configuration ✅

- **Goal**: Let users inspect and adjust live-editable agent settings from a native form.
- **Background**: The gateway exposes live-editable config paths. The real schema keys (verified against live `~/.nullclaw/config.json`) are: `agents.defaults.model.primary`, `default_temperature` (top-level), `agent.max_tool_iterations`, `agent.message_timeout_secs`, `agent.parallel_tools`, `agent.compact_context`, `agent.compaction_max_source_chars`.

### Real config schema (key reference)

| AgentConfig field | Config key | Notes |
|---|---|---|
| `primaryModel` | `agents.defaults.model.primary` | e.g. `"infini-ai/glm-5"` |
| `provider` | inferred from model prefix or `models.providers` | read-only |
| `temperature` | `default_temperature` | top-level key |
| `maxToolIterations` | `agent.max_tool_iterations` | default 25 |
| `messageTimeoutSecs` | `agent.message_timeout_secs` | default 300 |
| `parallelTools` | `agent.parallel_tools` | default false |
| `compactContext` | `agent.compact_context` | default false |
| `compactionThreshold` | `agent.compaction_max_source_chars` | default 8000 |

### Prompt strategy (verified against live gateway)

- **`load()`**: `"Read ~/.nullclaw/config.json and respond with ONLY a valid JSON object…"` — agent reads the file directly and returns clean JSON. Reliable.
- **`setTemperature`**: `"Set the default temperature to X."` — agent has a dedicated mutator. Works.
- **`setPrimaryModel`**: `"Update agents.defaults.model.primary to \"X\" in ~/.nullclaw/config.json."` — explicit path required.
- **`setMaxToolIterations`**: `"Update agent.max_tool_iterations to X in ~/.nullclaw/config.json."` — explicit path required.
- **`setMessageTimeout`**: `"Update agent.message_timeout_secs to X in ~/.nullclaw/config.json."` — note `_secs` not `_seconds`.
- **`setParallelTools`**: `"Update agent.parallel_tools to true/false in ~/.nullclaw/config.json."` — explicit path required.
- **`setCompactContext`**: `"Update agent.compact_context to true/false in ~/.nullclaw/config.json."` — explicit path required.
- **`setCompactionThreshold`**: `"Update agent.compaction_max_source_chars to X in ~/.nullclaw/config.json."` — explicit path required.

### What exists

- **`AgentConfigViewModel`** (`ViewModels/AgentConfigViewModel.swift`): `@Observable @MainActor` class. On `load()`, sends a structured one-shot A2A prompt instructing the agent to read `~/.nullclaw/config.json` directly and return a JSON object; parses the reply into an `AgentConfig` value type (`primaryModel`, `provider`, `temperature`, `maxToolIterations`, `messageTimeoutSecs`, `parallelTools`, `compactContext`, `compactionThreshold`). Individual setter methods (`setTemperature`, `setPrimaryModel`, `setMaxToolIterations`, `setMessageTimeout`, `setParallelTools`, `setCompactContext`, `setCompactionThreshold`) each send an explicit path-based config mutation prompt and optimistically update the local `config` on success. `AgentConfigRaw` decoding shim accepts both canonical and legacy key names. Confirmation and error banners exposed as `confirmationMessage` / `errorMessage`.
- **`AgentConfigView`** (`Views/AgentConfigView.swift`): `NavigationLink` target in `PairedSettingsView`. Sections: **Model** (text field + read-only provider row with ⚠️ restart warning), **Sampling** (temperature slider 0–2 with "Apply" button), **Limits** (max tool iterations stepper, message timeout stepper, parallel tools toggle), **Memory / Compaction** (compact context toggle + threshold stepper). Draft state decoupled from live config to prevent mid-edit flicker. Confirmation and error banners at the bottom.
- **NavigationLink** added to `PairedSettingsView` in the gateway settings navigation list.
- **10 unit tests** in `AgentConfigViewModelTests`: `parseConfig` happy path (using canonical key names), no-object, malformed JSON, partial JSON with defaults, `load()` with failing client, reentrancy guard, `AgentConfig` `Equatable` equality/inequality, and `AgentConfigParseError` localized descriptions. Total test count: **174**.
- Provider field is read-only with a ⚠️ "Requires restart" label per the spec.

---

## Phase 17: Autonomy & Safety Controls ✅

- **Goal**: Surface the gateway's autonomy and safety settings in a dedicated native UI so users can quickly raise or lower the agent's operating permissions.
- **Background**: The gateway has an `autonomy` config block: `level` (e.g. `low`, `medium`, `high`), `max_actions_per_hour`, `allowed_commands`, `block_high_risk_commands`, `require_approval_for_medium_risk`. These can be updated via agent prompts.
### Prompt strategy (verified against live gateway)

- **`load()`**: reads `~/.nullclaw/config.json` directly and requests a JSON object with the five autonomy keys. Stored as `AutonomyViewModel.loadPrompt`.
- **`setLevel`**: `"Update autonomy.level to \"X\" in ~/.nullclaw/config.json."` — explicit path required.
- **`setMaxActionsPerHour`**: `"Update autonomy.max_actions_per_hour to X in ~/.nullclaw/config.json."`
- **`setBlockHighRiskCommands`**: `"Update autonomy.block_high_risk_commands to true/false in ~/.nullclaw/config.json."`
- **`setRequireApprovalForMediumRisk`**: `"Update autonomy.require_approval_for_medium_risk to true/false in ~/.nullclaw/config.json."`
- **`setAllowedCommands`**: `"Update autonomy.allowed_commands to [...] in ~/.nullclaw/config.json."`

### What exists

- **`AutonomyViewModel`** (`ViewModels/AutonomyViewModel.swift`): `@Observable @MainActor` class. `load()` sends a structured one-shot A2A prompt to read `~/.nullclaw/config.json` and return the five autonomy fields as JSON; parses reply into an `AutonomyConfig` value type. Setter methods for each field send explicit path-based mutation prompts and optimistically update local `config` on success. `AutonomyConfigRaw` decoding shim. Confirmation and error banners exposed as `confirmationMessage` / `errorMessage`.
- **`AutonomyView`** (`Views/AutonomyView.swift`): `NavigationLink` target in `PairedSettingsView`. Sections: **Autonomy Level** (segmented control `Low / Medium / High` with color-coded risk badge and contextual footer text), **Limits** (max actions/hour stepper), **Safety** (block high-risk toggle + require-approval-for-medium-risk toggle), **Allowed Commands** (horizontal tag cloud or "No commands restricted" placeholder, with "Edit" button → `CommandEditorSheet`). `CommandEditorSheet` is a private sheet with a monospaced `TextEditor` (one command per line).
- **NavigationLink** added to `GatewayDetailView` in `PairedSettingsView.swift` (label: "Autonomy & Safety", icon: `shield.lefthalf.filled`).
- **12 unit tests** in `AutonomyViewModelTests`: `parseConfig` happy path, high-level with empty commands, no-object error, malformed JSON error, partial JSON with defaults, `load()` with failing client, reentrancy guard, `AutonomyConfig` equality/inequality (level + commands), and `AutonomyConfigParseError` localized descriptions.
- **3 regression tests** in `GatewayClientInitTokenTests`: empty-string token treated as nil (`.unpaired` guard fires), nil token also fires, valid token bypasses guard (reaches network layer).

### Other fixes in this phase

- **`GatewayClient.init` empty-token bug fixed**: `self.bearerToken` now applies the same `flatMap { $0.isEmpty ? nil : $0 }` filter as `setToken(_:)`.
- **`AgentConfigView` Stepper `onEditingChanged` inverted logic fixed**: `if !finished` → `if finished` (two steppers).
- **`CronJobViewModel` prompt strings fixed**: pause/resume/delete now include explicit `in ~/.nullclaw/cron.json` file path per PLAN.md Phase 15 spec.
- **`sendOneShot` extracted to `GatewayClient`**: removes 3× duplication across `AgentConfigViewModel`, `CronJobViewModel`, and `GatewayLiveStatusView`; Phase 17 uses it without adding a 4th copy.
- **`parseMCP`/`parseChannels` double-parse fixed**: `load(using:)` now calls `parseJSONStatus` once and branches; legacy fallbacks renamed to `parseMCPLegacy`/`parseChannelsLegacy`.
- **Dead `filteredProfiles` property removed** from `PairedSettingsView`.
- **Validation**: Switching autonomy level from `high` → `low` causes the agent to request approval before executing shell commands.

---

## Phase 18: MCP Server Management ✅

- **Goal**: Let users view registered MCP servers, their connection state, and add or remove servers from the native UI.
- **Background**: MCP servers are configured in the gateway's `mcp_servers` config block. Each entry has: `name`, `transport` (`stdio` or `http`), `command`, `args`, `env`, `headers`, `url`, `timeout_ms`. Connection status (connected / failed) is surfaced by the agent when queried.

### Prompt strategy

- **`load()`**: `"Read ~/.nullclaw/config.json and respond with ONLY a valid JSON object…"` with `"mcp_servers"` array of objects including `"connected"` boolean. Stored as `MCPServerViewModel.loadPrompt`.
- **`remove(_:)`**: `"Remove the MCP server named \"X\" from ~/.nullclaw/config.json."` — explicit file path required.
- **`addServer(_:)`**: constructed from `MCPServerDraft.toPrompt()` — describes name, transport, command/args or URL, and optional timeout.

### What exists

- **`MCPServer`** (`Models/MCPServer.swift`): `Codable, Identifiable, Sendable, Equatable` struct. Fields: `name`, `transport`, `command`, `args`, `env`, `url`, `headers`, `timeoutMs`, `connected` (runtime status). Computed helpers: `transportLabel`, `endpointDescription`. `id` is `name`.
- **`MCPServerViewModel`** (`ViewModels/MCPServerViewModel.swift`): `@Observable @MainActor` class. `load()` sends structured one-shot prompt and parses into `[MCPServer]`. Parser handles both bare JSON array and `{ "mcp_servers": [...] }` wrapped object. `remove(_:)` sends deletion prompt and re-fetches. `addServer(_:)` sends creation prompt and re-fetches. `removingName` tracks which server is being deleted (for per-row spinner). `confirmationMessage` / `errorMessage` banners.
- **`MCPServerListView`** (`Views/MCPServerListView.swift`): `NavigationLink` target in `PairedSettingsView`. Shows all servers with transport icon (globe for HTTP, terminal for stdio), transport badge pill, endpoint summary, and connection status (green/red/grey). Swipe-left to remove. Tap row → `MCPServerDetailView` (read-only: transport, endpoint, timeout, env keys masked). Add toolbar button → `AddMCPServerSheet` (name, transport picker, command+args for stdio, URL for http, optional timeout). Pull-to-refresh reloads.
- **NavigationLink** added to `GatewayDetailView` in `PairedSettingsView.swift` (label: "MCP Servers", icon: `puzzlepiece.extension.fill`).
- **19 unit tests** in `MCPServerViewModelTests`: parse happy path (array), parse happy path (wrapped object), connected nil when absent, empty array, no-JSON throws, prose prefix, `load()` with failing client, reentrancy guard, `remove()` with failing client, `MCPServer` computed helpers (transportLabel ×3, endpointDescription ×3, id), `MCPServerDraft.toPrompt()` (stdio, http), `loadPrompt` content, `MCPServerParseError` descriptions. Total test count at Phase 18: **208** (now 421+).

---

## Phase 19: Cost & Usage Monitoring ✅

- **Goal**: Show token usage and cost data so users can monitor spend and set limits.
- **Background**: The gateway has a `cost` config block with `enabled`, `daily_limit`, `monthly_limit`, and `warn_at_percent`. Usage stats can be retrieved from the agent via a `/usage` or "show usage stats" prompt.
- **Tasks**:
  1. On section open, send "show usage statistics" and parse the reply: total tokens today, total tokens this month, estimated cost today/month.
  2. Render a native summary card: today's usage progress bar vs. daily limit, month-to-date bar vs. monthly limit, cost enabled toggle.
  3. Editable fields: daily limit, monthly limit, warn-at percent — each change sends a config-set prompt.
  4. Show a local notification when the gateway reports a cost warning (parse cost-warning events from SSE stream).
- **Validation**: Viewing the Cost section shows non-zero usage data after a conversation; setting a very low daily limit causes a warning banner to appear.

---

## Phase 20: Channel Status & Management ✅

- **Goal**: Show the connection state of all configured gateway communication channels (Discord, Mattermost, Telegram, Slack, WhatsApp, IRC, Matrix, etc.) and surface read-only config details.
- **Background**: The gateway supports many channel integrations, each configured in the `channels` block. The agent can report their status when asked. Editing channel config generally requires a gateway restart; this phase is read-only status + a clear "restart required" affordance for any config changes.
- **Tasks**:
  1. On section open, send "show channel status" and parse the reply into a `[ChannelStatus]` list. Render each channel with icon, name, and connected/disconnected badge.
  2. Tap a channel row to see a read-only detail view: relevant config fields (server URL, bot name, etc. — no secrets shown).
  3. Show a persistent banner at the top of the section: "Channel configuration changes require a gateway restart."
  4. Future enhancement (Phase 20+): expose an "Edit" button wired to a restart-aware flow.
- **Validation**: Opening the Channel Status section shows all configured channels with accurate connection states.

---

## Phase 21: APNs Notifications ❌

- **Goal**: Let the gateway proactively push notifications to the device via Apple Push Notification service (APNs).
- **Background**: Pushover notifications are already fully operational at the gateway layer — the `pushover` tool (contributed by this project, nullclaw commit `20d7b97`, March 1 2026) can be called by the agent from cron jobs or on demand. No iOS app changes are needed for Pushover; users configure `PUSHOVER_TOKEN` and `PUSHOVER_USER_KEY` in the server's `.env` directly. APNs is the remaining work and requires both iOS app and gateway changes.
- **Tasks**:
  1. Register for remote notifications on launch (`UNUserNotificationCenter`); request permission.
  2. Send the APNs device token to the gateway via a new `/register-device` endpoint (requires gateway-side APNs integration — new gateway work, out of scope for the iOS app alone).
  3. Handle incoming push payloads — deep-link into the relevant conversation when the notification is tapped.
  4. Display rich notifications with conversation title and truncated first line of agent response.
- **Validation**: A completed background cron job pushes a notification that deep-links into the relevant conversation when tapped.

---

## Phase 22: Voice Input ❌

- **Goal**: Let users dictate messages using their voice.
- **Tasks**:
  1. Add push-to-talk mic button to the chat input bar.
  2. Use `SFSpeechRecognizer` + `AVAudioEngine` for on-device transcription.
  3. On recognition result, populate the input field (let user review before sending).
  4. Request `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` permissions.
- **Validation**: User can tap mic, speak a sentence, and see it transcribed into the input field.

---

## Phase 23: Multi-modal Input ❌

- **Goal**: Allow users to attach images and files to messages, not just text.
- **Background**: The A2A protocol supports non-text `parts` in a message (e.g. `{ "inlineData": { "mimeType": "image/jpeg", "data": "<base64>" } }`). The gateway has `multimodal.zig` for handling these. Vision-capable models (GPT-4o, Claude 3.x, Gemini) already work end-to-end once the client sends the right payload shape.
- **Tasks**:
  1. Add a paperclip / photo button to the chat input bar.
  2. Use `PhotosUI.PhotosPicker` for image selection; `UniformTypeIdentifiers` + `UIDocumentPickerViewController` for file selection.
  3. Encode selected image as base64 and append as an `inlineData` part alongside the text part.
  4. Render inbound image parts in assistant bubbles (gateway may echo or describe images).
  5. Request `NSPhotoLibraryUsageDescription` permission.
- **Validation**: Attach a photo and ask "what is in this image?" — the agent describes it correctly using the attached image data.

---

## Phase 24: macOS Menubar App ❌

- **Goal**: A native macOS menubar app that shares gateway configuration and conversation history with the iOS app via iCloud (Phase 11 is a prerequisite).
- **Deprioritization note**: Chat is well-covered on desktop via Mattermost/Discord/Telegram. The unique value of this phase is a fast, keyboard-driven chat popover without opening a browser. Implement only after Phases 14–23 are complete.
- **Tasks**:
  1. Add a macOS target to the Xcode project (menubar app, `LSUIElement = YES`).
  2. Share the SwiftData `ModelContainer` (App Group container, same CloudKit database).
  3. Implement a compact `NSStatusItem` popover with chat input + last-N messages.
  4. Reuse `GatewayClient`, `ChatViewModel`, and SSE streaming logic (already platform-agnostic).
  5. Support multiple gateways via the same `GatewayStore`.
  6. Keychain tokens stored separately per device (same key scheme, not synced).
- **Validation**: Chat on iOS, see the same conversation on macOS within one sync cycle.

---

## Appendix: NullClaw A2A API Reference

All requests (except `/health` and `/pair`) are `POST /a2a` with a JSON-RPC 2.0 envelope.

### Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/health` | Liveness check |
| GET | `/.well-known/agent-card.json` | Agent metadata |
| POST | `/pair` | Exchange pairing code for Bearer token |
| POST | `/a2a` | JSON-RPC dispatch (all task and message methods) |

### JSON-RPC Methods

| Method | Description |
|---|---|
| `message/send` | Send a message, receive a completed `Task` object |
| `message/stream` | Send a message, receive an SSE stream of `TaskStatusUpdateEvent` |
| `tasks/list` | List tasks; supports `state` filter and `pageSize` |
| `tasks/get` | Get full task by ID (includes message history) |
| `tasks/cancel` | Cancel a running task by ID |

### A2A Message Shape

```json
{
  "jsonrpc": "2.0",
  "id": "<uuid>",
  "method": "message/send",
  "params": {
    "message": {
      "role": "user",
      "parts": [{ "text": "Hello" }]
    }
  }
}
```

### SSE Event Shape (`message/stream`)

Each `data:` line is a `TaskStatusUpdateEvent`:
```json
{
  "id": "<task-id>",
  "contextId": "<context-uuid>",
  "status": { "state": "working" },
  "artifact": { "parts": [{ "text": "partial token..." }] },
  "append": true,
  "final": false
}
```

### TaskSummary Shape (from `tasks/list`)

```json
{ "id": "<uuid>", "status": { "state": "completed" } }
```

### Known Server Behaviours

- `role` in history messages is `"agent"` (not `"assistant"`) — remap on the client.
- Pairing codes are ephemeral (in-memory); a server restart invalidates all issued tokens and requires re-pairing.
- Bearer token is sent as `Authorization: Bearer <token>` on all `/a2a` requests.
- `contextId` is returned on SSE events and must be echoed on subsequent sends to maintain conversation context.

---

## Appendix: Open Gateway `requiresPairing` Invariant

Open gateways (`require_pairing: false` in the server config) respond 403 to `POST /pair`. The app detects this and marks the gateway as paired without issuing a token. This creates a subtle invariant that **must be maintained** throughout the codebase:

### The Invariant

**`requiresPairing = false` MUST be persisted on the `GatewayProfile` before `isPaired = true` is set.**

### Why

`GatewayStore.updateProfile()` uses `requiresPairing` to decide how to derive `isPaired`:
- `requiresPairing == true` → re-derives from `KeychainService.hasToken(for:)`. Open gateways have no token → returns `false` → **clears isPaired**.
- `requiresPairing == false` → uses the passed-in value directly → **preserves isPaired**.

If the order is wrong (isPaired set first, requiresPairing set second), any call to `updateProfile()` — triggered e.g. by the user editing the gateway name — will call the `requiresPairing == true` path, find no token, and set `isPaired = false`. The app then routes back to the pairing screen.

### Affected Code Sites (must all follow the invariant)

| Site | Code |
|---|---|
| `NullClawUIApp.setupGateway()` | `setProfileRequiresPairing(id, requiresPairing: false)` **before** `setProfilePaired(id, isPaired: true)` |
| `PairingViewModel.probeIfNeeded()` | `store.setProfileRequiresPairing(id, requiresPairing: false)` **before** `appModel.isPaired = true` |
| `AddGatewaySheet.completeOpenGateway()` (in `PairedSettingsView.swift`) | sets `requiresPairing = false` on the profile **before** `appModel.isPaired = true` |

### `GatewayClient.init` and open gateways

`GatewayClient` accepts a `requiresPairing: Bool = true` parameter. When `false`, `pairingMode` is set to `.notRequired` at init time, allowing all API calls to proceed without a bearer token. All code sites that construct a `GatewayClient` for an open gateway profile must pass `requiresPairing: profile.requiresPairing`.

Current sites: `GatewayViewModel.switchGateway`, `ChannelStatusListView`, `MCPServerListView`, `UsageStatsView`, `AutonomyView`, `AgentConfigView`, `CronJobListView`, `GatewayLiveStatusView` (both `.task` and `.refreshable`).

### Regression Tests

- `GatewayClientInitRequiresPairingTests.testInitWithRequiresPairingFalseSetsNotRequired`
- `GatewayStoreUpdateProfileOpenGatewayTests.testUpdateProfilePreservesIsPairedForOpenGateway`
- `PairingViewModelProbeIfNeededTests.testProbeIfNeededSetsRequiresPairingFalseOnOpenGateway`
