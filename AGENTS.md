# GaplessPaste

macOS 菜单栏工具：把本机剪贴板里的截图/文件/文本以最少步骤传到 SSH 可达的远端机器，让远端的 Claude Code 立刻可用。

## 功能现状

- 已实现：目录上传、快速上传、拖拽上传、剪贴板双向同步、预览远端目录窗口、设置窗口、窗口打开时的 Dock 形态
- 未实现：全局热键、登录启动项、浏览器图像数据拖拽
- 远端剪贴板注入只支持 macOS 远端；非 Darwin 时同步菜单项置灰，图像上传降级为回传路径

## 文档

- `README.md` — 面向用户的介绍（功能、安装、使用前提、配置格式、从源码构建）。仓库公开，功能、安装方式或配置格式变了要同步改它
- `kb/docs/features.md` — 各功能的行为规则（上传、命名与重名、剪贴板同步、传输层、配置、Dock 形态）。改这些行为或菜单前读
- `kb/docs/preview-window.md` — 预览窗口的导航、预览类型、缩放、导出、缓存规则。改预览窗口前读
- `kb/docs/release.md` — 发版方式、CI 流程、secrets、cask 下载地址、本地出包与失败处理。发版或改发布链路前读
- `kb/docs/ui-acceptance.md` — 验收通道、脚本清单、DEBUG 钩子、已踩过的坑。做真机 UI 验收或写新 AX 脚本前必读
- `kb/plans/2026-07-06-gapless-paste-v1-spec.md` — 原始需求与决策背景；部分内容已过时，现状以 `kb/docs/` 为准
- `kb/sessions/` — 历次改动；`kb/known-issues.md` — 未解决问题与未验收项

## 技术栈与分层

- macOS 14.0+，SwiftUI App lifecycle，Swift 5 语言模式（非 Swift 6 strict concurrency）
- `GaplessPasteCore/` — 本地 SPM 包，纯逻辑（状态机、编解码、数据模型），**禁止依赖 AppKit**，所有单测在此
- `GaplessPaste/` — app target，系统胶水与 UI，按 `App/` `Services/` `UI/` 组织
- 工具链：Xcode、xcodegen、xcbeautify（`brew install xcodegen xcbeautify`）

## 工程约定

- **构建/测试/运行一律走 Makefile，不用 Xcode GUI**
- 工程定义的唯一事实来源是 `project.yml`。以下三个文件由 xcodegen 生成，**不要手工编辑**：`GaplessPaste.xcodeproj`（不入库）、`GaplessPaste/Info.plist`、`GaplessPaste/GaplessPaste.entitlements`
- 加源文件：放进 `GaplessPaste/` 对应目录后 `make gen`；改 target 配置、Info.plist、entitlements、包依赖：改 `project.yml` 后 `make gen`
- 新功能 BDD：先在 `GaplessPasteCore/Tests/GaplessPasteCoreTests/` 写行为测试（Swift Testing，`@Test` / `#expect`）再实现；bug 修复 TDD：先写复现测试
- 新增可交互控件要加 `.accessibilityIdentifier("…")`，验收脚本靠它定位

## 命令

```
make build       # xcodegen + Debug 构建
make test        # GaplessPasteCore 单测
make run         # kill 旧实例并启动已构建的 app（不触发构建）
make dev         # build + run
make gen         # 仅重新生成 xcodeproj
make clean       # 清理构建产物与生成的 xcodeproj
make release-local   # 本地出已签名公证的 dmg（build-release / notarize-app / dmg / notarize），见 kb/docs/release.md
```

- 构建产物：`.build/DerivedData/Build/Products/Debug/GaplessPaste.app`
- 跑单个测试：`cd GaplessPasteCore && swift test --filter <测试名>`
- 需要直接调 xcodebuild 时，参数照抄 `Makefile` 的 `XCODEBUILD` 变量

## 签名

- Bundle ID `com.reorx.gaplesspaste`，**不要改**：通知授权、UserDefaults（探测缓存、近期路径）、DEBUG 钩子的通知名和验收脚本都绑定它
- app 不沙箱（要启动 ssh/scp 子进程、读 `~/.ssh`），目前也不使用任何受 TCC 保护的能力（辅助功能、录屏、麦克风都没有）。将来加入这类功能（如全局热键）后，签名身份一变授权就会失效，届时需要固定身份并用 `tccutil reset <服务名> com.reorx.gaplesspaste` 清旧授权
- Debug 签名身份来自 `Config/Local.xcconfig`（不入库）；新机器按 `Config/Local.xcconfig.example` 里的说明创建。没有它时回落 ad-hoc 签名，照常构建
- 正式发布用 Developer ID Application 签名 + hardened runtime + notarytool 公证，配置在 `Config/Release.xcconfig`（不 include `Local.xcconfig`，Team ID 由 Makefile 从 `~/Sync/apple-developer/secrets.env` 或 CI 传入）
- App 图标由 `swift scripts/gen_app_icon.swift` 生成到 `GaplessPaste/Assets.xcassets/`（产物入库）；Dock 仍显示旧图标时 `lsregister -f <app 路径>`

## CI

`.github/workflows/release.yml`：push `v*` tag → Core 单测 → Universal Release 构建 → 签名公证 dmg → 本仓库 Release → 自动更新 `reorx/homebrew-tap` 的 cask。发版就是 `git tag vX.Y.Z && git push origin vX.Y.Z`，版本号只来自 tag。细节见 `kb/docs/release.md`。

## 配置

- 文件：`~/Library/Application Support/GaplessPaste/config.json`；模型与校验规则在 Core 的 `ConfigModel.swift`（parse / validate / serialize 同一套）
- 设置窗口保存时整体重写 JSON，未知键（如 `_readme`）会丢失，这是预期行为
- 验收时改动它之前先备份，结束后恢复并 diff 确认

## UI 验收

- 截 app 窗口用自截图：`swift scripts/capture.swift <输出目录>`（DEBUG 构建，零 TCC 授权，熄屏和 SSH 会话下也可用）
- 操作界面用 `scripts/` 下的 AX 脚本；写新 AX 脚本前先跑 `ax_dump.applescript` 看真实结构
- 开预览窗口不走菜单，用 `swift scripts/preview_open.swift <机器名> <路径>`
- 操作前先 `wake-screen`：本机没有锁屏、只会熄屏，但熄屏时 `screen_locked.swift` 同样打印 `locked`，AX、按键、鼠标全部假失败，唤醒后即恢复（SSH 会话里也有效）。唤醒后仍是 `locked` 才是真锁屏，那时改用 DEBUG 钩子验模型逻辑，验不了的项登记到 `kb/known-issues.md`
- `ax_fill` 会覆盖剪贴板，操作前备份、结束后恢复
- 不要为验收安装新的自动化工具（需要用户手动过 TCC 授权）
- 长期有用的验收脚本放 `scripts/`，一次性脚本放 `tmp/`；截图归档到 `tmp/<日期>-<任务名>/`

脚本清单、各通道的前提、已踩过的坑、完整流程在 `kb/docs/ui-acceptance.md`。

## 日志

- `~/Library/Logs/GaplessPaste/GaplessPaste.log`（超 5MB 滚动为 `.log.1`）
- 每条 ssh/scp 命令的完整 argv、耗时、退出码、stderr 都在里面，排错先看它

## 构建排错

先怀疑环境再怀疑代码：

1. `make clean && make build`
2. 查僵尸进程：`pgrep -lx GaplessPaste`、`pgrep -l xcodebuild`
3. 清 SPM 缓存：`rm -rf GaplessPasteCore/.build`，删 `.build/DerivedData` 下的 SourcePackages
