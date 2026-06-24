# CatGuard macOS 菜单栏输入锁 App

## Goal

构建一个 macOS 菜单栏工具，在不锁屏、不睡眠、不黑屏的情况下，临时锁定键盘、触控板、鼠标和滚轮输入，防止办公室里的猫跳上桌后误触输入设备。

用户价值：屏幕内容照常显示，后台任务继续运行，猫无法通过普通输入干扰电脑。

## Confirmed Facts

- 平台：macOS 15 Sequoia，最低部署目标 macOS 15，Swift + SwiftUI + AppKit 菜单栏 App
- 菜单栏实现：`MenuBarExtra`（SwiftUI 原生，macOS 13+）
- 输入拦截：CGEventTap，使用 `kCGSessionEventTap` 层（普通 Accessibility 权限，无需 root）
- 解锁优先级：Touch ID > Apple Watch > iPhone/SSH 文件触发
- 认证：LocalAuthentication 框架，App 只接收认证成功/失败结果，不处理生物识别原始数据
- 状态机：Unlocked → Locked → Authenticating → Unlocked/Locked
- 远程解锁：轮询 `~/.catguard-unlock` 文件（0.5~1s 间隔），文件存在即解锁并删除，v0.1 不做 token 校验
- 权限要求：Accessibility/Input Monitoring（必须），LocalAuthentication（系统弹窗，无需额外授权）
- 隐私原则：不联网、不记录按键、不截屏、不读取用户文件

## MVP Scope (v0.1)

- 菜单栏 App，图标 `🐈` / 锁定时 `🐈🔒`
- 点击菜单栏 Lock 上锁
- 锁定时拦截键盘、鼠标、触控板、滚轮（Session 层 CGEventTap）
- 屏幕不黑、不睡眠、不锁屏
- Touch ID 解锁（主路径）
- Apple Watch 解锁（备用）
- iPhone/SSH 文件触发解锁（兜底）
- 基础权限引导提示
- 基础本地日志（os.Logger）
- 无网络、无统计、无自动更新

## Out of Scope (v0.1)

- App Store 发布、签名公证
- 自动更新
- 多语言
- HTTP 控制服务
- 复杂设置 UI
- 快捷键解锁（防猫误触）
- 黑屏清洁模式
- 命令行工具（后续版本）

## Open Questions

1. ~~**Xcode 项目结构**~~ ✅ 已决定：**单 Target**（App only），CLI helper 推迟到后续版本。
2. ~~**浮动解锁按钮**：v0.1 是否包含~~ ✅ 已决定：**v0.1 包含浮动解锁按钮**，右上角半透明小按钮，Event Tap 需识别点击坐标是否落在浮动窗口 frame 内以决定是否放行。
3. ~~**Event Tap 安装位置**：`kCGSessionEventTap` 是否对鼠标移动事件也要拦截~~ ✅ 已决定：**不拦截 MouseMoved**，光标可漂移，点击/滚轮/键盘仍全部拦截。
4. ~~**解锁文件 token 机制**~~ ✅ 已决定：**简单版**，文件存在即解锁，v0.3 再加 token。

## Acceptance Criteria

- [ ] App 启动后菜单栏显示 `🐈` 图标
- [ ] 点击 Lock 后菜单栏变为 `🐈🔒`，键盘/鼠标/触控板/滚轮输入全部被吞掉
- [ ] 屏幕内容不变、不黑屏、不进入屏保
- [ ] 点击菜单栏图标触发 Touch ID 认证，成功后解锁
- [ ] Touch ID 失败/取消后保持锁定状态
- [ ] Apple Watch 认证路径可用
- [ ] `~/.catguard-unlock` 文件存在时自动解锁并删除文件
- [ ] App 崩溃后系统自动恢复正常输入（不永久锁死）
- [ ] 首次启动引导用户开启 Accessibility 权限
- [ ] 本地日志记录 lock/unlock 事件，不记录按键内容
