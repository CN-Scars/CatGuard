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

## 下载安装

提供两种方式。**若你关心"辅助功能授权能否稳定保持"，推荐方式二（脚本安装）。**

### 方式二：脚本安装（推荐，授权稳定）

> 一行命令：下载现成的 release dmg → 在你本机用稳定的自签名证书重签 App → 装到
> 「应用程序」。**默认无需 sudo / 管理员密码**，仅用 macOS 系统自带工具（`codesign` /
> `security` / `openssl` / `hdiutil` / `curl`），**不需要完整 Xcode**。

```bash
# 克隆仓库后本地运行（推荐）
git clone https://github.com/CN-Scars/CatGuard.git
cd CatGuard
bash scripts/install.sh                 # 安装最新 release
bash scripts/install.sh --version v0.2.0  # 安装指定版本
bash scripts/install.sh --uninstall     # 卸载（移除 App，可选移除证书并重置授权）

# 或直接 curl 运行（请在交互终端中执行）
curl -fsSL https://raw.githubusercontent.com/CN-Scars/CatGuard/main/scripts/install.sh | bash
```

安装完成后，**直接打开即可**（脚本已自动移除隔离属性，无需右键绕过 Gatekeeper），
然后到「**系统设置 → 隐私与安全性 → 辅助功能**」给 CatGuard 打开开关即可。

> 说明：自签名 App 用 `spctl` 评估仍是 `rejected`（因为证书不被 Apple 根信任），但这
> **不影响打开和使用**——脚本已清除 `com.apple.quarantine` 隔离属性，macOS 不会拦截；
> 且辅助功能授权绑定的是签名哈希的稳定性，与 Gatekeeper 评估无关。

**原理 / 为什么推荐**：macOS 把辅助功能（TCC）授权**绑定到代码签名哈希**。release 的
dmg 是无签名（ad-hoc）的，没有稳定身份，导致授权"绑不住"——反复要求授权后仍无法
拦截输入。脚本在你本机生成一个**稳定的自签名 code-signing 证书**（10 年有效，仅本机
使用）并用它重签 App，签名哈希固定，**授权一次即长期保持，重装也不丢**。

### 方式一：直接安装 dmg

到 [Releases 页](https://github.com/CN-Scars/CatGuard/releases) 下载对应芯片的 .dmg：

| 芯片 | 文件 |
|------|------|
| Apple Silicon (M 系列) | `CatGuard_<版本>_aarch64.dmg` |
| Intel | `CatGuard_<版本>_x64.dmg` |
| 通用 (Universal) | `CatGuard_<版本>_universal.dmg` |

安装步骤：

1. 打开 .dmg，把 **CatGuard** 拖进「应用程序」
2. **首次打开**：当前版本未做 Apple 签名/公证，会被 Gatekeeper 拦截。绕过方式（任选其一）：
   - **右键** CatGuard.app → **打开** → 在弹窗中再点「打开」
   - 或到「**系统设置 → 隐私与安全性**」，在被拦提示处点「**仍要打开**」
   （Apple Silicon 上此提示尤为明显，属正常现象）
3. 启动后到「**系统设置 → 隐私与安全性 → 辅助功能**」给 CatGuard 授予权限，
   否则无法拦截输入

> ⚠️ **取舍**：方式一的 dmg 是无签名的，其辅助功能授权**可能不稳定**（系统更新、
> 重装后可能需要重新授权，甚至授权后仍无法拦截）。若遇到"反复要求授权"的问题，
> 请改用**方式二（脚本安装）**。

## 环境要求

- macOS 15+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
  （CI / release 锁定使用 **2.45.4** 以保证 `.xcodeproj` 生成结果可复现；本地用 brew 最新版通常也兼容）

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

### 发布

**发版前**先在 [`CHANGELOG.md`](CHANGELOG.md) 顶部写好对应版本段落（如 `## [0.2.0] - 2026-06-24`，
内部可自由分 ✨ 新功能 / 🐞 修复 / 🔧 改进 小节），再打 tag。

推送 `v*` tag（如 `git tag v0.2.0 && git push origin v0.2.0`）会触发
`.github/workflows/release.yml`：在 macOS runner 上以 Release 配置无签名构建
arm64 / x86_64 / universal 三个变体，各打包成 .dmg，并自动创建同名 GitHub Release
上传这 3 个资产。版本号以 tag 为准（注入 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`）。
也可在 Actions 页用 **workflow_dispatch** 手动触发（填入 tag）做测试。

Release 说明的变更日志会**自动从 `CHANGELOG.md` 提取**：脚本按 tag（去 `v` 前缀）匹配
`## [版本]` 段落，提取到下一个 `## ` 之前的内容填入。**若找不到对应段落**，则填默认占位
文案（“本次更新包含若干改进与修复……”），发布不中断。下载链接由 workflow 动态生成，无需手填。

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

v0.1 MVP。Release 提供的 .dmg 暂未做 Apple 签名/公证，首次打开需按上文绕过 Gatekeeper。
