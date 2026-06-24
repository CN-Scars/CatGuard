import AppKit
import SwiftUI

/// 菜单栏下拉菜单内容。
///
/// - 未锁定：显示 "Lock"
/// - 锁定 / 认证中：显示 "Unlock with Touch ID"
/// 两种状态都显示分隔线 + "Quit"。
struct MenuBarView: View {
    @EnvironmentObject private var lockManager: LockStateManager
    let authManager: AuthenticationManager
    /// 必须用 @ObservedObject 观察:权限在后台轮询中从未授权翻为已授权时,
    /// 菜单需要据此刷新 Lock 按钮的禁用态。用普通 let 会导致状态变更不触发重绘。
    @ObservedObject var permissionManager: PermissionManager
    let onRequestLock: () -> Void

    var body: some View {
        if !permissionManager.isTrusted {
            Text("等待辅助功能权限…")
            Button("打开系统设置授权") {
                permissionManager.ensureTrusted()
            }
            Divider()
        }

        switch lockManager.state {
        case .unlocked:
            // 不用 .disabled 门控:MenuBarExtra 的 NSMenu 桥接不保证 disabled
            // 状态随 @ObservedObject 实时刷新,会导致授权后按钮仍显示灰色。
            // requestLock() 内部已对未授权做引导,故让按钮始终可点更可靠。
            Button("Lock") {
                onRequestLock()
            }

        case .locked, .authenticating:
            Button("Unlock with Touch ID") {
                authManager.requestUnlock()
            }
        }

        Divider()

        Button("Quit CatGuard") {
            NSApp.terminate(nil)
        }
    }
}
