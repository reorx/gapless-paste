---
created: 2026-09-28
updated: 2026-10-20
tags:
  - ui-automation
  - acceptance
  - applescript
  - tcc
  - debug-hooks
---

# UI 自动化验收手册

写给要在真机上验收 GaplessPaste 界面改动的人或 agent：用哪些通道操作和截图、现成脚本怎么用、哪些坑已经踩过、验收按什么顺序走。

## 可用通道

| 通道 | 用途 | 前提 |
| --- | --- | --- |
| AppleScript AX（`scripts/ax_*.applescript`、`menu_*.applescript`） | 点按钮、填文本、选行、读菜单 | 终端有 Accessibility 授权（iTerm2 已有）；屏幕亮着 |
| app 自截图（`scripts/capture.swift`） | 截 app 自己的窗口 | 仅 DEBUG 构建；不需要任何 TCC 授权，熄屏和 SSH 远程会话下也能用 |
| DEBUG 钩子（`scripts/preview_open.swift`、`preview_action.swift`、`transfer_debug.swift`） | 绕过菜单和弹窗直达目标状态、传输夹具和图标导出 | 仅 DEBUG 构建；模型与窗口操作熄屏下也能用，原生菜单仍需亮屏 |
| `screencapture` | 截整个屏幕或菜单栏 | 只在本机 iTerm2 会话里可用（2026-09-28 实测）；屏幕熄着时截到的是黑图 |
| `cua-computer-use` MCP | 通用的后台 GUI 自动化 | CuaDriver 已有 Accessibility 和 Screen Recording 授权；**尚未在本项目验证过** |

截 app 窗口优先用自截图：它不依赖终端的授权状态，换终端、走 SSH 都不受影响。SSH 远程会话下 `screencapture` 是否可用没有验证过，推测不可用（授权归属于发起进程的宿主 app）。

不要为验收安装新的自动化工具：新二进制需要用户手动过 TCC 授权。

## 验收前检查

1. **唤醒屏幕**：跑 `wake-screen`，它确认屏幕可用后才退出 0。长验收用 `caffeinate -d -t 1800` 保持亮屏
2. **确认可操作**：`swift scripts/screen_locked.swift` 应打印 `unlocked`
3. **备份**：将被改动的真实数据（如 `config.json`）备份；剪贴板须逐 item/type 备份原始 Data，`pbpaste` 只能保留纯文本，不能完整恢复图像和文件引用

### 熄屏看起来和锁屏一模一样

本机关掉了锁屏（`sysadminctl -screenLock status` 为 `off`），屏幕 20 分钟无操作自动熄灭。熄屏不需要密码就能唤醒，但在熄着的这段时间里，系统的表现和真锁屏完全相同（2026-09-28 实测）：

| | 屏幕亮着 | 屏幕熄着 |
| --- | --- | --- |
| `screen_locked.swift` | `unlocked` | `locked`（熄屏后 1 秒内置位） |
| 前台 app（`lsappinfo front`） | 正常 | `loginwindow` |
| AX 读 app 的窗口 | 正常 | 数量为 0 |
| 按键、鼠标事件 | 正常 | 到不了 app |
| AX 读状态栏菜单项、自截图、DEBUG 钩子 | 正常 | 正常 |

`wake-screen` 之后 1 秒内全部恢复，SSH 远程会话里同样有效。所以看到 `locked` 不代表需要人来解锁，**先 `wake-screen` 再判断**。

`wake-screen` 之后仍是 `locked` 才是真锁屏。可能的原因：有人手动锁了屏（⌃⌘Q）、重启后停在 FileVault 登录界面、锁屏配置被改了回去（用 `sysadminctl -screenLock status` 查）。真锁屏需要人来解，这时用 DEBUG 钩子 + 自截图 + 日志把模型逻辑验完，需要真实点击、按键、手势的项登记到 `kb/known-issues.md`，不要挂着等。

本机熄屏与唤醒方案的来龙去脉见 `~/Documents/macos-monitoring/kb/docs/screen-sleep-and-unlock.md`。

## 脚本

都在 `scripts/`。AX 脚本的第一个参数是**窗口标题片段**（设置窗口传 `设置`，预览窗口传 `🔍`），进程名固定为 `GaplessPaste`。AppleScript 用 `osascript` 运行，Swift 脚本用 `swift` 运行。

