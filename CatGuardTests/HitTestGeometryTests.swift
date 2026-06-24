import CoreGraphics
import XCTest

/// `HitTestGeometry` 纯几何逻辑测试。
///
/// 重点覆盖历史 bug：主屏上方副屏的负 Quartz y 不应被误判为菜单栏。
final class HitTestGeometryTests: XCTestCase {

    // MARK: - quartzToAppKit

    func testQuartzToAppKitFlipsYAroundPrimaryHeight() {
        // 主屏高 1000，Quartz 顶部 (x,0) → AppKit 底部 (x,1000)。
        let top = HitTestGeometry.quartzToAppKit(CGPoint(x: 100, y: 0), primaryHeight: 1000)
        XCTAssertEqual(top, CGPoint(x: 100, y: 1000))

        // Quartz 底部 (x,1000) → AppKit (x,0)。
        let bottom = HitTestGeometry.quartzToAppKit(CGPoint(x: 100, y: 1000), primaryHeight: 1000)
        XCTAssertEqual(bottom, CGPoint(x: 100, y: 0))
    }

    func testQuartzToAppKitPreservesX() {
        let p = HitTestGeometry.quartzToAppKit(CGPoint(x: 42, y: 300), primaryHeight: 800)
        XCTAssertEqual(p.x, 42)
        XCTAssertEqual(p.y, 500)
    }

    // MARK: - isInMenuBar

    func testMenuBarTopEdgeIsInside() {
        XCTAssertTrue(HitTestGeometry.isInMenuBar(quartzY: 0, menuBarHeight: 24))
    }

    func testMenuBarBottomEdgeIsInside() {
        XCTAssertTrue(HitTestGeometry.isInMenuBar(quartzY: 24, menuBarHeight: 24))
    }

    func testMenuBarMiddleIsInside() {
        XCTAssertTrue(HitTestGeometry.isInMenuBar(quartzY: 12, menuBarHeight: 24))
    }

    func testMenuBarBelowStripIsOutside() {
        XCTAssertFalse(HitTestGeometry.isInMenuBar(quartzY: 25, menuBarHeight: 24))
    }

    /// 回归测试：主屏上方的副屏 Quartz y 为负，绝不能被当作菜单栏放行。
    func testMenuBarNegativeYIsOutside() {
        XCTAssertFalse(HitTestGeometry.isInMenuBar(quartzY: -1, menuBarHeight: 24))
        XCTAssertFalse(HitTestGeometry.isInMenuBar(quartzY: -500, menuBarHeight: 24))
    }

    // MARK: - isInFloatingButton

    func testFloatingButtonZeroFrameAlwaysOutside() {
        // 按钮未显示（frame == .zero）时任何点击都不命中。
        XCTAssertFalse(
            HitTestGeometry.isInFloatingButton(
                quartzPoint: CGPoint(x: 10, y: 10),
                windowFrame: .zero,
                primaryHeight: 1000
            ))
    }

    func testFloatingButtonHitInsideFrame() {
        // 主屏高 1000；按钮 AppKit frame 在右上角 (900,920,60,60)，即 y∈[920,980]。
        // 对应 Quartz y∈[20,80]。取 Quartz 点 (920,50) → AppKit (920,950)，落在 frame 内。
        let frame = CGRect(x: 900, y: 920, width: 60, height: 60)
        XCTAssertTrue(
            HitTestGeometry.isInFloatingButton(
                quartzPoint: CGPoint(x: 920, y: 50),
                windowFrame: frame,
                primaryHeight: 1000
            ))
    }

    func testFloatingButtonMissOutsideFrame() {
        let frame = CGRect(x: 900, y: 920, width: 60, height: 60)
        // Quartz (100,500) → AppKit (100,500)，远离 frame。
        XCTAssertFalse(
            HitTestGeometry.isInFloatingButton(
                quartzPoint: CGPoint(x: 100, y: 500),
                windowFrame: frame,
                primaryHeight: 1000
            ))
    }
}
