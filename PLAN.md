# NullClawUI — UI Redesign Plan

**Date**: 2026-04-05
**Inspiration**: LLMServerControl (~/Programming/Swift/llmservercontrol)
**Approach**: Test-Driven Development (TDD) — every phase ships with tests first

---

## 1. Vision

Transform NullClawUI from a "settings-first" app into a **server-management-first** app with a card-based dashboard, mirroring the visual quality of LLMServerControl while preserving NullClaw's multi-gateway, A2A-driven architecture.

### Key Changes

| Current | New |
|---|---|
| Tab 1: **Chat** | Tab 1: **Servers** (card-based dashboard) |
| Tab 2: **History** (all gateways, standalone) | Tab 2: **Chat** (with per-gateway history sidebar) |
| Tab 3: **Settings** (gateway list) | Tab 3: **Search** |
| History is global, gateway-agnostic | History is scoped to the active gateway |
| Gateway detail is a `List` inside Settings | Gateway detail is a tappable **Server Card** → detail view |
| `PairedSettingsView` is a flat list | `ServersView` is a card grid with status, health, quick actions |

### Design Language

Adopt LLMServerControl's patterns where they improve on NullClawUI's existing components:

| Element | LLMServerControl Pattern | NullClawUI Adaptation |
|---|---|---|
| Cards | `GlassCard` with `.regularMaterial`, 16pt radius | Existing `GlassCard` already uses `.glassEffect(.regular)` — update to match 16pt radius, `.regularMaterial` background |
| Status dots | 12pt pulsing dot with `.symbolEffect(.pulse)` | Upgrade existing `StatusBadge` dot to 12pt + pulse animation |
| Stat cards | 2-column `LazyVGrid`, tappable, health dot in corner | Upgrade existing `StatCard` to match LLMServerControl's `DashboardStatCard` |
| Action buttons | Icon + label, `.opacity(0.12)` tinted background, 12pt radius | Existing `ActionButton` — update to match |
| Typography | System font, `.title2`/`.subheadline`/`.caption` hierarchy | Align `DesignTokens` font sizes to match |
| Empty states | Large icon (48pt) + headline + subtitle | Upgrade existing `ContentUnavailableView` usage |

---

## 2. Target Tab Structure

### iPhone (TabView)

| Tab | Value | Icon | Content |
|---|---|---|---|
| **Servers** | `.servers` | `server.rack` | `ServersView` — card grid of gateway profiles |
| **Chat** | `.chat` | `bubble.left.and.bubble.right.fill` | `ChatView` — chat with per-gateway history drawer |
| **Search** | `.search` | `magnifyingglass` (role: `.search`) | `SearchResultsView` |

### iPad (NavigationSplitView)

- **Sidebar**: Server list (compact cards) + search bar
- **Detail**: Selected server's dashboard OR Chat view

---

## 3. ServersView — Card-Based Dashboard

### Layout

```
ScrollView {
    // Header
    Text("Servers")
        .font(.largeTitle.bold())
        .padding(.horizontal)
        .padding(.top)

    // Server cards (vertical stack, one per gateway)
    ForEach(store.profiles.sorted(by: \.sortOrder)) { profile in
        ServerCard(profile: profile)
            .padding(.horizontal)
            .padding(.bottom, DesignTokens.Spacing.minimal)
    }

    // Quick Actions (if multiple gateways)
    if store.profiles.count > 1 {
        QuickActionsCard()
            .padding(.horizontal)
            .padding(.vertical, DesignTokens.Spacing.standard)
    }

    // Add Server button
    AddServerButton()
        .padding(.horizontal)
        .padding(.bottom)
}
```

### ServerCard Component

Each card is a **tappable GlassCard** showing:

```
┌─────────────────────────────────────────────┐
│  🟢  TestAgent                        ›    │
│      http://localhost:5111                  │
│                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │  📡  5   │  │  🤖  12  │  │  ⏱️  3   │  │
│  │  Tasks   │  │  Models  │  │  Cron    │  │
│  └──────────┘  └──────────┘  └──────────┘  │
│                                             │
│  Last checked: 2m ago                       │
└─────────────────────────────────────────────┘
```

**Top row**: Pulsing status dot (12pt, green/red/orange) + gateway name (`.title3`, semibold) + chevron (`chevron.right`, secondary)

**URL**: Monospaced, `.caption`, `.secondary`

**Mini stats** (3-column `LazyVGrid`):
- **Tasks** — active conversation count for this gateway (from `ConversationStore`)
- **Models** — model name from agent card (truncated)
- **Cron** — cron job count (from `CronJobViewModel` or cached)

