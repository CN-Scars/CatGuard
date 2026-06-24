import AppKit
import SwiftUI

/// 设置窗口控制器（AppKit 受控）。
///
/// 为什么不用 SwiftUI `Settings` 场景 + `SettingsLink` / `showSettingsWindow:`：
/// - `SettingsLink` 在 `MenuBarExtra` 的 `.menu`(NSMenu) 环境下点击不触发；
/// - 私有 selector `showSettingsWindow:` / `showPreferencesWindow:` 跨 macOS 版本不稳定，
///   macOS 15 上不可靠。
/// 因此用 `NSWindow` + `NSHostingController` 自管理，菜单按钮直接调用 `show()`，
/// 行为完全可控，不依赖任何私有 API 或 SwiftUI 场景路由。
@MainActor
final class SettingsWindowController {

    private var window: NSWindow?

    /// 显示设置窗口；已存在则前置。LSUIElement 应用须先激活才能让窗口获焦。
    func show() {
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView())
        let win = NSWindow(contentViewController: hosting)
        win.title = "CatGuard 设置"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        window = win
        win.makeKeyAndOrderFront(nil)
    }
}
