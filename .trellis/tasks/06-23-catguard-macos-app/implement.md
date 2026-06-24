# CatGuard — Implementation Plan

## Prerequisites

- Xcode 16+ on macOS 15
- No external package dependencies (pure Apple frameworks: SwiftUI, AppKit, LocalAuthentication, IOKit, os.Logger)

## Ordered Checklist

### Step 1 — Xcode Project Setup

- [ ] New macOS App → Swift, SwiftUI, bundle ID `com.catguard.app`, deployment target macOS 15.0
- [ ] Delete default `ContentView.swift`
- [ ] Signing & Capabilities: remove **App Sandbox** entitlement
- [ ] Add to `Info.plist`: key `NSAccessibilityUsageDescription`, value `"CatGuard needs Accessibility permission to intercept keyboard and mouse input while locked."`
- [ ] Add **IOKit.framework** to Linked Frameworks
- [ ] Confirm empty App struct builds without errors

### Step 2 — LockStateManager

- [ ] Create `LockStateManager.swift`
- [ ] `enum LockState { case unlocked, locked, authenticating }`
- [ ] `@MainActor final class LockStateManager: ObservableObject`
- [ ] `@Published var state: LockState = .unlocked`
- [ ] Methods: `lock()`, `unlock()`, `beginAuthenticating()`, `authFailed()`
- [ ] Each method logs via `os.Logger` before changing state
- [ ] Verify state transitions compile and transitions match the design diagram

### Step 3 — EventTapManager

- [ ] Create `EventTapManager.swift`
- [ ] `start()`: call `CGEventTapCreate` with the mask from design.md (no `.mouseMoved`)
- [ ] Add tap to run loop: `CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)`
- [ ] Callback: if `!isLocked` pass through; if locked hit-test then swallow or pass
- [ ] `isHitFloatingButton(_ point: CGPoint) -> Bool`: convert Quartz→AppKit, check against `floatingWindow?.frame`
- [ ] `isHitMenuBar(_ point: CGPoint) -> Bool`: `point.y <= 24` in Quartz coords (top 24pt)
- [ ] Auto-recovery: on `tapDisabledByTimeout` / `tapDisabledByUserInput`, re-enable tap and log
- [ ] `stop()`: `CGEventTapEnable(tap, false)`, remove run loop source
- [ ] **Manual test gate**: lock → type on keyboard → zero characters appear in any app

### Step 4 — AuthenticationManager

- [ ] Create `AuthenticationManager.swift`
- [ ] `requestUnlock(lockManager:)`: guard `lockManager.state == .locked`, call `lockManager.beginAuthenticating()`
- [ ] `LAContext().evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock CatGuard")`
- [ ] On success → `lockManager.unlock()`; on failure/cancel → `lockManager.authFailed()`
- [ ] All callbacks dispatched on `DispatchQueue.main`
- [ ] **Manual test gate**: lock → click menu → Touch ID prompt appears → cancel → still locked → success → unlocked

### Step 5 — MenuBarExtra + MenuBarView

- [ ] Update `@main` App struct to use `MenuBarExtra("CatGuard", systemImage: ...) { MenuBarView() }.menuBarExtraStyle(.menu)`
- [ ] Label: `Text(lockManager.isLocked ? "🐈🔒" : "🐈")` (use `.labelStyle(.titleOnly)` or custom label)
- [ ] `MenuBarView` items when **unlocked**: "Lock" button → `lockManager.lock()`
- [ ] `MenuBarView` items when **locked**: "Unlock with Touch ID" → `authManager.requestUnlock()`
- [ ] Both states show Separator + "Quit" → `NSApp.terminate(nil)`
- [ ] Menu updates reactively via `@EnvironmentObject` (no manual refresh needed)
- [ ] **Manual test gate**: lock → menu shows "Unlock with Touch ID"; unlock → menu shows "Lock"

### Step 6 — FloatingWindowController

