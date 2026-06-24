# CHANGELOG-driven Release Notes — Technical Design

## Overview

Replace the hand-filled changelog sections in the release body with content extracted
from a repo-maintained `CHANGELOG.md`. The download-link substitution stays exactly as is.

## Files

| File | Change |
|------|--------|
| `CHANGELOG.md` (new) | Keep-a-Changelog style; one `## [version]` block per release |
| `.github/release-template.md` | Replace the three ✨🐞🔧 sections with a single `{{CHANGELOG}}` placeholder |
| `.github/workflows/release.yml` | Add a step to extract the version block and substitute `{{CHANGELOG}}` |
| `README.md` | Update 发布 section: write CHANGELOG.md before tagging |

## CHANGELOG.md format

```markdown
# Changelog

本项目所有重要变更记录于此。遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/)
风格，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.2.0] - 2026-06-24
### ✨ 新功能
- 全局快捷键上锁（默认 ⌘⌥⌃L）+ 设置窗口可编辑快捷键
- 发布流水线：push tag 自动打包 3 架构 DMG 并发布 Release

### 🔧 改进
- 自动从 CHANGELOG.md 生成 Release 说明
- 新增 App 图标；语言统计排除工具目录

## [0.1.0] - 2026-06-24
- 首个版本：防猫输入锁 MVP（Touch ID / Apple Watch / 远程文件解锁）
```

> Version header matched on the bracketed version number only; trailing `- date` is allowed
> and ignored by the matcher.

## Extraction logic (awk)

Extract lines between `## [<VERSION>]` and the next `## ` header:

```bash
extract_changelog() {
  local version="$1" file="CHANGELOG.md"
  [ -f "$file" ] || { echo ""; return; }
  awk -v ver="$version" '
    # match "## [ver]" with optional trailing text (date)
    $0 ~ "^## \\[" ver "\\]" { capture=1; next }
    capture && /^## / { exit }      # next version header ends the block
    capture { print }
  ' "$file"
}
```

Workflow step:

```bash
CHANGELOG_BODY="$(extract_changelog "$VERSION")"
# strip leading/trailing blank lines
CHANGELOG_BODY="$(printf '%s\n' "$CHANGELOG_BODY" | sed -e '/./,$!d' | tac | sed -e '/./,$!d' | tac)"
if [ -z "$CHANGELOG_BODY" ]; then
  CHANGELOG_BODY="本次更新包含若干改进与修复。详细变更请见提交历史。"
  echo "::warning::No CHANGELOG.md entry for $VERSION, using fallback text"
fi
```

## Substitution into template

`{{CHANGELOG}}` is multi-line, so `sed s|...|...|` (single-line) won't work cleanly. Use a
placeholder-replace approach robust to multi-line + special chars — write changelog to a
file and use awk to splice:

```bash
# template has a line containing exactly {{CHANGELOG}}
awk -v cl="$CHANGELOG_BODY" '
  /{{CHANGELOG}}/ { print cl; next }
  { print }
' .github/release-template.md > /tmp/step1.md

# then the existing VERSION / URL sed substitutions on /tmp/step1.md
sed -e "s|{{VERSION}}|${VERSION}|g" \
    -e "s|{{URL_ARM}}|${URL_ARM}|g" \
    -e "s|{{URL_X64}}|${URL_X64}|g" \
    -e "s|{{URL_UNIVERSAL}}|${URL_UNIVERSAL}|g" \
    /tmp/step1.md > release-notes.md
```

> **Gotcha**: passing multi-line content via `awk -v` works, but if the changelog contains
> backslashes awk may interpret escapes. Safer: read changelog from a file inside awk with
> `getline`. Implementation should prefer the file-based splice to avoid `-v` escape issues:
>
> ```bash
> awk 'FNR==NR{buf=buf $0 ORS; next} /{{CHANGELOG}}/{printf "%s", buf; next} {print}' \
>     changelog_block.txt .github/release-template.md > /tmp/step1.md
> ```
> (changelog_block.txt = the extracted block written to a temp file.)

## release-template.md (after)

```markdown
## CatGuard {{VERSION}}

> 🐈🔒 不锁屏的「输入防猫锁」。

{{CHANGELOG}}

---

## 下载
... (unchanged table with {{URL_*}}) ...

## 安装
... (unchanged) ...
```

## Ordering in workflow

The new extraction happens inside the existing "Generate release notes" step, before the
final `softprops/action-gh-release`. No new job, no new trigger.

## Risks

| Risk | Mitigation |
|------|------------|
| Multi-line / special-char substitution breaks | Use file-based awk splice, not `sed`/`-v` |
| Version header mismatch (`v` prefix, spacing) | Match on `## [VERSION]` with VERSION already v-stripped; allow trailing date |
| Forgot to add CHANGELOG entry | Fallback text, workflow still succeeds |
| Regex special chars in VERSION (e.g. test tags) | VERSION is numeric/dotted; safe in awk regex. Pre-release suffixes like `-test` contain `-` (safe in bracket-literal context) |
