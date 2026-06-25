#!/usr/bin/env bash
#
# CatGuard 一键安装脚本：下载 release dmg → 本机自签名重签 → 装到 /Applications
# ============================================================================
#
# 为什么需要这个脚本？
#   CI 产出的 dmg 是无签名（adhoc）的，macOS 把「辅助功能（TCC）」授权绑定到代码
#   签名哈希；adhoc 没有稳定身份，导致授权绑不住、反复要求授权后仍无法拦截输入。
#   本脚本在你本机生成一个稳定的自签名 code-signing 证书，用它重签 App，授权即可
#   稳定保持，重装也不丢。
#
# 依赖（全部 macOS 系统自带，无需完整 Xcode）：
#   codesign / security / openssl / hdiutil / curl / uname
#
# trust 路径结论（实测，2026-06）：
#   - 自签名证书 import 后，若未做 add-trusted-cert，不会出现在
#     `security find-identity -p codesigning` 中，codesign --sign 也找不到它
#     → trust 步骤是【必需】的。
#   - trust 写入【login keychain】即可（免 sudo），trust 后 find-identity 列出该
#     证书、codesign --sign 成功、codesign --verify --strict 通过。
#     因此本脚本默认 trust 到 login keychain，全程无需 sudo / 管理员密码。
#   - p12 导出必须用 `-macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES`，
#     否则 security import 失败。且【空密码 p12 在部分 macOS 上 import 失败】
#     （MAC verification failed），故本脚本统一使用固定密码。
#
# 用法：
#   bash scripts/install.sh                 # 安装最新 release
#   bash scripts/install.sh --version v0.2.0  # 安装指定版本
#   bash scripts/install.sh --uninstall     # 卸载
#   bash scripts/install.sh --help
#
# 建议：clone 仓库后本地运行；若用 `curl ... | bash` 请确保在交互终端中，
# 以便必要时正常输入（本脚本默认路径无需密码）。
# ============================================================================

set -euo pipefail

# ---- 常量 ------------------------------------------------------------------
REPO="CN-Scars/CatGuard"
APP_NAME="CatGuard.app"
BUNDLE_ID="com.catguard.app"
INSTALL_DIR="/Applications"
CERT_CN="CatGuard Self-Signed"        # 本脚本专用证书；勿与你本机其它证书混淆
P12_PASS="catguard"                   # 固定密码（空密码在部分 macOS import 失败）
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# ---- 全局状态（供 cleanup 使用）-------------------------------------------
WORKDIR=""
MOUNT_POINT=""

# ---- 颜色/日志 -------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_BLU=$'\033[34m'; C_RST=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_RST=""
fi
info() { printf '%s\n' "${C_BLU}==>${C_RST} $*"; }
ok()   { printf '%s\n' "${C_GRN}✓${C_RST} $*"; }
warn() { printf '%s\n' "${C_YEL}!${C_RST} $*" >&2; }
err()  { printf '%s\n' "${C_RED}✗ $*${C_RST}" >&2; }
die()  { err "$*"; exit 1; }

