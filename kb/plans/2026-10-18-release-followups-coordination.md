---
created: 2026-10-18
tags:
  - release
  - homebrew
  - sparkle
  - signing
  - coordination
---

# 发布链路后续：tap deploy key 迁移、Sparkle 自动更新、Debug 签名 Team（协调记录）

本文由协调者（本仓库里的 Claude 会话）编写，既是执行者共用的 brief，也是协调记录。背景：2026-10-17 给本仓库接好了全自动发布（见 `kb/sessions/2026-10-17-release-automation.md`），方案沉淀为 `macos-app-release` skill（本机 `~/.claude/skills/macos-app-release/`）。收尾时协调者提了几条建议，用户的回应见决定表。

决定表里标「协调者」的条目用户没有逐条确认，执行者有不同意见可以在总结里提出，但先照做。

**本仓库已公开。** 本文和执行者写进本仓库的任何文件都不要出现私有仓库的名字、私有仓库的路径或它们的细节。涉及私有项目的任务（T3）只在本文留一个占位，细节记在不入库的 `tmp/2026-10-18-release-followups/` 里。skill 用 `~/.claude/skills/<名字>/` 的路径指代，不写它实际所在的仓库。

## 决定表

| 问题 | 决定 | 谁定的 |
|---|---|---|
| mdnotate、feishu-lite 的 tap 写权限换成 deploy key | 做 | 用户 |
| 另一个私有项目补上 app 自身的公证票据（T3） | 做；细节不入库 | 用户 |
| 迁移后旧的 `TAP_PUSH_TOKEN` secret | 删除。它已不再被引用；feishu-lite 那个是 gh 的 OAuth token，权限覆盖整个账号，迁移的意义就在于删掉它 | 协调者 |
| mdnotate 的 cask 更新方式 | 只换凭据。保留 sed 改 `version` / `sha256`，保留「未配置则跳过」的行为 | 协调者 |
| feishu-lite 是否推送 | 不推送。本地 master 上有另一个协调会话的未推送提交 | 协调者 |
| 其他仓库是否推送 | `git log @{u}..HEAD` 里只有自己的提交才推送，否则不推，写进总结 | 协调者 |
| Debug 签名换成付费 Team（T5） | 换 | 用户 |
| T5 的范围 | 从根上修 `macos-app-bootstrap` 的 `setup-signing.sh`（现在取钥匙串里第一张 Apple Development 证书，排在前面的是已弃用的免费 Team），再用修好的脚本重新生成本仓库和 `gapless-paste-svg` worktree 的 `Config/Local.xcconfig`。其他项目不在本次范围 | 协调者 |
| Sparkle 的托管方式（T4） | 方案 A：仓库已转公开，appcast 和更新包都放本仓库的 GitHub Release | 用户 |
| Sparkle 的更新包 | 直接用已公证、已钉票据的那个 dmg，不另出 zip。执行者发现 dmg 不合适（如 Sparkle 的限制）可以改用 zip，在总结里说明 | 协调者 |
| appcast 的形式 | 每次发版生成只含当前版本一项的 `appcast.xml`，作为 Release 资源上传；`SUFeedURL` 用 `https://github.com/reorx/gapless-paste/releases/latest/download/appcast.xml`。不做增量更新、不做 beta 通道 | 协调者 |
| Sparkle 的 EdDSA 私钥存放 | 本机导出一份到 `~/Sync/apple-developer/sparkle/gapless-paste_ed25519.key`（600 权限）作为备份，CI 用 secret `SPARKLE_ED_PRIVATE_KEY`。私钥丢了，已安装的版本就再也收不到更新 | 协调者 |
| 自动检查 | Release 构建默认每天自动检查、有更新弹 Sparkle 的标准对话框，由用户点安装；不静默安装。Debug 构建不自动检查，避免开发时被正式版覆盖 | 协调者 |
| cask | 加 `auto_updates true`，避免 `brew upgrade` 和 Sparkle 打架 | 协调者 |
| Sparkle 的端到端验证 | 只发一个正式版 v0.2.0。验证「旧版收到更新」时，在本地用同样的代码构建一个版本号更低（如 0.1.9、构建号低于 CI 的 run number）的 Developer ID 签名版本，放在临时目录运行，让它从真实的 feed 更新到 v0.2.0 | 协调者 |
| T4 推送 master | 允许。master 上除协调者和 T5 的提交外，还有一个「仓库公开」提交（另一个会话做的公开准备：README、LICENSE、文档改为公开口径），它本来就是为公开准备的 | 协调者 |
| 正在运行的 `gapless-paste-svg` Debug 实例（2026-10-17 18:20 启动，启动它的 agent 已退出） | T4 验收需要启动同 bundle ID 的 app 时，可以退出它；T5 不需要启动 app，不碰它 | 协调者 |
| T4、T5 的顺序 | 先 T5 后 T4。两者都要在本仓库 `make gen` / `make build`，同时跑会互相读到对方改了一半的 `project.yml` | 协调者 |

