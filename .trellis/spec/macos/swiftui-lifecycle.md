# SwiftUI Lifecycle & Menu Bar

> Two runtime crashes/bugs that compile cleanly but fail at runtime.

---

## Don't: present a modal (`NSAlert.runModal`) during SwiftUI scene init

**Problem**:

```swift
@main
struct CatGuardApp: App {
    @StateObject private var controller = AppController()  // lazily init during first body eval
    // ...
}

final class AppController: ObservableObject {
    init() {
        if !AXIsProcessTrusted() {
            permissionManager.ensureTrusted()  // ❌ calls NSAlert().runModal() synchronously
        }
    }
}
```

**Why it's bad**: `@StateObject` initializes the controller lazily *inside* SwiftUI's
first scene-graph evaluation transaction. `NSAlert.runModal()` spins up a nested modal
run loop, which re-enters and corrupts the in-flight AttributeGraph transaction:

```
AG::precondition_failure → abort() → SIGABRT
(crash backtrace shows GraphHost.startTransactionUpdate)
```

**Instead**: defer any modal / nested run loop to the next run-loop tick:

```swift
init() {
    if AXIsProcessTrusted() {
        startServices()
    } else {
        DispatchQueue.main.async { [weak self] in   // ✅ after the current render transaction
            self?.permissionManager.ensureTrusted()
        }
    }
}
```

---

## Gotcha: `MenuBarExtra` + `.disabled()` does not refresh reliably

**Symptom**: A menu `Button("Lock").disabled(!isTrusted)` stays greyed out even after
`isTrusted` flips to `true` via a `@Published` change.

**Cause**: `MenuBarExtra(.menu style)` bridges to `NSMenu`. The disabled state of bridged
menu items is **not guaranteed to re-render** on `@ObservedObject`/`@Published` changes
the way normal SwiftUI views do.

**Fix**: Don't gate menu actions with `.disabled` bound to async-changing state. Make the
button always tappable and handle the not-ready case inside the action:

```swift
// ❌ Wrong — stale grey button
Button("Lock") { onRequestLock() }
    .disabled(!permissionManager.isTrusted)

// ✅ Correct — always tappable; requestLock() guides to permission if not trusted
Button("Lock") { onRequestLock() }
```

```swift
func requestLock() {
    guard permissionManager.isTrusted else {
        permissionManager.ensureTrusted()   // guide user instead of silently no-op
        return
    }
    lockManager.lock()
}
```

---

## Convention: observe injected ObservableObjects with `@ObservedObject`

**What**: Any `ObservableObject` whose `@Published` changes must drive a view's re-render
has to be held as `@ObservedObject` (or `@EnvironmentObject`), never a plain `let`.

**Why**: A plain `let permissionManager: PermissionManager` is *not observed*; background
changes (e.g. a poll timer flipping `isTrusted`) won't refresh the view.

```swift
struct MenuBarView: View {
    @EnvironmentObject private var lockManager: LockStateManager  // ✅ observed
    @ObservedObject var permissionManager: PermissionManager      // ✅ observed
    let authManager: AuthenticationManager                        // ok: no @Published drives UI
}
```

---

## Don't: open Settings from a MenuBarExtra menu via `SettingsLink` or `showSettingsWindow:`

**Symptom**: A "Settings…" item in a `MenuBarExtra(.menu)` does nothing when clicked.

**Cause**: Two unreliable paths, both fail in a menu-bar (LSUIElement) app:
- `SettingsLink` does not trigger inside the bridged `NSMenu` of `MenuBarExtra(.menu)`;
  `.simultaneousGesture` on a menu item doesn't fire either.
- The private selector `showSettingsWindow:` (and older `showPreferencesWindow:`) is
  version-dependent and unreliable on macOS 15.

**Fix**: Don't use SwiftUI's `Settings { }` scene for a menu-bar app. Self-manage an
`NSWindow` hosting the SwiftUI settings view, and call it directly from the menu button:

```swift
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    func show() {
        NSApp.activate(ignoringOtherApps: true)   // LSUIElement app must activate to focus
        if let window { window.makeKeyAndOrderFront(nil); return }
        let hosting = NSHostingController(rootView: SettingsView())
        let win = NSWindow(contentViewController: hosting)
        win.title = "CatGuard 设置"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false   // allow reopening after close
        win.center()
        window = win
        win.makeKeyAndOrderFront(nil)
    }
}

// menu:
Button("Settings…") { onOpenSettings() }   // → settingsWindowController.show()
```

**Why it works**: a self-managed `NSWindow` bypasses SwiftUI scene routing and all private
selectors — behavior is fully under your control, no version-dependent APIs.
