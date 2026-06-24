# CatGuard — Technical Design

## Architecture Overview

Single-process macOS 15 menu bar App. No XPC helpers, no CLI in v0.1. All state lives in-process; no inter-process communication except the `~/.catguard-unlock` file convention.

## Module Map

| Module | Type | Responsibility |
|--------|------|----------------|
| `CatGuardApp` | `@main App` | Scene graph, wires all managers as `@StateObject` |
| `LockStateManager` | `@MainActor ObservableObject` | State machine, single source of truth for lock state |
| `EventTapManager` | `class` | CGEventTap lifecycle, callback, auto-recovery |
| `AuthenticationManager` | `class` | LocalAuthentication calls, surfaces result to LockStateManager |
| `RemoteUnlockWatcher` | `class` | Polls `~/.catguard-unlock` every 0.5s |
| `FloatingWindowController` | `NSObject` | Borderless NSWindow + SwiftUI unlock button |
| `MenuBarView` | `SwiftUI View` | Menu items rendered by MenuBarExtra |

## State Machine

```
Unlocked ──lock()──────────────────▶ Locked ──requestUnlock()──▶ Authenticating
                                        ▲                               │
                                        │◀────── fail / cancel ─────────┤
                                        │                               ▼
                                        └──────────── success ──── Unlocked

Locked ──remote file detected──▶ Unlocked (direct, no auth dialog)
Any state ──app crash──▶ CGEventTap dies with process → system input restored
```

`LockState` enum: `.unlocked`, `.locked`, `.authenticating`

## Event Tap Design

### Installation

```swift
CGEventTapCreate(
    tap: .cgSessionEventTap,       // session layer, no root required
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(
        [.keyDown, .keyUp, .flagsChanged,
         .leftMouseDown, .leftMouseUp,
         .rightMouseDown, .rightMouseUp,
         .otherMouseDown, .otherMouseUp,
         .mouseDragged, .scrollWheel]
    ),
    callback: eventTapCallback,
    userInfo: Unmanaged.passUnretained(self).toOpaque()
)
```

`mouseMoved` is intentionally **excluded** — cursor position is not intercepted.

### Callback Decision Tree

```
isLocked == false
    → passRetained(event)

isLocked == true
    event is mouseDown family
        → convert CGEvent.location to AppKit coords
        → if hits floatingButton.windowFrame → passRetained(event)
        → if hits menu bar strip (y ≥ screenHeight - 24) → passRetained(event)
        → else → return nil  (swallow)
    event is anything else (key, scroll, drag)
        → return nil  (swallow)
```

### Coordinate System Conversion

`CGEvent.location` uses Quartz global coordinates: origin at **top-left** of primary display, Y increases downward.
`NSWindow.frame` / `NSScreen.frame` use AppKit coordinates: origin at **bottom-left**, Y increases upward.

```swift
func quartzToAppKit(_ p: CGPoint) -> CGPoint {
    let h = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? 0
    return CGPoint(x: p.x, y: h - p.y)
}
```

### Auto-Recovery

The system disables an event tap if the callback blocks too long. Handle inside the callback:

```swift
if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    CGEventTapEnable(tap, true)
    return nil
}
```

## Authentication

```swift
LAContext().evaluatePolicy(
    .deviceOwnerAuthenticationWithBiometrics,  // Touch ID + Apple Watch
    localizedReason: "Unlock CatGuard"
) { success, error in
    DispatchQueue.main.async {
        success ? lockManager.unlock() : lockManager.authFailed()
    }
}
```

- `.deviceOwnerAuthenticationWithBiometrics` covers both Touch ID and Apple Watch proximity unlock.
- `.deviceOwnerAuthentication` (which also allows password) is intentionally **not used**.
- Biometric data never leaves the Secure Enclave; the app only receives a Bool result.

## FloatingWindowController

```
NSWindow
  styleMask:          .borderless
  level:              .floating
  backgroundColor:    .clear
  isOpaque:           false
  hasShadow:          false
  collectionBehavior: [.canJoinAllSpaces, .stationary, .ignoresCycle]
  ignoresMouseEvents: false

Position: top-right corner of main screen, 60×60pt, 8pt margin
```

`showButton()` → `orderFront(nil)` when entering `.locked`
`hideButton()` → `orderOut(nil)` when leaving `.locked`

The window's `frame` property is read by `EventTapManager.isHitFloatingButton(_:)` for hit testing. Because both are on the main thread, no synchronization is needed.

## RemoteUnlockWatcher

```
Timer(interval: 0.5, repeats: true) on main run loop
  → FileManager.default.fileExists(atPath: unlockFilePath)
      true  → try? FileManager.default.removeItem(atPath: unlockFilePath)
             → logger.info("Remote unlock triggered")
             → lockManager.unlock()
      false → no-op
```

`unlockFilePath = (NSHomeDirectory() as NSString).appendingPathComponent(".catguard-unlock")`

## Display Sleep Prevention

While locked, assert `kIOPMAssertionTypeNoDisplaySleep` to keep the display on:

```swift
var assertionID: IOPMAssertionID = 0
IOPMAssertionCreateWithName(
    kIOPMAssertionTypeNoDisplaySleep as CFString,
    IOPMAssertionLevel(kIOPMAssertionLevelOn),
    "CatGuard input lock active" as CFString,
    &assertionID
)
// on unlock:
IOPMAssertionRelease(assertionID)
```

## Logging

```swift
let logger = Logger(subsystem: "com.catguard.app", category: "state")
```

Events logged: `locked`, `unlock-requested`, `unlock-success`, `unlock-failed`, `remote-unlock`, `tap-disabled`, `tap-restored`.
No key content, no mouse coordinates, no window titles are ever logged.

## Entitlements & Permissions

| Setting | Value | Reason |
|---------|-------|--------|
| App Sandbox | **OFF** | CGEventTap + `~/.catguard-unlock` require unrestricted home dir access |
| Hardened Runtime | **ON** | Required for future notarization; no exceptions needed for dev builds |
| `NSAccessibilityUsageDescription` | Info.plist string | Shown by macOS when requesting Accessibility permission |

On launch, call `AXIsProcessTrusted()`. If false, present an alert and open System Settings → Privacy & Security → Accessibility. Start `EventTapManager` only after permission is confirmed.

## Fail-Open Guarantee

If the CatGuard process exits for any reason while locked, the CGEventTap is torn down automatically by the kernel. The system resumes delivering events normally. There is no persistent kernel-level block that outlives the process.