| 脚本 | 用途 |
| --- | --- |
| `ax_dump.applescript <窗口> [深度]` | 打印 AX 树（层级、类型、AXIdentifier、值）。写新 AX 脚本前先跑它，不要猜结构 |
| `ax_press.applescript <窗口> <id>` | 按 AXIdentifier 找按钮并按下 |
| `ax_fill.applescript <窗口> <id> <第几个> <文本>` | 往文本框填值（走剪贴板，会覆盖用户剪贴板）；同 id 有多个时用序号区分 |
| `ax_select_row.applescript <窗口> <行文本>` | 选中 List 里的一行，如预览目录树里的文件 |
| `ax_double_click.applescript <窗口> <行文本>` | 双击 List 里某行，如双击目录进入。会真实移动鼠标（结束后移回），该行必须在屏幕上可见 |
| `mouse_double_click.swift <x> <y>` | 在屏幕坐标处发一次真实双击，供上一个脚本调用 |
| `ax_focused_window.applescript` | 打印 app 是否在前台、当前焦点窗口标题 |
| `ax_close_window.applescript <窗口>` | 关窗，收尾还原现场 |
| `menu_read.applescript` | 读状态栏菜单全部项的标题 |
| `menu_click.applescript <标题> <第几个>` | 点状态栏菜单项；同名项每台机器一个，用序号区分 |
| `dock_click.applescript [check]` | 点 Dock 里的 GaplessPaste 图标；传 `check` 只返回 `present` / `absent` |
| `capture.swift <输出目录>` | 触发自截图，每个可见窗口输出一张 `window-<n>-<标题>.png`（含标题栏） |
| `preview_open.swift <机器名> <路径>` | 直接打开预览窗口，跳过菜单和路径弹窗 |
| `preview_action.swift '<指令>'` | 驱动最近打开的预览窗口：`up`、`enter\|<路径>`、`select\|<路径>…`、`refresh`、`dump` |
| `screen_locked.swift` | 打印 `locked` / `unlocked`。熄屏时也打印 `locked`，先 `wake-screen` 再跑 |
| `transfer_debug.swift <指令> [参数…]` | 传输摘要、徽标、详情与真实业务入口验收，见下文 |
| `test_dock_presence.py` | 用 `make test-dock` 运行真机 Dock 回归；需已启动 DEBUG app、AX 可用，会关闭普通窗口 |

长期有用的验收脚本放 `scripts/`（入库），一次性的探索脚本放 `tmp/`（不入库）。

## DEBUG 钩子

app 的 DEBUG 构建监听以下分布式通知，上面的 Swift 脚本就是它们的发送端：

| 通知名 | 作用 |
| --- | --- |
| `com.reorx.gaplesspaste.debug.capture` | 自截图 |
| `com.reorx.gaplesspaste.debug.preview` | 打开预览窗口 |
| `com.reorx.gaplesspaste.debug.preview-action` | 驱动预览窗口 |
| `com.reorx.gaplesspaste.debug.transfer` | 驱动传输验收；object 是 JSON 字符串数组，避免路径／文件名分隔符歧义 |

什么时候用钩子而不是 AX：

- **打开预览窗口**：状态栏菜单项的点击有时静默失效（菜单开着不动，重试也没用），预览入口还叠了一层模态路径弹窗。验收要开预览窗口时直接用 `preview_open.swift`
- **只验模型逻辑，或遇到真锁屏**：用 `preview_action.swift` 驱动导航、选中、刷新，再发 `dump` 把窗口状态写进日志核对（在日志里找「DEBUG 预览状态」）。导航是异步的，`dump` 要等动作完成后单独发

遇到新的验收堵点，优先加一个同类钩子，不要硬磕 AX。

### 传输摘要与徽标

`swift scripts/transfer_debug.swift` 支持以下指令，全部仅存在于 DEBUG：

| 指令 | 用途 |
| --- | --- |
| `fixture empty\|sending\|receiving\|long-machine\|text\|failure\|partial` | 替换内存状态，不执行网络／剪贴板操作；长名称、多文件和长错误夹具 |
| `dump <JSON绝对路径>` | 导出状态、元数据、徽标动画、按钮屏幕坐标、AX 描述、activation policy、窗口标题及最近 40 条 Dock 转换记录 |
| `details` / `retry` | 调用当前详情／重试业务入口；详情窗口是稳定快照，打开失败详情只确认对应 ID |
| `open-menu` | 由原生 status button 打开真实菜单，便于坐标或 AX 截图；本身不证明键盘／鼠标操作通过 |
| `key down\|return\|escape` | 向 app 事件队列投递原生按键；可验菜单导航与选中态，区别于系统级 CGEvent／物理键盘 |
| `export <目录>` | 导出 5 种徽标的深浅色 1×／2× PNG；只是绘制资产，不能替代真实菜单栏截图 |
| `appearance light\|dark\|system` | 临时覆盖 app 外观，不改系统偏好；结束用 `system` 恢复 |
| `reduce-motion on\|off\|system` | 临时覆盖动画分支，不改系统偏好；结束用 `system` 恢复。系统通知链路仍须与真实系统切换区分 |
| `windows settings\|preview\|close` | 打开设置／localhost `/tmp` 预览，或关闭被追踪的普通窗口；用于 Dock 回归 |
| `action <动作> <SSH别名> <远端目录> [本地文件…]` | 临时机器调用真实上传／同步入口，不改配置，**会实际传输并改变剪贴板** |

