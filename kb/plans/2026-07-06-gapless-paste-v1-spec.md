---
created: 2026-07-06
updated: 2026-07-06
tags:
  - plan
  - spec
  - macos
  - swiftui
  - ssh
  - clipboard
---

# Gapless Paste v1 Spec

> 经头脑风暴访谈定稿（2026-07-06），关键决策见各节内嵌说明。工程套路复用 vocalflow-mac 已验证的一套（XcodeGen + Makefile + Core SPM 包 + BDD）。

## 背景与目标

核心工作流：**本机产生视觉材料（截图 / 下载图 / 生成的快照）→ 最少步骤传到远端机器 → 远端的 Claude Code 能立刻使用它**。

用户当前的远端是一台 **Mac mini**（SSH 可达，Claude Code 跑在其 tmux 里，已实测 Ctrl+V 能从 Mac mini 本机剪贴板读图）。设计上支持未来扩展为多台机器（含 Linux），但 v1 只实现 macOS 远端的完整链路。

产品形态：macOS 菜单栏 accessory app（无 Dock 图标）。名称 **Gapless Paste**，bundle ID `com.reorx.gaplesspaste`。

### 两条回传通道（本产品的核心设计）

上传/同步完成后，如何让远端 Claude Code 拿到材料，按内容类型走不同通道：

| 剪贴板内容 | 动作 | 回传通道 | 用户在远端的操作 |
|---|---|---|---|
| 文件引用（Finder ⌘C） | 按原名上传到目标目录 | **本地剪贴板** ← 远端绝对路径（文本） | 终端里 ⌘V 把路径粘给 Claude Code |
| 图像数据（截图/浏览器拷图） | 重命名浮窗 → 上传到目标目录 | **远端剪贴板** ← 图像本体 | Claude Code 里 Ctrl+V 直接吸入图片 |
| 图像/文本（剪贴板同步） | 不进目录，直通远端剪贴板 | **远端剪贴板** ← 内容本体 | 同上 |

原理：文本粘贴进终端会转成键入流传到远端，所以路径走本地剪贴板即可；图像走不了终端键入流，所以反向注入远端剪贴板，配合 Claude Code 的 Ctrl+V 读图能力完成闭环。

## 功能需求

### 四条触发路径

**A. 菜单点击 — 剪贴板上传（M1）**
1. 点开菜单栏图标 → 菜单按机器分区列出预设远端目录
2. 点击某目录 → 读剪贴板并分类：
   - **文件引用**：按原文件名上传（支持多文件），完成后把远端绝对路径写入本地剪贴板（多文件换行分隔）
   - **图像数据**：一律弹出**重命名浮窗**（预填默认名，见「命名」节），Enter 确认上传，Esc 取消；M2 起上传成功后追加注入远端剪贴板
   - **空/不支持**：系统通知提示「剪贴板没有可上传的内容」

**B. 剪贴板同步（M2）**
每台机器菜单区的第一项「⇄ 同步剪贴板」：
1. 点击 → 读本地剪贴板
2. **图像数据**：写本地临时 PNG → scp 到远端固定临时路径（`~/.cache/gapless-paste/clipboard.png`，每次覆盖，不累积）→ osascript 注入远端剪贴板 → 通知成功
3. **纯文本**：直接 `ssh <host> pbcopy` 注入
4. **文件引用**：不支持同步（提示改用目录上传路径）
- 场景：某工具只提供「复制到剪贴板」、图片不落盘时，同步后直接在远端 Claude Code 里 Ctrl+V
- 无重命名浮窗、无目录选择——这是最快路径，名字无意义

**C. 拖拽上传（M3）**
1. 拖文件到菜单栏图标上（NSStatusItem button 注册 drop target）
2. 拖入时图标下方弹出 DropPanel：所有「机器 × 目录」平铺成行，每行是独立 drop target
3. 松手 → 按文件引用模式上传（同 A），拖离后延迟隐藏
- v1 只接受 file URL 拖拽；浏览器图像数据拖拽记入 known-issues 留 M4+
- Dropzone 式「一开始拖动就全局弹出」不做（见非目标）