## 必读

所有执行者开工前读：

1. 本文
2. 所在仓库的 `AGENTS.md`
3. `~/.claude/skills/macos-app-release/SKILL.md`：发布方案总览和设计决定
4. `~/.claude/skills/macos-app-release/references/troubleshooting.md`：踩过的坑，尤其「Shell 脚本」一节

T1、T2 另读 `~/.claude/skills/macos-app-release/references/homebrew.md`「tap 的写权限：deploy key」一节，以及参照实现 `~/Code/gapless-paste/.github/workflows/release.yml` 的 homebrew job。

T4 另读：

- `kb/docs/release.md`、`kb/docs/features.md`、`kb/docs/ui-acceptance.md`
- `~/.claude/docs/DESKTOP_APP_TESTING.md`（实机验收前必读）
- `~/.claude/skills/macos-app-release/references/pipeline.md`
- Sparkle 2 的官方文档：用 context7 查，重点是 Programmatic Setup、Publishing an update（`sign_update` / `generate_appcast`）、EdDSA 密钥、非沙盒 app 的代码签名（Xcode Archive 以外的构建方式要自己重签框架里的辅助程序）

T5 另读 `~/.claude/skills/macos-app-bootstrap/SKILL.md` 和 `scripts/setup-signing.sh`、`~/Sync/apple-developer/AGENTS.md`、本仓库 `Config/Local.xcconfig.example`。

## 任务

| 任务 | agent | 仓库（tab 的 cwd） | 依赖 | 验证方式 |
|---|---|---|---|---|
| T1 feishu-lite 换 deploy key | `rel-feishu-key` | `~/Code/feishu-lite` | 无 | actionlint、tap 的 deploy key 列表、secret 列表 |
| T2 mdnotate 换 deploy key | `rel-mdnotate-key` | `~/Code/mdnotate` | 无 | 同上，外加推送 |
| T3 私有项目的两轮公证 | （不入库） | 不入库 | 无 | 不入库 |
| T5 Debug 签名换付费 Team | `rel-debug-team` | `~/Code/gapless-paste` | 无 | 脚本测试、两份 Local.xcconfig、Debug 构建的签名 |
| T4 Sparkle 自动更新 | `rel-sparkle` | `~/Code/gapless-paste` | T5 签收后开始 | 本地出包、v0.2.0 正式发布、旧版从真实 feed 更新到 v0.2.0 |

### T1 feishu-lite：tap 写权限换成 deploy key（已签收）

范围：运行 `bash ~/.claude/skills/macos-app-release/scripts/setup-secrets.sh --repo reorx/feishu-lite --skip-apple`；homebrew job 检出 tap 改用 `ssh-key: ${{ secrets.TAP_DEPLOY_KEY }}`，凭据检查改查 `TAP_DEPLOY_KEY`；`README.md`、`kb/docs/releases.md` 同步；提交后删除旧 secret。不推送、不构建、不发版，不改那边协调会话的 `kb/` 共享文件。

完成标准：actionlint 无报错；tap 的 deploy key 列表里有可写的 `release: reorx/feishu-lite`；secret 列表有 `TAP_DEPLOY_KEY`、没有 `TAP_PUSH_TOKEN`；`TAP_PUSH_TOKEN` 只剩历史记录里的引用；一个只含自己文件的提交，未推送。

### T2 mdnotate：tap 写权限换成 deploy key（已签收）

范围：同 T1 的脚本；「Bump Homebrew cask」不再用带 token 的 https 克隆，改为 `actions/checkout` + `ssh-key:` 检出到 `tap/`，照旧 sed、提交、`git push origin HEAD`；没配 key 时仍跳过（`if:` 里不能直接引用 secrets，用 job env 判断）；`.claude/skills/release/SKILL.md` 等文档同步；推送后删除旧 secret。

完成标准：同 T1，外加提交已推送。旧 fine-grained PAT 在 GitHub 上仍然有效，吊销只能在网页上做。

### T3 私有项目：app 和 dmg 两轮公证（已签收）