真实动作包括 `upload`、`quick`、`push`、`pull`、`drop`；`drop` 参数为本地文件列表，只覆盖 drop 的业务入口，不能替代物理拖拽手势。`image-exit` / `image-throw` 接收本地图像文件，先实际上传，再分别模拟剪贴板注入非零退出／抛出异常；用于确认部分成功保留路径、无重传。验完恢复完整剪贴板，核对远端文件内容／数量与本地配置。

`open-menu` 必须脱离 Swift MainActor Task 后进入 tracking：当前用 common run-loop block 调 `performClick`，否则同步嵌套 tracking 会占住 actor，后续 fixture／dump 不能执行。读 dump 前删除旧 JSON，确认收到本次输出，避免把旧文件误当菜单展开期间的实时更新证据。菜单刚打开时可能需先按一次 Down 进入键盘导航，再按 Down 选中详情；以真实选中态和详情窗口 AX 树为准。

`make test-dock` 同时检查实际 Dock 项与 app 的 activation policy，覆盖无窗口、仅详情、仅设置、混合窗口依次关闭。最小化仍属于有窗口，不能按关闭处理。

## 用本机充当远端

需要一台完全可控的远端时用 `localhost`（本机开了远程登录）：备份 `config.json`，临时加一台 SSH 别名为 `localhost` 的机器，`make run` 重启加载，验完恢复备份。夹具目录里放一个 `chmod 000` 的子目录就能验失败路径。

## 已踩过的坑

**AX 查找**

- `entire contents of window` 在深层 SwiftUI 树上稳定地返回空集合，`whose` 子句也不递归。查找一律自己沿 `UI elements of` 递归下降，现成脚本都是这个写法
- 控件要有 `.accessibilityIdentifier("…")` 才能被脚本按 id 定位

**AX 操作**

- 操作前 `set frontmost to true`（菜单栏 app 不会自己到前台），操作窗口前先 `perform action "AXRaise"`
- 点自定义按钮用 `perform action "AXPress"`。`click` 按坐标点，布局动过后会点偏
- List 行选中：对 row 元素 `set selected to true` 有效，对行内文本做 `AXPress` 无效
- AppleScript 的 `click` 发不出双击，SwiftUI 的双击手势收不到，所以双击要走 `mouse_double_click.swift`
- 状态栏菜单的位置是 `menu bar item 1 of menu bar 2 of process "GaplessPaste"`，`key code 53`（Esc）收起菜单
- Thaw 等菜单栏管理工具可能把 status item 移到屏幕外（`dump` 中 x 为负数），此时 AX click 可能只展开管理工具的栏，不能视为 app 菜单打开。先核对菜单真实位置与尺寸；必要时临时退出管理工具，验完恢复。`open-menu` 能绕开按钮点击，但合成按键／AXPress 仍可能静默失效，报告要区分钩子、实际手势与用户手工验收

**文本输入**

- 直接设置 TextField 的 AXValue 只改显示、不触发数据绑定，数据不会变。必须发真实的键盘事件
- 中文输入法会把 `keystroke` 的字母吞进组合缓冲（只有 `-` 等符号直通）。填文本一律走剪贴板：先 `set the clipboard to …`，再 ⌘A、⌘V

**存储 / 打开面板**

- 系统的存储和打开面板由另一个进程渲染，app 进程里看到的 AX 元素只是代理：点击、按下、设值全部静默无效，自截图也是黑的。只能纯键盘驱动：`AXRaise` 面板窗口 → ⌘⇧G → ⌘A、⌘V（路径先放进剪贴板）→ 回车（前往）→ 回车（存储）。每步之间留足延时

**AppleScript 语言**

- 保留字会毒化变量名：缓冲变量别叫 `line`，也别叫 `outLine`（会被解析成 `outline`），赋值时直接报 `-10003 Access not allowed`。用 `buf` 这类无歧义的名字

**截图时机**

- 顶栏提示 3 秒后消失，要验提示是否出现，自截图得赶在这之前

## 验收流程

1. 做完「验收前检查」
2. `make build && make run`，打开目标界面。每步操作后**读实际落盘的文件或日志**核对，不要只看界面；关键状态触发自截图
3. 恢复备份的数据和剪贴板，让 app 重载；改过 `config.json` 就和备份 diff 确认一致
4. 截图归档到 `tmp/<日期>-<任务名>/`，报告里给出目录路径
5. 没能验证的项登记到 `kb/known-issues.md`

## 相关位置

- 钩子实现：`GaplessPaste/App/DebugHooks.swift`
- 运行日志：`~/Library/Logs/GaplessPaste/GaplessPaste.log`
- 当前未验收的项：`kb/known-issues.md`
