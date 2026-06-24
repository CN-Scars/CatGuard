# Event Tap & Threading

> Contracts for the CGEventTap input-interception core.

---

## Convention: session-layer tap, explicit event mask, fail-open

**Signature**:

```swift
CGEvent.tapCreate(
    tap: .cgSessionEventTap,        // session layer — normal Accessibility perm, no root
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: mask,
    callback: callback,
    userInfo: Unmanaged.passUnretained(self).toOpaque()
)
```

**Event mask contract** — intercept these, and **deliberately exclude `.mouseMoved`** so
the cursor can drift (clicks/keys/scroll are still swallowed):

```
keyDown, keyUp, flagsChanged,
leftMouseDown/Up, rightMouseDown/Up, otherMouseDown/Up,
leftMouseDragged, rightMouseDragged, otherMouseDragged,
scrollWheel
```

**Fail-open contract**: if `tapCreate` returns nil (usually missing Accessibility perm),
log and return `false` — never block input on failure. Process exit tears the tap down
via the kernel, so a crash can never permanently lock the user out.

> **Gotcha**: building the mask with a long `|` chain triggers "compiler unable to
> type-check in reasonable time". Build it with `reduce` over a `[CGEventType]` instead.

### Auto-recovery contract

The system disables a tap whose callback is too slow. Handle it inside the callback:

```swift
if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    CGEvent.tapEnable(tap: tap, enable: true)   // re-enable and log
    return nil
}
```

---

## Gotcha: Quartz vs AppKit coordinate flip (the multi-display bug)

**Symptom (real bug we shipped then caught in review)**: menu-bar hit-test used
`quartzPoint.y <= 24`. On a display positioned *above* the primary, Quartz `y` is
**negative**, so `y <= 24` is always true → all clicks on the upper secondary display
were passed through while locked, **bypassing the input lock**.

**Contract**: menu-bar hit test needs a lower bound:

```swift
static func isInMenuBar(quartzY: CGFloat, menuBarHeight: CGFloat) -> Bool {
    quartzY >= 0 && quartzY <= menuBarHeight   // lower bound 0 is mandatory
}
```

Quartz (top-left origin, +Y down) → AppKit (bottom-left origin, +Y up):

```swift
static func quartzToAppKit(_ p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
    CGPoint(x: p.x, y: primaryHeight - p.y)
}
```

**Convention**: keep this geometry as **pure functions** (no `NSScreen` calls inside) so
it is unit-testable; pass `primaryHeight` in. See
[build-and-test.md](./build-and-test.md) — these functions carry the multi-display
regression test.

---

## Convention: reading `@MainActor` state from the C tap callback

The tap is installed on the main run loop's `.commonModes`, so the callback runs on the
main thread. Read main-actor state with `MainActor.assumeIsolated` (correct for Swift 6
concurrency, runtime-safe here):

```swift
private func isLockedNow() -> Bool {
    MainActor.assumeIsolated { lockManager.isLocked }
}
```

> Only valid because the callback is guaranteed main-thread. If the tap is ever moved off
> the main run loop, this becomes unsound.
