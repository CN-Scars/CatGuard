# CatGuard Homebrew Cask
#
# 未签名构建：postflight 做两件事（与 scripts/install.sh 同一套逻辑、同名证书）——
#   1) 清 quarantine（否则 Gatekeeper 拦首启）
#   2) 本机自签名重签（辅助功能 TCC 授权绑签名 hash，adhoc 绑不住；重签后授权稳定）
#
# 发新版后需同步更新 version 与 sha256：
#   shasum -a 256 CatGuard_<ver>_universal.dmg
cask "catguard" do
  version "0.2.0"
  sha256 "efeac817528e6a4027bc72eac5854f450d44d028014c43716e0dca3a3617c015"

  url "https://github.com/CN-Scars/CatGuard/releases/download/v#{version}/CatGuard_#{version}_universal.dmg"
  name "CatGuard"
  desc "Input lock that blocks cat-on-keyboard chaos without locking the screen"
  homepage "https://github.com/CN-Scars/CatGuard"

  # brew 6.x 语义：symbol 形式即最低版本（上限才用 maximum_macos）
  depends_on macos: :sequoia

  app "CatGuard.app"

  # 重签脚本（与 scripts/install.sh 核心序列一致，幂等）。
  # 注意：单引号 heredoc（<<~'BASH'），避免 bash 的 $ 变量被 Ruby 插值吃掉；
  # postflight 环境 PATH 可能精简，工具全部使用绝对路径。
  resign_script = <<~'BASH'
    set -euo pipefail
    APP="/Applications/CatGuard.app"
    CN="CatGuard Self-Signed"
    KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

    # 1) 清 quarantine
    /usr/bin/xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

    # 2) 证书：已有则复用（与 install.sh 共享同名证书，幂等）
    if ! /usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -qF "$CN"; then
      d="$(/usr/bin/mktemp -d)"
      /bin/cat > "$d/req.conf" <<CONF
    [req]
    distinguished_name = dn
    x509_extensions    = v3
    prompt             = no
    [dn]
    CN = $CN
    [v3]
    basicConstraints   = critical,CA:false
    keyUsage           = critical,digitalSignature
    extendedKeyUsage   = critical,codeSigning
    CONF
      /usr/bin/openssl req -x509 -newkey rsa:2048 -keyout "$d/key.pem" -out "$d/cert.pem" \
        -days 3650 -nodes -config "$d/req.conf" >/dev/null 2>&1
      # p12 必须 SHA1/3DES 且非空密码，否则 security import 失败（install.sh 已验证）
      /usr/bin/openssl pkcs12 -export -inkey "$d/key.pem" -in "$d/cert.pem" -out "$d/cert.p12" \
        -name "$CN" -passout pass:catguard \
        -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES >/dev/null 2>&1
      /usr/bin/security import "$d/cert.p12" -k "$KEYCHAIN" -P catguard \
        -T /usr/bin/codesign -A >/dev/null 2>&1
      # trust 写 login keychain（免 sudo）；trust 后 codesign 才能找到该身份
      /usr/bin/security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" "$d/cert.pem" >/dev/null 2>&1
      /bin/rm -rf "$d"
    fi

    # 3) 重签 + 校验
    /usr/bin/codesign --force --deep --options runtime --sign "$CN" "$APP"
    /usr/bin/codesign --verify --strict "$APP"
  BASH

  postflight do
    system_command "/bin/bash",
                   args: ["-c", resign_script],
                   sudo: false
  end

  uninstall quit: "com.catguard.app"

  caveats <<~EOS
    CatGuard 需要辅助功能权限才能拦截输入：
      系统设置 → 隐私与安全性 → 辅助功能 → 打开 CatGuard

    安装时已用本机自签名证书（CatGuard Self-Signed）重签 App 并清除隔离属性，
    可直接打开，辅助功能授权一次后长期保持。
  EOS
end
