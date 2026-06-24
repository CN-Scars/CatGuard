# Release Automation — Implementation Plan

## Prerequisites

- Existing ci.yml works; repo builds via XcodeGen
- No secrets needed (unsigned route)

## Ordered Checklist

### Step 1 — Release notes template

- [ ] Create `.github/release-template.md` with `{{VERSION}}`, `{{URL_ARM}}`,
      `{{URL_X64}}`, `{{URL_UNIVERSAL}}` placeholders + changelog sections (HTML comments)
      + 下载表 + 安装/绕过 Gatekeeper 说明 (see design.md)

### Step 2 — Release workflow skeleton

- [ ] Create `.github/workflows/release.yml`
- [ ] `on: push: tags: ["v*"]` + `workflow_dispatch` with `tag` input
- [ ] `permissions: contents: write` (needed to create releases)
- [ ] `runs-on: macos-15`
- [ ] Derive `VERSION` and `TAG` env from `github.ref_name` or `inputs.tag`
- [ ] Steps: checkout → select latest Xcode (reuse ci.yml logic) → install xcodegen +
      create-dmg → `xcodegen generate`

### Step 3 — Build 3 variants

- [ ] For each (arm64 / x86_64 / arm64+x86_64): `xcodebuild` Release, no signing,
      inject MARKETING_VERSION/CURRENT_PROJECT_VERSION, with `ARCHS` + `ONLY_ACTIVE_ARCH=NO`
- [ ] Verify each output: `build/Build/Products/Release/CatGuard.app` exists; check arch
      with `lipo -info CatGuard.app/Contents/MacOS/CatGuard`
- [ ] Clean build dir between variants (avoid arch bleed)

### Step 4 — Package dmgs

- [ ] `create-dmg` per variant → `CatGuard_<ver>_<archtag>.dmg`
- [ ] Tolerate create-dmg exit code: assert dmg file exists afterward
- [ ] (arch tags: `aarch64`, `x64`, `universal`)

### Step 5 — Generate release notes

- [ ] Substitute `{{VERSION}}` and `{{URL_*}}` in template → `release-notes.md`
      (URLs: `https://github.com/${{ github.repository }}/releases/download/<tag>/<file>`)

### Step 6 — Publish release

- [ ] `softprops/action-gh-release@v2`: tag_name, name `CatGuard <ver>`, body_path,
      files = 3 dmgs, draft:false

### Step 7 — README

- [ ] Add "下载安装" section: download table + Gatekeeper bypass (right-click open /
      系统设置 放行) + Accessibility 授权提醒

### Step 8 — Verify (manual, real tag)

- [ ] Local dry-run of build+dmg commands using the workflow's exact xcodebuild line
      (DEVELOPER_DIR=~/Downloads/Xcode.app) to confirm Release build + create-dmg work
- [ ] Push a test tag (e.g. `v0.0.1-test`) OR use workflow_dispatch → confirm:
      - workflow runs green
      - release created with 3 dmgs
      - each dmg mounts, app launches (after Gatekeeper bypass)
      - `lipo -info` shows correct arch per variant
- [ ] Delete test tag/release after验证

## Validation Commands

```bash
# Local dry-run of one variant (universal):
xcodebuild -project CatGuard.xcodeproj -scheme CatGuard -configuration Release \
  -destination 'generic/platform=macOS' ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="0.0.1" CURRENT_PROJECT_VERSION="0.0.1" \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build clean build
lipo -info build/Build/Products/Release/CatGuard.app/Contents/MacOS/CatGuard

# yamllint / actionlint if available
actionlint .github/workflows/release.yml
```

## Risky Points / Rollback

| Item | Risk | Action |
|------|------|--------|
| create-dmg exit code | false failure | check file existence, not exit code |
| Release config + ENABLE_DEBUG_DYLIB | startup crash if debug dylib leaks | verify Release app is single binary |
| permissions: contents: write | release step 403 | ensure permissions block present |
| test tag pollution | leftover test releases | delete after dry-run |

## Notes

- This task does NOT touch ci.yml. Both workflows coexist.
- Homebrew Tap update is out of scope (separate future task).
