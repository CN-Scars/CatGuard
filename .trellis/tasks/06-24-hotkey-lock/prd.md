# 快捷键锁定 + 可编辑快捷键设置

## Goal

为 CatGuard 增加全局快捷键上锁功能：用户按下快捷键即可上锁（无需点菜单栏），
并可在菜单栏进入设置自定义该快捷键。首次启动提供一个默认快捷键。

用户价值：离开电脑时一键上锁更快，不必精确点击菜单栏图标。

## Confirmed Facts

- 符合 spec.md 第 8 节设计：快捷键**仅作为上锁入口**，不作为解锁入口（猫可能误触，
  解锁必须经 Touch ID / Apple Watch / 远程文件认证）
- 当前代码无任何 UserDefaults / Settings / HotKey 基础设施，需从零搭建
- 现有上锁入口：`AppController.requestLock()`（菜单栏 Lock 按钮调用）
- 平台 macOS 15，Swift + SwiftUI，菜单栏用 MenuBarExtra

## Decisions (resolved)

1. ✅ **热键实现**：引入第三方库 [`KeyboardShortcuts`](https://github.com/sindresorhus/keyboardshortcuts)
   （sindresorhus，SPM，MIT，High reputation）。封装全局热键 + 自带 SwiftUI `Recorder`
   组件 + 自动持久化（内部 UserDefaults）+ `initial:` 默认值。打破了原"零依赖"原则，
   但换取成熟稳定的录制 UI 与持久化，用户已确认接受。
2. ✅ **默认快捷键**：`⌘⌥⌃L`（Command+Option+Control+L），L=Lock 好记，三修饰键独特不撞系统。
3. ✅ **设置 UI**：标准 SwiftUI `Settings { }` 窗口，菜单新增 "Settings…"。Recorder 需键盘
   焦点，必须在真实窗口（不能塞进 NSMenu，会与已知 MenuBarExtra/NSMenu 限制同源）。
4. ✅ **持久化**：由库自动处理，无需自建 UserDefaults 层。
5. ✅ **权限**：`RegisterEventHotKey`（库底层用 Carbon）独立于 Accessibility 权限工作，
   上锁热键即使未授予辅助功能也能触发（但 event tap 拦截仍需权限——与现有逻辑一致）。

## Confirmed Facts (API, via Context7)

- `KeyboardShortcuts.Name("lockNow", initial: .init(.l, modifiers: [.command, .option, .control]))`
  — 定义名称 + 默认值
- `KeyboardShortcuts.Recorder("Lock shortcut:", name: .lockNow)` — 录制 UI 组件
- `KeyboardShortcuts.onKeyUp(for: .lockNow) { ... }` — 全局触发回调（用 keyUp 避免长按重复）
- `KeyboardShortcuts.reset(.lockNow)` — 恢复默认

## Acceptance Criteria

- [ ] 按下 `⌘⌥⌃L`（或用户自定义键）即可上锁，CatGuard 不在前台也生效
- [ ] 触发路径复用现有 `AppController.requestLock()`（含未授权时的权限引导）
- [ ] 菜单新增 "Settings…"，打开标准设置窗口（LSUIElement 应用需 `NSApp.activate` 唤起）
- [ ] 设置窗口含 `KeyboardShortcuts.Recorder` 可编辑快捷键 + "恢复默认"按钮
- [ ] 首次启动默认快捷键为 `⌘⌥⌃L`
- [ ] 自定义快捷键重启后保留（库自动持久化）
- [ ] 快捷键只上锁不解锁（解锁仍仅 Touch ID / Apple Watch / 远程文件）
- [ ] 现有 22 个单测仍通过，swift-format lint 与 CI 全绿
- [ ] SPM 依赖在 `project.yml` 中声明，CI（无签名构建）能拉取并编译

## Out of Scope

- 解锁快捷键（设计上明确不做）
- 多组快捷键 / 宏
- 其它设置项（解锁方式开关、超时等，留待 v0.2）

## Out of Scope

- 解锁快捷键（设计上明确不做）
- 多组快捷键 / 宏
