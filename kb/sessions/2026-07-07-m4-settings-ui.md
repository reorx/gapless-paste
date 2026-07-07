---
created: 2026-07-07
tags:
  - settings-ui
  - swiftui
  - config
  - ui-automation
  - tcc
---

# M4 设置界面：GUI 编辑配置取代手改 config.json

## 概要

为 GaplessPaste 增加设置窗口，把基于文件的配置（手改 `config.json` + 菜单「重载配置」）升级为 GUI 操作。按 BDD 先在 Core 写序列化行为测试，再给 `Config` 系列模型加可变属性与 `serialize()`；App 侧新增 master-detail 布局的设置窗口（左侧机器列表 +/−，右侧 grouped Form 编辑名称/SSH 别名/上传目录），遵循 macOS HIG「设置即时生效」惯例：编辑即校验，合法则防抖 0.5s 原子写回 config.json 并清探测缓存，非法则显示内联提示且不落盘。菜单「打开配置」替换为「设置…」，首启改为打开设置窗口引导。完成后在真机做了全链路自动化验收：AppleScript AX 模拟操作（改机器名、添加目录、添加机器），逐步核对 config.json 实际变化，并用 app 自截图钩子取证三张截图（初始态、校验拦截态、双机器落盘态），验收后恢复了用户原配置与剪贴板。

## 修改的文件

- `GaplessPasteCore/Sources/GaplessPasteCore/ConfigModel.swift` — `Config`/`Machine`/`RemoteDirectory` 属性改 `var`；新增 `serialize()`（校验 + prettyPrinted/sortedKeys/withoutEscapingSlashes 编码）
- `GaplessPasteCore/Tests/GaplessPasteCoreTests/ConfigModelTests.swift` — 新增「GUI 编辑与序列化」suite：往返等值、人类可读输出、校验失败不产出、模型可变性（BDD 先行）
- `GaplessPaste/UI/SettingsWindow.swift` — 新增：`SettingsModel`（草稿编辑 + 校验 + 防抖落盘 + 关窗冲刷）、`SettingsView`（HSplitView master-detail + footer 状态条/「打开配置文件…」）、`SettingsWindowController`（LSUIElement 下显式 activate）
- `GaplessPaste/Services/ConfigStore.swift` — 新增 `save(_:)`（序列化 + 原子写盘 + 同步内存态）；首启不再自动打开编辑器，改为记录 `isFirstLaunch`
- `GaplessPaste/App/AppState.swift` — 新增 `openSettings()` 与 `applySettings(_:)`（写盘 + 清探测缓存，不弹通知）
- `GaplessPaste/UI/StatusMenuController.swift` — 「打开配置」→「设置…」（keyEquivalent «,»）；空配置引导文案更新
- `GaplessPaste/App/GaplessPasteApp.swift` — 首启打开设置窗口；安装 DEBUG 钩子
- `GaplessPaste/App/DebugHooks.swift` — 新增：DEBUG-only 分布式通知触发窗口自截图（`cacheDisplay`，零 TCC 权限）
- `AGENTS.md` — 进度更新：M4 设置 UI ✅
- `tmp/capture.swift`、`tmp/ax_paste.applescript`、`tmp/ax_click.applescript` — 自动化验收辅助脚本
- `tmp/settings-acceptance/*.png` — 三张验收截图

## 注意事项

- **设置保存模型**：不做「保存」按钮（HIG：设置即时生效）。草稿每次变更立即校验：合法 → 防抖 0.5s 落盘（对比已落盘快照避免空写），非法 → footer 显示原因并暂缓，窗口关闭时 `flushSave()` 冲刷。校验复用 Core 的 `Config.validate()`，GUI 与文件解析共享同一套规则。
- **GUI 保存会重写整个 JSON**：`_readme` 等未知键会丢失（Config 不含该字段），字段序按 sortedKeys 稳定输出。这是预期行为——GUI 成为配置事实来源后文件不再需要说明注释。
- **iTerm2 无 Screen Recording 权限**（TCC auth=0，用户明确拒绝过），`screencapture` 不可用；新装 Peekaboo 之类工具同样要用户手动授权。解法：app 自截图——`NSView.cacheDisplay` 截自己的窗口零 TCC 需求，DEBUG-only 钩子经分布式通知 `com.reorx.gaplesspaste.debug.capture` 触发。
- **SwiftUI TextField 直接 set AXValue 只改显示不触发 binding**，自动化必须走真实键盘事件；而**中文输入法会吞掉 `keystroke` 的字母**（只有符号直通），最终方案是剪贴板粘贴（`⌘A` + `⌘V`），操作前后备份/恢复用户剪贴板。
- **状态栏菜单的 AX 路径**：LSUIElement app 的 status item 在 `menu bar 2` 的 `menu bar item 1`，click 展开后再 click menu item；菜单项、SwiftUI 控件都可用 `AXIdentifier` 精确定位（代码里已埋 `accessibilityIdentifier`）。
- 热重载无需额外接线：菜单每次打开经 `menuNeedsUpdate` 全量重建、DropPanel 每次展示现取 `configStore.lastResult`，`save()` 更新内存态后 UI 自动一致。
