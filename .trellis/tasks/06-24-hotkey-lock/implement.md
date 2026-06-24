# Hotkey Lock — Implementation Plan

## Prerequisites

- Existing CatGuard project builds & 22 tests pass
- Network access for SPM to fetch KeyboardShortcuts

## Ordered Checklist

### Step 1 — Add SPM dependency

- [ ] In `project.yml` add top-level `packages:` with `KeyboardShortcuts` (`from: 2.0.0`)
- [ ] Add `- package: KeyboardShortcuts` to `CatGuard` target `dependencies`
- [ ] `xcodegen generate`
- [ ] `xcodebuild -scheme CatGuard build` — confirm package resolves and links
- [ ] Verify `.gitignore` covers `.build/` and `.swiftpm/` (already present)

### Step 2 — Define the shortcut name + default

- [ ] Create `CatGuard/Shortcuts.swift`
- [ ] `extension KeyboardShortcuts.Name { static let lockNow = Self("lockNow", initial: .init(.l, modifiers: [.command, .option, .control])) }`
- [ ] Build

### Step 3 — HotKeyManager

- [ ] Create `CatGuard/HotKeyManager.swift` (`@MainActor final class`)
- [ ] `init(onTrigger:)` stores closure; `start()` registers `KeyboardShortcuts.onKeyUp(for: .lockNow)`
- [ ] Use **keyUp** (not keyDown) to avoid auto-repeat double-lock
- [ ] Build

### Step 4 — Wire HotKeyManager into AppController

- [ ] Add `hotKeyManager` to `AppController`, closure calls `self.requestLock()`
- [ ] Call `hotKeyManager.start()` in init (after managers set up)
- [ ] Build
- [ ] **Manual test gate**: press ⌘⌥⌃L → app locks (🐈🔒); if unauthorized → permission guidance

### Step 5 — SettingsView

- [ ] Create `CatGuard/SettingsView.swift` with `Form` + `KeyboardShortcuts.Recorder("上锁快捷键:", name: .lockNow)` + reset button
- [ ] Build

### Step 6 — Add Settings scene + menu entry

- [ ] In `CatGuardApp.swift` add `Settings { SettingsView() }` to the scene body
- [ ] In `MenuBarView.swift` add "Settings…" button between Lock and Quit
- [ ] Button action: `NSApp.activate(ignoringOtherApps: true)` then open settings
      (try `SettingsLink`; fallback `NSApp.sendAction(Selector(("showSettingsWindow:")), ...)`)
- [ ] Build
- [ ] **Manual test gate**: menu → Settings… → window opens & is focused (LSUIElement activate works)

### Step 7 — Recorder + persistence verification (manual)

- [ ] In Settings, record a new shortcut (e.g. ⌥⌘K) → press it → app locks
- [ ] Quit & relaunch → custom shortcut persists (library auto-persists)
- [ ] Click "恢复默认快捷键" → recorder shows ⌘⌥⌃L again

### Step 8 — Format, test, full verification

- [ ] `xcrun swift-format format -i -p -r --configuration .swift-format CatGuard CatGuardTests`
- [ ] `xcrun swift-format lint --strict -r --configuration .swift-format CatGuard CatGuardTests` → 0 warnings
- [ ] `xcodebuild -scheme CatGuard test` → existing 22 tests still pass
- [ ] Simulate CI: build+test with `CODE_SIGNING_ALLOWED=NO`

## Manual Test Checklist (runtime, human-only)

1. ⌘⌥⌃L locks while CatGuard is in background (another app focused)
2. Hotkey does NOT unlock (press while locked → stays locked)
3. Settings… opens a focused window from the menu
4. Recorder rebinds shortcut; new shortcut works; old one stops working
5. Custom shortcut survives relaunch
6. Reset restores ⌘⌥⌃L
7. Unauthorized state: hotkey triggers permission guidance (same as menu Lock)

## Validation Commands

```bash
xcodegen generate
xcodebuild -scheme CatGuard -configuration Debug build
xcodebuild -scheme CatGuard -configuration Debug test
xcrun swift-format lint --strict -r --configuration .swift-format CatGuard CatGuardTests
```

## Rollback Points

| After step | Risk | Mitigation |
|------------|------|------------|
| Step 1 | SPM resolve fails | Revert project.yml package block; feature aborts cleanly |
| Step 6 | Settings window won't open | Selector vs SettingsLink fallback; isolated to one button |
| Step 4 | Hotkey double-fires | Ensure keyUp not keyDown |