**D. 全局热键（M4）**
一键「剪贴板 → 上次使用的目标」，跳过菜单。图像数据仍弹重命名浮窗（保持行为一致）。

### 命名与重名

- 图像默认名：`shot-YYYYMMDD-HHmmss.png`（本地时间）
- 重命名浮窗预填默认名并**选中主文件名部分**（直接输入即整体覆盖），扩展名锁定 `.png`
- 清洗规则：文件名中的 `/`、`:`、控制字符、空白替换为 `-`（避免远端路径含空格给 Claude Code 引用添乱）
- 重名策略：上传前 `ssh <host> test -e <path>` 探测，存在则在**扩展名之前**追加 `-1`、`-2`（`shot-xxx-1.png`），循环递增直到不存在（对文件引用与图像统一适用）；ControlMaster 复用连接下这次往返开销可忽略

### 上传后行为

- **文件引用模式**：远端绝对路径（文本，多文件换行分隔）写入本地剪贴板；发成功通知（含路径）
- **图像模式**：M1 仅通知（含远端路径）+ 不覆盖本地剪贴板（图像保留在本地剪贴板）；M2 起追加远端剪贴板注入
- **失败**：通知含错误摘要（stderr 首行），菜单顶部「重试上次操作」
- 菜单常驻「拷贝上次上传的远端路径」项，随时可取回路径

### 路径回传的绝对化

Claude Code 不一定展开 `~`，因此回传路径必须是绝对路径。首次对某机器操作时执行一次探测（结果缓存，**「重载配置」时清缓存**）：

```
ssh <host> 'echo "$HOME"; uname'
```

- `$HOME` 用于把配置里的 `~/...` 目录展开为绝对路径——**M1 即需要**（路径回传依赖它）
- `uname` 用于远端平台判定（剪贴板注入方式），M2 才消费；探测命令一次拿全，避免两次往返

### 远端剪贴板注入（M2）

- **Darwin**（v1 唯一实现）：图像先确保在远端有文件（目录上传的产物，或同步路径的临时文件），然后
  `ssh <host> osascript -e 'set the clipboard to (read (POSIX file "<remote-path>") as «class PNGf»)'`
  ；纯文本用 `pbcopy`
- **非 Darwin**：v1 不实现注入。目录上传场景**自动降级为路径模式**（远端路径以文本写回本地剪贴板），通知注明「远端无剪贴板注入，已拷贝路径」；「⇄ 同步剪贴板」菜单项对非 Darwin 机器直接**禁用**（降级语义对它不成立）；尚未探测过的机器该项保持可用，点击时探测、发现非 Darwin 则提示并置灰。探测与命令生成留出平台分支接口（Linux 未来按 `wl-copy` / `xclip` 扩展）
- ⚠️ 前提：osascript 写剪贴板需要 SSH 用户与 Mac mini 上已登录 GUI 会话的用户一致（pasteboard 按用户会话隔离）。列入 M2 验收前的手工验证项

### 传输层：系统 ssh/scp 子进程

不内嵌 SSH 库（SwiftNIO SSH / libssh2 需要自行解析 ssh config、对接 agent、实现跳板，工作量大一个数量级而收益为零）。直接 `Process` 调 `/usr/bin/ssh` 与 `/usr/bin/scp`：

- 天然继承 `~/.ssh/config`：host alias、密钥、agent、ProxyJump 全部可用，配置里只需写 alias
- **ControlMaster 连接复用**：所有调用统一追加
  `-o ControlMaster=auto -o ControlPath=<app支持目录>/sockets/%C -o ControlPersist=600 -o ConnectTimeout=10`
  首次连接后重复上传毫秒级，适配「截图连发」场景；socket 走 app 自己的目录，不污染用户 ssh 配置
- macOS 的 scp 默认走 SFTP 协议，行为一致，无需特殊处理
- 远端路径含特殊字符的引号/转义由 Core 的命令构建器统一处理（纯函数，可测）

