# CatGuard — Roadmap & Design Rationale (archived from spec.md)

This file preserves the post-MVP roadmap and key design rationale from the original
`spec.md`, which has been removed from the repo root. v0.1 implementation details
already live in `prd.md` / `design.md` / `implement.md`; this file captures what was
**not** migrated: future versions and the reasoning behind unlock-method choices.

## Version Roadmap

### v0.1 Prototype — 验证可行性（current MVP, see prd.md/design.md/implement.md）

- 菜单栏图标、手动 Lock/Unlock、输入拦截、Touch ID 解锁、屏幕不黑

### v0.2 Daily Use — 日常可用

- Apple Watch 解锁
- 远程文件解锁
- event tap 自动恢复
- 错误提示
- 简单设置页

### v0.3 Safe Release — 更安全、更可靠

- 解锁 token（远程解锁文件加 `unlock:<token>` 校验 + 时间戳 + owner + 权限检查）
- 本地日志
- 权限引导
- 自动兜底超时（Emergency Timeout，建议 4 小时）
- 浮动解锁按钮完善
- 打包签名和公证

> 注：v0.1 已提前纳入 Apple Watch、远程文件解锁、浮动按钮（见 prd.md 决策），
> 故实际 v0.2/v0.3 剩余项主要是 token 安全、设置页、超时兜底、签名公证。

## Unlock Method Design Rationale

### 优先级

```
1. Touch ID         (主路径，默认中心)
2. Apple Watch      (最舒服的备用)
3. iPhone/Shortcuts (最可靠的兜底)
```

### Touch ID（主）

- 不需键盘；猫无法通过指纹认证；对 MacBook 用户最自然、最快
- 安全策略：默认仅生物认证，不回退密码；失败/取消不解锁
- 限制：不能被动监听传感器，必须先由 App 触发一次系统认证

### Apple Watch（备用）

- 不依赖 MacBook 键盘区域；戴表时方便；MacBook 放远也能认证
- 适合外接屏 / 外接键鼠 / 合盖工作站场景
- 默认作为 Touch ID 之后的备用，可选启用 "Touch ID or Apple Watch" 混合模式

### iPhone / Shortcuts 远程解锁（兜底）

- 实现：`iPhone 快捷指令 → SSH 到 Mac → touch ~/.catguard-unlock`
- 防止"把自己锁在外面"的最佳兜底
- 安全策略：默认不开 HTTP，不监听公网；仅建议局域网 SSH 或 Tailscale SSH
- v0.3 可选 token：`unlock:<random-token>` + 30s 内创建 + owner 校验 + 权限校验

## Recommended Default Config (post-MVP)

```text
Primary Unlock:   Touch ID
Secondary Unlock: Apple Watch
Failsafe Unlock:  iPhone Shortcut / SSH file trigger
Password Fallback: Off
Emergency Timeout: 4 hours (稳妥默认)
Remote unlock token: Optional (v0.3)
```

## Settings (post-MVP, 建议尽量少)

```text
Unlock Methods:  Touch ID / Apple Watch / Remote Unlock File
Security:        Allow password fallback (Off) / Emergency auto-unlock (4h) / Remote unlock token (Optional)
UI:              Show floating unlock button / Show lock-unlock notifications
Advanced:        Unlock file path (~/.catguard-unlock) / Enable command line helper
```

## Failure Scenarios（兜底参考）

- Touch ID 不可用（手指湿/系统禁用/刚重启需密码/失败过多）→ 保持锁定，提示用 Apple Watch 或远程
- Apple Watch 不可用（没戴/未解锁/没电/蓝牙异常）→ 保持锁定，提示用 Touch ID 或远程
- 本机输入入口失效（菜单栏点不动/event tap 异常）→ iPhone 快捷指令或另一台设备 SSH `touch ~/.catguard-unlock`
- App 崩溃 → 输入拦截随进程退出停止，系统恢复正常（fail-open）
- Event Tap 被系统禁用（响应过慢）→ App 自动重启 tap，菜单栏提示异常