- [ ] Create `FloatingWindowController.swift` as `NSObject`
- [ ] Create `NSWindow(contentRect: NSRect(x:0, y:0, width:60, height:60), styleMask: .borderless, ...)`
- [ ] Set `level = .floating`, `backgroundColor = .clear`, `isOpaque = false`, `hasShadow = false`
- [ ] Set `collectionBehavior = [.canJoinAllSpaces, .stationary]`
- [ ] Host SwiftUI view: rounded rect, semi-transparent, unlock symbol "🔓", `Button` action → `authManager.requestUnlock()`
- [ ] `positionInTopRight()`: read `NSScreen.main?.visibleFrame`, place 8pt from top-right edge
- [ ] `showButton()` / `hideButton()`: `orderFront` / `orderOut`
- [ ] Expose `var windowFrame: NSRect { window.frame }` for EventTapManager
- [ ] Subscribe to `lockManager.$state` to call show/hide automatically
- [ ] **Manual test gate**: lock → button appears top-right; unlock → button disappears; click button → Touch ID fires

### Step 7 — RemoteUnlockWatcher

- [ ] Create `RemoteUnlockWatcher.swift`
- [ ] `start()`: `Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true)`
- [ ] Timer body: `FileManager.default.fileExists(atPath: unlockFilePath)` → remove + unlock + log
- [ ] `stop()`: `timer?.invalidate()`
- [ ] `unlockFilePath`: `NSHomeDirectory() + "/.catguard-unlock"`
- [ ] **Manual test gate**: lock → `touch ~/.catguard-unlock` in Terminal → app unlocks within 0.5s

### Step 8 — Display Sleep Prevention

- [ ] In `LockStateManager.lock()`: `IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep, ..., &assertionID)`
- [ ] In `LockStateManager.unlock()`: `IOPMAssertionRelease(assertionID)`
- [ ] Guard against double-assert (check `assertionID != kIOPMNullAssertionID`)

### Step 9 — Permission Guidance on Launch

- [ ] In App `init` or `.onAppear` of scene: call `AXIsProcessTrusted()`
- [ ] If `false`: show `NSAlert` with message directing user to System Settings → Privacy & Security → Accessibility
- [ ] Start `EventTapManager.start()` only after `AXIsProcessTrusted()` returns `true`
- [ ] Optionally poll every 2s until permission is granted, then auto-start

### Step 10 — Wire All Managers in App Struct

- [ ] Instantiate `LockStateManager`, `EventTapManager`, `AuthenticationManager`, `RemoteUnlockWatcher`, `FloatingWindowController` as stored properties or `@StateObject`
- [ ] Pass `lockManager` to `EventTapManager` (weak ref or closure for `isLocked` state)
- [ ] Pass `floatingWindowController` to `EventTapManager` (for hit-test frame)
- [ ] Start `EventTapManager` and `RemoteUnlockWatcher` once Accessibility permission is confirmed
- [ ] Inject `lockManager` and `authManager` into `MenuBarView` via `.environmentObject`

### Step 11 — End-to-End Verification

- [ ] Lock → type keyboard → no input reaches any app
- [ ] Lock → scroll trackpad → no scrolling
- [ ] Lock → click random location → no click registered
- [ ] Lock → click menu bar icon → "Unlock with Touch ID" shown → Touch ID → unlock
- [ ] Lock → click floating button → Touch ID → unlock
- [ ] Lock → Touch ID cancel → still locked
- [ ] Lock → `touch ~/.catguard-unlock` → unlock within 1s
- [ ] Lock → quit app → input resumes immediately
- [ ] Lock → force-quit app → input resumes immediately (fail-open check)
- [ ] Unlock → type keyboard → input works normally
- [ ] Screen does not sleep while locked (verify with 5min wait or `caffeinate` baseline)

## Rollback Points

| After step | Risk | Mitigation |
|------------|------|-----------|
| Step 3 | CGEventTap creation fails (permission denied) | Alert user, run without interception (fail-open) |
| Step 4 | `LAContext` unavailable (no biometric hardware) | Surface error in menu, suggest remote unlock |
| Step 6 | FloatingWindow z-order conflicts with other apps | Can disable FloatingWindowController without breaking core lock |
| Step 8 | IOPMAssertion API changes | Wrap in `if #available` guard; non-fatal if it fails |

## Validation Commands

```bash
# Build
xcodebuild -scheme CatGuard -configuration Debug build

# Static analysis
xcodebuild -scheme CatGuard -configuration Debug analyze
```