细节不入库，见 `tmp/2026-10-18-release-followups/T3-summary.md`。

### T5 Debug 签名换成付费 Team

背景：`macos-app-bootstrap` 的 `setup-signing.sh` 用 `security find-certificate -c "Apple Development"` 取第一张匹配的证书来定 Team。本机钥匙串里有两个 Team 的 Apple Development 证书：已弃用的免费 Personal Team `QFW98B7VB4`（Xcode 自动续了一张到 2027-06 的）和付费 Team `YU3FMV36N2`，排在前面的是免费 Team，所以用这个脚本初始化的项目 Debug 签名都落在免费 Team 上。免费 Team 靠 Xcode 里登录的免费 Apple ID 续证，哪天登出或续不上，Debug 构建就会失败；以后加了 TCC 能力再换签名身份，所有授权都要重新给一次。本仓库目前不用任何 TCC 能力，现在换没有代价。

范围：

1. 修 `~/.claude/skills/macos-app-bootstrap/scripts/setup-signing.sh`（skill 目录是软链，进 `realpath` 之后在它所在的 git 仓库里提交，不推送）：
   - Team 的来源依次是：环境变量 `APPLE_TEAM_ID`；`~/Sync/apple-developer/secrets.env` 里的 `APPLE_TEAM_ID`（只取这一个变量，不打印其他任何值）；都没有时，钥匙串里有效的 Apple Development 证书只属于一个 Team 就用它，属于多个 Team 就报错退出并列出各 Team，不许默默选一个
   - 选定 Team 后确认钥匙串里确实有这个 Team 的有效 Apple Development 身份（按证书 subject 的 OU 匹配），没有就报错并给出处理办法
   - 输出的 `Config/Local.xcconfig` 格式不变
   - bug 修复按 TDD：先写能复现「免费 Team 证书排在前面时选错」的测试再改。测试用假的 `security` 命令（放进临时 PATH）模拟钥匙串，不依赖本机真实钥匙串；测试放在 skill 目录里能长期保留的位置，跑法写进 skill 文档
   - skill 文档里关于 Team 检测的说明同步更新
2. 在本仓库根目录运行修好的脚本，重新生成 `Config/Local.xcconfig`，结果应为 `DEVELOPMENT_TEAM = YU3FMV36N2`。对 `~/Code/gapless-paste-svg`（本仓库的另一个 worktree）做同样的事，只改它的 `Config/Local.xcconfig`（不入库），不在那里构建、不提交
3. 本仓库 `Config/Local.xcconfig.example` 的注释里提取 Team ID 的命令有同样的问题，改成指向 `setup-signing.sh` 和付费 Team 的说明

验证：

- 新测试修复前失败、修复后通过，输出贴进总结
- 本仓库 `make build` 成功；`codesign -dvv .build/DerivedData/Build/Products/Debug/GaplessPaste.app` 显示 `TeamIdentifier=YU3FMV36N2`、`Authority=Apple Development: … (P3X7S2FBA5)` 这一类付费 Team 的身份
- `make test` 通过

不做：

- 不改其他项目的 `Local.xcconfig`，不在其他项目里运行脚本
- 不启动 app（`make run` 会杀掉正在运行的 `gapless-paste-svg` 实例），不 `make clean`
- 不改 `AGENTS.md`，需要改的写进「交给协调者」

完成标准：上面三项验证的证据都在总结里；skill 仓库一个提交（未推送）；本仓库一个提交，只含 `Config/Local.xcconfig.example`（`Local.xcconfig` 不入库）。

### T4 Sparkle 应用内自动更新（T5 签收后开始）

目标：GaplessPaste 的 Release 构建带 Sparkle 2，每天自动检查更新、菜单里能手动「检查更新」。发版 CI 在同一个 release job 里为最终的 dmg 生成 EdDSA 签名的 `appcast.xml`，作为 Release 资源上传；cask 加 `auto_updates true`。发布 v0.2.0，并验证一个旧版本能从真实的 feed 更新到 v0.2.0。

范围：

