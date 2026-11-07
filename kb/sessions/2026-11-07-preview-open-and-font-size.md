---
created: 2026-11-07
tags:
  - preview-window
  - settings
  - acceptance
---

# 默认应用打开预览文件与全局文本字号

## 概要

按已授权计划在 master 实现每栏默认应用打开按钮，以及设置中的全局文本预览字号。打开使用完整本地缓存 URL，经 NSWorkspace 查询并调用系统默认应用；字号通过 AppStorage 即时同步，独立于机器配置。实机验收发现 SwiftUI 长文本在 32 pt 下阻塞主线程，采样定位后改用原生只读 NSTextView 按需布局，同一大文件已恢复可用。代码、原计划与文档一起提交，不 push 或发版。

## 修改的文件

- `GaplessPaste/UI/PreviewWindow.swift`：下载右侧新增打开按钮，默认应用调用、缓存存在检查、失败反馈与日志。
- `GaplessPaste/UI/PreviewPreferences.swift`：独立本机偏好、设置 Stepper、原生只读等宽文本视图；更新字号时复用视图和选区。
- `GaplessPaste/UI/SettingsWindow.swift`：机器分栏外加入文本预览设置。
- `GaplessPasteCore/Sources/GaplessPasteCore/PreviewTextFontSize.swift` 和对应测试：默认 12、8–32 边界、步进 1、非法值归一化；不依赖 AppKit。
- `README.md`、`AGENTS.md`、`kb/docs/features.md`、`kb/docs/preview-window.md`：同步当前功能、本地副本语义、字号范围与持久化规则。
- `kb/plans/2026-11-07-preview-open-and-font-size.md`：原未提交计划与实际验收结果。

## 测试与实机验收

字号测试先失败再实现，最终 `make test` 通过全部 161 项；`make build` 通过，`git diff --check` 通过。未跑 formatter/linter。构建环境有 CoreDevice/CoreSimulator 版本告警，但不影响 macOS 构建。

`agent-inspect-session.sh` 显示 context 16%，在本会话完成验收。用现有 agent-desktop、AX 脚本、DEBUG 导航和自截图操作本机 localhost SSH，无需安装工具或新增授权。`wake-screen` 的屏幕状态辅助脚本缺失，使用其唤醒后另跑 `screen_locked.swift` 确认 unlocked，随后 AX 操作正常。

实机通过：文本与图片真实打开、多栏对应、空格/单引号路径、810021 字节完整缓存、无默认应用和缓存消失提示、真实刷新中的禁用、下载失败后禁用；8/12/20/32 pt 双窗口原生字体属性同步、选区不变、重启持久化、空机器配置独立性、机器名称自动保存、最小设置窗口布局、图片/音频及截断提示不放大；有文本选区且正文获焦时，真实 ⌘C 仍复制文件引用。

截图及原始证据目录：`tmp/2026-11-07-preview-open-and-font-size/`。其中 `native-font-*.txt` 是两个窗口的实际字体与选区，`opened-documents.txt` 和 `large-opened-document.txt` 是默认应用的实际文档 URL，`file-integrity.txt` 是源文件/缓存校验。`large-text-hang.sample.txt` 记录修复前的阻塞，`large-text-fixed/` 是修复后的同文件截图。截图和临时脚本不入库。

原配置逐字节恢复、原字号偏好恢复、逐 item/type 完整剪贴板恢复，关闭本次测试文档和普通窗口；没有启动浏览器或模拟器。

## 注意事项

- 系统默认应用接收的是完整本地缓存，预览截断不改变文件。外部编辑不回传；刷新会用远端内容覆盖缓存。
- NSWorkspace 完成回调表示系统已交付文件，不能证明第三方应用内部成功解析。界面不显示虚假的成功提示，日志只记录交付。
- 长文本 UI 验收必须包含大字号。纯 SwiftUI Text 的整段布局不能仅凭小文本通过就认为大文件也可用。
- 原生文本视图只在文本改变时重设内容、只在字号改变时更新字体，避免破坏现有文本选区。

## 遗留问题

本任务无未解决的使用缺陷。验收未强制注入 LaunchServices 异步回调错误；真实失败覆盖了没有默认应用与缓存文件消失。没有扩展处理既有的目录导航和 Dock 未验收项。

## 相关文档

- [实施计划](../plans/2026-11-07-preview-open-and-font-size.md) — 本次实现依据及验收结果。
- [预览窗口](../docs/preview-window.md) — 更新默认应用打开与字号行为。
- [功能规则](../docs/features.md) — 更新设置中本机偏好的说明。
- [UI 验收手册](../docs/ui-acceptance.md) — 参考现有 AX、DEBUG 与截图流程。
