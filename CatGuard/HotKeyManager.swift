import KeyboardShortcuts

/// 注册全局上锁快捷键，触发时调用注入的上锁回调。
///
/// 快捷键**仅作为上锁入口**（见 spec 第 8 节）：猫可能误触，解锁必须经
/// Touch ID / Apple Watch / 远程文件认证，故此处不注册任何解锁路径。
///
/// 使用 `onKeyUp`（而非 `onKeyDown`）注册：避免长按时自动重复触发导致多次上锁。
@MainActor
final class HotKeyManager {

    private let onTrigger: () -> Void

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    /// 注册全局快捷键回调。底层使用 Carbon `RegisterEventHotKey`，
    /// 独立于 Accessibility 权限工作；即使未授予辅助功能也能触发上锁回调，
    /// 而回调内的 `requestLock()` 仍会做权限引导。
    func start() {
        KeyboardShortcuts.onKeyUp(for: .lockNow) { [weak self] in
            self?.onTrigger()
        }
    }
}
