# NullClawUI — Agents & Roles

## Platform Baseline

| Property | Value |
|---|---|
| **iOS Deployment Target** | iOS 26.0 |
| **Swift Version** | Swift 6 (strict concurrency) |
| **UI Paradigm** | Liquid Glass (iOS 26 materials) |
| **Xcode Version** | Xcode 26+ |
| **Project Generation** | xcodegen (`project.yml`) |

All agents operate under **Swift 6 strict concurrency** (`-strict-concurrency=complete`). Every network call must be `async/await`-based; no `DispatchQueue` usage. All state mutations touching the UI must happen on `@MainActor`.

---

## Roles

### Swift/SwiftUI Architect
- **Focus**: App lifecycle, navigation (`NavigationStack` with `NavigationPath`), and state management using the `@Observable` macro.
- **Goal**: Clean, idiomatic SwiftUI structure.
- **Notes**:
  - Target iOS 26 exclusively — use new APIs freely; no `@available` guards needed.
  - Apply **Liquid Glass** materials for surfaces, cards, and overlaid controls.
  - Animate with `withAnimation(.spring(duration: 0.35, bounce: 0.2))`.

### Network & Protocol Specialist
- **Focus**: `URLSession` configuration, SSE streaming via `AsyncSequence`, JSON-RPC 2.0 for the A2A protocol, REST API calls (`/api/*`).
- **Goal**: Robust, error-resistant communication with the NullClaw Gateway.
- **A2A Request Shape**:
  ```json
  {
    "jsonrpc": "2.0",
    "id": "<uuid>",
    "method": "message/send",
    "params": { "message": { "role": "user", "parts": [{ "text": "…" }] } }
  }
  ```
  Streaming uses `method: "message/stream"` and returns SSE lines.
- **REST API**: `GatewayClient` exposes typed methods for `/api/cron`, `/api/mcp`, `/api/channels`, `/api/config/*`, `/api/doctor`, etc.
- **Notes**:
  - `NSAllowsLocalNetworking: true` in Info.plist for development HTTP.
  - Exponential-backoff reconnect for dropped SSE streams (max 3 retries).
  - Endpoints: `GET /health`, `GET /.well-known/agent-card.json`, `POST /pair`, `POST /a2a`, `GET /tasks/{id}`, `POST /tasks/{id}/cancel`, plus the full `/api/*` surface.

### Security & Identity Guard
- **Focus**: Pairing flow, Bearer token handling, and secure storage in the system Keychain.
- **Goal**: Zero-leak credential management.
- **Keychain Keying**: Each credential keyed by the normalized gateway base URL (scheme + host + port).
- **Notes**:
  - Use `kSecAttrAccessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
  - On token deletion / re-pair, explicitly delete the old Keychain item before writing a new one.

### UX/UI Designer (Apple Standard)
- **Focus**: HIG compliance, Liquid Glass design language, iconography, animations, and accessibility.
- **Notes**:
  - All interactive elements must have `accessibilityLabel` and `accessibilityHint`.
  - Accent color dynamically sourced from `agent-card.json`; falls back to system tint.

### Validation & QA Engineer
- **Focus**: Unit tests (XCTest), network mocking, and integration testing.
- **Test Targets**:
  - `NullClawUITests` — unit tests (JSON-RPC parsing, Keychain, REST API models)
  - `NullClawUIUITests` — UI tests (XCUIApplication)
- **Build & Test Commands**:
  ```bash
  # Unit tests
  xcodebuild test -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'

  # Build only (no simulator launch)
  xcodebuild build-for-testing -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17'
  ```

### Test Coverage Mandate

**Every code change must be accompanied by tests.** No exceptions.

- **Behavior changes** (new methods, changed logic): add or update `XCTestCase` tests that directly exercise the changed code path.
- **Bug fixes**: add a regression test that would have caught the original failure.
- **Pure UI-layout changes**: add a comment: `// NOTE: No unit test — pure layout change; covered by visual inspection in Simulator.`
- **New ViewModel methods**: always test both the happy path and key failure/edge cases. For `@MainActor` methods use `@MainActor func test...() async`.
- **Keychain operations**: every method that reads or writes to the Keychain must be tested. Always call `KeychainService.deleteToken(for:)` in `tearDown()`.

### Code Quality Requirements

All changes must pass these checks:

1. **SwiftLint** (`swiftlint --strict`) — zero warnings
2. **SwiftFormat** (`swiftformat --lint .`) — zero violations
3. **Periphery** (`periphery scan`) — zero unused code warnings (run with `RUN_PERIPHERY=1`)
4. **Build** — `xcodebuild build-for-testing` succeeds with no errors
