# Contributing to NullClawUI

Thank you for your interest in contributing. This document describes the requirements for all changes.

---

## Code Quality Gates

All changes must pass the following checks before being submitted:

### 1. SwiftLint

```bash
swiftlint --strict
```

Zero warnings allowed.

### 2. SwiftFormat

```bash
swiftformat --lint .
```

Zero violations allowed. Run `swiftformat .` to auto-fix.

### 3. Periphery (unused code detection)

```bash
RUN_PERIPHERY=1 xcodebuild build-for-testing \
  -scheme NullClawUI \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Zero unused code warnings.

### 4. Build

```bash
xcodebuild build-for-testing \
  -scheme NullClawUI \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Must succeed with no errors.

---

## Test Requirements

**Every code change must be accompanied by tests.** No exceptions.

| Change type | Requirement |
|---|---|
| New methods or changed logic | Add or update `XCTestCase` tests in `NullClawUITests/` |
| Bug fixes | Add a regression test that would have caught the original failure |
| New ViewModel methods | Test happy path and failure/edge cases; use `@MainActor func test...() async` |
| Keychain operations | Test directly; call `KeychainService.deleteToken(for:)` in `tearDown()` |
| Pure UI-layout changes | Add comment: `// NOTE: No unit test — pure layout change; covered by visual inspection in Simulator.` |

Run tests:

```bash
xcodebuild test \
  -scheme NullClawUI \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

---

## Project Setup

This project uses [xcodegen](https://github.com/yonaskolb/xcodegen). After adding, removing, or renaming source files, regenerate the Xcode project:

```bash
xcodegen generate
```

Set your development team in Xcode's **Signing & Capabilities** after regenerating.

---

## Architecture

- **Swift 6 strict concurrency** (`-strict-concurrency=complete`) — no `DispatchQueue`; all network calls use `async/await`; all UI mutations on `@MainActor`
- **State management**: `@Observable` macro (not `ObservableObject`)
- **Navigation**: `NavigationStack` with `NavigationPath`
- **Persistence**: SwiftData
- **Credentials**: System Keychain only

See [`AGENTS.md`](./AGENTS.md) for detailed role descriptions and coding conventions.

---

## Pull Request Process

1. Create a branch from `main`
2. Make your changes with accompanying tests
3. Ensure all quality gates pass (SwiftLint, SwiftFormat, Periphery, build, tests)
4. Open a pull request with a clear description of the change and its motivation
5. Link any related issues

---

## Reporting Issues

When filing an issue, please include:

- Steps to reproduce
- Expected behavior
- Actual behavior
- iOS version and device/simulator
- Gateway version (if relevant)
