# NullClawUI — Improvement Plan

**Source**: Patterns and practices gleaned from LLMServerControl
**Date**: 2026-04-02

---

## Executive Summary

**Status**: Updated 2026-04-07. Many improvements catalogued in this document have been implemented. NullClawUI now has a comprehensive component library (`Components.swift`), design tokens (`DesignTokens.swift`), a robust network layer (`GatewayClient`), and centralized error handling. The primary remaining gap is **test infrastructure** (missing MockURLProtocol, TestFixtures, MockGatewayServer). This updated plan focuses on completing test infrastructure and addressing remaining code quality items.

---

## 1. Reusable Component Library

### Current State (Updated)

`GlassCard.swift` remains a minimal 13-line container component. However, `Components.swift` (140 lines) now provides a comprehensive reusable component library with:

- `HealthIndicator` enum mapping status to semantic colors
- `StatusBadge` capsule pill with pulsing dot and label
- `StatCard` icon + numeric value + title with health indicator dot and `.contentTransition(.numericText())`
- `LoadingView` centered spinner with optional message
- `EmptyStateView` icon + title + description
- `ActionButton` icon + label quick-action button with tinted background

Components like `TypingIndicator`, `BubbleShape`, `DocumentPickerView`, and the chat `Theme` extension remain embedded inside `ChatView.swift` (now 973 lines).

### Target Pattern (LLMServerControl)

`GlassCard.swift` (118 lines) defines **six reusable components** in a single file, all used across views:

| Component | Description | Used In |
|-----------|-------------|---------|
| `GlassCard` | `.regularMaterial` card container with configurable padding | Dashboard, Quick Actions |
| `StatusBadge` | Capsule pill with pulsing dot + label | Server status everywhere |
| `StatCard` | Icon + numeric value + title with `.contentTransition(.numericText())` | Dashboard grid |
| `LoadingView` | Centered `ProgressView` + message | All loading states |
| `EmptyStateView` | Icon + title + message placeholder | All empty states |
| `RefreshButton` | Button with loading overlay | Settings, detail views |

### Action Items (Updated)

- [x] **Expand component library** → `Components.swift` now exists with HealthIndicator, StatusBadge, StatCard, LoadingView, EmptyStateView, ActionButton
- [x] **Extract from `ChatView.swift`** into `Components.swift`:
  - `TypingIndicator` → standalone component (done)
  - `BubbleShape` → standalone shape (done)
  - `MessageBubble` → standalone view (done)
  - `Theme+Chat.swift` → markdown theme extension (still in ChatView)
- [x] **Add `CopyButton`** — clipboard copy with `.contentTransition(.symbolEffect(.replace))` animation (done)
- [ ] **Add `DashboardStatCard`** — adapted from LLMServerControl with health indicator dot and tap-to-navigate (optional)

---

## 2. Design System Formalism

### Current State (NullClawUI)

No documented spacing scale, corner radius convention, or typography system. Values like padding, corner radii, and font sizes are ad-hoc across views.

### Target Pattern (LLMServerControl)

LLMServerControl uses a consistent (if undocumented) design system:

| Token | Value | Usage |
|-------|-------|-------|
| Corner radius (large) | `16` | Cards, message bubbles |
| Corner radius (medium) | `12` | Action buttons, input fields |
| Corner radius (small) | `8` | Inner content, code blocks |
| Corner radius (tiny) | `4` | Method/status badges |
| Padding (card) | `16` | GlassCard default |
| Padding (section) | `12` | Internal card spacing |
| Padding (tight) | `8` | Input area, message bubbles |
| Padding (minimal) | `4` | Typing indicator dots |
| Spacing (VStack) | `20` | Dashboard sections |
| Spacing (tight VStack) | `12` | Card internals |

### Action Items

