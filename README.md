# NullClawUI

A native iOS/iPadOS client for interacting with a [NullClaw](https://github.com/nullclaw) AI Gateway using the **A2A (Agent-to-Agent)** protocol.

---

## Platform Requirements

| Property | Value |
|---|---|
| **iOS / iPadOS** | 26.0+ |
| **macOS** | 26.0 Tahoe+ (Mac Catalyst, optional) |
| **Xcode** | 26+ |
| **Swift** | 6 (strict concurrency) |

---

## Features (by phase)

| Phase | Name | Status |
|---|---|---|
| 0 | Project Setup | 🔲 Planned |
| 1 | Foundation & Discovery | 🔲 Planned |
| 2 | Secure Pairing | 🔲 Planned |
| 3 | Simple Interaction (Chat) | 🔲 Planned |
| 4 | Real-time Streaming | 🔲 Planned |
| 5 | Task Management & History | 🔲 Planned |
| 6 | Polish & Native Integration | 🔲 Planned |

See [`PLAN.md`](./PLAN.md) for full details on each phase.

---

## Project Structure

```
NullClawUI/
├── App/              # @main entry point, AppModel (@Observable)
├── Views/            # SwiftUI screens
├── ViewModels/       # @Observable view models
├── Networking/       # URLSession, A2AClient, SSEParser (AsyncSequence)
├── Security/         # KeychainService (per-gateway credential storage)
├── Models/           # Codable types: AgentCard, Task, Message, …
└── Resources/        # Assets.xcassets, Info.plist
NullClawUITests/      # XCTest unit tests
NullClawUIUITests/    # XCUIApplication UI tests
```

---

## Getting Started

### Prerequisites

1. **Xcode 26** or later installed.
2. A running **NullClaw Gateway** instance (see the [NullClaw repository](https://github.com/nullclaw) for setup instructions). Default address: `http://localhost:5111`.

### Build & Run

```bash
# Clone the repository
git clone <repo-url>
cd NullClawUI

# Open in Xcode (recommended)
open NullClawUI.xcodeproj

# Or build from the command line
xcodebuild build \
  -scheme NullClawUI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.0'
```

### Run Tests

```bash
# Unit tests
xcodebuild test \
  -scheme NullClawUI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.0'

# UI tests (separate test plan)
xcodebuild test \
  -scheme NullClawUI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.0' \
  -testPlan NullClawUIUITests
```

---

## Design Language

NullClawUI follows the **Liquid Glass** design language introduced in iOS 26:

- Panels and cards use `.glassBackgroundEffect()` / `GlassEffect`.
- Accent color is dynamically sourced from the gateway's `agent-card.json`.
- All animations use `spring(duration:bounce:)` for a fluid, native feel.
- Full Light / Dark mode and Dynamic Type support.

---

## Security

Credentials (Bearer tokens) are stored exclusively in the **system Keychain**, keyed by the normalized gateway URL. No tokens are written to disk, UserDefaults, or iCloud. See [`AGENTS.md`](./AGENTS.md) — Security & Identity Guard for the full credential management policy.

---

## Architecture

| Layer | Technology |
|---|---|
| State | `@Observable` macro (Swift 6) |
| Navigation | `NavigationSplitView` (iPad) / `NavigationStack` (iPhone) |
| Networking | `URLSession` + `async/await`, `AsyncSequence` for SSE |
| Keychain | `Security` framework |
| Markdown | `swift-markdown-ui` (Phase 6) |

All UI mutations are `@MainActor`-isolated. Network operations run in unstructured `Task {}` off the main actor.

---

## Contributing

See [`AGENTS.md`](./AGENTS.md) for the agent roles and responsibilities used during development.

---

## License

TBD.