# ---- 清理（trap）----------------------------------------------------------
cleanup() {
  # 卸载可能仍挂着的 dmg
  if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || \
      hdiutil detach "$MOUNT_POINT" -force -quiet 2>/dev/null || true
  fi
  # 删除临时工作目录
  if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
    rm -rf "$WORKDIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ---- 帮助 ------------------------------------------------------------------
usage() {
  cat <<'EOF'
CatGuard 安装脚本

用法:
  install.sh [选项]

选项:
  --version <vX.Y.Z>   安装指定版本（默认：最新 release）
  --uninstall          卸载 CatGuard（移除 App，可选移除证书并重置授权）
  -h, --help           显示本帮助

说明:
  本脚本下载现成的 release dmg，在你本机用稳定的自签名证书重签 App 后安装，
  以解决「未签名 dmg 的辅助功能授权绑不住」的问题。仅依赖系统自带工具，
  默认无需 sudo / 管理员密码。
EOF
}

# ---- 前置检查 --------------------------------------------------------------
preflight() {
  [[ "$(uname)" == "Darwin" ]] || die "本脚本仅支持 macOS。"
  if [[ "$(id -u)" -eq 0 ]]; then
    die "请勿用 root / sudo 运行本脚本（codesign 需使用当前用户的钥匙串）。"
  fi
  local missing=()
  local cmd
  for cmd in curl hdiutil codesign security openssl uname; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "缺少必需命令：${missing[*]}（这些通常是 macOS 系统自带）。"
  fi
}

# ---- 架构 → 资产名 ---------------------------------------------------------
# 返回首选与兜底（universal）资产名，空格分隔。
asset_candidates() {
  local ver="$1"   # 不含 v 前缀的版本号
  case "$(uname -m)" in
    arm64)  printf '%s %s\n' "CatGuard_${ver}_aarch64.dmg" "CatGuard_${ver}_universal.dmg" ;;
    x86_64) printf '%s %s\n' "CatGuard_${ver}_x64.dmg"     "CatGuard_${ver}_universal.dmg" ;;
    *)      printf '%s\n' "CatGuard_${ver}_universal.dmg" ;;
  esac
}

# ---- 解析最新版本 tag ------------------------------------------------------
resolve_latest_tag() {
  local api="https://api.github.com/repos/${REPO}/releases/latest"
  local json tag
  if ! json="$(curl -fsSL "$api" 2>/dev/null)"; then
    die "无法访问 GitHub API 获取最新版本，请检查网络，或用 --version vX.Y.Z 指定版本。"
  fi
  # 提取 "tag_name": "vX.Y.Z"
  tag="$(printf '%s\n' "$json" \
        | grep -m1 '"tag_name"' \
        | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
  [[ -n "$tag" ]] || die "无法从 GitHub API 解析最新版本 tag。"
  printf '%s\n' "$tag"
}

# ---- 下载 dmg --------------------------------------------------------------
# 入参：tag（含 v）；输出：下载到的 dmg 路径（写入全局 DMG_PATH）
DMG_PATH=""
download_dmg() {
  local tag="$1"
  local ver="${tag#v}"            # 去掉前缀 v
  local base="https://github.com/${REPO}/releases/download/${tag}"
  local candidates
  read -r -a candidates <<< "$(asset_candidates "$ver")"

  local asset url out
  for asset in "${candidates[@]}"; do
    url="${base}/${asset}"
    out="${WORKDIR}/${asset}"
    info "尝试下载：${asset}"
    if curl -fL --progress-bar -o "$out" "$url"; then
      DMG_PATH="$out"
      ok "下载完成：${asset}"
      return 0
    fi
    warn "未找到或下载失败：${asset}，尝试下一个候选…"
  done
  die "无法下载 ${tag} 的可用 dmg（已尝试：${candidates[*]}）。请确认该版本存在对应架构的资产。"
}

# ---- 挂载 dmg 并取出 App ---------------------------------------------------
# 入参：dmg 路径；输出：App 拷贝路径（写入全局 EXTRACTED_APP）
EXTRACTED_APP=""
extract_app() {
  local dmg="$1"
  MOUNT_POINT="$(mktemp -d "${WORKDIR}/mnt.XXXXXX")"
  info "挂载 dmg…"
  hdiutil attach "$dmg" -nobrowse -quiet -mountpoint "$MOUNT_POINT" \
    || die "挂载 dmg 失败：$dmg"

  local src="${MOUNT_POINT}/${APP_NAME}"
  [[ -d "$src" ]] || die "dmg 中未找到 ${APP_NAME}。"

  EXTRACTED_APP="${WORKDIR}/${APP_NAME}"
  info "从 dmg 拷出 App…"
  cp -R "$src" "$EXTRACTED_APP" || die "拷贝 App 失败。"

  hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null \
    || hdiutil detach "$MOUNT_POINT" -force -quiet 2>/dev/null || true
  MOUNT_POINT=""
  ok "已取出 ${APP_NAME}"
}

