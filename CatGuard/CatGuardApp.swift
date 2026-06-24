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
                onRequestLock: { controller.requestLock() },
                onOpenSettings: { controller.settingsWindowController.show() }
            )
            .environmentObject(controller.lockManager)
        } label: {
            // 图标随锁状态切换：🐈 / 🐈🔒
            Text(controller.lockManager.isLocked ? "🐈🔒" : "🐈")
        }
        .menuBarExtraStyle(.menu)

        // 不使用 SwiftUI Settings 场景：其唤起依赖 SettingsLink / 私有 selector，
        // 在 MenuBarExtra(.menu) 下不可靠。改由 SettingsWindowController 自管理窗口。
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
    let settingsWindowController = SettingsWindowController()

    /// 全局上锁快捷键。lazy 因其回调捕获 self，须在所有属性初始化后再构造。
    private lazy var hotKeyManager = HotKeyManager { [weak self] in
        // 复用菜单 Lock 的同一路径：内含未授权时的权限引导。
        self?.requestLock()
    }

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

        // 注册全局上锁快捷键。底层 Carbon RegisterEventHotKey 独立于 Accessibility
        // 权限，即使未授权也能触发回调（回调内 requestLock 会做权限引导）。
        hotKeyManager.start()

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
