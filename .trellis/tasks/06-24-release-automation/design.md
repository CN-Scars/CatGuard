# Release Automation — Technical Design

## Overview

A new workflow `.github/workflows/release.yml` triggered by `v*` tags (and manual
`workflow_dispatch`). It builds CatGuard unsigned on a macOS runner for three architecture
variants, packages each as a `.dmg` via `create-dmg`, and publishes a GitHub Release with
a templated body and the three dmgs attached.

Existing `ci.yml` is untouched (it stays as the push/PR lint+build+test gate).

## Trigger

```yaml
on:
  push:
    tags: ["v*"]
  workflow_dispatch:
    inputs:
      tag:
        description: "Version tag to build (e.g. v0.2.0), for manual test runs"
        required: true
```

Version derivation: `VERSION="${TAG#v}"` (strip leading `v`). For `push` the tag comes
from `github.ref_name`; for dispatch from `inputs.tag`.

## Build matrix (3 architecture variants)

| Variant | xcodebuild ARCHS | dmg filename |
|---------|------------------|--------------|
| Apple Silicon | `arm64` | `CatGuard_<ver>_aarch64.dmg` |
| Intel | `x86_64` | `CatGuard_<ver>_x64.dmg` |
| Universal | `arm64 x86_64` | `CatGuard_<ver>_universal.dmg` |

Build with explicit archs and no signing:

```bash
xcodebuild -project CatGuard.xcodeproj -scheme CatGuard -configuration Release \
  -destination 'generic/platform=macOS' \
  ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$VERSION" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build clean build
```

> Use **Release** configuration for distribution (existing ci.yml uses Debug for tests).
> The built app: `build/Build/Products/Release/CatGuard.app`.

> **Gotcha to verify**: `ENABLE_DEBUG_DYLIB: false` is already set in project.yml — required
> so the Release app is a single self-contained binary (no debug dylib). Confirm Release
> build also honors it.

## DMG packaging

```bash
brew install create-dmg
create-dmg \
  --volname "CatGuard" \
  --window-size 540 380 \
  --icon-size 100 \
  --icon "CatGuard.app" 150 180 \
  --app-drop-link 390 180 \
  --no-internet-enable \
  "CatGuard_${VERSION}_${ARCH_TAG}.dmg" \
  "build/Build/Products/Release/CatGuard.app"
```

> `create-dmg` exits non-zero in some CI environments even on success (known quirk when it
> can't set certain Finder properties headlessly). Wrap with tolerance: check the dmg file
> exists afterward rather than relying solely on exit code.

## Release publication

Single job builds all three variants sequentially (or a matrix that uploads to one
release). Use `softprops/action-gh-release` (de-facto standard, maintained):

```yaml
- uses: softprops/action-gh-release@v2
  with:
    tag_name: ${{ env.TAG }}
    name: CatGuard ${{ env.VERSION }}
    body_path: release-notes.md      # generated from template, see below
    files: |
      CatGuard_*_aarch64.dmg
      CatGuard_*_x64.dmg
      CatGuard_*_universal.dmg
    draft: false
    prerelease: false
```

If a matrix is used, each variant uploads its own asset to the same release (action-gh-release
appends). Simpler alternative: one job builds all three, then a single release step uploads
all. **Design choice: single job, sequential 3 builds → one release step** (simpler, no
cross-job artifact passing; ~3× build time but acceptable).

## Release notes template

Stored at `.github/release-template.md`, placeholders substituted by the workflow:

```markdown
## CatGuard {{VERSION}}

> 🐈🔒 不锁屏的「输入防猫锁」。

### ✨ 新功能
<!-- 发版后在此补充 -->

### 🐞 修复
<!-- 发版后在此补充 -->

### 🔧 改进
<!-- 发版后在此补充 -->

---

## 下载

| 芯片 | 下载 |
|------|------|
| Apple Silicon (M 系列) | [CatGuard_{{VERSION}}_aarch64.dmg]({{URL_ARM}}) |
| Intel | [CatGuard_{{VERSION}}_x64.dmg]({{URL_X64}}) |
| 通用 (Universal) | [CatGuard_{{VERSION}}_universal.dmg]({{URL_UNIVERSAL}}) |

## 安装

1. 下载对应芯片的 .dmg 并打开，将 CatGuard 拖入「应用程序」
2. **首次打开**：因未签名，需绕过 Gatekeeper —
   右键点 CatGuard.app → 打开 → 在弹窗中再点「打开」；
   或在「系统设置 → 隐私与安全性」点「仍要打开」
3. 启动后到「系统设置 → 隐私与安全性 → 辅助功能」授予 CatGuard 权限
```

The workflow substitutes `{{VERSION}}` and the three `{{URL_*}}` (asset download URLs follow
the predictable pattern
`https://github.com/<owner>/<repo>/releases/download/<tag>/<filename>`).
Changelog sections are left as HTML comments for the developer to fill in on the Release page.

## Files

| File | Change |
|------|--------|
| `.github/workflows/release.yml` (new) | The release pipeline |
| `.github/release-template.md` (new) | Release notes skeleton |
| `README.md` | Add download + Gatekeeper-bypass section |

## Risks

| Risk | Mitigation |
|------|------------|
| `create-dmg` headless exit-code quirk | Verify dmg exists, don't trust exit code alone |
| Unsigned app: users hit Gatekeeper | Documented bypass steps in release notes + README |
| Universal build size/time | Acceptable; single job sequential |
| Xcode version on runner lacks Swift 6.1 (KeyboardShortcuts dep) | Reuse ci.yml's "pick latest Xcode" step |
| Tag pushed but build fails | Release not created; fix & re-tag (or delete tag and re-push) |