# ---- 证书：幂等生成/复用 ---------------------------------------------------
# trust 写 login keychain（免 sudo）。详见文件头部 trust 路径结论。
ensure_cert() {
  if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$CERT_CN"; then
    ok "复用已有自签名证书：$CERT_CN"
    return 0
  fi

  info "未发现自签名证书，正在生成「${CERT_CN}」（10 年有效，仅本机使用）…"

  local certdir key cert p12 conf
  certdir="$(mktemp -d "${WORKDIR}/cert.XXXXXX")"
  key="${certdir}/key.pem"
  cert="${certdir}/cert.pem"
  p12="${certdir}/cert.p12"
  conf="${certdir}/req.conf"

  cat > "$conf" <<EOF
[req]
distinguished_name = dn
x509_extensions    = v3
prompt             = no
[dn]
CN = ${CERT_CN}
[v3]
basicConstraints   = critical,CA:false
keyUsage           = critical,digitalSignature
extendedKeyUsage   = critical,codeSigning
EOF

  openssl req -x509 -newkey rsa:2048 -keyout "$key" -out "$cert" \
    -days 3650 -nodes -config "$conf" >/dev/null 2>&1 \
    || { rm -rf "$certdir"; die "openssl 生成自签名证书失败。"; }

  # 关键：SHA1/3DES，否则 macOS security 拒绝导入；固定密码（空密码部分系统失败）
  openssl pkcs12 -export -inkey "$key" -in "$cert" -out "$p12" -name "$CERT_CN" \
    -passout "pass:${P12_PASS}" \
    -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES >/dev/null 2>&1 \
    || { rm -rf "$certdir"; die "生成 p12 失败。"; }

  # 导入 login keychain，授权 codesign 使用，-A 允许所有应用访问私钥
  security import "$p12" -k "$LOGIN_KEYCHAIN" -P "$P12_PASS" \
    -T /usr/bin/codesign -A >/dev/null 2>&1 \
    || { rm -rf "$certdir"; die "导入证书到钥匙串失败。"; }

  # trust：写 login keychain（免 sudo）。trust 后 codesign 才能找到它。
  info "将证书标记为受信任的代码签名证书（写入登录钥匙串，无需密码）…"
  security add-trusted-cert -d -r trustRoot -p codeSign -k "$LOGIN_KEYCHAIN" "$cert" \
    >/dev/null 2>&1 \
    || { rm -rf "$certdir"; die "标记证书为受信任失败。"; }

  rm -rf "$certdir"

  # 校验确实可被 codesign 识别
  if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$CERT_CN"; then
    die "证书已创建但未出现在 codesigning 身份列表中，无法用于签名。"
  fi
  ok "自签名证书已就绪：$CERT_CN"
}

# ---- 重签 App --------------------------------------------------------------
resign_app() {
  local app="$1"
  # 先移除隔离属性（com.apple.quarantine）。从浏览器下载的 dmg 取出的 app 可能带此
  # 属性，会触发 Gatekeeper 拦截；重签前清除可确保安装后直接打开，无需手动右键放行。
  xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
  info "用「${CERT_CN}」重签 App…"
  codesign --force --deep --options runtime --sign "$CERT_CN" "$app" \
    || die "重签 App 失败。"
  info "校验签名（--verify --strict）…"
  codesign --verify --strict --verbose=2 "$app" >/dev/null 2>&1 \
    || die "签名校验未通过（--verify --strict）。"
  ok "签名校验通过"
}

