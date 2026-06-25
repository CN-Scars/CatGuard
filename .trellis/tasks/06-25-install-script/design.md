# 一键安装脚本 — Technical Design

## Overview

`scripts/install.sh`：检测架构 → 下载最新 release 的对应 dmg → 挂载取出 .app →
本机生成/复用自签名 code-signing 证书（含 trust）→ 重签名 .app → 装到 /Applications →
引导辅助功能授权。仅依赖系统自带工具，无需完整 Xcode。

## 关键事实（本会话实测确认）

- CommandLineTools 无 `xcodebuild`；但 `codesign`/`security`/`openssl`/`hdiutil`/`curl` 均系统自带
- **未 `add-trusted-cert` 的自签名证书不出现在 `find-identity -p codesigning`** → `codesign --sign` 找不到它
  → **trust 步骤必需**（需 sudo 一次）。本机 `CatGuard Local Dev` 即走了 trust，授权稳定可用（活证据）
- p12 必须 `-macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES` 否则 macOS security 拒绝导入
- 重签命令：`codesign --force --deep --options runtime --sign "<cert>" App.app` → `--verify --strict` 通过

## 脚本流程

```
install.sh [--version vX.Y.Z] [--uninstall]
 0. 前置检查：macOS、必需命令存在、非 root 运行（codesign 用当前用户钥匙串）
 1. 解析架构：uname -m → arm64 用 aarch64.dmg，x86_64 用 x64.dmg（取不到则 universal）
 2. 解析版本：默认 GitHub API latest（curl .../releases/latest 取 tag_name）；--version 覆盖
 3. 下载 dmg 到临时目录（mktemp -d；trap 清理）
 4. hdiutil attach -nobrowse -quiet → 拷出 CatGuard.app 到临时目录 → detach
 5. 证书：ensure_cert()
      - security find-identity -v -p codesigning 含 "CatGuard Self-Signed" → 复用
      - 否则 openssl 生成 + import + add-trusted-cert（提示将需密码）
 6. 重签：codesign --force --deep --options runtime --sign "CatGuard Self-Signed" App
      - codesign --verify --strict 校验
 7. 安装：killall 旧进程 → rm -rf /Applications/CatGuard.app → cp -R
 8. 提示：打开系统设置授予辅助功能；首次启动 open /Applications/CatGuard.app
 --uninstall：killall → rm app → 可选 security delete-identity → tccutil reset Accessibility com.catguard.app
```

## 证书创建（ensure_cert，幂等）

```bash
CERT_CN="CatGuard Self-Signed"
if security find-identity -v -p codesigning | grep -q "$CERT_CN"; then
  echo "复用已有证书：$CERT_CN"; return
fi
# 生成（openssl，codeSigning EKU）→ p12（SHA1/3DES）→ import → trust
tmpconf=$(mktemp); cat > "$tmpconf" <<EOF
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
[dn]
CN=$CERT_CN
[v3]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -keyout "$k" -out "$c" -days 3650 -nodes -config "$tmpconf"
openssl pkcs12 -export -inkey "$k" -in "$c" -out "$p12" -name "$CERT_CN" \
  -passout pass: -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES
security import "$p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "" -T /usr/bin/codesign -A
echo "需要管理员权限把自签名证书标记为受信任的代码签名证书（仅一次）："
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$c"
```

> 注：p12 空密码在部分 macOS 上 import 失败，实现时若空密码失败则回退用固定密码（如 `catguard`）。
> trust 写 System.keychain（`-d`）需 sudo；也可写 login keychain 免 sudo 但部分场景 codesign 仍不认——
> 实现首步用本机实测选定可行的最简路径，并把结论写进注释。

## 架构与下载

```bash
case "$(uname -m)" in
  arm64)  ASSET="CatGuard_${VER}_aarch64.dmg" ;;
  x86_64) ASSET="CatGuard_${VER}_x64.dmg" ;;
  *)      ASSET="CatGuard_${VER}_universal.dmg" ;;
esac
URL="https://github.com/CN-Scars/CatGuard/releases/download/v${VER}/${ASSET}"
# latest: curl -fsSL https://api.github.com/repos/CN-Scars/CatGuard/releases/latest | grep tag_name
```

## 健壮性

- `set -euo pipefail`；`trap 'cleanup' EXIT`（detach dmg、rm 临时目录）
- 每步失败给中文可读错误（找不到 release / 下载失败 / 挂载失败 / 签名失败）
- 重复运行幂等（证书复用、覆盖安装）
- 不以 root 运行主体（codesign 用用户钥匙串）；仅 add-trusted-cert / 必要时单独 sudo

## 文档

- README 新增「方式二：脚本安装（推荐，授权稳定）」：一行命令 + 原理（本地自签名解决 TCC 绑定）+ 与 dmg 直装取舍
- 保留现有 dmg 直装说明（标注其辅助功能授权可能不稳定）

## 风险

| 风险 | 缓解 |
|------|------|
| add-trusted-cert 需 sudo，破坏"全自动" | 接受：用户输一次密码；脚本明确提示用途 |
| 不同 macOS 上 p12/trust 行为差异 | 实现首步在本机实测选定路径；空密码失败回退固定密码 |
| 下载的 dmg 仍是 adhoc | 正是脚本要重签的对象，预期内 |
| 用户用 curl|bash 时交互(sudo/密码) | 文档建议 clone 后运行；或脚本检测非交互时提示改用本地运行 |
