# CatGuard 🐈🔒

一个 macOS 菜单栏工具，在**不锁屏、不睡眠、不黑屏**的前提下，临时锁定键盘、触控板、鼠标和滚轮输入——防止猫跳上桌后误触打断你正在运行的任务。

> 它不是系统锁屏，而是"输入防猫锁"：屏幕照常显示、后台任务继续运行，但普通输入被吞掉，猫无法干扰电脑。

## 特性

- 🐈 菜单栏常驻，一键上锁（图标变 `🐈🔒`）
- ⌨️ 锁定时拦截键盘 / 鼠标点击 / 触控板 / 滚轮（光标仍可移动）
- 👆 **Touch ID** 解锁（主路径）
- ⌚ **Apple Watch** 解锁（备用）
- 📱 **远程文件解锁**兜底：`touch ~/.catguard-unlock`（iPhone 快捷指令 / SSH）
- 🖥️ 屏幕不黑、不睡眠、不锁屏，任务继续运行
- 🔒 Fail-open：进程退出即恢复输入，绝不把自己锁死
- 🛡️ 不联网、不记录按键、不读文件、不截屏

## 环境要求

- macOS 15+
- Xcode 16+
- [XcodeGen](https://github.com/yonomoto/XcodeGen)：`brew install xcodegen`

## 构建与运行

本仓库**不包含 `.xcodeproj`**（它由 `project.yml` 生成）。克隆后：

```bash
# 1. 生成 Xcode 工程
xcodegen generate

# 2. 用 Xcode 打开
open CatGuard.xcodeproj
#    或命令行构建
xcodebuild -scheme CatGuard -configuration Debug build
```

### 本地签名（避免每次 rebuild 丢授权）

macOS 把辅助功能授权绑定到代码签名哈希；默认 ad-hoc 签名每次编译哈希都变，会导致
授权失效。建议配置一个**稳定的本地自签名身份**，详见
[`.trellis/spec/macos/code-signing-and-tcc.md`](.trellis/spec/macos/code-signing-and-tcc.md)。

## 使用

1. 首次启动后到 **系统设置 → 隐私与安全性 → 辅助功能** 授予 CatGuard 权限
2. 点菜单栏 `🐈` → **Lock** 上锁
3. 回来后点**右上角浮动按钮** → Touch ID 解锁
4. 兜底：在另一设备 `touch ~/.catguard-unlock` 即可解锁

## 开发

```bash
# 格式化
xcrun swift-format format -i -p -r --configuration .swift-format CatGuard CatGuardTests

# Lint（CI 同款）
xcrun swift-format lint --strict -r --configuration .swift-format CatGuard CatGuardTests

# 测试
xcodebuild -scheme CatGuard -configuration Debug test
```

CI（`.github/workflows/ci.yml`）在每次 push / PR 时于 macOS runner 上跑
lint → build → test。

## 架构

| 模块 | 职责 |
|------|------|
| `LockStateManager` | 状态机（unlocked / locked / authenticating）+ 息屏防护 |
| `EventTapManager` | CGEventTap 输入拦截 + 命中测试放行 + 自动恢复 |
| `AuthenticationManager` | LocalAuthentication（Touch ID / Apple Watch） |
| `RemoteUnlockWatcher` | 轮询 `~/.catguard-unlock` 兜底解锁 |
| `FloatingWindowController` | 右上角浮动解锁按钮 |
| `PermissionManager` | Accessibility 权限检查与引导 |
| `HitTestGeometry` | 坐标系换算 + 命中测试（纯函数，可测） |

设计文档见 `.trellis/tasks/06-23-catguard-macos-app/`（prd / design / implement / roadmap）。

## 状态

v0.1 MVP。仅供个人本地使用，暂未签名公证。
