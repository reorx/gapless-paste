# GaplessPaste

macOS 菜单栏工具：把本机剪贴板里的截图/文件/文本以最少步骤传到 SSH 可达的远端机器（目录上传 + 剪贴板同步 + 拖拽上传），让远端的 Claude Code 立刻可用。完整需求见 `kb/plans/2026-07-06-gapless-paste-v1-spec.md`。

## 进度

- M1 目录上传闭环 ✅、M2 剪贴板闭环 ✅、M3 拖拽上传（图标 drop 检测 + DropPanel）✅、M4 设置 UI（GUI 编辑配置，SettingsWindow）✅
- 快速上传 ✅：目录可标 `default_of`（FILE/IMAGE），菜单「⚡ 快速上传」按剪贴板类型直传默认目录（每机器内唯一）
- 同步剪贴板支持单个图片文件引用 ✅：Finder ⌘C 的图片文件（png/jpg/heic/webp 等）读文件转 PNG 后走图像同步路径注入远端剪贴板；多文件/非图片仍拒绝
- 预览远端目录 ✅：每机器菜单「🔍 预览远端目录…」（同步剪贴板下方）→ 输入路径开独立预览窗口（可多开）：左树（`ls -1Ap` 懒加载）右预览（文本/图像，二进制拒绝），每窗口内存缓存（切回瞬时）、⌘ 多选分栏对比、pin 置顶；纯逻辑在 Core `RemoteBrowse.swift`，UI 在 `UI/PreviewWindow.swift`
- 预览窗口导出与缩放 ✅：⌘C/⌃C 复制选中文件（文件引用，Finder 可粘贴）；分栏标题栏右侧按钮组——图像的 −/百分比/＋ 缩放（pinch 手势同步支持，百分比点击还原 100%）+ 复制 + 下载（NSSavePanel 另存，二进制文件同样可导出）；缓存以 `<UUID>/<原文件名>` 存放保证导出保留原名
- 预览缓存持久化 ✅：文件缓存从每窗口临时目录改为 `~/Library/Caches/GaplessPaste/preview/` 共享持久目录，机器-路径-文件 稳定映射（`<alias>/<远端路径 SHA256 前16位>/<原文件名>`，纯逻辑在 Core `PreviewCache.swift`），跨窗口/跨启动命中即免 scp；分栏标题栏新增刷新按钮（`preview-file-refresh`）强制重新下载（先下到 `.part-<uuid>` 再替换，多窗口并发安全）；顶栏刷新只重列目录树、不清磁盘缓存；关窗不再删缓存
- 预览窗口打磨 ✅：侧栏宽度自绘分割条（弃 HSplitView，宽度只随用户拖动变化，不再被内容重排跳变）；图像默认 fit 模式（适应窗口、从不放大超过原图，`PreviewZoom.fitScale` 纯逻辑在 Core），工具栏加 fit 按钮回到适应窗口；顶栏「连接 Zoom」/「连接 Scroll」按钮（选中 ≥2 张图片时出现）分别同步多栏缩放与滚动位置（zoom 模式图像容器为 NSScrollView 封装 `ZoomedImageScrollView`，滚动按归一化比例同步，pinch 走 NSMagnificationGestureRecognizer）；预览路径输入弹窗展示近期路径（点击覆盖输入框，UserDefaults `previewRecentPaths.<sshAlias>` 按机器存 8 条，`RecentPaths` 纯逻辑在 Core，弹窗 UI 在 `UI/PreviewPathPrompt.swift`）
- 同步剪贴板拆双向 ✅：每机器菜单拆成「同步到远端剪贴板 →」（原路径 B 推送）与「从远端剪贴板同步 ←」（新增拉取）：一次 ssh `osascript` try `the clipboard as «class PNGf»` 打印 `«data PNGf<hex>»` 拿图像（本机 hex 解码写回本地剪贴板，PNG+TIFF 双格式），非图像输出哨兵后回退 `pbpaste` 拉文本，空文本提示远端剪贴板为空；纯逻辑（提取命令 + 输出解析 `parseImageExtractionOutput`）在 Core `RemoteClipboard.swift`，非 Darwin 两项均置灰
- ControlPath 目录抗 /tmp 清理 ✅：macOS 周期清理会删掉 `/tmp/gaplesspaste-<uid>`（长时间挂机后所有 ssh 报 `unix_listener: cannot bind`），改为 `SSHRunner.run` 每次执行前幂等重建（Core `SSHCommandBuilder.ensureControlPathDirectory`，0700），不再依赖启动时一次性创建
- 预览音频文件 ✅：wav/mp3/m4a/aac/flac/aiff/caf（AVAudioPlayer 可解码集合，ogg 不支持仍按文本兜底）在分栏内播放/暂停 + 可拖动进度条 + 当前时间/总时长（`FilePreview.kind` 新增 `.audio`、`DisplayFormatter.durationText` 纯逻辑在 Core）；播放进度 0.1s 定时器刷新（不用 AVAudioPlayerDelegate，靠定时器检测自然结束并复位），切走分栏自动停播；侧栏音频文件显示音符图标
- M4 待做：全局热键、登录启动项、浏览器拖图评估
- 历次改动细节见 `kb/sessions/`

