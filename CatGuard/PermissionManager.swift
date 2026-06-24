import AppKit
import ApplicationServices
import os

/// Accessibility 权限检查与引导。
///
/// CGEventTap 需要 Accessibility（Input Monitoring）权限。启动时检查
/// `AXIsProcessTrusted()`，未授权则弹窗引导用户前往系统设置，并轮询直到授权。
@MainActor
final class PermissionManager: ObservableObject {

    private let logger = Logger(subsystem: "com.catguard.app", category: "permission")

    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()

    private var pollTimer: Timer?

    /// 当权限从未授权变为已授权时回调（仅触发一次）。
    var onGranted: (() -> Void)?

    /// 检查权限；未授权则弹窗 + 打开系统设置，并开始轮询。
    /// - Returns: 当前是否已授权。
    @discardableResult
    func ensureTrusted() -> Bool {
        isTrusted = AXIsProcessTrusted()
        logger.info("ensureTrusted AXIsProcessTrusted=\(self.isTrusted, privacy: .public)")
        if isTrusted {
            return true
        }
        presentGuidance()
        startPolling()
        return false
    }

    private func presentGuidance() {
        let alert = NSAlert()
        alert.messageText = "CatGuard 需要辅助功能权限"
        alert.informativeText = """
            请在「系统设置 → 隐私与安全性 → 辅助功能」中开启 CatGuard，\
            以便在锁定时拦截键盘与鼠标输入。授权后即可点击菜单栏的 Lock 上锁。
            """
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    private func poll() {
        let trusted = AXIsProcessTrusted()
        logger.info("poll AXIsProcessTrusted=\(trusted, privacy: .public)")
        guard trusted else { return }
        isTrusted = true
        pollTimer?.invalidate()
        pollTimer = nil
        onGranted?()
    }
}
