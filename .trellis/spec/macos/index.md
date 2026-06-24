# macOS App Development Guidelines

> Executable contracts and gotchas for the CatGuard macOS menu bar app
> (Swift + SwiftUI + AppKit + CGEventTap + LocalAuthentication).

---

## Overview

CatGuard is a sandbox-disabled, menu-bar-only macOS app that intercepts input via
`CGEventTap` and unlocks via biometrics. Most of its hard-won knowledge is about
**code signing, SwiftUI lifecycle, and system-API threading** — areas where bugs are
non-obvious and only surface at runtime, not at compile time.

---

## Guidelines Index

| Guide | Description |
|-------|-------------|
| [Code Signing & TCC](./code-signing-and-tcc.md) | Stable local signing identity, Debug Dylib conflict, TCC re-authorization |
| [SwiftUI Lifecycle & Menu Bar](./swiftui-lifecycle.md) | No modal in init, MenuBarExtra `.disabled` refresh trap, `@ObservedObject` |
| [Event Tap & Threading](./event-tap-threading.md) | Session tap, hit-test geometry, MainActor callbacks, fail-open |
| [Build & Test Setup](./build-and-test.md) | XcodeGen single-source-of-truth, standalone logic tests, swift-format CI |

---

**Language**: Documentation in English; inline code comments may be Chinese (matches codebase).
