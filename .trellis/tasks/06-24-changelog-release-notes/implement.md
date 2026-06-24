# CHANGELOG-driven Release Notes — Implementation Plan

## Ordered Checklist

### Step 1 — Create CHANGELOG.md

- [ ] Keep-a-Changelog style header (中文)
- [ ] `## [0.2.0] - <date>` block: 本次累积变更（快捷键上锁+设置窗口、发布流水线、
      CHANGELOG 机制、App 图标、gitignore/gitattributes 等），分 ✨/🐞/🔧
- [ ] `## [0.1.0] - 2026-06-24` block: 简述 MVP（防猫输入锁 / Touch ID / Apple Watch / 远程解锁）
- [ ] 日期用占位（脚本不解析日期；写实际日期即可，避免脚本里用 date 命令）

### Step 2 — Update release-template.md

- [ ] 删除 ✨/🐞/🔧 三个固定小节
- [ ] 在标题下、`---` 之上放单行 `{{CHANGELOG}}`
- [ ] 下载表 + 安装说明保持不变

### Step 3 — Update release.yml "Generate release notes" step

- [ ] 加 `extract_changelog`：awk 提取 `## [VERSION]` 到下一个 `## ` 的内容，写入 changelog_block.txt
- [ ] 去除首尾空行
- [ ] fallback：空则写默认占位文案 + `::warning::`
- [ ] 用 file-based awk splice 把 changelog_block.txt 注入 `{{CHANGELOG}}`（避免 -v 转义问题）
- [ ] 再跑原有 VERSION / URL 的 sed 替换 → release-notes.md
- [ ] 保留 `cat release-notes.md` 的 debug 输出

### Step 4 — Update README 发布 section

- [ ] 说明：发版前在 CHANGELOG.md 写好 `## [新版本]` 段落，再打 tag
- [ ] 简述自动提取行为 + fallback

### Step 5 — Local verification (no GitHub needed)

- [ ] 本地模拟提取：`VERSION=0.2.0`，跑 awk 提取逻辑，确认输出正确段落
- [ ] 本地模拟 fallback：`VERSION=9.9.9`（不存在）→ 确认得到占位文案
- [ ] 本地模拟完整替换：手动设 VERSION/URL 变量跑 awk-splice + sed，
      检查产出的 release-notes.md：无残留 `{{...}}`、changelog 内容正确、下载链接正确
- [ ] actionlint .github/workflows/release.yml（若可用）

### Step 6 — GitHub verification (主会话, 测试 tag)

- [ ] 合并到 main 后，push `v0.0.2-test` → 确认 Release 描述含 0.2.0... 等内容
      （注意：测试 tag 版本号需在 CHANGELOG 里有对应段落才非 fallback；
      或专门验证 fallback 行为）
- [ ] 删除测试 tag/release

## Validation Commands

```bash
# 本地提取测试
awk -v ver="0.2.0" '$0 ~ "^## \\[" ver "\\]"{c=1;next} c&&/^## /{exit} c{print}' CHANGELOG.md

# actionlint
actionlint .github/workflows/release.yml
```

## Risky Points

| Item | Risk | Action |
|------|------|--------|
| 多行/特殊字符注入 | sed 多行失败 | 用 file-based awk splice |
| 版本头匹配 | v 前缀/空格/日期 | 匹配 `## [VERSION]`，VERSION 已去 v，允许尾随日期 |
| 不碰 ci.yml / Swift 代码 | 范围蔓延 | 仅改 release.yml + 模板 + CHANGELOG + README |

## Notes

- 不改动 ci.yml、不碰 Swift 源码、不动下载链接生成逻辑。
- 测试 tag 验证时清理干净。