## 非目标（v1）

- 不做传输队列 / 断点续传 / 并发上传（单任务串行，进行中时菜单项禁用）
- 不做远端目录浏览 / 自动补全，目录全靠配置文件预设
- 不做下载方向（远端 → 本地）
- 不做 Linux 远端的剪贴板注入实现（仅留平台分支接口，探测到非 Darwin 即降级路径模式）
- 不做 Dropzone 式「开始拖动即全局弹出」（需要全局拖拽监听，v1 用「拖到图标弹出」够用）
- 不做图像格式选择（统一 PNG；剪贴板 TIFF 数据转 PNG 后处理）
- 不做设置 UI（M4 再议），v1 配置 = JSON 文件 + 菜单「打开配置 / 重载配置」
- 不做浏览器图像数据拖拽（记 known-issues）
- 不上 MAS、无沙箱（需要读 `~/.ssh` 与起子进程）

## 配置模型

`~/Library/Application Support/GaplessPaste/config.json`：

```json
{
  "machines": [
    {
      "name": "mini",
      "sshAlias": "mini",
      "directories": [
        { "name": "inbox", "path": "~/claude-inbox" },
        { "name": "screenshots", "path": "~/claude-inbox/screenshots" }
      ]
    }
  ]
}
```

- `sshAlias` 对应 `~/.ssh/config` 的 Host 条目；认证、端口、跳板全部由 ssh config 负责
- `path` 支持 `~/` 前缀，运行时用探测到的 `$HOME` 展开
- 配置解析失败：菜单显示错误态 + 通知，提供「打开配置」修复入口
- 首启无配置文件：写入示例模板并打开它（标准 JSON 无注释，说明文字放顶层 `_readme` 字段，解析时忽略未知键）

## 菜单结构

```
[G 图标]
├ （状态行：进行中/上次结果，禁用项）
├ 拷贝上次上传的远端路径
├ 重试上次操作            （仅失败后出现）
├ ── mini ──              （机器名 section header）
│  ├ ⇄ 同步剪贴板
│  ├ 📁 inbox
│  └ 📁 screenshots
├ ── （其他机器同构）──
├ 打开配置
├ 重载配置
└ 退出
```

- 单机器时也保留 section header（结构一致，避免两套渲染逻辑）
- 目录不嵌子菜单——高频操作不藏第二层

## 重命名浮窗

- 居中偏上的小浮窗（NSPanel，可成 key window 以接收输入）
- 内容：目标「机器/目录」标注 + 图像缩略图预览 + 文件名输入框（预填默认名、选中主文件名、扩展名锁定）
- Enter = 确认上传；Esc = 取消（不上传、剪贴板不动）
- 浮窗弹出时 app 临时 `NSApp.activate` 抢焦点，关闭后交还前台 app

## 项目骨架

```
gapless-paste/
  project.yml                      # XcodeGen 唯一事实来源
  Makefile                         # build / test / run / dev / gen / clean（同 vocalflow-mac）
  Config/                          # Debug/Release/Local.xcconfig 签名套路（同 vocalflow-mac）
  CLAUDE.md                        # agent 工程约定（AGENTS.md 软链）
  kb/                              # 知识库（本 spec 所在）
  GaplessPasteCore/                # 本地 SPM 包，纯逻辑，禁止 AppKit，swift test 全部在此
    Sources/GaplessPasteCore/
      PasteboardClassifier.swift   # 剪贴板快照 → fileURLs | imageData | text | empty（优先级：fileURLs > image > text）
      NameGenerator.swift          # 默认名生成（Date 注入）、清洗、重名后缀
      TransferPlanner.swift        # (内容类型, 目标) → 步骤序列（落盘/scp/注入/回传/通知）
      SSHCommandBuilder.swift      # ssh/scp 参数数组构建：ControlMaster 选项、远端路径转义
      RemoteClipboard.swift        # 平台探测结果 → 注入命令（Darwin: osascript/pbcopy；其他: nil→降级）
      ProbeResult.swift            # $HOME / uname 探测结果模型与解析
      ConfigModel.swift            # Codable 配置模型 + 校验
    Tests/GaplessPasteCoreTests/
  GaplessPaste/                    # app target
    Services/
      PasteboardService.swift      # NSPasteboard 读写（含 TIFF→PNG 转换）
      SSHRunner.swift              # Process 执行 + 超时 + stderr 采集；串行任务队列
      ProbeService.swift           # 首次探测 + 缓存（$HOME、uname）
      ConfigStore.swift            # 配置读写/监听重载
      NotificationService.swift    # UNUserNotificationCenter
    UI/
      StatusMenuController.swift   # 菜单构建/状态
      DropPanel.swift              # 拖拽目标浮窗（M3）
      RenamePopup.swift            # 重命名浮窗
    App/
      AppState.swift               # 全局状态，桥接 Planner 与 Services
      GaplessPasteApp.swift
```

