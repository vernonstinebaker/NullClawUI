# NullClawUI — Development Plan

A Swift/SwiftUI app for interacting with a NullClaw AI Gateway using the A2A (Agent-to-Agent) protocol.

## Platform & Tech Stack

| Property | Value |
|---|---|
| **iOS / iPadOS Target** | 26.0 (no backward compatibility) |
| **macOS Target** | 26.0 Tahoe (future — see Phase 13) |
| **Swift Version** | Swift 6 (strict concurrency) |
| **UI Paradigm** | Liquid Glass (iOS 26 material system) |
| **State Management** | `@Observable` macro (Swift 6) |
| **Networking** | URLSession + AsyncSequence for SSE |
| **Persistence** | UserDefaults (JSON) + System Keychain — see Phase 13 for planned migration |
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

## Phase 12: LAN Gateway Discovery ❌

- **Goal**: Auto-discover NullClaw gateways on the local network without manual URL entry.
- **Tasks**:
  1. Implement `GatewayDiscoveryModel` using `Network.framework` (`NWBrowser`).
  2. Surface discovered gateways in the "Add Gateway" sheet as a tap-to-add list.
  3. Fall back gracefully to manual URL entry if no gateways are found.
  4. Add `NSBonjourServices` key to `Info.plist`.
- **Validation**: With NullClaw running on the same LAN, the app discovers it without typing the IP address.

---

## Phase 13: macOS Menubar App ❌

- **Goal**: A native macOS menubar app that shares gateway configuration and conversation history with the iOS app via iCloud (Phase 11 is a prerequisite).
- **Tasks**:
  1. Add a macOS target to the Xcode project (menubar app, `LSUIElement = YES`).
  2. Share the SwiftData `ModelContainer` (App Group container, same CloudKit database).
  3. Implement a compact `NSStatusItem` popover with chat input + last-N messages.
  4. Reuse `GatewayClient`, `ChatViewModel`, and SSE streaming logic (already platform-agnostic).
  5. Support multiple gateways via the same `GatewayStore`.
  6. Keychain tokens stored separately per device (same key scheme, not synced).
- **Validation**: Chat on iOS, see the same conversation on macOS within one sync cycle.

---

## Phase 14: Voice Input ❌

- **Goal**: Let users dictate messages using their voice.
- **Tasks**:
  1. Add push-to-talk mic button to the chat input bar.
  2. Use `SFSpeechRecognizer` + `AVAudioEngine` for on-device transcription.
  3. On recognition result, populate the input field (let user review before sending).
  4. Request `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` permissions.
- **Validation**: User can tap mic, speak a sentence, and see it transcribed into the input field.

---

## Phase 15: Health Monitoring & Reconnect ❌

- **Goal**: Robust real-time gateway health tracking with automatic reconnect.
- **Tasks**:
  1. Implement `GatewayHealthMonitor` — periodic `GET /health` polling (default 30 s).
  2. Pause polling in background; resume on foreground (`scenePhase` observer already in place).
  3. Surface health failure as a non-intrusive banner (not a modal alert).
  4. On reconnect success, automatically resume any interrupted SSE stream.
- **Validation**: Killing and restarting NullClaw while the app is open causes the status badge to go red then green automatically.

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
