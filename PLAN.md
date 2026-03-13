# NullClawUI — Agents & Roles

## Platform Baseline

| Property | Value |
|---|---|
| **iOS Deployment Target** | iOS 26.0 |
| **macOS Deployment Target** | macOS 26.0 (Tahoe) |
| **Swift Version** | Swift 6 (strict concurrency) |
| **UI Paradigm** | Liquid Glass (iOS 26 / visionOS-aligned materials) |
| **Xcode Version** | Xcode 26+ |
| **NullClaw API Reference** | See PLAN.md Phase 0 and the NullClaw Gateway OpenAPI spec at the configured gateway URL (/openapi.json). |

All agents operate under **Swift 6 strict concurrency** (-strict-concurrency=complete). Every network call must be async/await-based; no DispatchQueue usage. All state mutations touching the UI must happen on @MainActor.

---

## Roles

### Swift/SwiftUI Architect
- **Focus**: App lifecycle, navigation (NavigationStack / NavigationSplitView), and state management using the **Swift @Observable macro** (iOS 26 / Swift 6 preferred over legacy ObservableObject).
- **Goal**: Clean, idiomatic SwiftUI structure that is easy to extend phase-by-phase.
- **Notes**:
  - Target iOS 26 exclusively — use new APIs freely; no @available guards needed.
  - Favor NavigationSplitView for iPad; NavigationStack for iPhone compact-width.
  - Apply **Liquid Glass** materials (GlassEffect, .glassBackgroundEffect()) for surfaces, cards, and overlaid controls.

### Network & Protocol Specialist
- **Focus**: URLSession configuration, SSE (Server-Sent Events) streaming via AsyncSequence, JSON-RPC 2.0 serialization for the A2A protocol.
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
  Streaming uses method: "message/stream" and returns SSE lines of the form data: { …TaskStatusUpdateEvent… }.
- **Notes**:
  - Use NSAllowsLocalNetworking: true in Info.plist to permit plain-HTTP http:// gateway connections during development. Production should use HTTPS.
  - Implement exponential-backoff reconnect for dropped SSE streams (max 3 retries).
  - Endpoints: GET /health, GET /.well-known/agent-card.json, POST /pair, POST /a2a, GET /tasks/{id}, POST /tasks/{id}/cancel.

### Security & Identity Guard
- **Focus**: Pairing flow, Bearer token handling, and secure storage in the system Keychain.
- **Goal**: Zero-leak credential management.
- **Keychain Keying Strategy**: Each stored credential must be keyed by the normalized gateway base URL (scheme + host + port), allowing the user to connect to multiple gateways without collision. Example key: nullclaw.token.https://my-server.local:5111.
- **Notes**:
  - Use kSecAttrAccessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly.
  - On token deletion / re-pair, explicitly delete the old Keychain item before writing a new one.

### UX/UI Designer (Apple Standard)
- **Focus**: HIG compliance, **Liquid Glass** design language, iconography, animations, and accessibility.
- **Goal**: A professional, Apple-native feel targeting iOS 26 and iPadOS 26.
- **Liquid Glass Guidelines**:
  - Use .glassBackgroundEffect() for floating panels, modals, and overlaid toolbars.
  - Use GlassEffect with .regularMaterial for card surfaces.
  - Animate with withAnimation(.spring(duration: 0.35, bounce: 0.2)).
  - Accent color should be dynamically sourced from agent-card.json once fetched; fall back to system tint.
- **Notes**:
  - iPad layout uses NavigationSplitView (sidebar = task list, detail = chat). Defined in Phase 6 but the architecture must support it from Phase 1.
  - All interactive elements must have accessibilityLabel and accessibilityHint.

### Validation & QA Engineer
- **Focus**: Unit tests (XCTest / Swift Testing framework), network mocking, and integration testing against a running NullClaw instance.
- **Goal**: Verify that every phase of PLAN.md is fully functional and regression-free before advancing.
- **How to Run NullClaw Locally**: A NullClaw Gateway instance must be running at http://localhost:5111. Refer to the NullClaw repository (README.md → "Running Locally") for setup steps.
- **Test Targets**:
  - NullClawUI — main app target.
  - NullClawUITests — XCTest unit tests (JSON-RPC parsing, Keychain read/write, SSE token parsing).
  - NullClawUIUITests — UI tests (XCUIApplication).
- **Build & Test Commands**:
  ```bash
  # Unit tests
  xcodebuild test -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.2'

  # UI tests
  xcodebuild test -scheme NullClawUI -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.2' -only-testing:NullClawUIUITests
  ```

### Test Coverage Mandate

**Every code change must be accompanied by tests.** No exceptions.

- **Behavior changes** (new methods, changed logic): add or update `XCTestCase` tests in `NullClawUITests/NullClawUITests.swift` that directly exercise the changed code path.
- **Bug fixes**: add a regression test that would have caught the original failure.
- **Logging-only / pure UI-layout changes**: formal tests may not be practical. Add a comment near the change:
  ```swift
  // NOTE: No unit test — pure layout change; covered by visual inspection in Simulator.
  ```
- **New ViewModel methods**: always test both the happy path and the key failure/edge cases. For `@MainActor` methods use `@MainActor func test...() async`.
- **Keychain operations**: every method that reads or writes to the Keychain must be tested via `KeychainService` directly. Always call `KeychainService.deleteToken(for:)` in `tearDown()` to avoid state leakage between tests.
- Regression tests must include a comment citing the bug they guard, e.g.:
  ```swift
  // Regression: unpairGateway(_:) on an inactive profile must not clear appModel.isPaired.
  ```
