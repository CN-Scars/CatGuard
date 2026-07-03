# Homebrew Cask 分发 — Implementation Plan

## Step 0 — 前置事实收集

- [ ] `shasum -a 256` 计算线上 v0.2.0 universal dmg 的真实 sha256（下载后算）
- [ ] `brew --version` 确认本机 brew 可用

## Step 1 — Casks/catguard.rb

- [ ] 按 design.md 写 cask：version 0.2.0 / 真实 sha256 / universal dmg url / app
- [ ] postflight：`system_command "/bin/bash", args: ["-c", <重签脚本>], sudo: false`
      重签脚本与 install.sh 同逻辑（清 quarantine → 幂等证书 → 重签 → 校验），
      全绝对路径
- [ ] caveats：辅助功能授权指引
- [ ] `brew style --cask Casks/catguard.rb`（或 brew audit）过一遍，修 style 问题

## Step 2 — 本机实测（核心验收）

- [ ] 先卸载现有 /Applications/CatGuard.app（保留证书）
- [ ] 验证 tap 路径：`brew tap cn-scars/catguard https://github.com/CN-Scars/CatGuard`
      （需 cask 已推到 main；若 tap 验证需先推，可先用本地文件方式装：
      `brew install --cask ./Casks/catguard.rb`）
- [ ] `brew install --cask` 成功；装后验证：
      - `codesign -dvv /Applications/CatGuard.app` → Authority=CatGuard Self-Signed
      - `xattr -l` 无 quarantine
      - app 能直接打开
- [ ] `brew uninstall --cask catguard` 正常
- [ ] 重装幂等（证书复用）

## Step 3 — README 重构

- [ ] 「下载安装」改为三方式：brew（推荐，含 tap+install 命令与初始化说明）/
      install.sh（保留）/ dmg 直装（保留）
- [ ] 发布流程文档补：发新版后更新 cask version+sha256

## Step 4 — 提交与验证

- [ ] feature 分支 + PR + CI 绿 + 合并
- [ ] 合并后（cask 在 main 上）再真实验证一次 brew tap 路径
- [ ] spec 沉淀：cask postflight 重签模式

## 验证命令

```bash
shasum -a 256 CatGuard_0.2.0_universal.dmg
brew style --cask Casks/catguard.rb
brew install --cask ./Casks/catguard.rb
codesign -dvv /Applications/CatGuard.app
brew uninstall --cask catguard
```

## Risky Points

| Item | 处理 |
|------|------|
| 本机已装 CatGuard（Self-Signed 版） | 测前先删 app（证书保留复用） |
| brew tap 非标准命名 | 实测；失败则 README 用本地 .rb 口径 |
| postflight 失败导致 brew 报错 | 脚本 set -e + 绝对路径；先本地 bash -c 干跑该脚本 |
