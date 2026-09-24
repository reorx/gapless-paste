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

## 预览窗口目录导航：真实按钮 / ⌘↑ / 双击手势未经真机验收

- 记录：2026-09-24（`kb/sessions/2026-09-24-preview-dir-navigation.md`；验收时屏幕锁定，AX 与鼠标事件全部无效）
- 已验证（DEBUG 钩子 `scripts/preview_action.swift` + 自截图 + 日志）：向上 / 进入的模型逻辑、节点复用零 ssh、选中过滤、刷新作用于当前根、无权限目录失败提示、根 `/` 时向上置灰、窗口标题跟随
- 未验证（解锁后逐项跑，夹具与配置见 `tmp/nav_acceptance_setup.py`）：
  - `osascript scripts/ax_press.applescript 🔍 preview-go-up` 真正触发向上
  - ⌘↑（`key code 126 using command down`）等价于按钮；目录树 List 有焦点时是否被 NSOutlineView 先吃掉
  - `osascript scripts/ax_double_click.applescript 🔍 <目录名>` 双击目录行进入；推测风险：DisclosureGroup label 上的 `onTapGesture(count: 2)` 在 macOS sidebar List 里可能不触发，或让单击展开/选中变迟钝。退路：目录行打 tag + List 上 `.contextMenu(forSelectionType:primaryAction:)`（双击/回车触发）
  - `scripts/ax_double_click.applescript` 与 `mouse_double_click.swift` 本身还没在解锁状态下跑通过（子进程发 CGEvent 依赖 iTerm2 的 Accessibility 授权）

## 预览窗口：符号链接目录被当作文件

- `ls -1Ap` 不给符号链接加尾随 `/`，指向目录的链接在树里显示为文件，不能展开，也不能双击进入
- 连带：以符号链接路径打开窗口后向上，原根目录在父目录里变成文件节点，无法再双击回去（只能重开窗口）
- 修法方向：列目录改 `ls -1ApL`，或用 `find -maxdepth 1 -printf '%y %p\n'` 区分链接类型（需兼容 BSD/GNU）

## 预览窗口：相对路径打开时不能向上

- 路径输入非 `/`、非 `~` 开头时（如 `claude-inbox`），ssh 以远端 `$HOME` 为 cwd 能正常列出，但根 id 是相对路径，`RemoteBrowse.parentPath` 返回 nil，向上按钮置灰
- 修法很小：`start()` 里对非绝对路径用 `RemoteBrowse.joinPath(probe.home, path)` 补成绝对路径