1. **依赖与配置（`project.yml`，改完 `make gen`）**：Sparkle 2 用 SPM 引入，固定到当前最新的 2.x 稳定版；Info 加 `SUFeedURL`、`SUPublicEDKey`、`SUEnableAutomaticChecks`；Debug 构建不自动检查（用 build setting 区分配置，或 DEBUG 下不自动启动检查，执行者定）。Sparkle 只进 app target，`GaplessPasteCore` 不依赖它
2. **代码**：app 层持有 `SPUStandardUpdaterController`；菜单栏菜单加「检查更新…」（文案风格跟现有菜单一致），按 `canCheckForUpdates` 启用或置灰，加 `accessibilityIdentifier`
3. **密钥**：用 Sparkle 的 `generate_keys --account gapless-paste` 生成（钥匙串里已有这个 account 就复用，不重新生成），导出到决定表里的路径，`gh secret set SPARKLE_ED_PRIVATE_KEY -R reorx/gapless-paste < <文件>` 存进 CI；公钥写进 `project.yml`。全程不把私钥打到终端或日志里。`~/Sync/apple-developer/` 下只允许新建 `sparkle/` 目录和这一个文件，那里的 `AGENTS.md` 由协调者更新
4. **签名**：`xcodebuild build` 不会像 Archive 那样重签 Sparkle.framework 里的辅助程序（Autoupdate、Updater.app、XPC 服务）。按 Sparkle 文档在构建后、公证前用 Developer ID + hardened runtime + timestamp 重签。`scripts/release/verify-app.sh` 扩展为检查 bundle 里所有嵌套代码，Developer ID、runtime、timestamp 一样都不能少
5. **appcast**：新脚本（如 `scripts/release/render-appcast.sh`）对最终的 dmg（钉完票据之后的字节）用 `sign_update` 计算签名，生成只含当前版本一项的 `appcast.xml`。要包含：`sparkle:version`（= `CFBundleVersion`，即 run number）、`sparkle:shortVersionString`、`sparkle:minimumSystemVersion`（14.0）、dmg 的版本化下载地址、长度、`sparkle:edSignature`，以及更新说明（用 Release 正文的安装说明还是另写一段，执行者定，在 Sparkle 对话框里要能看）。Makefile 加对应目标，`release-local` 也会生成 appcast。CI 里 `sign_update` 的来源固定版本；私钥从 secret 写到 `$RUNNER_TEMP`，用完删除，清理步骤 `if: always()`
6. **发布**：tag 发版时 `appcast.xml` 和 dmg、`SHA256SUMS` 一起上传；`workflow_dispatch` 时 appcast 只进 artifact。`render-cask.sh` 加 `auto_updates true`
7. **文档**：`kb/docs/release.md` 加 Sparkle 一节（密钥在哪、丢了的后果、appcast 怎么生成、feed 地址）；`kb/docs/features.md` 写「检查更新」的行为；`AGENTS.md` 里功能现状、签名、CI 相关的几行（T4 进行时本仓库没有别的执行者，所以这几行允许 T4 改）

验证：

1. `make test` 通过；新菜单项的行为按 `kb/docs/ui-acceptance.md` 的通道在 Debug 构建上实机看一次（菜单项存在、可点、点了出现 Sparkle 的检查窗口）
2. 本地 `make release-local`：两次公证 Accepted；`verify-app.sh` 的嵌套代码检查通过；挂载 dmg 后 `syspolicy_check distribution` 通过；`appcast.xml` 能被 `xmllint` 解析，签名能被 `sign_update` 校验（看它支持的校验方式）
3. 正式发布：推送 master，打 `v0.2.0` 并推送。两个 job 都成功；Release 页有 dmg、`SHA256SUMS`、`appcast.xml`；`curl -fsSL https://github.com/reorx/gapless-paste/releases/latest/download/appcast.xml` 拿到 v0.2.0 那一项；tap 里的 cask 是普通下载地址、带 `auto_updates true`
4. 端到端更新：在本地用当前代码构建一个更低版本（如 `VERSION=0.1.9`，`BUILD_NUMBER` 低于 v0.2.0 那次 run 的 run number）的正式签名版本，放到 `tmp/2026-10-18-release-followups/T4/` 下的临时目录运行（Sparkle 要求新旧版本的代码签名一致，所以旧版也要用 Developer ID 签）。点「检查更新…」，Sparkle 找到 0.2.0 → 安装 → 重新启动。之后那个路径下的 app 版本是 0.2.0，`codesign --verify --deep --strict` 通过，`spctl -a -t execute -vv` 是 `source=Notarized Developer ID`。关键步骤截图归档到 `tmp/2026-10-18-release-followups/T4/screenshots/`

不做：

- 不做增量更新、beta 通道、设置窗口里的更新开关，不改 Bundle ID
- 不把 Sparkle 通用化到 skill 里。等 T4 签收后另派
- 不动 `feat/svg-preview` 分支

怎么做：

