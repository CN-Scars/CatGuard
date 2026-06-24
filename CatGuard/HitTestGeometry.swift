import CoreGraphics

/// 锁定状态下的点击命中测试几何逻辑（纯函数，无副作用，可单测）。
///
/// 从 `EventTapManager` 抽出，剥离对 `NSScreen` 系统单例的依赖：
/// 屏幕高度作为参数显式传入，便于在测试中覆盖多屏 / 边界场景。
enum HitTestGeometry {

    /// Quartz 全局坐标（左上原点，Y 向下）→ AppKit 坐标（左下原点，Y 向上）。
    /// - Parameter primaryHeight: 主屏高度（origin 在 (0,0) 的那块屏）。
    static func quartzToAppKit(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// 点击是否落在主屏顶部菜单栏条带内。
    ///
    /// 必须有下界 `>= 0`：主屏上方的副屏 Quartz y 为负值，
    /// 缺少下界会把副屏上半部分点击全部误判为菜单栏，导致锁定被绕过。
    static func isInMenuBar(quartzY: CGFloat, menuBarHeight: CGFloat) -> Bool {
        quartzY >= 0 && quartzY <= menuBarHeight
    }

    /// 点击是否落在浮动解锁按钮窗口内。
    /// - Parameter windowFrame: 浮动窗口的 AppKit frame；`.zero` 表示按钮未显示。
    static func isInFloatingButton(
        quartzPoint: CGPoint,
        windowFrame: CGRect,
        primaryHeight: CGFloat
    ) -> Bool {
        guard windowFrame != .zero else { return false }
        return windowFrame.contains(quartzToAppKit(quartzPoint, primaryHeight: primaryHeight))
    }
}
