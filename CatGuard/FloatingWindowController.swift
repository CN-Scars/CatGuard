import AppKit
import Combine
import SwiftUI

/// 右上角半透明浮动解锁按钮的窗口控制器。
///
/// 锁定时显示一个 60×60、无边框、半透明、置顶的小窗口；点击触发 Touch ID。
/// `EventTapManager` 通过读取 `windowFrame` 做命中测试，放行落在按钮内的点击。
@MainActor
final class FloatingWindowController: NSObject {

    private let window: NSWindow
    private let lockManager: LockStateManager
    private var cancellable: AnyCancellable?

    /// 按钮窗口的尺寸与边距。
    private let size = CGSize(width: 60, height: 60)
    private let margin: CGFloat = 8

    /// 供 `EventTapManager` 做命中测试的窗口 frame（AppKit 坐标，左下原点）。
    /// 仅在窗口可见时有意义；隐藏时返回 `.zero`。
    var windowFrame: NSRect {
        window.isVisible ? window.frame : .zero
    }

    init(lockManager: LockStateManager, authManager: AuthenticationManager) {
        self.lockManager = lockManager

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false

        let root = FloatingUnlockButton {
            authManager.requestUnlock()
        }
        window.contentView = NSHostingView(rootView: root)

        super.init()

        // 跟随锁状态自动显隐。
        cancellable = lockManager.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state == .unlocked {
                    self.hideButton()
                } else {
                    self.showButton()
                }
            }
    }

    private func positionInTopRight() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = visible.maxX - size.width - margin
        let y = visible.maxY - size.height - margin
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func showButton() {
        positionInTopRight()
        window.orderFront(nil)
    }

    func hideButton() {
        window.orderOut(nil)
    }
}

/// 浮动按钮的 SwiftUI 内容：圆角半透明背景 + 解锁符号。
private struct FloatingUnlockButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                    )
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 60, height: 60)
        .help("Unlock CatGuard")
    }
}
