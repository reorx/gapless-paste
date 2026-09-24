# Known Issues

> 当前 app 已知、待后续处理的问题：缺陷、简化实现、未验收项、待建流程。只反映最新状态——解决了就删掉条目，经过记到 `kb/sessions/`。

## Dock 形态：窗口打开时切 regular 的交互行为未经真机验收

- 记录：2026-09-24（`kb/sessions/2026-09-24-dock-presence.md`；验收时屏幕锁定，用户通过 SSH 远程连接，无法解锁，按用户要求跳过）
- 已验证：启动时为 UIElement，Dock 中没有图标；打开预览窗口后变为 Foreground，Dock 出现图标；bundle 图标生效。
- 未验证（逐项在解锁的会话里跑，脚本见 AGENTS.md 脚本表）：
  - ⌘\` 在多个预览窗口之间轮转，加 ⇧ 反向（`key code 50 using command down`，每次按完读 `ax_focused_window.applescript`）。如果不生效，退路是在 `.commands` 里加 `CommandGroup(after: .windowList)`，按被追踪的窗口循环切换
  - 焦点在别的 app 时 `dock_click.applescript`，GaplessPaste 应成为 frontmost；窗口全部设为 `AXMinimized` 后再点 Dock，最近用过的窗口应被恢复并获得焦点（依赖 SwiftUI 把 `applicationShouldHandleReopen` 转发给 `AppDelegate`）
  - 主菜单（`menu bar 1`）里有「设置…」、没有 Help；按 ⌘, 打开的是「GaplessPaste 设置」，不是无标题的空窗口
  - 关闭全部预览窗口但设置窗口还开着时，应仍为 Foreground；再关设置窗口，应变回 UIElement，Dock 图标消失；单独开设置窗口时也应出现 Dock 图标
  - 在 regular 模式下，状态栏菜单照常可用（`menu_read.applescript`）；预览窗口里 ⌘C 复制出的仍是文件引用
  - 推测中的风险：从 accessory 切到 regular 后，菜单栏可能要再激活一次才会显示本 app 的菜单（需要用户亲眼看，iTerm 没有录屏权限，截不到菜单栏）
