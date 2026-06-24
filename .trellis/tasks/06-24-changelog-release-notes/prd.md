# CHANGELOG 驱动的 Release 说明自动填充

## Goal

升级发布流水线（方案 B / clash-verge 式）：维护仓库内 `CHANGELOG.md`，发版时
release workflow 自动提取当前版本段落填入 Release 说明的变更日志部分，无需在
Release 页手填。下载链接的动态生成保持不变。

用户价值：变更日志进版本控制、可追溯、随 tag 一起管理；发版一步到位。

## Confirmed Facts

- 现有 `release.yml` 的 "Generate release notes" 步骤已用 sed 动态填入 `{{VERSION}}`
  和三个 `{{URL_*}}` 下载链接 —— **这部分保持不变**
- 现有 `release-template.md` 把变更分 ✨/🐞/🔧 三个固定小节（HTML 注释占位，手填）
- v0.1.0 已发布（变更日志留白），保持原样不回填

## Decisions (resolved)

1. ✅ **方案 A 整段注入**：模板删掉固定三小节，改用单个 `{{CHANGELOG}}` 占位符；
   脚本从 `CHANGELOG.md` 提取当前版本段落整体填入。版本内如何分小节（✨🐞🔧）
   由 CHANGELOG.md 自由决定。
2. ✅ **CHANGELOG 格式**：每版一个 `## [版本号]` 段落（可带日期，如 `## [0.2.0] - 2026-06-24`）。
   脚本按 `VERSION`（tag 去 v 前缀）匹配版本号部分，提取到下一个 `## ` 之前的内容。
3. ✅ **fallback**：找不到对应版本段落时填默认占位文案，**发布不中断**（参考 clash-verge）。
4. ✅ **v0.1.0 不回填**，新机制从 v0.2.0 启用；本次所有变更（快捷键、设置窗口、发布流水线、
   图标、gitignore/gitattributes、CHANGELOG 机制等）作为 **v0.2.0** 的 changelog 内容。

## Acceptance Criteria

- [ ] 新增 `CHANGELOG.md`，含 `## [0.2.0]` 段落（本次累积变更）+ Keep-a-Changelog 风格头部
- [ ] `release-template.md` 用 `{{CHANGELOG}}` 替换原三小节
- [ ] `release.yml` 新增"提取 CHANGELOG 段落"逻辑（脚本或内联），按版本号匹配
- [ ] 提取到 → 填入；提取不到 → 默认占位文案，workflow 不失败
- [ ] 下载链接动态生成逻辑保持不变
- [ ] 用测试 tag 验证：Release 描述含 CHANGELOG 内容 + 正确下载链接
- [ ] 不破坏 ci.yml；现有 22 测试不受影响（本任务不碰 Swift 代码）
- [ ] README「发布」章节更新：说明发版前需在 CHANGELOG.md 写好对应版本段落

## Out of Scope

- 从 git commit 全自动生成 changelog（方案 C，不做）
- 回填并更新线上 v0.1.0 Release
- 签名/公证
