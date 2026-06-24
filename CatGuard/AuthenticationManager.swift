import Foundation
import LocalAuthentication
import os

/// 生物识别解锁。
///
/// 使用 `.deviceOwnerAuthenticationWithBiometrics`，覆盖 Touch ID 与 Apple Watch，
/// 故意不回退到密码（`.deviceOwnerAuthentication`），以防猫误触或他人用密码解锁。
/// App 只接收 `Bool` 结果，生物识别原始数据永不离开 Secure Enclave。
@MainActor
final class AuthenticationManager {

    private let logger = Logger(subsystem: "com.catguard.app", category: "state")

    private unowned let lockManager: LockStateManager

    init(lockManager: LockStateManager) {
        self.lockManager = lockManager
    }

    /// 发起一次解锁认证。仅在 `.locked` 状态下生效（避免重复弹窗）。
    func requestUnlock() {
        guard lockManager.state == .locked else { return }

        lockManager.beginAuthenticating()

        let context = LAContext()
        // 不允许回退到密码。
        context.localizedFallbackTitle = ""

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        else {
            // 无生物识别硬件可用：保持锁定，提示走远程解锁兜底。
            logger.info("unlock-failed")
            lockManager.authFailed()
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock CatGuard"
        ) { [weak self] success, _ in
            Task { @MainActor in
                guard let self else { return }
                if success {
                    self.lockManager.unlock()
                } else {
                    self.lockManager.authFailed()
                }
            }
        }
    }
}