# ---- 安装到 /Applications --------------------------------------------------
install_app() {
  local app="$1"
  local dest="${INSTALL_DIR}/${APP_NAME}"

  # 关闭可能在运行的旧实例
  if pgrep -x "CatGuard" >/dev/null 2>&1; then
    info "关闭正在运行的 CatGuard…"
    killall "CatGuard" 2>/dev/null || true
    sleep 1
  fi

  if [[ -d "$dest" ]]; then
    info "移除旧版本：$dest"
    rm -rf "$dest" || die "无法移除旧版本（可能需要权限）。"
  fi

  info "安装到 ${INSTALL_DIR}…"
  cp -R "$app" "$dest" || die "复制到 ${INSTALL_DIR} 失败。"

  # 安装后再清一次隔离属性，确保首次打开不被 Gatekeeper 拦。
  xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true

  # 复制后再次校验（cp 不应改变签名，保险起见）
  codesign --verify --strict "$dest" >/dev/null 2>&1 \
    || die "安装后签名校验失败。"
  ok "已安装：$dest"
}

# ---- 安装主流程 ------------------------------------------------------------
do_install() {
  local tag="$1"   # 可能为空，表示用最新

  preflight

  WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/catguard-install.XXXXXX")"

  if [[ -z "$tag" ]]; then
    info "解析最新 release 版本…"
    tag="$(resolve_latest_tag)"
    ok "最新版本：$tag"
  else
    # 规整：允许用户传 0.2.0 或 v0.2.0
    [[ "$tag" == v* ]] || tag="v${tag}"
    info "目标版本：$tag"
  fi

  download_dmg "$tag"
  extract_app "$DMG_PATH"
  ensure_cert
  resign_app "$EXTRACTED_APP"
  install_app "$EXTRACTED_APP"

  printf '\n'
  ok "CatGuard ${tag} 安装完成！"
  cat <<EOF

${C_BLU}下一步：授予辅助功能权限${C_RST}
  1. 即将为你打开 CatGuard（首次启动）。
  2. 打开「系统设置 → 隐私与安全性 → 辅助功能」，为 CatGuard 打开开关。
     （因为是稳定的本地签名，授权一次后不会反复失效，重装也不丢。）

如需卸载：bash scripts/install.sh --uninstall
EOF

  # 首次启动（失败不致命）
  open "${INSTALL_DIR}/${APP_NAME}" 2>/dev/null || true
}

# ---- 卸载 ------------------------------------------------------------------
do_uninstall() {
  preflight
  local dest="${INSTALL_DIR}/${APP_NAME}"

  if pgrep -x "CatGuard" >/dev/null 2>&1; then
    info "关闭正在运行的 CatGuard…"
    killall "CatGuard" 2>/dev/null || true
    sleep 1
  fi

  if [[ -d "$dest" ]]; then
    info "移除 ${dest}…"
    if rm -rf "$dest"; then ok "已移除 App"; else warn "移除 App 失败。"; fi
  else
    warn "未发现已安装的 CatGuard（${dest}）。"
  fi

  # 重置辅助功能授权（清掉绑定，便于干净重装）
  if command -v tccutil >/dev/null 2>&1; then
    info "重置 CatGuard 的辅助功能授权…"
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
  fi

  # 可选：移除自签名证书
  if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$CERT_CN"; then
    local ans=""
    if [[ -t 0 ]]; then
      printf '%s' "${C_YEL}是否同时删除本机自签名证书「${CERT_CN}」？[y/N] ${C_RST}"
      read -r ans || ans=""
    fi
    if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
      if security delete-identity -c "$CERT_CN" "$LOGIN_KEYCHAIN" >/dev/null 2>&1; then
        ok "已删除证书：$CERT_CN"
      else
        warn "删除证书失败。"
      fi
    else
      info "保留证书（再次安装可复用）。"
    fi
  fi

  ok "卸载完成。"
}

# ---- 参数解析 --------------------------------------------------------------
main() {
  local version=""
  local action="install"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        [[ $# -ge 2 ]] || die "--version 需要一个参数，如 --version v0.2.0"
        version="$2"; shift 2 ;;
      --version=*)
        version="${1#*=}"; shift ;;
      --uninstall)
        action="uninstall"; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        err "未知参数：$1"; echo; usage; exit 2 ;;
    esac
  done

  case "$action" in
    install)   do_install "$version" ;;
    uninstall) do_uninstall ;;
  esac
}

main "$@"