## 技术栈

- macOS 14.0+，SwiftUI App lifecycle，Swift 5 语言模式（非 Swift 6 strict concurrency）
- 本地 SPM 包 `GaplessPasteCore`（纯逻辑 + 单测）+ app target（系统胶水与 UI）
- 本机工具链：Xcode、xcodegen、xcbeautify（后两者 `brew install xcodegen xcbeautify`）

## 工程约定（重要）

- **一切构建/测试/运行走 Makefile，不用 Xcode GUI。**
- 工程定义的唯一事实来源是 `project.yml`（XcodeGen）。**永远不要手工编辑 `GaplessPaste.xcodeproj`**（已 gitignore，`make gen` 随时重新生成）。
  - 加源文件：直接放进 `GaplessPaste/` 目录（目录即 sources），然后 `make gen`
  - 改 target 配置 / Info.plist / entitlements / 包依赖：改 `project.yml`，然后 `make gen`
  - `GaplessPaste/Info.plist` 和 `GaplessPaste/GaplessPaste.entitlements` 是 xcodegen 从 project.yml 生成的，不要直接编辑
- 分层规则：
  - `GaplessPasteCore/` — 本地 SPM 包，纯逻辑（状态机、编解码、数据模型），**禁止依赖 AppKit**，所有单测在此
  - `GaplessPaste/` — app target，系统胶水与 UI，按 `Services/` `UI/` `App/` 组织
- 开发方法：新功能 BDD —— 先在 `GaplessPasteCore/Tests/GaplessPasteCoreTests/` 写行为测试（Swift Testing，`@Test` / `#expect`），再实现；bug 修复 TDD —— 先写复现测试再修

## 命令

```
make build       # xcodegen + xcodebuild Debug 构建（xcbeautify 美化输出）
make test        # GaplessPasteCore swift test
make run         # kill 旧实例并启动已构建的 app（不触发构建）
make dev         # build + run
make gen         # 仅重新生成 xcodeproj
make clean       # 清理构建产物与生成的 xcodeproj
```

- 构建产物：`.build/DerivedData/Build/Products/Debug/GaplessPaste.app`
- 跑单个测试：`cd GaplessPasteCore && swift test --filter <测试名>`
- 改了 `project.yml` 后必须 `make gen`（`make build` 已包含）
- 直接调 xcodebuild 时固定参数：`-project GaplessPaste.xcodeproj -scheme GaplessPaste -destination 'platform=macOS' -derivedDataPath .build/DerivedData`，并 `set -o pipefail` 后接 `| xcbeautify`

## 签名与 TCC

- Bundle ID：`com.reorx.gaplesspaste`。**TCC 授权与 bundle ID + 签名身份绑定，两者都不要随意改动**，否则麦克风/辅助功能等授权会被系统重置
- Debug 签名身份由 `Config/Local.xcconfig`（gitignore）提供；新机器初始化：装好 Apple Development 证书后 `cp Config/Local.xcconfig.example Config/Local.xcconfig` 填 Team ID（从证书提取：`security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject`，取 OU 字段）；无证书时回落 ad-hoc 签名，能构建但 TCC 会反复弹窗
- 签名身份变更后用 `tccutil reset <服务名> com.reorx.gaplesspaste` 清掉旧授权再重新授权
- Release 必须 Developer ID Application + hardened runtime + notarytool 公证

