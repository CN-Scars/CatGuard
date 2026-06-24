# Hotkey Lock — Technical Design

## Overview

Add a global hotkey to trigger lock, plus a Settings window to customize it. Uses the
`KeyboardShortcuts` SPM package for the global hotkey, the recorder UI, and persistence.
Unlock paths are unchanged (hotkey locks only, never unlocks).

## Dependency

```yaml
# project.yml
packages:
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: 2.0.0
targets:
  CatGuard:
    dependencies:
      - package: KeyboardShortcuts
```

> First SPM dependency in the project. `.gitignore` already ignores `.build/` and
> `.swiftpm/`; XcodeGen resolves packages into the generated project. CI runs unsigned
> build — package fetch works without signing.

## New / Changed Modules

| Module | Change |
|--------|--------|
| `Shortcuts.swift` (new) | Defines `KeyboardShortcuts.Name.lockNow` with `initial:` default `⌘⌥⌃L` |
| `HotKeyManager.swift` (new) | Registers the global `onKeyUp` handler → calls `AppController.requestLock()` |
| `SettingsView.swift` (new) | SwiftUI form with `KeyboardShortcuts.Recorder` + reset button |
| `CatGuardApp.swift` | Add `Settings { SettingsView() }` scene; wire HotKeyManager |
| `MenuBarView.swift` | Add "Settings…" button that opens the Settings window |
| `AppController` | Hold `HotKeyManager`; start it after init |

No changes to `EventTapManager`, `AuthenticationManager`, `RemoteUnlockWatcher`,
`LockStateManager`, `HitTestGeometry` — keeps the tested core untouched.

## Shortcut Definition

```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let lockNow = Self(
        "lockNow",
        initial: .init(.l, modifiers: [.command, .option, .control])
    )
}
```

## HotKeyManager

```swift
@MainActor
final class HotKeyManager {
    private let onTrigger: () -> Void

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    func start() {
        // keyUp (not keyDown) avoids auto-repeat firing lock multiple times.
        KeyboardShortcuts.onKeyUp(for: .lockNow) { [weak self] in
            self?.onTrigger()
        }
    }
}
```

Wiring in `AppController`:

```swift
lazy var hotKeyManager = HotKeyManager { [weak self] in
    self?.requestLock()    // reuse existing path incl. permission guidance
}
// in init, after other setup:
hotKeyManager.start()
```

> `requestLock()` already guards on Accessibility permission and guides the user if not
> trusted, so the hotkey path needs no extra handling.

## SettingsView

```swift
import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        Form {
            Section("快捷键") {
                KeyboardShortcuts.Recorder("上锁快捷键:", name: .lockNow)
            }
            Section {
                Button("恢复默认快捷键") {
                    KeyboardShortcuts.reset(.lockNow)
                }
            }
        }
        .padding()
        .frame(width: 360)
    }
}
```

## App scene + opening Settings from a menu-bar (LSUIElement) app

```swift
var body: some Scene {
    MenuBarExtra { MenuBarView(...) } label: { ... }
    Settings { SettingsView() }   // standard ⌘, Settings scene
}
```

Opening the Settings window from the menu — LSUIElement apps are not activated by
default, so activate first, then open:

```swift
Button("Settings…") {
    NSApp.activate(ignoringOtherApps: true)
    if #available(macOS 14, *) {
        // SettingsLink is the SwiftUI-native way; if not feasible inside NSMenu,
        // fall back to the selector below.
    }
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
}
```

> **Gotcha to verify at runtime**: the private `showSettingsWindow:` selector changed
> across macOS versions (`showPreferencesWindow:` on older). On macOS 15 target,
> `showSettingsWindow:` is correct. Prefer SwiftUI `SettingsLink` if it renders acceptably
> in the menu; otherwise use the selector. This is the one item that needs a manual check.

## Menu structure

```
🐈 CatGuard
- Lock                       (unchanged)
- Settings…                  (new)
- Divider
- Quit CatGuard              (unchanged)
```

When locked, the menu still shows "Unlock with Touch ID" as today; Settings… can remain
visible but is non-essential while locked.

## Testing strategy

- The hotkey trigger and Recorder are system/UI bound → not unit-testable; verify by
  manual run (consistent with existing test policy).
- No new pure-logic units are introduced that warrant XCTest. Existing 22 tests must keep
  passing (no changes to tested modules).
- Add a manual test checklist to implement.md.

## Risks / Rollback

| Risk | Mitigation |
|------|------------|
| SPM dep fails to resolve in CI | Pin `from: 2.0.0`; CI already unsigned; verify on first push |
| Settings window won't open from LSUIElement menu | Try `SettingsLink` then selector fallback; isolated to one button |
| Hotkey conflicts with another app | User can rebind in Settings; default chosen to minimize conflict |
| Library breaks "zero-dependency" audit principle | Accepted by user; documented in prd decision #1 |
