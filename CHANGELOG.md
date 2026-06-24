# Changelog

本项目所有重要变更记录于此。遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/)
风格，版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.2.0] - 2026-06-24
### ✨ 新功能
- 全局快捷键上锁（默认 ⌘⌥⌃L）+ 设置窗口可编辑快捷键
- 发布流水线：推送 `v*` tag 自动以 Release 配置无签名构建 arm64 / x86_64 / universal 三个变体并打包 .dmg，自动创建 GitHub Release 上传资产
- 新增 App 图标

### 🔧 改进
- Release 说明的变更日志改为从仓库 `CHANGELOG.md` 自动提取对应版本段落填入，发版一步到位
- `.gitignore` / `.gitattributes` 优化：工具目录排除出语言统计，`.xcodeproj` 规则覆盖 `project.pbxproj`

## [0.1.0] - 2026-06-24
- 首个版本：防猫输入锁 MVP——不锁屏、不睡眠、不黑屏的前提下临时锁定键盘 / 触控板 / 鼠标 / 滚轮输入
- Touch ID 解锁（主路径）、Apple Watch 解锁（备用）、远程文件解锁兜底（`touch ~/.catguard-unlock`）