## CI

`.github/workflows/build.yml`（name: build app），仅在 push `v*` tag 时触发，单 job 顺序执行：Core 单测 → xcodegen → 无签名 Release 构建（`CODE_SIGNING_ALLOWED=NO`）→ `ditto` 打包为 `GaplessPaste-<tag>.zip` → `softprops/action-gh-release` 自动创建 release 并上传 zip（附自动生成的 release notes）

## 配置与设置界面

- 配置文件：`~/Library/Application Support/GaplessPaste/config.json`，模型在 Core 的 `ConfigModel.swift`（parse/validate/serialize 同一套规则）
- 主要编辑入口是菜单「设置…」（`GaplessPaste/UI/SettingsWindow.swift`）：编辑即校验，合法则防抖 0.5s 自动写盘并热重载（无「保存」按钮），非法暂缓落盘并显示内联提示
- GUI 保存会整体重写 JSON（sortedKeys），`_readme` 等未知键会丢失，这是预期行为；手改文件仍可走「重载配置」
- 首启写入模板后直接打开设置窗口（不再打开文本编辑器）
- 目录可选 `default_of`（`FILE`/`IMAGE`）标记快速上传默认落点，每台机器每类至多一个（`Config.validate` 保证，缺省=普通目录）；菜单「⚡ 快速上传」按剪贴板类型（文件→FILE、图像→IMAGE）直传对应默认目录、复用完整上传路径（图像仍弹重命名浮窗），机器未配任何默认目录则该项不显示

## UI 自动化验收（真机模拟操作 + 截图，已验证可行）

本机不装任何新自动化工具（Peekaboo 等新二进制都需要用户手动过 TCC 授权，走不通）。可行通道只有两条：AppleScript AX（iTerm2 已有 Accessibility）+ app 自截图（零 TCC）。

**截图：app 自截图，不要用 `screencapture`**

- 本机 iTerm2 的 Screen Recording 在 TCC 里被明确拒绝（auth=0），`screencapture` 必失败；查授权状态：`sqlite3 /Library/"Application Support"/com.apple.TCC/TCC.db "SELECT service,client,auth_value FROM access WHERE service='kTCCServiceScreenCapture'"`
- DEBUG 构建内置自截图钩子 `App/DebugHooks.swift`：监听分布式通知，用 `NSView.cacheDisplay` 截 app 自己的每个可见窗口（含标题栏），**不需要任何 TCC 权限**
- 触发：`swift scripts/capture.swift <输出目录>`，每个可见窗口输出一张 `window-<n>-<标题>.png`

**现成脚本都在 `scripts/`（随仓库走，全部真机验证过）**

长期有用的验收脚本放 `scripts/`，一次性的探索脚本才放 `tmp/`（整目录 gitignore）。所有 AX 脚本第一个参数都是**窗口标题片段**（设置窗口传 `设置`，预览窗口传 `🔍`），进程名固定 `GaplessPaste`：

| 脚本 | 用途 |
| --- | --- |
| `ax_dump.applescript <窗口> [深度]` | 打印 AX 树（层级 + 类型 + AXIdentifier + 值）。**写任何新 AX 脚本前先跑它**，别猜结构 |
| `ax_press.applescript <窗口> <id>` | 按 AXIdentifier 找按钮并 AXPress |
| `ax_fill.applescript <窗口> <id> <第几个> <文本>` | 往文本框填值（走剪贴板绕开 IME）；同 id 多个用序号区分 |
| `ax_select_row.applescript <窗口> <行文本>` | 选中 SwiftUI List 里的一行（如预览窗口目录树的文件） |
| `ax_close_window.applescript <窗口>` | 关窗收尾还原现场 |
| `menu_read.applescript` | 读状态栏菜单全部项标题（不截图核对菜单状态） |
| `menu_click.applescript <标题> <第几个>` | 点状态栏菜单项（同名项每机器一个，用序号区分） |
| `capture.swift <输出目录>` | 触发 app 自截图（见上节） |
| `preview_open.swift <机器名> <路径>` | 直接开预览窗口（见下节 DEBUG 钩子） |