**Footer**: "Last checked: X ago" with clock icon, `.caption2`, `.tertiary`

**Tap action**: Pushes `GatewayDetailView` via `NavigationLink`

### ServerCard Health States

| State | Dot Color | Card Border | Condition |
|---|---|---|---|
| Online | `.green` | None | Health check returned 200 |
| Offline | `.red` | `.red.opacity(0.3)` | Health check failed |
| Checking | `.orange` | None | Health check in progress |
| Unknown | `.gray` | None | Never checked |

---

## 4. ChatView — With Per-Gateway History

### Current Problem

History is a standalone tab showing **all** conversations across **all** gateways. This is noisy and doesn't match how users think (they think "what did I chat about with *this* gateway?").

### New Design

The Chat tab gets a **history drawer** that shows only conversations for the **currently active gateway**:

```
┌─────────────────────────────────────┐
│  [Model: Claude Sonnet 4    ▼]     │  ← Model selector (if applicable)
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐   │
│  │  💬  Previous conversations  │   │  ← Collapsible history section
│  │  ─────────────────────────  │   │
│  │  Summarize alerts      2m   │   │
│  │  Check server health   1h   │   │
│  │  Deploy config         3h   │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │  You: Hello!                │   │
│  └─────────────────────────────┘   │
│  ┌─────────────────────────────┐   │
│  │  Agent: Hi there!           │   │
│  └─────────────────────────────┘   │
│                                     │
├─────────────────────────────────────┤
│  [Type a message...]          [↑]  │
└─────────────────────────────────────┘
```

**History section**:
- Collapsible (tap header to expand/collapse, spring-animated)
- Shows only `ConversationRecord`s where `gatewayProfileID == activeProfile.id`
- Each row: title + relative timestamp
- Tap a row: loads that conversation into the chat area
- "Clear History" button in the header (destructive confirmation)

**Implementation**: Add a `@State private var showHistory: Bool = false` to `ChatView`. The history section is a `GlassCard` that appears above the message list when expanded.

---

## 5. Implementation Phases (TDD)

Each phase follows: **Write failing test → Implement → Green → Refactor**.

### Phase 1: Foundation — Design Token Updates & Component Tests

**Goal**: Update `DesignTokens` and reusable components to match LLMServerControl's visual language. All changes are pure UI — no behavioral changes.

**Files changed**:
- `DesignTokens.swift` — update values
- `Components.swift` — upgrade `StatusBadge`, `StatCard`, `ActionButton`
- `GlassCard.swift` — update to match LLMServerControl's pattern

**New tests** (`NullClawUITests/ComponentTests.swift`):
```swift
// StatusBadge tests
func testStatusBadgeShowsPulsingDotWhenOnline()
func testStatusBadgeShowsRedDotWhenOffline()
func testStatusBadgeShowsOrangeDotWhenChecking()

// StatCard tests
func testStatCardDisplaysIconValueAndTitle()
func testStatCardHealthDotAppearsWhenUnhealthy()
func testStatCardIsTappable()

// ActionButton tests
func testActionButtonShowsIconAndLabel()
func testActionButtonHasTintedBackground()
func testActionButtonTriggersActionOnTap()

// GlassCard tests
func testGlassCardHasRegularMaterialBackground()
func testGlassCardHasCorrectCornerRadius()
```

**DesignToken changes**:
```swift
// BEFORE → AFTER
CornerRadius.card: 20 → 16
CornerRadius.medium: 12 → 12 (unchanged)
Spacing.section: 24 → 20
Spacing.card: 20 → 16
```

**Duration**: 1-2 hours

---

### Phase 2: ServerCard Component & Tests

**Goal**: Build the `ServerCard` view component with full test coverage.

**New files**:
- `NullClawUI/Views/ServerCard.swift`

**Files changed**:
- `NullClawUI/Views/PairedSettingsView.swift` → renamed to `ServersView.swift`

**New tests** (`NullClawUITests/ServerCardTests.swift`):
```swift
func testServerCardShowsGatewayName()
func testServerCardShowsURL()
func testServerCardShowsOnlineStatus()
func testServerCardShowsOfflineStatus()
func testServerCardShowsCheckingStatus()
func testServerCardTappingPushesDetailView()
func testServerCardShowsMiniStats()
func testServerCardShowsLastCheckedTime()
func testServerCardBorderWhenOffline()
```

**ServerCard API**:
```swift
struct ServerCard: View {
    let profile: GatewayProfile
    let healthStatus: ConnectionStatus
    let lastChecked: Date?
    let taskCount: Int
    let cronJobCount: Int
    let onTap: () -> Void

    var body: some View { ... }
}
```

