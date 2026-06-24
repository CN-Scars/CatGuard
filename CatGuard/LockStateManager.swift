import Foundation
import IOKit.pwr_mgt
import os

/// 输入锁的状态机。
///
/// 状态流转（见 design.md）：
/// ```
/// Unlocked ──lock()──▶ Locked ──beginAuthenticating()──▶ Authenticating
///                         ▲                                    │
///                         │◀──── authFailed() (fail/cancel) ───┤
///                         └──────────── unlock() (success) ────┘
///
/// Locked ──unlock() (remote file) ──▶ Unlocked（直接，无认证弹窗）
/// ```
enum LockState {
    case unlocked
    case locked
    case authenticating
}

/// 锁状态的唯一真实来源（single source of truth）。
///
/// 所有状态变更都在主线程进行，并通过 `@Published` 通知 SwiftUI；
/// `EventTapManager` 的回调通过读取 `state` 决定是否拦截输入。
@MainActor
final class LockStateManager: ObservableObject {

    private let logger = Logger(subsystem: "com.catguard.app", category: "state")

    @Published private(set) var state: LockState = .unlocked

    /// 息屏防护断言句柄；`0` 表示未持有断言。
    private var sleepAssertionID: IOPMAssertionID = 0

    var isLocked: Bool { state != .unlocked }

    // MARK: - Transitions

    /// Unlocked → Locked。开始拦截输入，并阻止显示器息屏。
    func lock() {
        guard state == .unlocked else { return }
        logger.info("locked")
        state = .locked
        preventDisplaySleep()
    }

    /// Locked → Authenticating。准备弹出生物识别认证。
    func beginAuthenticating() {
        guard state == .locked else { return }
        logger.info("unlock-requested")
        state = .authenticating
    }

    /// Authenticating/Locked → Unlocked。认证成功或远程文件触发。
    func unlock() {
        guard state != .unlocked else { return }
        logger.info("unlock-success")
        state = .unlocked
        allowDisplaySleep()
    }

    /// Authenticating → Locked。认证失败或被用户取消，保持锁定。
    func authFailed() {
        guard state == .authenticating else { return }
        logger.info("unlock-failed")
        state = .locked
    }

    /// 远程文件触发解锁的专用入口，日志类别区别于生物识别成功。
    func remoteUnlock() {
        guard state != .unlocked else { return }
        logger.info("remote-unlock")
        state = .unlocked
        allowDisplaySleep()
    }

    // MARK: - Display Sleep Prevention (Step 8)

    private func preventDisplaySleep() {
        guard sleepAssertionID == 0 else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "CatGuard input lock active" as CFString,
            &sleepAssertionID
        )
        if result != kIOReturnSuccess {
            // 非致命：锁仍然有效，仅息屏防护失败。
            sleepAssertionID = 0
        }
    }

    private func allowDisplaySleep() {
        guard sleepAssertionID != 0 else { return }
        IOPMAssertionRelease(sleepAssertionID)
        sleepAssertionID = 0
    }
}
