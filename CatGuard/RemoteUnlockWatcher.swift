import Foundation

/// 远程解锁兜底：轮询 `~/.catguard-unlock`，存在即删除并解锁。
///
/// 用于 iPhone 快捷指令 / SSH `touch ~/.catguard-unlock` 等场景。
/// v0.1 不做 token 校验，文件存在即触发。
///
/// 状态日志（`remote-unlock`）由 `LockStateManager.remoteUnlock()` 统一记录，
/// 本类不持有 logger，避免重复与死代码。
@MainActor
final class RemoteUnlockWatcher {

    private unowned let lockManager: LockStateManager
    private var timer: Timer?

    private let unlockFilePath = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".catguard-unlock")

    init(lockManager: LockStateManager) {
        self.lockManager = lockManager
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // 滚动菜单 / 模态等场景下也保持轮询。
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard FileManager.default.fileExists(atPath: unlockFilePath) else { return }
        try? FileManager.default.removeItem(atPath: unlockFilePath)
        // 仅在锁定时才触发解锁动作，但无论如何都清除文件。
        if lockManager.isLocked {
            lockManager.remoteUnlock()
        }
    }
}
