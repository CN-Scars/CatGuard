# Homebrew Cask 分发 — Technical Design

## Overview

主仓库内 `Casks/catguard.rb`。cask 下载 release 的 universal dmg，postflight 执行
「清 quarantine → 确保自签名证书 → 重签 → 校验」，逻辑与 `scripts/install.sh` 一致、
证书同名共享（`CatGuard Self-Signed`）。

## Cask 结构（参照 tokenscope + 我们的重签需求）

```ruby
cask "catguard" do
  version "0.2.0"
  sha256 "<v0.2.0 universal dmg 的真实 sha256>"

  url "https://github.com/CN-Scars/CatGuard/releases/download/v#{version}/CatGuard_#{version}_universal.dmg"
  name "CatGuard"
  desc "Input lock that blocks cat-on-keyboard chaos without locking the screen"
  homepage "https://github.com/CN-Scars/CatGuard"

  depends_on macos: ">= :sequoia"   # macOS 15+

  app "CatGuard.app"

  # 未签名构建：postflight 做两件事（与 scripts/install.sh 同一套逻辑）——
  # 1) 清 quarantine（否则 Gatekeeper 拦首启）
  # 2) 本机自签名重签（辅助功能授权绑签名 hash，adhoc 绑不住；重签后授权稳定）
  postflight do
    system_command "/bin/bash",
                   args: ["-c", RESIGN_SCRIPT],   # 见下
                   sudo: false
  end

  caveats <<~EOS
    CatGuard 需要辅助功能权限：
      系统设置 → 隐私与安全性 → 辅助功能 → 打开 CatGuard
    postflight 已用本机自签名证书重签 App，授权一次后长期保持。
  EOS
end
```

## postflight 的重签脚本（嵌入 cask 的 bash -c 字符串）

复用 install.sh 已验证的核心序列（幂等）：

```bash
set -euo pipefail
APP="/Applications/CatGuard.app"; CN="CatGuard Self-Signed"
# 1) 清 quarantine
/usr/bin/xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
# 2) 证书：已有则复用
if ! /usr/bin/security find-identity -v -p codesigning | grep -qF "$CN"; then
  d=$(mktemp -d)
  cat > "$d/req.conf" <<CONF
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
[dn]
CN=$CN
[v3]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CONF
  /usr/bin/openssl req -x509 -newkey rsa:2048 -keyout "$d/k.pem" -out "$d/c.pem" -days 3650 -nodes -config "$d/req.conf"
  /usr/bin/openssl pkcs12 -export -inkey "$d/k.pem" -in "$d/c.pem" -out "$d/p.p12" -name "$CN" \
    -passout pass:catguard -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES
  /usr/bin/security import "$d/p.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P catguard -T /usr/bin/codesign -A
  /usr/bin/security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$d/c.pem"
  rm -rf "$d"
fi
# 3) 重签 + 校验
/usr/bin/codesign --force --deep --options runtime --sign "$CN" "$APP"
/usr/bin/codesign --verify --strict "$APP"
```

> Ruby 侧用 heredoc 常量嵌入该脚本。工具全用绝对路径（postflight 环境 PATH 可能精简）。
> openssl：macOS /usr/bin/openssl 是 LibreSSL，本会话已验证同参数可用。

## brew 安装路径（文档口径）

优先验证：`brew tap CN-Scars/CatGuard https://github.com/CN-Scars/CatGuard` 后
`brew install --cask catguard`（brew 支持显式 URL tap 任意命名仓库，cask 从 Casks/ 目录发现）。
若该路径有坑，回退文档口径：
`curl -O <raw>/Casks/catguard.rb && brew install --cask ./catguard.rb`。

## README 重构（下载安装 三方式）

1. **方式一 brew（推荐）**：tap + install 命令；说明 postflight 自动重签，装完直接打开，
   只需去系统设置开辅助功能
2. **方式二 install.sh**：保留现有内容（clone 或 curl|bash）
3. **方式三 dmg 直装**：保留，右键绕过 + 授权可能不稳的取舍说明

## 发版联动（文档化，不做自动化）

发新版后手动更新 `Casks/catguard.rb` 的 `version` 与 `sha256`
（`shasum -a 256 CatGuard_<ver>_universal.dmg`）。CHANGELOG/发布流程文档补一句。

## Risks

| 风险 | 缓解 |
|------|------|
| postflight 环境 PATH 精简 | 全部绝对路径 |
| brew tap 非标准命名不工作 | 实测；不行走 raw-url 文档口径 |
| 用户同时用过 install.sh | 证书同名复用，天然幂等兼容 |
| 发版忘更新 cask sha256 | 文档写入发布流程；后续可 CI 自动化 |
| brew 审计（brew audit）对非官方 cask 的告警 | 本地 brew style 检查；非官方 tap 无强制门槛 |
