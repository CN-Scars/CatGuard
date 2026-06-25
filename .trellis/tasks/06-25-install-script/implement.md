# 一键安装脚本 — Implementation Plan

## Step 0 — 实现首步必做的本机验证（决定 trust 路径）

- [ ] 实测：生成自签名证书 + `add-trusted-cert` 写 **login keychain**（免 sudo）后，
      `find-identity -p codesigning` 是否列出 + `codesign --sign` 是否成功
- [ ] 若 login keychain trust 即可 → 脚本免 sudo（最优）
- [ ] 若必须 System.keychain（需 sudo）→ 脚本走 sudo 路径
- [ ] 把结论写进脚本注释。**用一个临时证书测试，测完删除，不污染本机现有 CatGuard Self-Signed/Local Dev**

## Step 1 — scripts/install.sh 主体

- [ ] shebang `#!/usr/bin/env bash` + `set -euo pipefail` + `trap cleanup EXIT`
- [ ] 参数解析：`--version vX.Y.Z`、`--uninstall`、`--help`
- [ ] 前置检查：`[[ $(uname) == Darwin ]]`、必需命令（curl/hdiutil/codesign/security/openssl）、非 root
- [ ] 架构检测 + 资产名（design.md）
- [ ] 版本解析：latest（GitHub API）或 --version
- [ ] 下载 dmg（curl -fL，失败报错）

## Step 2 — 证书 ensure_cert()（幂等）

- [ ] 复用检测：`find-identity -v -p codesigning | grep "CatGuard Self-Signed"`
- [ ] 生成（openssl codeSigning EKU）→ p12（SHA1/3DES；空密码失败回退 `catguard`）→ import
- [ ] trust（按 Step 0 结论选 login 或 System keychain）
- [ ] 清理证书临时文件

## Step 3 — 挂载 / 重签 / 安装

- [ ] hdiutil attach → 拷 .app 到临时目录 → detach（trap 兜底 detach）
- [ ] `codesign --force --deep --options runtime --sign "CatGuard Self-Signed"` → `--verify --strict`
- [ ] killall 旧进程 → rm -rf /Applications/CatGuard.app → cp -R → 验证签名
- [ ] 成功提示 + 引导辅助功能授权 + `open`

## Step 4 — --uninstall

- [ ] killall → rm app → 询问是否删证书（`security delete-identity`）→ `tccutil reset Accessibility com.catguard.app`

## Step 5 — 文档

- [ ] README「方式二：脚本安装（推荐）」：命令 + 原理 + 取舍；保留 dmg 直装并标注授权可能不稳定
- [ ] 脚本顶部注释说明用途、依赖、trust 路径结论

## Step 6 — 本机端到端验证（核心验收）

- [ ] 用脚本 `--version v0.2.0` 实际跑一遍（会下载真实 release dmg）
- [ ] `tccutil reset Accessibility com.catguard.app` → 重新授权一次 → 确认 Lock 可用、不再反复要求授权
- [ ] 再跑一次脚本（幂等性：证书复用、覆盖安装不报错）
- [ ] `--uninstall` 验证
- [ ] **注意**：本机当前装的是 `CatGuard Local Dev` 签名的好用版本；脚本验证会改成
      `CatGuard Self-Signed` 签名版。验证后若想恢复，可重新本地构建装回。验证前提示这一点。

## 验证命令

```bash
bash scripts/install.sh --help
shellcheck scripts/install.sh   # 若可用
bash scripts/install.sh --version v0.2.0
```

## Risky Points

| Item | 处理 |
|------|------|
| 改动本机在用的 CatGuard 签名 | Step 6 验证会替换；接受（功能一致），可事后重建恢复 |
| sudo 交互 | 脚本明确提示；文档建议 clone 后运行而非 curl|bash |
| 不碰 Swift / workflow / ci | 仅新增 scripts/install.sh + README |
```
