---
created: 2026-09-24
tags:
  - preview-window
  - navigation
  - remote-browse
  - debug-hooks
  - ui-automation
---

# 预览窗口自由进出目录：「向上」按钮 + 双击进入目录

> **更正（2026-09-28）**：文中说的「屏幕锁定、无法解锁」是误判。本机已关掉锁屏，当时屏幕只是熄着（监控指标显示键鼠已闲置 4 小时）；熄屏时锁定标志同样置位、AX 同样失效，跑一次 `wake-screen` 即可恢复，不需要人来解锁。详见 [UI 自动化验收手册](../docs/ui-acceptance.md)「熄屏看起来和锁屏一模一样」。

## 概要

预览窗口的目录树根原本固定在打开时输入的路径，只能往下展开，想看上级或把深层目录当根只能关窗重开。本次在顶栏路径右侧加「↑」按钮（⌘↑），把根切到上一级；双击目录行，把根切到该目录。导航不重建树，而是复用 `nodesByPath` 里已有的节点：向上时父目录列表里与旧根同路径的条目直接用旧根节点，所以刚才所在的目录在新树里是展开的，选中的文件和右侧预览都还在；已经列过子项的目录再进出不发 ssh。进入子目录时，选中集合只保留新根之下的文件。顺带修了几处既有问题：刷新和错误页「重试」原来总回到初始路径，现在作用于当前根；根节点 `name` 原是完整路径，向上后复用为子节点会显示成整条路径，现改为末段；输入路径带尾随 `/` 时根 id 和父目录拼出的子路径对不上，入口处现在做规范化；窗口标题跟随当前根。路径的纯逻辑（规范化、求父目录、判断是否在目录之下）放在 Core，按 BDD 先写了 11 个行为测试。验收时屏幕锁定，AX、按键、鼠标事件都不可用，唯一配置的机器 `mini` 也连不上（ssh banner 超时），于是临时在 `config.json` 加了一台 `sshAlias: localhost` 的机器，用 `tmp/nav-fixture` 做夹具，新增 DEBUG 钩子 `preview-action` 驱动窗口并 dump 状态到日志，把模型逻辑逐项验完。真实的按钮点击、⌘↑、双击手势需要解锁后才能验；用户是 SSH 远程连接、无法解锁，按用户要求跳过，已登记到 known-issues。

## 修改的文件

- `GaplessPasteCore/Sources/GaplessPasteCore/RemoteBrowse.swift` — 新增 `normalizedDirectoryPath`（折叠 `//`、去尾随 `/`，根 `/` 不变）、`parentPath`（根与相对路径返回 nil）、`isPath(_:inside:)`（按路径段判断，`/ab` 不在 `/a` 之下）
- `GaplessPasteCore/Tests/GaplessPasteCoreTests/RemoteBrowseTests.swift` — 上述三个函数的 11 个行为测试，其中一条锁定"规范化后的根 id == 父目录 joinPath 出的子路径"，这是节点复用的前提
- `GaplessPaste/UI/PreviewWindow.swift`
  - 模型：新增 `currentPath` / `isNavigating` / `onRootChange`；`start()` 读 `currentPath` 并规范化，根节点 name 取末段，赋根统一走 `setRoot`；列目录抽成 `listChildren(of:)`（失败抛 `ListingError`，展开和导航共用，错误在顶层处理）；`makeChildren` 优先复用索引里同路径、同类型的节点；新增 `canGoUp` / `goUp()` / `enterDirectory(_:)` / `setRoot(_:)`。`enterDirectory` 在 await 之后检查 `root === current`，列目录期间点了刷新就放弃这次导航
  - 视图：顶栏路径标签改读 `currentPath`，后面加「↑」按钮（`preview-go-up`，⌘↑，不可用时置灰），导航中显示小号 ProgressView；目录行 label 撑满整行、`contentShape` 后挂 `onTapGesture(count: 2)`
  - 控制器：`onRootChange` 更新窗口标题；DEBUG 下 `debugPerform` 转发给模型的 `#if DEBUG` 扩展（放在同文件，能访问 private 状态）
- `GaplessPaste/App/DebugHooks.swift` — 新增通知 `com.reorx.gaplesspaste.debug.preview-action`，转发给最近打开的预览窗口
- `GaplessPaste/App/AppState.swift` — DEBUG 下暴露 `latestPreviewController`
- `scripts/preview_action.swift`（新增）— 发 `up` / `enter|<路径>` / `select|<路径>…` / `refresh` / `dump` 指令
- `scripts/mouse_double_click.swift`（新增）— CGEvent 发双击（第二击 `clickState=2`），结束后鼠标移回原位
- `scripts/ax_double_click.applescript`（新增）— 按行文本递归找到元素，取中心坐标后调上面的脚本
- `AGENTS.md` — 进度段加一条；脚本表补三行；DEBUG 钩子段补 `preview-action` 和"用 localhost 当可控远端"的验收做法
- `kb/known-issues.md` — 新增三条（见遗留问题）

## 注意事项

- **节点复用依赖 id 一致**：树节点 id 就是远端绝对路径，入口路径必须先规范化，否则 `~/foo/` 生成的根 id 和父目录拼出的 `/home/me/foo` 对不上，复用会静默失效（退化成重新列目录、丢失展开状态）。Core 的 `normalizedDirectoryPathMatchesJoinedChildPath` 用例锁的就是这个
- **导航的过时数据交给顶栏刷新**：列过的目录进出不再重列，这与既有的"展开过的目录不重列"一致；刷新会清空 `nodesByPath`，复用自然失效
- **异步导航与刷新竞争**：`enterDirectory` 在 await 后用 `root === current` 判断树是否已被刷新重建，是就丢弃结果，避免把旧树的节点塞回新树
- **锁屏时的验收路径**：AX、按键、鼠标事件全都无效，但分布式通知和自截图照常工作。给窗口模型加一个 `#if DEBUG` 的指令入口（放在同文件的 extension 里，能访问 private 状态），加上 `dump` 写日志，就能在锁屏下验完模型逻辑；再从日志里 `$ /usr/bin/ssh` 行数的差值确认"零 ssh"
- **本机当远端**：本机开了远程登录，`ssh localhost` 可达，是验收时完全可控的"远端"；夹具里放一个 `chmod 000` 的目录就能验失败路径。脚本 `tmp/nav_acceptance_setup.py setup|restore` 负责备份/改配置/造夹具/还原
- 自截图要赶在 3s 的顶栏提示消失之前，否则会误判为提示没显示（第一次截图就踩了）

## 遗留问题

- 真实的「↑」按钮点击、⌘↑、双击目录手势都还没在解锁状态下验过；双击用的 `ax_double_click.applescript` / `mouse_double_click.swift` 也还没真机跑通过。推测有风险：DisclosureGroup label 上的 `onTapGesture(count: 2)` 在 macOS sidebar List 里可能不触发，退路是目录行打 tag，再在 List 上用 `.contextMenu(forSelectionType:primaryAction:)`
- 符号链接目录仍被当作文件（`ls -1Ap` 的局限），不能展开或双击进入；以链接路径打开后向上，就回不去了
- 相对路径打开（如 `claude-inbox`）时向上置灰，补一行 `joinPath(probe.home, path)` 就能修

以上三条已同步到 `kb/known-issues.md`。

## 相关文档

- [GaplessPaste v1 需求](../plans/2026-07-06-gapless-paste-v1-spec.md) — 预览窗口的原始需求背景
- [Dock 形态会话](./2026-09-24-dock-presence.md) — 同日前一个 session，锁屏验收的处理方式与本次相同