- macOS 14+，SwiftUI App lifecycle，Swift 5 语言模式，`LSUIElement = true`
- 无第三方依赖（v1 连 GRDB 都不需要——无持久化数据，探测缓存进 UserDefaults）
- 权限面只有「通知」（可选，拒绝也不影响核心功能）——无 TCC 大礼包，签名约定仍沿用固定 Apple Development 身份（Config/Local.xcconfig）
- CI：`.github/workflows/test.yml`，core-tests（swift test）+ app-build（无签名 xcodebuild）两个 job

## 开发方法与测试

- 新功能 BDD：先在 `GaplessPasteCoreTests` 写行为测试（Swift Testing `@Test`/`#expect`）再实现
- Core 的可测面刻意做大：分类判定、命名/清洗/重名、命令与参数构建、注入命令生成、探测输出解析、计划步骤序列——全部纯函数
- app 侧每里程碑附手工验收清单（见下）

## 里程碑与验收

**M1 — 目录上传闭环**：骨架 + 配置加载 + 菜单 + `$HOME` 探测（`uname` 一并采集但 M2 才消费）+ 路径 A（文件/图像分类、重命名浮窗、重名探测、路径回传、通知）
- 验收：⌃⇧⌘4 截图拷贝 → 菜单点 `inbox` → 重命名回车 → 文件出现在 mini 对应目录，本地通知含远端绝对路径；Finder ⌘C 两个文件 → 点目录 → 两文件上传、本地剪贴板为两行绝对路径；`swift test` 全绿

**M2 — 剪贴板闭环**：Darwin 远端剪贴板注入（消费 M1 已采集的 `uname`）+ 「⇄ 同步剪贴板」+ 非 Darwin 降级/禁用
- 验收：截图 → 菜单点目录 → 上传后在 mini 的 tmux 里 Claude Code Ctrl+V 出图；「同步剪贴板」对图像与纯文本均生效；前置手工验证：SSH 会话里 osascript 写剪贴板对已登录同用户生效

**M3 — 拖拽**：图标 drop target + DropPanel
- 验收：从 Finder/桌面拖文件到菜单栏图标 → 浮窗出现 → 丢到目录行 → 上传成功路径回传

**M4 — 打磨**：全局热键（剪贴板→上次目标）、设置 UI、登录启动项、浏览器拖图评估

## 已知风险 / 开工前验证项

1. **osascript over SSH 写剪贴板**：需 SSH 用户与 Mac mini 控制台登录用户一致；若 mini 处于无 GUI 会话状态（未登录/锁屏下行为）需实测。M2 开工前先手工跑一遍注入命令 + Ctrl+V 验证
2. **`«class PNGf»` 的引号转义**：osascript 命令经 ssh 传输的两层引号问题，Core 单测覆盖构建结果，开工时用真实命令行先验证一次
3. **剪贴板图像格式**：部分应用只放 TIFF；统一经 NSBitmapImageRep 转 PNG，需覆盖「TIFF-only」用例
4. **NSStatusItem 拖拽兼容性**：菜单栏图标作为 drop target 在不同 macOS 版本的行为差异，M3 开工时先做最小 spike
