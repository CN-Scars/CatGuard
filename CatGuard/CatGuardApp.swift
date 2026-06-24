import ApplicationServices
import SwiftUI

/// 应用入口。装配所有管理器，渲染菜单栏。
@main
struct CatGuardApp: App {

    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                authManager: controller.authManager,
                permissionManager: controller.permissionManager,
                onRequestLock: { controller.requestLock() }
            )
            .environmentObject(controller.lockManager)
        } label: {
            // 图标随锁状态切换：🐈 / 🐈🔒
            Text(controller.lockManager.isLocked ? "🐈🔒" : "🐈")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// 持有所有管理器并协调启动顺序的主控对象。
///
/// `LockStateManager` 是唯一真实来源；其余管理器围绕它协作。
/// EventTap 与 RemoteUnlockWatcher 仅在 Accessibility 权限确认后启动。
@MainActor
final class AppController: ObservableObject {

    let lockManager: LockStateManager
    let authManager: AuthenticationManager
    let permissionManager: PermissionManager
    let floatingController: FloatingWindowController
    let eventTapManager: EventTapManager
    let remoteWatcher: RemoteUnlockWatcher

    /// EventTap / Watcher 是否已启动，避免权限授予回调重复启动。
    private var servicesStarted = false

    init() {
        let lock = LockStateManager()
        let auth = AuthenticationManager(lockManager: lock)
        let floating = FloatingWindowController(lockManager: lock, authManager: auth)
        let tap = EventTapManager(lockManager: lock, floatingController: floating)
        let watcher = RemoteUnlockWatcher(lockManager: lock)
        let permission = PermissionManager()

        self.lockManager = lock
        self.authManager = auth
        self.floatingController = floating
        self.eventTapManager = tap
        self.remoteWatcher = watcher
        self.permissionManager = permission

        permission.onGranted = { [weak self] in
            self?.startServices()
        }

        // 启动时检查权限。注意：绝不能在此同步弹出 NSAlert.runModal()，
        // 因为 AppController 由 @StateObject 在 SwiftUI 首次评估场景图的事务中
        // 惰性初始化，此时开启嵌套 modal run loop 会破坏 AttributeGraph 并 abort。
        // 因此把权限引导推迟到当前渲染事务结束后的下一个 run loop tick。
        if AXIsProcessTrusted() {
            startServices()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.permissionManager.ensureTrusted()
            }
        }
    }

    /// 用户从菜单点击 Lock。
    func requestLock() {
        guard permissionManager.isTrusted else {
            permissionManager.ensureTrusted()
            return
        }
        // 若 EventTap 尚未就绪（极端情况），先尝试启动。
        if !servicesStarted {
            startServices()
        }
        lockManager.lock()
    }

    private func startServices() {
        guard !servicesStarted else { return }
        let installed = eventTapManager.start()
        remoteWatcher.start()
        // 即使 tap 安装失败也算尝试过；fail-open 下不强制 servicesStarted。
        servicesStarted = installed
    }
}