**Duration**: 2-3 hours

---

### Phase 3: ServersView — Replace PairedSettingsView

**Goal**: Replace the current `PairedSettingsView` (flat list) with `ServersView` (card-based dashboard).

**Files changed**:
- `MainTabView.swift` — replace Settings tab with Servers tab
- `PairedSettingsView.swift` → `ServersView.swift` (rename + rewrite)
- `ContentView.swift` — update routing references

**New tests** (`NullClawUIUITests/ServersViewUITests.swift`):
```swift
func testServersTabIsFirstTab()
func testServersViewShowsCardForEachGateway()
func testServersViewShowsEmptyStateWhenNoGateways()
func testTappingServerCardOpensDetailView()
func testAddServerButtonOpensAddSheet()
func testServerCardsOrderedByName()
```

**Tab order change**:
```swift
// BEFORE
Tab { Chat, History, Settings, Search }
// AFTER
Tab { Servers, Chat, Search }
```

**Duration**: 2-3 hours

---

### Phase 4: Per-Gateway History in ChatView

**Goal**: Move history from a standalone tab into the Chat view, scoped to the active gateway.

**Files changed**:
- `ChatView.swift` — add collapsible history section
- `TaskHistoryView.swift` — simplify (now only used from ChatView's history drawer)
- `MainTabView.swift` — remove History tab

**New tests** (`NullClawUITests/ChatHistoryTests.swift` + `NullClawUIUITests/ChatHistoryUITests.swift`):
```swift
// Unit tests
func testHistoryFiltersByActiveGateway()
func testHistorySectionIsCollapsible()
func testHistoryShowsOnlyActiveGatewayConversations()

// UI tests
func testHistorySectionAppearsInChatView()
func testTappingHistoryRowLoadsConversation()
func testHistorySectionCanBeCollapsed()
func testHistoryTabIsRemovedFromTabBar()
```

**Implementation details**:
- Add `@State private var showHistory: Bool = false` to `ChatView`
- Filter `ConversationRecord` by `gatewayProfileID == store.activeProfile?.id`
- History section is a `GlassCard` above the message list
- Tap header toggles `showHistory` with spring animation
- Each row taps into `viewModel.openRecord(record, gatewayViewModel:)`

**Duration**: 3-4 hours

---

### Phase 5: GatewayDetailView — Card-Aligned Detail View

**Goal**: Update `GatewayDetailView` to match the card-based aesthetic. Currently it's a plain `List` — convert to a `ScrollView` with `GlassCard` sections.

**Files changed**:
- `GatewayDetailView.swift` — rewrite from `List` to `ScrollView + GlassCard` sections

**New tests** (`NullClawUIUITests/GatewayDetailUITests.swift` — extend existing):
```swift
func testDetailViewUsesCardLayout()
func testDetailViewShowsAgentInfoCard()
func testDetailViewShowsCapabilitiesCard()
func testDetailViewShowsGatewayInfoCard()
func testDetailViewShowsManagementLinksCard()
func testDetailViewManagementLinksNavigate()
```

**Layout change**:
```
// BEFORE: List { Section { ... } Section { ... } }
// AFTER:
ScrollView {
    VStack(spacing: DesignTokens.Spacing.card) {
        AgentInfoCard(agentCard: agentCard)
        CapabilitiesCard(capabilities: agentCard?.capabilities)
        GatewayInfoCard(profile: profile, health: healthStatus)
        ManagementLinksCard(profile: profile)
        EditButtonCard()
        PairUnpairCard(profile: profile)
    }
    .padding(.horizontal)
    .padding(.vertical)
}
```

**Duration**: 3-4 hours

---

### Phase 6: iPad Adaptive Layout

**Goal**: Ensure the new layout works beautifully on iPad with `NavigationSplitView`.

**Files changed**:
- `MainTabView.swift` — iPad layout update

**iPad sidebar** (replaces the Servers tab):
```
Sidebar {
    // Header
    Text("Servers")
        .font(.headline)
        .padding()

    // Server list (compact cards)
    ForEach(store.profiles) { profile in
        CompactServerRow(profile: profile, health: ...)
    }

    Divider()

    // Add server button
    Button { ... } label: { Label("Add Server", systemImage: "plus") }
}
```

**iPad detail** (replaces the Servers card grid):
- Default: Shows the active server's `GatewayDetailView`
- When chat is selected: Shows `ChatView`

**New tests** (`NullClawUIUITests/iPadLayoutTests.swift`):
```swift
func testiPadShowsSidebarWithServerList()
func testTappingServerInSidebarShowsDetail()
func testiPadChatViewAccessibleFromSidebar()
```

**Duration**: 2-3 hours

---

### Phase 7: Polish & Regression Testing

**Goal**: Ensure all existing UI tests pass, fix any visual regressions, add missing accessibility labels.

**Tasks**:
1. Run full UI test suite — all must pass
2. Verify all accessibility labels are present
3. Verify Dark Mode rendering
4. Verify Dynamic Type support
5. Add snapshot tests for key views (optional)

**Existing tests to update**:
- `GatewayDetailSubPageTests` — already updated (Live Status removed, Cancel fixed)
- `GatewaySwitcherTests` — already updated
- `PairedUITests` — may need updates if tab order changed

**New regression tests**:
```swift
// NullClawUITests/RegressionTests.swift
func testTabOrderIsServersChatSearch()
func testHistoryIsScopedToActiveGateway()
func testServerCardShowsCorrectHealthStatus()
```

**Duration**: 2-3 hours

---

## 4. File Change Summary

| File | Action | Phase |
|---|---|---|
| `DesignTokens.swift` | Modify values | 1 |
| `Components.swift` | Upgrade components | 1 |
| `GlassCard.swift` | Update to match LLMServerControl | 1 |
| `ServerCard.swift` | **New** | 2 |
| `ServersView.swift` | **New** (replaces `PairedSettingsView.swift`) | 3 |
| `PairedSettingsView.swift` | **Delete** (replaced by ServersView) | 3 |
| `MainTabView.swift` | Modify tab order and content | 3, 4, 6 |
| `ContentView.swift` | Update routing references | 3 |
| `ChatView.swift` | Add per-gateway history drawer | 4 |
| `TaskHistoryView.swift` | Simplify (used only as drawer content) | 4 |
| `GatewayDetailView.swift` | Rewrite from List to ScrollView+Cards | 5 |
| `NullClawUITests/ComponentTests.swift` | **New** | 1 |
| `NullClawUITests/ServerCardTests.swift` | **New** | 2 |
| `NullClawUIUITests/ServersViewUITests.swift` | **New** | 3 |
| `NullClawUITests/ChatHistoryTests.swift` | **New** | 4 |
| `NullClawUIUITests/ChatHistoryUITests.swift` | **New** | 4 |
| `NullClawUIUITests/GatewayDetailUITests.swift` | Extend | 5 |
| `NullClawUIUITests/iPadLayoutTests.swift` | **New** | 6 |
| `NullClawUITests/RegressionTests.swift` | **New** | 7 |

---

## 5. TDD Workflow

Each phase follows this cycle:

```
1. Write failing test(s) that describe the desired behavior
2. Run tests → RED (tests fail)
3. Implement the minimum code to make tests pass
4. Run tests → GREEN (tests pass)
5. Refactor code (improve structure, no behavior change)
6. Run tests → GREEN (tests still pass)
7. Commit
```

**Test priority order** (within each phase):
1. **Unit tests first** — fast, deterministic, test logic
2. **UI tests second** — slower, test integration and layout
3. **Regression tests last** — ensure nothing broke

**Running tests**:
```bash
# Unit tests
xcodebuild test -scheme NullClawUI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' \
  -only-testing:NullClawUITests

# UI tests
xcodebuild test -scheme NullClawUI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' \
  -only-testing:NullClawUIUITests

# Full suite
xcodebuild test -scheme NullClawUI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4'
```

---

## 6. Risk Mitigation

| Risk | Mitigation |
|---|---|
| Tab order change breaks existing UI tests | Update all UI tests in Phase 3 as part of the tab change |
| History scoping loses conversations | `ConversationRecord` already has `gatewayProfileID` — filter, don't delete |
| ServerCard performance with many gateways | Use `LazyVStack` inside `ScrollView`, not `ForEach` directly |
| iPad layout complexity | Implement iPhone first, then adapt to iPad in Phase 6 |
| GlassCard visual regression | Write unit tests for component properties (cornerRadius, material) |

---

## 7. Success Criteria

1. **Zero test failures** — all existing + new tests pass
2. **Servers tab is first** — replaces Settings as the primary tab
3. **Server cards are tappable** — tapping pushes GatewayDetailView
4. **History is per-gateway** — only shows conversations for the active gateway
5. **Chat tab is second** — after Servers
6. **Visual parity with LLMServerControl** — card-based layout, pulsing status dots, consistent spacing
7. **iPad support** — NavigationSplitView with server sidebar
8. **No regression** — all existing functionality works (pairing, gateway switching, cron, MCP, etc.)
