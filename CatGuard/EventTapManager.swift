import AppKit
import CoreGraphics
import os

/// CGEventTap 生命周期与回调管理。
///
/// 使用 `.cgSessionEventTap` 会话层（普通 Accessibility 权限，无需 root）。
/// 锁定时吞掉键盘 / 鼠标点击 / 拖拽 / 滚轮事件；故意不拦截 `mouseMoved`，
/// 因此光标仍可漂移。落在浮动解锁按钮或菜单栏区域的点击会被放行。
///
/// Fail-open：进程退出时 tap 由内核自动拆除，系统恢复正常输入。
///
/// 线程模型：tap 装在主 run loop 的 `.commonModes`，回调在主线程执行，
/// 因此回调内访问 `lockManager` / `floatingController` 的主线程状态是安全的。
final class EventTapManager {

    private let logger = Logger(subsystem: "com.catguard.app", category: "state")

    private let lockManager: LockStateManager
    private let floatingController: FloatingWindowController

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// 菜单栏顶部条带高度（Quartz 坐标，自顶部向下），用于放行菜单栏点击。
    private let menuBarHeight: CGFloat = 24

    init(lockManager: LockStateManager, floatingController: FloatingWindowController) {
        self.lockManager = lockManager
        self.floatingController = floatingController
    }

    // MARK: - Lifecycle

    /// 创建并启用 event tap。需在 Accessibility 权限确认后调用。
    /// - Returns: 是否成功安装。失败时 fail-open（不拦截任何输入）。
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        // 故意不含 .mouseMoved：光标可漂移。
        let interestedTypes: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel,
        ]
        let mask: CGEventMask = interestedTypes.reduce(into: CGEventMask(0)) { acc, type in
            acc |= (CGEventMask(1) << CGEventMask(type.rawValue))
        }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo).takeUnretainedValue()
            return manager.handle(type: type, event: event)
        }

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            // 通常是 Accessibility 权限未授予。Fail-open。
            logger.error("tap-create-failed")
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    // MARK: - Callback

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 自动恢复：系统因回调超时 / 用户输入而禁用 tap 时重新启用。
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.info("tap-disabled")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                logger.info("tap-restored")
            }
            return nil
        }

        // 未锁定：全部放行。
        guard isLockedNow() else {
            return Unmanaged.passUnretained(event)
        }

        // 锁定中。鼠标点击 / 拖拽需做命中测试放行浮动按钮与菜单栏。
        if isMouseEvent(type) {
            let location = event.location  // Quartz 全局坐标，左上原点
            if isHitFloatingButton(location) || isHitMenuBar(location) {
                return Unmanaged.passUnretained(event)
            }
        }

        // 其余（键盘 / 滚轮 / 非命中区域的点击）一律吞掉。
        return nil
    }

    private func isLockedNow() -> Bool {
        // 回调运行在主线程；安全地同步读取 @MainActor 状态。
        MainActor.assumeIsolated { lockManager.isLocked }
    }

    private func isMouseEvent(_ type: CGEventType) -> Bool {
        switch type {
        case .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return true
        default:
            return false
        }
    }

    // MARK: - Hit Testing

    /// 主屏高度（origin 在 (0,0) 的那块屏），用于 Quartz↔AppKit 坐标换算。
    private var primaryScreenHeight: CGFloat {
        NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? 0
    }

    private func isHitFloatingButton(_ quartzPoint: CGPoint) -> Bool {
        let frame = MainActor.assumeIsolated { floatingController.windowFrame }
        return HitTestGeometry.isInFloatingButton(
            quartzPoint: quartzPoint,
            windowFrame: frame,
            primaryHeight: primaryScreenHeight
        )
    }

    private func isHitMenuBar(_ quartzPoint: CGPoint) -> Bool {
        HitTestGeometry.isInMenuBar(quartzY: quartzPoint.y, menuBarHeight: menuBarHeight)
    }
}
