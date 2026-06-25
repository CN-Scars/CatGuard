# 一键脚本：下载 + 本地自签名 + 安装

## Goal

提供一个一键安装脚本，让没有 Apple Developer 账号、甚至没有完整 Xcode 的用户，也能
顺畅安装并使用 CatGuard（含辅助功能授权稳定不丢）。脚本下载现成的 release dmg，
在用户本机生成稳定的自签名证书并重签名 App，再安装到 /Applications。

用户价值：解决"未签名 dmg 的辅助功能授权绑不住、反复要求授权"的核心痛点。

## 背景与第一性原理（已验证）

- **痛点**：CI 产出的 dmg 是 adhoc/无签名（`CODE_SIGNING_ALLOWED=NO`），其辅助功能（TCC）
  授权绑不住，用户反复被要求授权后仍无法使用（本会话已复现）。
- **根因**：TCC 授权绑定代码签名 hash；adhoc 无稳定身份。
- **关键验证**（本会话实测）：
  - CommandLineTools **没有** `xcodebuild` → "让用户编译"门槛过高（需完整 Xcode 十几 GB），**否决**
  - `codesign` / `security` 是系统自带（`/usr/bin`），**不依赖 Xcode**
  - 对现成 .app 用本地自签名证书 `codesign --force --deep --options runtime --sign` 重签 → 签名有效
  - 纯命令行 openssl 生成 + security import 自签名 code-signing 证书可行
  - 本机 `CatGuard Local Dev` 稳定签名 → 授权绑住 → Lock 可用（活证据）

## Decisions (resolved, 自行敲定)

1. ✅ **方案：下载 dmg + 本地重签名**，不要求用户编译。门槛最低、复用现有 release。
2. ✅ **脚本形态**：仓库内 `scripts/install.sh`，用户 clone 后运行或 `curl -fsSL <raw-url> | bash`。
3. ✅ **证书**：脚本检测本机是否已有名为 `CatGuard Self-Signed` 的 code-signing 证书；
   无则用 openssl 生成（10 年有效）+ 导入 login 钥匙串（`-T /usr/bin/codesign -A`）。幂等。
4. ✅ **架构**：脚本 `uname -m` 判断 arm64/x86_64，下载对应 dmg（universal 兜底）。
5. ✅ **版本**：默认装最新 release（GitHub API 取 latest tag），支持 `--version vX.Y.Z`。
6. ✅ **trust 处理**：优先不依赖 add-trusted-cert（避免 sudo/GUI）；实现首步验证"未 trust 时
   重签 app 授权能否绑住"。若必须 trust，脚本加一步 `sudo security add-trusted-cert`（用户输一次密码，仍可接受）。

## Acceptance Criteria

- [ ] `scripts/install.sh`：检测架构 → 下载最新 release 对应 dmg → 挂载 → 取出 .app
- [ ] 幂等生成/复用本机自签名 code-signing 证书（不重复创建）
- [ ] 用该证书重签名 .app（`--force --deep --options runtime`），`codesign --verify --strict` 通过
- [ ] 安装到 /Applications，卸载旧副本
- [ ] `--uninstall`：移除 app + 可选移除证书 + reset TCC
- [ ] 脚本健壮：set -euo pipefail、错误提示清晰、dmg 用完 detach、临时文件清理、trap 清理
- [ ] 不需要完整 Xcode（仅依赖系统自带 codesign/security/openssl/hdiutil/curl）
- [ ] README + 教程：一键安装命令 + 原理说明 + 与 dmg 直装的取舍
- [ ] **核心验收**：在"重置 TCC 后用脚本安装"场景下，授权一次后稳定可用、Lock 生效、重装不丢

## Out of Scope

- 让用户从源码编译（门槛过高，已否决）
- Apple Developer 签名/公证
- 提交 Homebrew 官方 cask / 自建 Tap（可作后续）

## Open Questions（实现阶段验证，非阻塞）

- 自签名证书未 add-trusted-cert 时，重签 app 的授权能否稳定绑住？（实现首步验证）
