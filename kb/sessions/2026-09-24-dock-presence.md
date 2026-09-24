---
created: 2026-09-24
tags:
  - dock
  - activation-policy
  - app-icon
  - preview-window
  - settings-window
  - ui-automation
---

# 预览/设置窗口打开时以 Dock app 形式存在 + 生成 AppIcon

## 概要

GaplessPaste 是 LSUIElement 菜单栏 app（`.accessory`），预览远端目录窗口可以多开，但它们没有 Dock 图标、不进 ⌘Tab，被别的 app 盖住后只能回状态栏菜单去找。本次新增 `DockPresence`：追踪普通窗口（预览窗口和设置窗口），只要还有一个开着，就把 activation policy 切成 `.regular`，这样有 Dock 图标、主菜单栏，能进 ⌘Tab，也能用 ⌘\` 切窗口。最后一个窗口关掉后，下一轮 runloop 退回 `.accessory`。窗口全部最小化时点 Dock，会恢复最近使用的那个。切到 regular 后会露出 SwiftUI 默认主菜单，其中「Settings… ⌘,」会打开空的 `Settings { EmptyView() }` 场景，这是个潜伏 bug，本次改为转发到真正的设置窗口，同时去掉了空的 Help 菜单。app 原本没有图标，新增 `scripts/gen_app_icon.swift`，按像素渲染蓝色渐变底板加白色 SF Symbol（与状态栏同款），产物入库。已验证：Core 138 个测试通过，构建没有警告，bundle 里有 `AppIcon.icns` 和 `CFBundleIconName`，LaunchServices 读到了新图标；真机上启动时是 UIElement、Dock 没有图标，开 3 个预览窗口后变成 Foreground、Dock 出现图标。这时发现屏幕是锁定的，用户又是 SSH 远程连进来、没法解锁，其余需要交互的验收（⌘\`、点 Dock、主菜单、关窗退回、⌘C 回归）按用户要求跳过，已登记到 known-issues。

## 修改的文件

- `GaplessPaste/App/DockPresence.swift`（新增）— `@MainActor enum`：`track(window)` 按对象去重登记窗口，订阅 willClose（触发 untrack）和 didBecomeKey（移到列表末尾，维持最近使用顺序），并切到 `.regular`；列表清空后 `DispatchQueue.main.async` 里再判断一次，仍为空才切回 `.accessory`；`focusMostRecent()` 负责 deminiaturize、makeKeyAndOrderFront 和激活
- `GaplessPaste/UI/PreviewWindow.swift` — `PreviewWindowController.show()` 激活前调用 `DockPresence.track`
- `GaplessPaste/UI/SettingsWindow.swift` — `SettingsWindowController.show(config:)` 每次 show 都 track（窗口复用，关窗时自动 untrack）
- `GaplessPaste/App/GaplessPasteApp.swift` — `Settings` 场景加 `.commands`：用 `CommandGroup(replacing: .appSettings)` 替换出「设置… ⌘,」转发给 `AppDelegate.openSettings()`，`CommandGroup(replacing: .help) {}` 去掉 Help 菜单；新增 `applicationShouldHandleReopen`（没有可见窗口时调 `focusMostRecent`，返回 false）；更新文件头注释
- `scripts/gen_app_icon.swift`（新增）— 生成 `GaplessPaste/Assets.xcassets/AppIcon.appiconset`（16 到 512，各 @1x/@2x，共 10 张）
- `GaplessPaste/Assets.xcassets/**`（新增）— 脚本产物，入库
- `project.yml` — target 加 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`
- `scripts/ax_focused_window.applescript`（新增）— 打印 app 是否在前台，以及当前焦点窗口的标题
- `scripts/dock_click.applescript`（新增）— 点击 Dock 里的 GaplessPaste 图标；传 `check` 参数时只返回 present/absent
- `scripts/screen_locked.swift`（新增）— 打印 locked/unlocked，AX 验收前先跑它检查
- `scripts/capture.swift` — 相对路径的输出目录先转成绝对路径（原先会按 app 的 cwd `/` 解析，截图落到 `/tmp/...`）
- `AGENTS.md`（即 CLAUDE.md）— 进度加一条；脚本表加入 3 个新脚本；新增一条「锁屏」坑；新增图标重新生成的说明

## 注意事项

- **切回 `.accessory` 必须推迟**：`willCloseNotification` 触发时窗口还在屏幕上，当场切 policy 可能会有残留。放到下一轮 runloop 做，并且再检查一次列表是否仍为空，防止「关一个、马上又开一个」时误切回去
- **LSUIElement 仍为 true**：启动时没有 Dock 图标，policy 只在运行时切换。不要为了让 Dock 显示图标去改 Info.plist
- **SwiftUI `Settings { EmptyView() }` 的潜伏 bug**：即使是 accessory 模式，主菜单的 key equivalent 仍然生效，焦点在预览窗口时按 ⌘, 就会打开一个空白窗口。菜单栏 app 用这个占位场景时，要用 `.commands` 把 `.appSettings` 替换掉
- **锁屏会让 AX 和按键验收全部假失败**：`windows of process` 返回空，`lsappinfo front` 显示的是 loginwindow，按键也发不到 app；但 app 自截图和 `lsappinfo info -only ApplicationType` 不受影响。锁屏时仍可靠的验证手段是：用 `lsappinfo` 看 policy（UIElement 或 Foreground），用 `dock_click.applescript check` 看 Dock 里有没有图标（Dock 进程的 AX 在锁屏下依然能读）
- **macOS 26 会给旧式图标加系统玻璃边**：`NSWorkspace.icon(forFile:)` 导出的图标带有系统加的圆角高光，这是正常的；源图按 824/1024 网格留边即可

## 遗留问题

- 交互式 GUI 验收没做（锁屏加 SSH 远程，无法解锁）：⌘\` 切窗口、点 Dock 恢复、主菜单内容和 ⌘,、关窗退回 accessory、设置窗口和预览窗口混开、⌘C 回归，都已登记到 `kb/known-issues.md`
- 推测中的风险：从 accessory 切到 regular 后，菜单栏可能要再激活一次才会显示本 app 的菜单；⌘\` 能否直接生效也有待实测。已一并登记到 known-issues

## 相关文档

无涉及 KB 文档（开发计划在对话中给出，未存入 `kb/plans/`）。