- [ ] **Create `DesignTokens.swift`** (or add to `Color+Extensions.swift`) with:
  - `enum CornerRadius` — `.card: 20`, `.medium: 16`, `.small: 12`, `.tiny: 8` (adapt from LLMServerControl but aligned with NullClawUI's existing `.continuous` rounded rects)
  - `enum Spacing` — `.section: 20`, `.card: 16`, `.tight: 12`, `.minimal: 8`
  - Note: NullClawUI already uses `20` for GlassCard corner radius and `18` for padding — maintain consistency with existing choices while establishing the convention.
- [ ] **Audit existing views** for hardcoded spacing values and migrate to the token system.
- [ ] **Standardize `.continuous` vs `.rect`** — NullClawUI uses `RoundedRectangle(cornerRadius:style:.continuous)`, LLMServerControl uses `.rect(cornerRadius:)`. Pick one and be consistent. `.continuous` is more Apple-native; keep it.

---

## 3. Network Layer Architecture

### Current State (NullClawUI)

`GatewayClient.swift` is **corrupted** (contains AGENTS.md content). Based on 35 call sites, the reconstructed API surface is large but the file has no implementation. The `APIClient`-like patterns (generic request helper, typed errors, `EmptyResponse` for void endpoints, `AnyEncodable` type-erasure) are missing.

### Target Pattern (LLMServerControl)

`APIClient.swift` (417 lines) demonstrates clean HTTP client architecture:

```
Private helpers:
  makeURL(path:)              → URL?
  makeRequest(path:method:body:) → URLRequest  (adds Accept, Cache-Control, Bearer token)
  performRequest<T>(_:)       → async throws T  (generic: decode or EmptyResponse)

Public endpoints:
  healthCheck()               → HealthResponse
  getSettings()               → SettingsDTO
  chatCompletionStream(req)   → AsyncThrowingStream<SSEEvent, Error>
  ... (24 endpoints total)
```

Key patterns:
- **`EmptyResponse: Decodable, Sendable`** — stub type for void endpoints
- **`AnyEncodable`** — type-erased `Encodable` wrapper for request bodies
- **`APIErrorType`** — typed error enum with `LocalizedError` conformance
- **URLSession configuration** — `waitsForConnectivity: true`, `timeoutIntervalForRequest: 30`, iOS `multipathServiceType: .handover`

### Action Items

- [ ] **Reconstruct `GatewayClient.swift`** following the LLMServerControl `APIClient` pattern:
  - Private `makeRequest(path:method:body:)` helper that injects Bearer token from Keychain
  - Private `performRequest<T>(_:)` generic response handler
  - `EmptyResponse` stub for void endpoints (tasks/cancel, config/reload)
  - `AnyEncodable` type-erasure wrapper
  - Typed error enum `GatewayClientError` with cases: `.invalidURL`, `.noConnection`, `.httpError(statusCode:message:)`, `.decodingError`, `.networkError`, `.streamingError`
  - URLSession configured with `waitsForConnectivity: true` and appropriate timeouts
- [ ] **Verify all 35 call sites** compile against the reconstructed API surface.
- [ ] **Add `setToken(_:)` and `setBaseURL(_:)`** — these exist in usage but need implementation. Follow LLMServerControl's `@Published var config` pattern (or better, use `@Observable` per AGENTS.md).

---

## 4. SSE Streaming Robustness

### Current State (NullClawUI)

The SSE streaming implementation is inside the corrupted `GatewayClient.swift`. The ChatViewModel has retry logic with exponential backoff (`2^n` seconds, max 3 retries) but the underlying byte-level parser is missing.

### Target Pattern (LLMServerControl)

LLMServerControl's `chatCompletionStream` (lines 231-318) implements a **byte-level SSE parser**:

```swift
func chatCompletionStream(_ request: ChatCompletionRequest) -> AsyncThrowingStream<SSEEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task { @MainActor in
            let (bytes, response) = try await self.session.bytes(for: req)
            var buffer = ""
            var byteBuffer: [UInt8] = []
            for try await byte in bytes {
                if byte == UInt8(ascii: "\n") {
                    // blank line = SSE event boundary → yield SSEEvent
                }
            }
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
    }
}
```

### Action Items

- [ ] **Reconstruct SSE parser** in `GatewayClient.swift` following LLMServerControl's byte-level approach. Ensure:
  - `AsyncThrowingStream<SSEEnvelope, Error>` return type
  - `onTermination` cancels the underlying URLSession task
  - `[DONE]` sentinel handling
  - Proper flush of trailing bytes on stream end
- [ ] **Verify NullClawUI's existing exponential backoff** in `ChatViewModel` works with the reconstructed parser. NullClawUI already has `maxStreamingRetries = 3` and `2^n` backoff — this is actually **more robust** than LLMServerControl (which has no retry). Keep it.
- [ ] **Add 401/413 non-retriable handling** — NullClawUI's ChatViewModel already does this. Confirm it works end-to-end after GatewayClient reconstruction.

---

## 5. Structured Concurrency Patterns

### Current State (NullClawUI)

NullClawUI uses `Task { }` for most async work. Some views do parallel loading but there's no consistent pattern.

### Target Pattern (LLMServerControl)

LLMServerControl's `DashboardView.refreshAll()` demonstrates **`async let` for parallel data loading**:

```swift
private func refreshAll() async {
    await appState.checkHealth()
    if appState.serverStatus.isConnected {
        async let m: () = appState.loadModels()
        async let p: () = appState.loadProviders()
        async let s: () = appState.loadMCPServers()
        async let l: () = appState.loadLogs()
        _ = await (m, p, s, l)
    }
}
```

### Action Items

- [ ] **Audit NullClawUI views** for sequential `await` calls that could use `async let`. Candidates:
  - `GatewayStatusViewModel.refreshAll()` — concurrent health checks (already does this well)
  - `ChatViewModel` loading history + agent card on gateway switch
  - `GatewayDetailView` loading config, MCP, cron, channels, usage on appear
- [ ] **Establish a pattern**: When loading multiple independent data sources on view appear, always use `async let` + tuple await.
- [ ] **Add guard on health** — LLMServerControl only loads data when the server is connected. Apply this pattern to NullClawUI's gateway-dependent views.

---

## 6. View Decomposition

### Current State (NullClawUI)

`ChatView.swift` is 766 lines containing: `ChatView`, `MessageBubble`, `BubbleShape`, `TypingIndicator`, `DocumentPickerView`, and the `Theme` extension. Other views like `CronJobListView` (481 lines) and `MCPServerListView` (469 lines) are similarly large with inline sheet views.

### Target Pattern (LLMServerControl)

`ChatPlaygroundView.swift` (579 lines) contains 8 sub-types, but they are organized with clear `// MARK:` sections and each sub-type is self-contained. More importantly, LLMServerControl uses **private nested structs** within the same file rather than separate files for tightly-coupled components.

`DashboardView.swift` (265 lines) cleanly separates:
- View body (section composition)
- `DashboardStatCard` (private struct)
- `ActionButton` (private struct)
- `HealthIndicator` (enum, non-private)

### Action Items

- [ ] **Split `ChatView.swift`** into logical files:
  - `ChatView.swift` (~400 lines) — main view + input bar + offline banner
  - `MessageBubble.swift` (~150 lines) — `MessageBubble` + `BubbleShape`
  - `TypingIndicator.swift` (~30 lines) — extracted from ChatView
  - `Theme+Chat.swift` (~80 lines) — markdown theme extension
  - `DocumentPickerView.swift` (~30 lines) — UIKit bridge
- [ ] **Split `CronJobListView.swift`** — extract `AddCronJobSheet` and `EditCronJobSheet` into separate views or at minimum separate MARK sections.
- [ ] **Split `MCPServerListView.swift`** — extract `AddMCPServerSheet` and `MCPServerDetailView`.
- [ ] **Establish file size guideline**: No Swift file should exceed ~400 lines. Files exceeding this should be split by component or by concern.

---

## 7. Animation & Symbol Effects

### Current State (NullClawUI)

NullClawUI uses `.spring(duration: 0.35, bounce: 0.2)` consistently (per AGENTS.md). Uses `.contentTransition(.symbolEffect(.replace))` on the send button. The `TypingIndicator` uses `TimelineView(.animation)` with custom triangle-wave math.

### Target Pattern (LLMServerControl)

LLMServerControl demonstrates additional animation patterns worth adopting:

| Pattern | Code | Usage |
|---------|------|-------|
| Pulse on active state | `.symbolEffect(.pulse.wholeSymbol, isActive: isConnected)` | Status dots, live indicators |
| Numeric text transition | `.contentTransition(.numericText())` | Stat card counts |
| Symbol replace | `.contentTransition(.symbolEffect(.replace))` | Copy → checkmark |
| Expand/collapse | `.transition(.opacity.combined(with: .move(edge: .top)))` | Thinking bubbles |
| Spring (quick) | `.spring(response: 0.25)` | Tab switching |
| Spring (standard) | `.spring(response: 0.3)` | Scroll anchoring |

### Action Items

- [ ] **Add `.symbolEffect(.pulse.wholeSymbol, isActive:)`** to:
  - Gateway connection status indicators
  - Live status dots in `GatewayStatusView`
  - Health check indicators
- [ ] **Add `.contentTransition(.numericText())`** to:
  - Gateway status counts (active tasks, cron jobs)
  - Usage stats counters (tokens, cost)
- [ ] **Add `CopyButton`** component with `.contentTransition(.symbolEffect(.replace))` for chat message copy-to-clipboard.
- [ ] **Review transition consistency** — ensure all expand/collapse animations use `.transition(.opacity.combined(with: .move(edge: .top)))` pattern.

---

## 8. Test Infrastructure

### Current State (NullClawUI)

**Zero working unit tests.** Both files in `NullClawUITests/` are corrupted (contain AGENTS.md). Only UI tests in `NullClawUIUITests/` (573 lines) are functional.

### Target Pattern (LLMServerControl)

LLMServerControl has **four test targets** with ~137 tests and ~2,400 lines of test code:

| Target | Infrastructure |
|--------|---------------|
| Unit Tests | `MockURLProtocol` (URLProtocol interceptor), `TestFixtures` (JSON fixture strings) |
| Integration Tests | `MockServer` (actor-based NWListener HTTP server), `XCTAssertSkip` for unavailable server |
| UI Tests | `--ui-testing` launch arguments, `waitForExistence(timeout:)` |

Key patterns:
- **`TestFixtures`** — static JSON strings for every API model with `data(_:)`, `decode(_:from:)`, `encode(_:)` helpers
- **`MockURLProtocol`** — intercepts all URLSession requests; uses `nonisolated(unsafe)` for Swift 6 static state
- **`MockServer`** — full actor-based HTTP server on random port with route handlers matching production API
- **`tearDown()` cleanup** — always deletes Keychain items to prevent state leakage
- **`@MainActor` on test classes** — for testing `@MainActor` view models
- **`XCTAssertSkip`** — integration tests skip gracefully when server is unavailable
- **Port safety assertion** — `assert(!url.contains(":5801"))` prevents tests from hitting production

### Action Items

- [x] **Add `MockURLProtocol`** — for testing GatewayClient without a real server. Register via `URLSessionConfiguration.protocolClasses`. (done)
- [x] **Add `TestFixtures` enum** — static JSON strings for AgentCard, A2AMessage, SSEEnvelope, NullClawTask, HealthResponse, GatewayProfile. (done)
- [x] **Add `MockGatewayServer`** — actor-based mock HTTP server implementing health, agent-card, pair, a2a endpoints. (done)
- [x] **Establish Keychain cleanup** — every test that writes to Keychain must call `KeychainService.deleteToken(for:)` in `tearDown()`. (done)
- [ ] **Reconstruct `NullClawUITests.swift`** with unit tests for JSON-RPC 2.0 serialization, SSE envelope parsing, `ChatMessage` Codable, `AgentCard` Codable, KeychainService read/write. (partial: GatewayClientTests exist)
- [ ] **Reconstruct `GatewayLiveIntegrationTests.swift`** with integration tests for health check, agent card fetch, pairing flow, message send, message stream, task get/cancel.
- [ ] **Add `--uitesting` / `--uitesting-paired`** launch argument handling to `NullClawUIApp` for in-memory SwiftData during UI tests (already done — verify it still works after GatewayClient reconstruction).
- [ ] **Target test coverage**:
  - GatewayClient: every public method (happy path + HTTP error + network error)
  - KeychainService: store, read, delete, move, hasToken
  - GatewayStore: CRUD + active profile selection + URL migration
  - ChatViewModel: send, stream, abort, load history, start new conversation
  - A2AMessage: JSON-RPC serialization, SSE parsing
  - AgentCard: Codable, capabilities parsing

---

## 9. Pull-to-Refresh & Data Loading Patterns

### Current State (NullClawUI)

Some views use `.task` and `.refreshable` but the pattern is inconsistent. No standard template for "load on appear + pull to refresh."

### Target Pattern (LLMServerControl)

Every data-backed view in LLMServerControl follows this exact pattern:

```swift
.refreshable { await appState.loadXxx() }
.task {
    if appState.xxx.isEmpty { await appState.loadXxx() }
}
```

### Action Items

- [ ] **Audit all data-backed views** and ensure they have both `.task` (conditional load on appear) and `.refreshable` (pull-to-refresh).
- [ ] **Apply the conditional pattern** — only load on appear if data is empty; use pull-to-refresh for explicit reload. This avoids redundant network calls on navigation.
- [ ] **Views to audit**:
  - `GatewayDetailView` — sub-pages (cron, MCP, channels, agent config, autonomy, usage)
  - `TaskHistoryView` — conversation records
  - `GatewayStatusView` — multi-gateway health

---

## 10. Error Handling & Presentation

### Current State (NullClawUI)

Errors are handled ad-hoc: `ChatViewModel.errorMessage` triggers an `.alert`. Other ViewModels may throw but there's no centralized error presentation.

### Target Pattern (LLMServerControl)

LLMServerControl uses a centralized pattern:
- `AppState.presentError(_:)` sets `errorMessage` + `showError = true`
- A single `.alert("Error", isPresented: $appState.showError)` in the root view catches everything
- `APIErrorType` implements `LocalizedError` for human-readable messages

### Action Items

- [ ] **Centralize error presentation** in `AppModel`:
  - Add `var presentedError: String?` and `var showError: Bool`
  - Add `func presentError(_ error: Error)` that extracts `LocalizedError.errorDescription`
  - Add a root `.alert("Error", ...)` in `ContentView` or `NullClawUIApp`
- [ ] **Create `GatewayClientError` enum** with `LocalizedError` conformance matching LLMServerControl's `APIErrorType` pattern.
- [ ] **Remove per-view error alerts** in favor of centralized presentation (keep ChatViewModel.errorMessage for chat-specific UX like inline error bubbles if desired).

---

## 11. Accessibility

### Current State (NullClawUI)

Good — every interactive element has `accessibilityLabel` and `accessibilityHint`. Uses `accessibilityIdentifier` for UI testing. Uses `ContentUnavailableView` for empty states.

### Target Pattern (LLMServerControl)

LLMServerControl has **minimal accessibility** — no `accessibilityLabel` or `accessibilityHint` found. NullClawUI is actually **ahead** here.

### Action Items

- [ ] **Maintain NullClawUI's accessibility leadership** — don't regress.
- [ ] **Add accessibility to new components** — any component added from this plan must include `accessibilityLabel` and `accessibilityHint`.
- [ ] **Audit `StatCard`, `StatusBadge`, `ActionButton`** when created — ensure they are accessible by default.
- [ ] **Add `accessibilityValue`** for dynamic content like status indicators ("Connected" / "Disconnected") and numeric counters.

---

## 12. Persistence & Data Layer

### Current State (NullClawUI)

Uses **SwiftData** with CloudKit for `GatewayProfile` and `ConversationRecord`. Has a robust migration chain. `KeychainService` correctly uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and keys by normalized gateway URL.

### Target Pattern (LLMServerControl)

LLMServerControl uses **UserDefaults** for config persistence (a security gap per AGENTS.md). NullClawUI's approach is **superior**.

### Action Items

- [ ] **No changes to persistence strategy** — SwiftData + Keychain is the right approach.
- [ ] **Do NOT adopt** LLMServerControl's UserDefaults pattern for credentials.
- [ ] **Consider adopting** LLMServerControl's `SlotCache` (LRU, max 10 entries) pattern for caching conversation transcripts if memory pressure becomes an issue. NullClawUI already has message trimming (max 200) but no LRU cache.

---

## 13. Navigation Architecture

### Current State (NullClawUI)

Uses `NavigationSplitView` on iPad + `TabView` on iPhone. Has `Tab(role: .search)` for the search tab. Adaptive layout with `horizontalSizeClass`.

### Target Pattern (LLMServerControl)

Uses `.tabViewStyle(.sidebarAdaptable)` with `ForEach` over `AppTab.allCases`. Tab icons change between selected/unselected states. Programmatic tab switching via `appState.selectedTab`.

### Action Items

- [ ] **Consider `.tabViewStyle(.sidebarAdaptable)`** for NullClawUI's iPhone tab bar. This is the iOS 26 native style that adapts between tab bar and sidebar. However, NullClawUI's current approach with explicit `horizontalSizeClass` branching and `NavigationSplitView` on iPad is already solid — evaluate whether `.sidebarAdaptable` simplifies the code or adds complexity.
- [ ] **Add selected/unselected tab icon variants** — LLMServerControl uses `.fill` for selected and non-`.fill` for unselected (e.g., `bubble.left.and.bubble.right` vs `.fill`). NullClawUI already does this partially; make it consistent across all tabs.
- [ ] **Consider a Dashboard tab** — LLMServerControl's Dashboard provides at-a-glance health, stats, and quick actions. NullClawUI could benefit from a similar overview tab showing gateway health, active tasks, recent conversations, and cost summary. This would consolidate information currently spread across Settings, Gateway Detail, and Usage Stats.

---

## Priority Matrix

| Priority | Area | Effort | Impact |
|----------|------|--------|--------|
| **P0** | Reconstruct `GatewayClient.swift` | High | Critical (app won't compile) |
| **P0** | Reconstruct unit tests | High | Critical (zero test coverage) |
| **P1** | Expand component library | Medium | High (reusability, consistency) |
| **P1** | Extract components from ChatView | Medium | High (maintainability) |
| **P2** | Design system tokens | Low | Medium (consistency) |
| **P2** | Structured concurrency audit | Low | Medium (performance) |
| **P2** | Centralize error handling | Medium | Medium (UX consistency) |
| **P3** | View decomposition (large files) | Medium | Low (code hygiene) |
| **P3** | Animation & symbol effects | Low | Low (polish) |
| **P3** | Dashboard tab (new) | High | Medium (feature) |

---

## Files to Create

| File | Purpose |
|------|---------|
| `NullClawUI/Views/Components/StatCard.swift` | Reusable stat card component |
| `NullClawUI/Views/Components/StatusBadge.swift` | Connection status capsule pill |
| `NullClawUI/Views/Components/LoadingView.swift` | Centered loading indicator |
| `NullClawUI/Views/Components/ActionButton.swift` | Quick action button |
| `NullClawUI/Views/Components/CopyButton.swift` | Clipboard copy with animation |
| `NullClawUI/Views/Theme+Chat.swift` | Markdown theme (extracted from ChatView) |
| `NullClawUI/DesignTokens.swift` | Spacing, corner radius, and typography constants |
| `NullClawUITests/TestFixtures.swift` | JSON fixture strings for all models |
| `NullClawUITests/MockURLProtocol.swift` | URLSession request interceptor |
| `NullClawUITests/MockGatewayServer.swift` | Actor-based mock HTTP server |

## Files to Refactor

| File | Action |
|------|--------|
| `NullClawUI/Views/GlassCard.swift` | Expand into full component library |
| `NullClawUI/Views/ChatView.swift` | Extract MessageBubble, TypingIndicator, Theme, BubbleShape |
| `NullClawUI/Views/CronJobListView.swift` | Extract AddCronJobSheet, EditCronJobSheet |
| `NullClawUI/Views/MCPServerListView.swift` | Extract AddMCPServerSheet, MCPServerDetailView |
| `NullClawUI/Networking/GatewayClient.swift` | Full reconstruction (currently corrupted) |
| `NullClawUITests/NullClawUITests.swift` | Full reconstruction (currently corrupted) |
| `NullClawUITests/GatewayLiveIntegrationTests.swift` | Full reconstruction (currently corrupted) |
