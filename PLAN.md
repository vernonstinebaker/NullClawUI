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
| **Persistence** | UserDefaults (JSON) + System Keychain — see Phase 11 for SwiftData migration |
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
  - **iPadOS layout**: `NavigationSplitView` (sidebar = history list, detail = chat); `TabView` on iPhone.
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
  - 29 unit tests passing.

---

## Phase 8: UI Polish & New Chat ✅

- **Goal**: Elevate visual quality; ship "New Conversation" feature.
- **What exists**:
  - **SettingsView** (unpaired): large SF Symbol hero, animated pulse, cleaner card hierarchy.
  - **ChatView**: asymmetric bubble corners, per-role avatar dots, `ultraThinMaterial` input bar.
  - **PairedSettingsView**: hero header with agent avatar, `ConnectionBadge` inline.
  - **New Conversation**: pencil icon in `ChatView` navbar; sidebar button on iPad.
  - `--uitesting-paired` launch mode for UI tests; 36 UI tests (3 skipped), 0 failures.

---

## Phase 9: Multiple Gateways ✅

- **Goal**: Connect to and switch between multiple NullClaw gateway instances.
- **What exists**:
  - `GatewayProfile` struct (`id`, `name`, `url`, `isPaired`, `normalizedURL`, `displayHost`).
  - `GatewayStore`: add, edit, delete, activate profiles; JSON-persisted in UserDefaults.
  - One Keychain token per gateway, keyed by `normalizedURL`.
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
  - All 36 UI tests pass (3 skipped), 0 failures.

---

## Phase 11: SwiftData Migration & iCloud Sync ✅

- **Goal**: Replace the current UserDefaults JSON persistence with SwiftData + CloudKit so that gateway configuration and conversation history sync automatically across devices (iOS app ↔ future macOS menubar app).
- **Motivation**:
  - UserDefaults has no query capability, no schema migrations, and a size limit unsuitable for large history.
  - iCloud sync via `NSUbiquitousKeyValueStore` has a 1 MB cap — impractical for history.
  - SwiftData's `cloudKitDatabase: .automatic` gives sync in one line; sharing a `ModelContainer` via an App Group is the path to the macOS companion app.
  - Multi-modal message content (future images/files) cannot be stored in UserDefaults.
- **Tasks**:
  1. Add an App Group entitlement (`group.plus.agillity.nullclawui`) to the main target — required for shared container between iOS and macOS targets.
  2. Convert `GatewayProfile` → `@Model` class; `ConversationRecord` → `@Model` class. Add `@Relationship` between record and profile.
  3. Replace `GatewayStore` with a SwiftData-backed store using `ModelContext`. Replace `ConversationStore` similarly.
  4. Configure `ModelContainer` in `NullClawUIApp` with `cloudKitDatabase: .automatic` (requires an iCloud-capable provisioning profile).
  5. Write a one-time migration: on first launch after upgrade, read UserDefaults JSON blobs, insert as SwiftData records, then delete the old keys.
  6. Update `ConversationStore.current` query and all `updateCurrent` / `startNewRecord` call sites.
  7. Keychain items remain as-is (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) — tokens are per-device and must never sync via CloudKit.
  8. Verify UI tests still pass (inject an in-memory `ModelContainer` for `--uitesting` paths).
- **Dependencies**: iCloud-capable App ID and provisioning profile; Apple Developer account with CloudKit enabled.
- **Validation**: Add a gateway on the iPhone; confirm it appears on the Mac companion target within ~30 s. Delete a conversation on one device; confirm it disappears on the other.

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
- **Design** (redesigned from original A2A-prompt approach):
  - **Status tab** (`GatewayStatusView`): fast, lightweight list of all gateway profiles. Fires concurrent `GET /health` against every profile simultaneously — no A2A prompts, results appear in under a second. Each row shows: status dot (green/red/grey), name, host, "Active" badge, last-checked relative time, and a quick-switch button for inactive gateways. Pull-to-refresh supported.
  - **Live Status section** in `GatewayDetailView` (Settings → tap a gateway): on-demand MCP servers and channels list, loaded by tapping "Load Live Status". Uses A2A prompt streaming against the active gateway only. Reload button appears once loaded.
- **Files**:
  - `GatewayStatusViewModel.swift` — per-profile `/health` poller using `TaskGroup`; holds `[UUID: ProfileHealthState]`
  - `GatewayStatusView.swift` — multi-gateway health list with pull-to-refresh
  - `PairedSettingsView.swift` — `GatewayDetailView` enhanced with `GatewayLiveStatus`, `MCPServerStatus`, `ChannelStatus` models and on-demand A2A section
  - `MainTabView.swift` — Status tab at index 2 (`gauge.with.dots.needle.67percent`)
- **Validation**: Status tab immediately shows all gateways with live health dots. GatewayDetailView Live Status section loads MCP/channels on demand for the active gateway.

---

## Phase 15: Cron Job Manager ❌

- **Goal**: Let users view, pause/resume, trigger, add, and delete gateway cron jobs from native UI.
- **Background**: The gateway stores cron jobs in `cron.json`. The agent understands commands like "list my cron jobs", "pause cron job heartbeat-1", "run cron job heartbeat-1 now", and "delete cron job heartbeat-1". Adding a job requires the agent to write a new entry; the app composes the appropriate prompt.
- **Cron job schema** (for UI field mapping):
  - `id`, `expression` (cron string), `command` / `prompt`, `model`, `job_type` (`shell` or `agent`), `paused`, `enabled`, `one_shot`, `delete_after_run`
  - `delivery_mode`, `delivery_channel`, `delivery_to`
  - `last_run_secs`, `last_status`, `next_run_secs`