- 先读必读，再动手；每完成一块就 `make build` / `make test`
- 实机验收前先 `wake-screen`，按 `DESKTOP_APP_TESTING.md` 和 `kb/docs/ui-acceptance.md` 操作；改 `config.json` 前备份、结束后恢复并 diff
- `gapless-paste-svg` 的 Debug 实例挡住验收时可以退出它（见决定表）。验收结束后退出所有自己启动的 GaplessPaste，删掉临时目录里的 app，清理 Sparkle 下载缓存（`~/Library/Caches/com.reorx.gaplesspaste/` 下 Sparkle 的目录）
- 发版失败按 `kb/docs/release.md` 的失败处理：还没生成 Release 就删 tag，在修复后的提交上重打；Release 已生成就发 `v0.2.1`。本任务只授权 v0.2.0，以及失败时的一次补发
- context 用到 60% 以上还没进入实机验收时，停下写总结交回，由协调者另派验收

完成标准：上面四项验证的证据（命令、关键输出、截图路径）都在总结里；本仓库的提交已推送，`v0.2.0` 已发布；新加的 secret 和本机密钥备份的位置写进总结。

## 共同约束

- 只做自己的任务，做完不开始下一个，不改本文件
- 只 `git add` 自己改的文件，提交前看一遍 `git status`。要改的文件里已有别人未提交的改动时不要改，写进总结
- 不开辅助 tab
- env 文件只能通过 `envops` 操作（读用 `envops show` 看打码的值），不能 cat、grep 或用读文件工具打开 `~/Sync/apple-developer/secrets.env`；Makefile 或脚本里 `source` 它而不打印内容可以。任何命令都不要把密钥、私钥、p8、p12 的内容打到终端或日志里
- bash 里中文全角标点紧跟变量（`$tap：`）会被当成变量名的一部分，一律写 `${var}`
- 除本任务写明的以外，不改 `~/.claude/skills/` 下的文件、`~/Code/homebrew-tap/` 和 `~/Sync/apple-developer/`。skill 的脚本或文档有问题，写进总结的「交给协调者」
- 对外可见的动作只限本文写明的。不改仓库设置
- 本仓库已公开：写进本仓库的文件（代码、注释、文档、提交信息）不提私有仓库的名字和路径
- 协调者负责的文件：本文、`kb/next-up.md`、`kb/known-issues.md`、`~/.claude/skills/macos-app-release/`（T4 之后的通用化另派）、tap 的 README、`~/Sync/apple-developer/AGENTS.md`。需要登记的写进「交给协调者」
- 临时文件和证据放 `~/Code/gapless-paste/tmp/2026-10-18-release-followups/<任务编号>/`

## 交付物

- 提交（代码和文档同一个提交）
- 总结写到 `~/Code/gapless-paste/tmp/2026-10-18-release-followups/<任务编号>-summary.md`，包括：做了什么、自己做的决定、验证证据（命令和关键输出）、未验证项、交给协调者
- tab 里最后一条回复：提交 hash、是否已推送、总结路径

## 状态区（只有协调者改）

审阅基线（已审完的最后一个提交）：feishu-lite `88ad5d3`、mdnotate `7d451d8`、homebrew-tap `a3a1e0b`；skill 文档已由协调者更新到「已接入项目」表、homebrew.md 迁移步骤、troubleshooting 的 dmg 重复签名一条

| 任务 | 状态 | agent / tab | 结果提交 | 备注 |
|---|---|---|---|---|
| T1 | 已签收 | `rel-feishu-key` / tab `w3Z:t4` | feishu-lite `88ad5d3`（未推送） | deploy key id 166777169；旧 secret 已删；真实推送待下一次发版 |
| T2 | 已签收 | `rel-mdnotate-key` / tab `w3Z:t5` | mdnotate `7d451d8`（已推送） | deploy key id 166777200；旧 secret 已删；旧 PAT 待用户网页吊销；真实推送待下一次发版 |
| T3 | 已签收 | （不入库） / tab `w3Z:t6` | 不入库 | 见 tmp 里的总结 |
| T5 | 已签收 | `rel-debug-team` / tab `w3Z:t7`（pane `w3Z:p8`） | 本仓库 `ea1edb6`；skill 仓库提交（未推送） | 13 个脚本测试通过；两份 Local.xcconfig 为 `YU3FMV36N2`；Debug 构建签名为付费 Team |
| T4 | 进行中 | `rel-sparkle` / tab `w3Z:t8`（pane `w3Z:p9`） | | 监视器 bd9a2pucp |
