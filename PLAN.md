# NullClawUI — Development Plan

A Swift/SwiftUI app for interacting with a NullClaw AI Gateway using the A2A (Agent-to-Agent) protocol.

## Platform & Tech Stack

| Property | Value |
|---|---|
| **iOS / iPadOS Target** | 26.0 (no backward compatibility) |
| **macOS Target** | 26.0 Tahoe (optional Mac Catalyst) |
| **Swift Version** | Swift 6 (strict concurrency) |
| **UI Paradigm** | Liquid Glass (iOS 26 material system) |
| **State Management** | `@Observable` macro (Swift 6) |
| **Networking** | `URLSession` + `AsyncSequence` for SSE |
| **Keychain** | `Security` framework (keyed per gateway URL) |
| **Markdown** | `swift-markdown-ui` (Phase 6) |
| **Xcode** | 26+ |
| **Preferred Simulator** | `iPhone 17 Pro Max, iOS 26.0` |

---

## Phase 0: Project Setup (The "Ground")

- **Goal**: Establish the Xcode project structure, dependencies, entitlements, and version control before writing any app code.
- **Tasks**:
  - Create Xcode project: `NullClawUI`, targets `NullClawUI` (app), `NullClawUITests` (unit), `NullClawUIUITests` (UI).
  - Set deployment target iOS 26.0 on all targets.
  - Enable Swift 6 language mode and `-strict-concurrency=complete` on all targets.
  - Add `Info.plist` key: `NSAllowsLocalNetworking = true` (under `NSAppTransportSecurity`) to allow plain-HTTP connections to `http://localhost`.
  - Add Keychain Sharing entitlement: `com.nullclaw.nullclawui`.
  - Add Swift Package dependency: `swift-markdown-ui` (for Phase 6; add early to avoid project file churn).
  - Create folder structure:
    ```
    NullClawUI/
      App/            # @main entry point, AppModel
      Views/          # SwiftUI screens
      ViewModels/     # @Observable view models
      Networking/     # URLSession, A2A client, SSE parser
      Security/       # KeychainService
      Models/         # Codable types (AgentCard, Task, Message…)
      Resources/      # Assets.xcassets, Info.plist
    NullClawUITests/
    NullClawUIUITests/
    ```
  - `git init`, create `.gitignore` and `README.md`.
- **Validation**: `xcodebuild build -scheme NullClawUI -destination 'generic/platform=iOS Simulator'` succeeds with zero warnings.

---

## Phase 1: Foundation & Discovery (The "Hello World")

- **Goal**: Confirm the app can "see" a NullClaw instance.
- **Features**:
  - Settings screen with a URL input field (default: `http://localhost:5111`).
  - `GET /health` connectivity check on app foreground / manual refresh.
  - `GET /.well-known/agent-card.json` to display agent name, version, and capabilities.
  - A status indicator using a Liquid Glass badge: green "Online" / red "Offline".
- **A2A Note**: `agent-card.json` shape:
  ```json
  { "name": "NullClaw", "version": "1.0.0", "capabilities": { … } }
  ```
- **Implementation Note**: `NSAllowsLocalNetworking` must already be set (Phase 0) or HTTP requests will fail on-device.
- **Validation**: App shows a green "Online" badge and the agent's name from `agent-card.json`.

---

## Phase 2: Secure Pairing (The "Key")

- **Goal**: Establish a trusted connection and persist credentials.
- **Features**:
  - Pairing UI: a 6-digit numeric code entry (user-chosen, not TOTP; codes are issued by the NullClaw admin interface).
  - `POST /pair` with body `{ "code": "123456" }` returns `{ "token": "<bearer>" }`.
  - Secure storage of the token in the system Keychain, keyed by normalized gateway URL.
  - Auto-load token on launch; show "Paired" status in settings.
  - "Unpair" action: deletes the Keychain item and resets to the pairing screen.
- **Validation**: App successfully pairs once and remembers the connection across restarts. Re-launching without unpairing skips the pairing screen.

---

## Phase 3: Simple Interaction (The "Chat")

- **Goal**: Send a prompt and receive a complete (non-streaming) response.
- **Features**:
  - Chat UI: `ScrollView` with message bubbles + `TextEditor` input bar (Liquid Glass toolbar).
  - `POST /a2a` with JSON-RPC method `message/send`:
    ```json
    {
      "jsonrpc": "2.0",
      "id": "<uuid>",
      "method": "message/send",
      "params": {
        "message": { "role": "user", "parts": [{ "text": "Hello" }] }
      }
    }
    ```
  - Decode the response `Task` object and display the assistant's reply text.
  - Show a loading indicator (Liquid Glass spinner) while awaiting the response.
- **Validation**: User can send "Hello" and see the agent's reply rendered in the chat view.

---

## Phase 4: Real-time Streaming (The "Life")

- **Goal**: Update the UI token-by-token as the agent generates a response.
- **Features**:
  - `POST /a2a` with JSON-RPC method `message/stream` (same request shape as Phase 3).
  - `AsyncSequence`-based SSE parser: splits on `\n\n`, strips `data: ` prefix, decodes `TaskStatusUpdateEvent` JSON.
  - "Thinking…" state displayed while `status == "working"`.
  - Partial token rendering: append each text chunk to the in-progress message bubble.
  - **Reconnect strategy**: on stream drop, retry up to 3 times with exponential backoff (1 s, 2 s, 4 s) before surfacing an error.
- **Validation**: User sees the response appearing word-by-word. A simulated network drop triggers visible retry behaviour.

---

## Phase 5: Task Management & History (The "Memory")

- **Goal**: Allow users to browse and manage previous interactions.
- **Features**:
  - Sidebar / List view populated by `GET /tasks` (REST endpoint returning a JSON array of `Task` summaries).
  - Tapping a task calls `GET /tasks/{id}` (REST) and re-populates the chat view with the full message history.
  - "Abort" button (shown only while streaming) calls `POST /tasks/{id}/cancel` (REST).
  - Tasks are cached locally in-memory for the session; no persistent local store in this phase.
- **Note**: All task history endpoints are REST (not JSON-RPC). Only `message/send` and `message/stream` are JSON-RPC via `POST /a2a`.
- **Validation**: User can stop a response mid-stream via the Abort button, and can tap an old task in the sidebar to reload its conversation.

---

## Phase 6: Polish & Native Integration (The "Experience")

- **Goal**: Make it feel like a first-class Apple application.
- **Features**:
  - **Markdown rendering** using `swift-markdown-ui` for assistant responses.
  - **Multi-modal input**: attach images/files via the `/a2a` protocol (`parts` array with `{ "type": "file", … }`).
  - **Adaptive accent color**: parse `accentColor` from `agent-card.json`; fall back to system tint.
  - **iPadOS layout**: `NavigationSplitView` with sidebar (task list) and detail (chat). `NavigationStack` for iPhone compact width.
  - **Light/Dark mode**: fully system-adaptive; no hard-coded colors.
  - **Accessibility**: all controls have `accessibilityLabel` and `accessibilityHint`; VoiceOver tested.
- **Validation**: App renders markdown correctly in the simulator. Accent color updates after connecting to a new gateway. VoiceOver can navigate and send a message without visual assistance.