- **Tasks**:
  1. On "Cron Jobs" section open, send "list cron jobs in JSON" to the agent; parse the response into a `[CronJob]` model and render a native `List` with id, schedule expression, last-run time, last status, and paused/enabled badge.
  2. Swipe actions per row: **Pause / Resume**, **Run Now**, **Delete** (each sends the appropriate natural-language command and refreshes the list).
  3. "Add Job" sheet: fields for id, cron expression, type (Shell command vs. Agent prompt), command/prompt text, optional model override, delivery channel/target. On submit, compose and send an "Add cron job: …" prompt to the agent.
  4. Show `next_run_secs` as a human-readable countdown ("in 47 min").
- **Validation**: User can pause, trigger, and add cron jobs entirely from the native UI; changes persist across app restarts (confirmed by re-fetching the list).

---

## Phase 16: Agent Configuration ❌

- **Goal**: Let users inspect and adjust live-editable agent settings from a native form.
- **Background**: The gateway's `config_mutator` allows certain paths to be changed at runtime (no restart needed). Live-editable paths relevant to the agent include: `agents.defaults.model.primary`, `default_temperature`, tool iteration limits, message timeout, parallel tool count, compaction settings, and memory/session knobs.
- **Tasks**:
  1. On "Agent Config" section open, send "show agent configuration" to the agent and parse the reply into typed fields.
  2. Render a native `Form` with grouped sections:
     - **Model**: model-name text field + provider picker.
     - **Sampling**: temperature slider (0.0–2.0).
     - **Limits**: max tool iterations stepper, message timeout stepper, parallel tools toggle.
     - **Memory / Compaction**: compaction enabled toggle, compaction threshold stepper.
  3. On any field change, compose and send the appropriate config-set prompt (e.g. "Set default temperature to 0.7"). Show a confirmation banner on success.
  4. Paths that require a gateway restart are marked with a ⚠️ "Requires restart" label and a disabled edit control.
- **Validation**: Changing the temperature slider from 1.0 → 0.5 causes subsequent agent responses to be visibly more deterministic; reverting to 1.0 restores prior behavior.

---

## Phase 17: Autonomy & Safety Controls ❌

- **Goal**: Surface the gateway's autonomy and safety settings in a dedicated native UI so users can quickly raise or lower the agent's operating permissions.
- **Background**: The gateway has an `autonomy` config block: `level` (e.g. `low`, `medium`, `high`), `max_actions_per_hour`, `allowed_commands`, `block_high_risk_commands`, `require_approval_for_medium_risk`. These can be updated via agent prompts.
- **Tasks**:
  1. On section open, send "show autonomy configuration" and parse the reply.
  2. Render:
     - **Autonomy Level**: segmented control (`Low / Medium / High`) with a color-coded risk indicator (green / yellow / red).
     - **Max actions / hour**: stepper.
     - **Block high-risk commands**: toggle.
     - **Require approval for medium-risk**: toggle.
     - **Allowed commands list**: read-only tag cloud with an "Edit" button that opens a text-entry sheet.
  3. On any change, compose and send the config-set prompt and confirm success via a banner.
- **Validation**: Switching autonomy level from `high` → `low` causes the agent to request approval before executing shell commands.

---

## Phase 18: MCP Server Management ❌

- **Goal**: Let users view registered MCP servers, their connection state, and add or remove servers from the native UI.
- **Background**: MCP servers are configured in the gateway's `mcp_servers` config block. Each entry has: `name`, `transport` (`stdio` or `http`), `command`, `args`, `env`, `headers`, `url`, `timeout_ms`. Connection status (connected / failed) is visible in gateway logs and surfaced by the agent when queried.
- **Tasks**:
  1. On section open, send "list MCP servers and their status" and parse the reply into a `[MCPServer]` list. Render each with name, transport type, and connection badge (connected / failed / unknown).
  2. "Add MCP Server" sheet: fields for name, transport selector (stdio / http), command + args (stdio) or URL (http), optional timeout.
  3. Row swipe action: **Remove** (sends "Remove MCP server <name>" to the agent).
  4. Tap a row to view raw config details (read-only).
- **Validation**: Adding a new MCP server entry causes it to appear in the list on refresh; removing it causes it to disappear.

---

## Phase 19: Cost & Usage Monitoring ❌

- **Goal**: Show token usage and cost data so users can monitor spend and set limits.
- **Background**: The gateway has a `cost` config block with `enabled`, `daily_limit`, `monthly_limit`, and `warn_at_percent`. Usage stats can be retrieved from the agent via a `/usage` or "show usage stats" prompt.
- **Tasks**:
  1. On section open, send "show usage statistics" and parse the reply: total tokens today, total tokens this month, estimated cost today/month.
  2. Render a native summary card: today's usage progress bar vs. daily limit, month-to-date bar vs. monthly limit, cost enabled toggle.
  3. Editable fields: daily limit, monthly limit, warn-at percent — each change sends a config-set prompt.
  4. Show a local notification when the gateway reports a cost warning (parse cost-warning events from SSE stream).
- **Validation**: Viewing the Cost section shows non-zero usage data after a conversation; setting a very low daily limit causes a warning banner to appear.

---

## Phase 20: Channel Status & Management ❌

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
