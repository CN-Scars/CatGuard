# Tag 触发自动打包 DMG 并发布 Release

## Goal

建立发布流水线：开发者推送版本 tag（如 `v0.2.0`）后，GitHub Action 自动在 macOS runner
上构建 CatGuard、打包成 .dmg、创建对应 GitHub Release 并上传 .dmg 资产。

用户价值：一键发版，用户可从 Release 页下载 .dmg 安装试用。

## Confirmed Facts

- 已有 `.github/workflows/ci.yml`（push/PR 触发 lint+build+test），可复用其 Xcode 选择 /
  XcodeGen / 无签名构建逻辑
- 构建产物为 `CatGuard.app`（menu-bar app，LSUIElement）
- CI 用 `macos` runner，动态选最新 Xcode（满足 Swift 6.1+ 依赖）
- 现用本地签名 `CatGuard Local Dev`（仅本机有效，不用于分发）

## Decisions (resolved)

1. ✅ **不签名路线**：dmg 内 App 不做 Developer ID 签名/公证（用户无 Apple Developer 账号）。
   后果：用户下载后首次打开会被 Gatekeeper 拦，需手动右键打开或系统设置放行，
   Apple Silicon 上尤其明显。README 需写明绕过步骤。

## Decisions (resolved, cont.)

2. ✅ **三种架构都打包**：arm64（Apple Silicon）、x86_64（Intel）、universal（通用）各出一个 .dmg，
   共 3 个资产。命名如 `CatGuard_<version>_aarch64.dmg` / `_x64.dmg` / `_universal.dmg`。
3. ✅ **Release description 用 markdown 模板**：参考 clash-verge-rev 风格——版本标题 +
   emoji 分类变更日志（✨新功能/🐞修复/🔧改进等）+ 按架构的下载表（`|` 分隔）+
   安装/绕过 Gatekeeper 说明。模板存为仓库内文件，发布时把变更内容填入。

## Decisions (resolved, cont.)

4. ✅ **版本号 tag 为准**：从 tag 解析（`v0.2.0` → `0.2.0`），构建时
   `xcodebuild ... MARKETING_VERSION=<ver> CURRENT_PROJECT_VERSION=<ver>` 注入。
   project.yml 里的值仅作本地占位，发布版本以 tag 为单一真实来源。
5. ✅ **DMG 工具 `create-dmg`**：CI 中 `brew install create-dmg`，生成带「拖到 Applications」
   引导的标准 dmg。
6. ✅ **触发**：`push` tag 匹配 `v*` 为主路径；同时支持 `workflow_dispatch` 手动触发（便于测试）。
7. ✅ **Release 说明**：Action 自动生成含「下载表 + 安装/绕过 Gatekeeper 说明」的骨架，
   变更条目（✨/🐞/🔧）留给开发者在 Release 页手动编辑。模板存为仓库内文件。

## Acceptance Criteria (draft)

- [ ] push `v*` tag 触发 release workflow
- [ ] 在 macOS runner 构建出 CatGuard.app（复用 CI 构建配置，无签名）
- [ ] 打包为 .dmg
- [ ] 自动创建与 tag 同名的 GitHub Release 并上传 .dmg
- [ ] 不破坏现有 ci.yml
- [ ] README 增补下载安装 + 绕过 Gatekeeper 说明

## Out of Scope

- Developer ID 签名 / 公证（明确不做）
- 自动更新器（Sparkle 等）
- 提交官方 homebrew-cask