- 给可交互控件埋 `.accessibilityIdentifier("xxx")`（映射为 AXIdentifier）才能被上述脚本定位
- 状态栏菜单路径：LSUIElement app 的 status item 是 `menu bar item 1 of menu bar 2 of process "GaplessPaste"`，`key code 53`（Esc）收起菜单
- 操作前 `set frontmost to true`（LSUIElement app 不会自己在前台），操作窗口前 `perform action "AXRaise"`

**DEBUG 钩子：绕过 UI 直达目标状态（AX 不可靠时的兜底，`App/DebugHooks.swift`）**

- 状态栏菜单项的 `click`/`AXPress` 有时静默失效（菜单开着不动、action 不触发，重试也没用），且预览入口的 NSAlert 模态弹窗又叠一层不确定性——验收要打开预览窗口时不走菜单，直接发分布式通知：`swift scripts/preview_open.swift <机器名> <远端路径>`（通知名 `com.reorx.gaplesspaste.debug.preview`，object 为 `机器名|路径`，跳过路径弹窗直接开窗）
- 自截图钩子同理（通知名 `com.reorx.gaplesspaste.debug.capture`）；两个钩子都只在 DEBUG 构建注册，新增验收堵点时优先考虑加同类钩子而不是硬磕 AX

**必踩的坑（都已验证）**

- `entire contents of window` **在深层 SwiftUI 树上会静默返回空集合**（窗口明明有子元素，count 却是 0，且稳定复现不是偶发）——所有查找一律自己递归下降 `UI elements of`，`scripts/ax_*.applescript` 已是这个写法；`whose` 子句不递归，同样别指望
- AppleScript 保留字会毒化变量名：拼接缓冲别叫 `line`，也别叫 `outLine`（会被解析成 `outline`），赋值直接报 `-10003 Access not allowed`——用 `buf` 这类无歧义的名字
- SwiftUI TextField 直接 `set value of text field`（AXValue）只改显示、**不触发 binding**，数据不会真正变化——必须发真实键盘事件
- 中文输入法会把 `keystroke` 的字母吞进组合缓冲（只有 `-` 等符号直通）——填文本一律走剪贴板：`set the clipboard to`… 后 `⌘A` + `⌘V`；操作前 `pbpaste` 备份用户剪贴板，结束后恢复
- NSSavePanel/NSOpenPanel 是 XPC 远程渲染（openAndSavePanelService）：app 进程里的 AX 元素只是代理，`click`/`AXPress`/`set value` 全部静默无效，app 自截图也是黑的——**只能纯键盘驱动**：AXRaise 面板窗口后 `⌘⇧G` → `⌘A`+`⌘V`（路径先放剪贴板）→ 回车（确认前往）→ 回车（默认按钮存储）；每步间留足 delay
- SwiftUI List 行选中：对 row 元素 `set selected to true` 有效（`AXPress` 行内 static text 无效）；点自定义按钮用 `perform action "AXPress"`（`click` 按坐标点，面板/布局动过后会点偏）

**验收闭环**

1. 先备份将被改动的真实数据（如 `config.json`）和用户剪贴板（`ax_fill` 会覆盖剪贴板）
2. `make build && make run` → AX 打开目标界面 → 每步操作后**读实际落盘文件/日志**核对（不要只看 UI），关键状态触发自截图
3. 结束后恢复备份、恢复剪贴板，让 app 重载，确认现场还原（改过 `config.json` 就 diff 回备份确认一致）
4. 验收截图归档到 `tmp/<日期>-<任务名>/`，报告里给出目录路径

## 日志

- 运行时日志固定写到 `~/Library/Logs/GaplessPaste/GaplessPaste.log`（超 5MB 滚动为 `.log.1`）
- 菜单「打开日志」打开该文件；命令行排错直接 `tail -f` / `cat` 它
- 每条 ssh/scp 命令的完整 argv、耗时、退出码、stderr 都在日志里（DEBUG/INFO 级）

## 排错顺序

构建怪异时先怀疑环境再怀疑代码：

1. `make clean && make build`（清 DerivedData + 重新生成工程）
2. 检查僵尸进程：`pgrep -lx GaplessPaste`、`pgrep -l xcodebuild`
3. SPM 缓存问题：`rm -rf GaplessPasteCore/.build`、删 `.build/DerivedData` 下 SourcePackages
4. 以上无效再看代码
