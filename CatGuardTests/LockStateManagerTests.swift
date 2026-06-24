import XCTest

/// `LockStateManager` 状态机测试。
///
/// 验证 design.md 的状态转换规则，以及非法转换被 guard 拦截。
@MainActor
final class LockStateManagerTests: XCTestCase {

    func testInitialStateIsUnlocked() {
        let sut = LockStateManager()
        XCTAssertEqual(sut.state, .unlocked)
        XCTAssertFalse(sut.isLocked)
    }

    // MARK: - 合法转换

    func testLockFromUnlocked() {
        let sut = LockStateManager()
        sut.lock()
        XCTAssertEqual(sut.state, .locked)
        XCTAssertTrue(sut.isLocked)
    }

    func testBeginAuthenticatingFromLocked() {
        let sut = LockStateManager()
        sut.lock()
        sut.beginAuthenticating()
        XCTAssertEqual(sut.state, .authenticating)
        XCTAssertTrue(sut.isLocked)  // authenticating 仍视为锁定
    }

    func testUnlockFromAuthenticating() {
        let sut = LockStateManager()
        sut.lock()
        sut.beginAuthenticating()
        sut.unlock()
        XCTAssertEqual(sut.state, .unlocked)
    }

    func testAuthFailedReturnsToLocked() {
        let sut = LockStateManager()
        sut.lock()
        sut.beginAuthenticating()
        sut.authFailed()
        XCTAssertEqual(sut.state, .locked)
    }

    func testRemoteUnlockFromLocked() {
        let sut = LockStateManager()
        sut.lock()
        sut.remoteUnlock()
        XCTAssertEqual(sut.state, .unlocked)
    }

    func testRemoteUnlockFromAuthenticating() {
        let sut = LockStateManager()
        sut.lock()
        sut.beginAuthenticating()
        sut.remoteUnlock()
        XCTAssertEqual(sut.state, .unlocked)
    }

    // MARK: - 非法转换被 guard 拦截

    func testLockIgnoredWhenAlreadyLocked() {
        let sut = LockStateManager()
        sut.lock()
        sut.lock()  // 应为 no-op，保持 locked
        XCTAssertEqual(sut.state, .locked)
    }

    func testBeginAuthenticatingIgnoredFromUnlocked() {
        let sut = LockStateManager()
        sut.beginAuthenticating()  // unlocked 下非法
        XCTAssertEqual(sut.state, .unlocked)
    }

    func testUnlockIgnoredWhenAlreadyUnlocked() {
        let sut = LockStateManager()
        sut.unlock()  // 已 unlocked，no-op
        XCTAssertEqual(sut.state, .unlocked)
    }

    func testAuthFailedIgnoredWhenNotAuthenticating() {
        let sut = LockStateManager()
        sut.lock()
        sut.authFailed()  // locked 下（非 authenticating）应为 no-op
        XCTAssertEqual(sut.state, .locked)
    }

    // MARK: - 完整往返

    func testFullLockUnlockCycle() {
        let sut = LockStateManager()
        sut.lock()
        sut.beginAuthenticating()
        sut.authFailed()  // 第一次认证失败
        XCTAssertEqual(sut.state, .locked)
        sut.beginAuthenticating()
        sut.unlock()  // 第二次成功
        XCTAssertEqual(sut.state, .unlocked)
    }
}
