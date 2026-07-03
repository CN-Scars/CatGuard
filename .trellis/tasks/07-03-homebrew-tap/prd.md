# Homebrew Cask 分发（主仓库内 cask + postflight 重签名）

## Goal

参照 tokenscope 的分发方式，为 CatGuard 提供 Homebrew Cask 安装路径：cask 从 GitHub
Release 下载 dmg，postflight 自动完成「清 quarantine + 本机自签名重签」，让 brew 用户
装完即获得辅助功能授权稳定的 CatGuard。同时完善 README，给 brew / dmg 两种方式各自
清晰的初始化引导。

## 背景（参照对象已调研）

- tokenscope（HduSy/tokenscope）：未签名 Tauri app，自建 Tap，cask postflight 用
  `system_command "/usr/bin/xattr", args: ["-cr", ...]` 清 quarantine → 首次打开无警告
- **关键差异**：tokenscope 不需要辅助功能权限，`xattr -cr` 就够；CatGuard 需要辅助功能，
  授权绑签名 hash，adhoc 绑不住 → cask postflight 必须**重签名**（复用 install.sh 已验证
  的自签名逻辑）
- postflight 本质是以当前用户执行 shell（`system_command`，sudo: false），可以跑
  openssl/security/codesign

## Decisions (resolved)

1. ✅ **postflight 完整重签名**：生成/复用 `CatGuard Self-Signed` 证书 + 重签 + 清 quarantine
   （与 install.sh 同一套逻辑与证书名，两种安装方式共享证书）
2. ✅ **先放主仓库，不建独立 Tap**：cask 文件放 `Casks/catguard.rb`，README 指导用户
   `brew tap` 主仓库或用 raw URL 安装；日后成熟再迁独立 homebrew-catguard 仓库
   （注：`brew tap CN-Scars/CatGuard` 非标准命名也可工作——brew 允许 tap 任意 repo，
   实现时验证；不行则用 `brew install --cask <本地/raw .rb>` 路径并写清文档）
3. ✅ cask url 指向 GitHub Release 的 universal dmg（单一资产，避免 cask 里按架构分流的复杂度）
4. ✅ sha256 用真实 release 资产校验和（发版后需同步更新 cask 的 version/sha256）

## Acceptance Criteria

- [ ] `Casks/catguard.rb`：version/sha256/url(universal dmg)/app + postflight（重签名+清 quarantine）
- [ ] postflight 复用与 install.sh 一致的证书逻辑（同名 `CatGuard Self-Signed`，幂等复用）
- [ ] 本机实测：`brew install --cask` 装上后 app 签名为 CatGuard Self-Signed、无 quarantine、
      能打开；辅助功能授权可稳定绑住（与 install.sh 效果一致）
- [ ] `brew uninstall --cask` 正常卸载
- [ ] README「下载安装」重构为三种方式并给各自初始化步骤：
      brew（推荐）/ install.sh 脚本 / dmg 直装（含右键绕过）
- [ ] cask 文件里 sha256 与线上 v0.2.0 universal dmg 实际一致
- [ ] 发版流程文档补充：发新版后需更新 cask 的 version + sha256

## Out of Scope

- 独立 homebrew-catguard Tap 仓库（后续）
- 提交官方 homebrew-cask（星标门槛未达）
- cask 自动升级 sha256 的 CI 自动化（后续可做）
- Apple Developer 签名/公证

## Open Questions（实现时验证）

- `brew tap CN-Scars/CatGuard`（非 homebrew- 前缀命名）能否工作；不能则文档改用
  raw-url / 本地 .rb 安装路径
- postflight 中 system_command 跑多行 shell 的最佳写法（bash -c 一段脚本 vs 多个 system_command）
