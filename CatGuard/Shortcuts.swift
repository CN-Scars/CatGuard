import AppKit
import KeyboardShortcuts

/// 全局快捷键名称定义。
///
/// `lockNow` 是唯一的上锁快捷键。`default:` 提供首次启动默认值 ⌘⌥⌃L
/// （Command+Option+Control+L），三修饰键组合独特，不易与系统/其它应用冲突。
/// 快捷键值由 KeyboardShortcuts 库自动持久化到 UserDefaults，无需自建存储层。
extension KeyboardShortcuts.Name {
    static let lockNow = Self(
        "lockNow",
        default: .init(.l, modifiers: [.command, .option, .control])
    )
}
