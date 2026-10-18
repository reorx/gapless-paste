---
created: 2026-10-17
updated: 2026-10-18
tags: [release, signing, notarization, homebrew, ci]
---

# 发布

> 写给要发新版本、排查发布失败、或在新机器上本地出包的人。通用发布流程见 `~/.claude/skills/macos-app-release/SKILL.md`；Apple 凭据的权威说明在 `~/Sync/apple-developer/AGENTS.md`。

用户安装：

```sh
brew install --cask reorx/tap/gapless-paste
```

## 发一个版本

在 master 上打 `vMAJOR.MINOR.PATCH` tag 并 push，其余全部由 CI 完成：

```sh
git tag v0.2.0
git push origin v0.2.0
```

版本号只来自 tag（`v0.2.0` → `CFBundleShortVersionString` 0.2.0），构建号取 CI 的 run number。`project.yml` 里的 `MARKETING_VERSION` 只是本地构建的占位，发版不用改它。

## CI 流程

`.github/workflows/release.yml` 有两个 job：

**release**（macos-15）
1. 跑 Core 单测和 `make test-release` 发布脚本行为测试
2. 临时 keychain 导入 Developer ID Application 证书
3. `make build-release`：Universal（arm64 + x86_64）Release 构建，签名设置来自 `Config/Release.xcconfig`；`sign-app.sh` 从内到外重签所有 Mach-O 和代码 bundle（包含 Sparkle 的 Autoupdate、Updater.app、XPC 服务），然后 `verify-app.sh` 对每个代码对象检查 Developer ID、hardened runtime、时间戳、无 `get-task-allow`，主程序还需双架构。不能只重签最外层 app：`xcodebuild build` 不会像 Archive 导出那样重签框架里的辅助程序
4. `make notarize-app dmg notarize`，公证两轮：
   - app 打 zip 公证，票据钉进 app。Homebrew 安装的是从 dmg 里拷出来的 app，只钉 dmg 的话装好的 app 没票据，离线首次启动会被 Gatekeeper 拦（v0.1.0 就是这样，`syspolicy_check distribution` 判 Fatal）
   - 用已带票据的 app 打 dmg → 签 dmg → 公证 → staple → 终验：挂载后对 app 评估要求 `source=Notarized Developer ID`，且 app 自带票据
5. staple 之后算 `SHA256SUMS`，`make appcast` 对最终 dmg 做 EdDSA 签名并自校验，生成单项 `appcast.xml`。dmg、SHA256SUMS、appcast 一起上传 artifact，在本仓库创建 Release（安装说明 + 自动生成的变更列表）

**homebrew**（ubuntu，只在 tag 触发时跑）
1. 从刚发布的 Release 下载 dmg 与 `SHA256SUMS` 并核验
2. `scripts/release/render-cask.sh` 生成 `Casks/gapless-paste.rb`，使用普通版本化下载地址并标记 `auto_updates true`
3. 拒绝降级（tap 里已有更高版本就失败），用 deploy key 推到 `reorx/homebrew-tap`

`workflow_dispatch` 手动触发只跑 release job 到 artifact 为止（版本 0.0.0），不发 Release、不动 tap，用来验证链路。

## cask 的下载地址

仓库 2026-10-18 起公开，cask 用 Release 的版本化地址 `github.com/reorx/gapless-paste/releases/download/v<版本>/GaplessPaste-<版本>.dmg`，安装不需要任何 GitHub 凭据。cask 由 CI 每版重新渲染，不要手改。

homebrew job 可独立重跑（`gh run rerun <run-id> --job <job-id>`），同版本不算降级。

Homebrew 7 默认只加载 trust 过的第三方 tap，新机器上先 `brew trust --tap reorx/tap`。

## secrets

| Secret | 内容 |
|---|---|
| `CERT_P12` | Developer ID Application 证书 + 私钥的 p12，base64 |
| `CERT_P12_PASSWORD` | p12 密码 |
| `APPLE_TEAM_ID` | Team ID |
| `ASC_PRIVATE_KEY` | App Store Connect API key（Developer 角色）p8，base64 |
| `ASC_KEY_ID` / `ASC_ISSUER_ID` | 上面那把 key 的 ID 与 Issuer |
| `TAP_DEPLOY_KEY` | `reorx/homebrew-tap` 上标题为 `release: reorx/gapless-paste` 的可写 deploy key 的私钥 |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle Ed25519 私钥（由下文的独立步骤配置） |

Apple 与 tap 凭据由 skill 脚本一次配好（可重复执行，deploy key 会轮换）：

```sh
bash ~/.claude/skills/macos-app-release/scripts/setup-secrets.sh --repo reorx/gapless-paste
```

## 本地出包

```sh
make build-release     # Release 构建 + 自查（DEVELOPMENT_TEAM 从 secrets.env 读）
make notarize-app      # 公证 app 并钉票据
make dmg               # → dist/GaplessPaste-<version>.dmg
make notarize          # 签 dmg + 公证 + staple + 终验
make appcast           # 对最终 dmg 签名，生成 dist/appcast.xml 并自校验
make release-local VERSION=0.2.0 BUILD_NUMBER=6 SPARKLE_PRIVATE_KEY_FILE="$HOME/Sync/apple-developer/sparkle/gapless-paste_ed25519.key"
# 上述步骤连跑，不上传、不改 tap；指定密钥文件可避免本机首次访问钥匙串的授权弹窗
```

需要本机钥匙串里有 Developer ID Application 证书和 `~/Sync/apple-developer/secrets.env`。

## Sparkle 应用内更新

Sparkle 2.10.0 以 SPM 精确版本依赖进入 app target，Core 不依赖它。Release 默认每天自动检查，安装由用户点击确认；`SUAllowsAutomaticUpdates=false` 禁止静默安装。Debug delegate 拒绝后台检查，只允许手动「检查更新…」，不改同 bundle ID 正式版的持久偏好。

feed 固定为 `https://github.com/reorx/gapless-paste/releases/latest/download/appcast.xml`。每版只保留当前一项；`sparkle:version` 取 app 的 `CFBundleVersion`（CI run number），展示版本取 `CFBundleShortVersionString`，最低系统取 `LSMinimumSystemVersion`。更新包沿用最终已公证、钉票据的 dmg，URL 固定到版本 tag。更新说明以内嵌 HTML 显示，并链接完整 Release 记录。无 delta、beta 通道。

`scripts/release/sparkle-tools.sh` 下载官方固定版本工具包并校验 SHA256。升级 Sparkle 时同时修改它与 `project.yml` 的版本和工具包校验和。`render-appcast.sh` 用 `sign_update -p` 签名，再用 `sign_update --verify <dmg> <signature>` 自校验，最后用 `xmllint` 解析 XML。**签名以后不能再改 dmg（包括 staple）**。

本机密钥保存在登录钥匙串 account `gapless-paste`，备份为 `~/Sync/apple-developer/sparkle/gapless-paste_ed25519.key`（权限 600）。公钥固定在 `project.yml` 的 `SUPublicEDKey`。用 skill 脚本配置 CI 的 Sparkle secret：备份文件或钥匙串里已有密钥时只复用，绝不重新生成或覆盖备份；只有两处都不存在时才生成。以下命令跳过 Apple 和 tap 凭据，仅配置 Sparkle：

```sh
bash ~/.claude/skills/macos-app-release/scripts/setup-secrets.sh \
  --repo reorx/gapless-paste --skip-apple --skip-tap --sparkle
```

CI 只把该 secret 写入 `$RUNNER_TEMP/sparkle-ed25519.key`（600 权限），签完立即删除，`if: always()` 的清理步骤再兜底。本地默认从钥匙串签名，也可通过 `SPARKLE_PRIVATE_KEY_FILE` 指定备份文件。不能打印或提交私钥；丢失会阻断既有安装的更新信任链，不能靠重新生成密钥恢复。更换签名身份或 EdDSA 密钥时按 [Sparkle 官方密钥轮换文档](https://sparkle-project.org/documentation/#rotating-signing-keys) 单独设计迁移，不能同时更换两者。

首次接入的实机验收用相同源码构建 0.1.9 / build 1、Developer ID 签名后放临时目录，从真实 feed 更新到 0.2.0；生产 v0.1.x 本身未内置 Sparkle，需要先经 dmg/Homebrew 升级一次。

## 失败了怎么办

- **只有 homebrew job 失败**（deploy key 失效、tap 冲突）：修好后在 Actions 页面 Re-run failed jobs。它只读已发布的 Release，不会重新签名公证
- **release job 失败**：看日志里的步骤。公证被拒时脚本会自动打印 `notarytool log`。修好后删掉 tag 重打：`git push --delete origin vX.Y.Z && git tag -d vX.Y.Z`，前提是 Release 还没建出来
- **stapler 报 Error 68 / network connection was lost**：stapler 访问 Apple CloudKit 时断连，GitHub 的 macOS runner 上常见（v0.1.1 前两次 CI 都是这样挂的），`notarize.sh` 的 stapler 调用已统一重试 5 次；仍失败就 Re-run failed jobs
- Release 已发布后发现问题，发新版本，不要替换已发布的 dmg：tap 里的 sha256 和 asset id 都绑定旧文件

## 相关文件

- `.github/workflows/release.yml`
- `scripts/release/`：`verify-app.sh`、`make-dmg.sh`、`notarize.sh`、`render-cask.sh`、`release-notes.sh`
- `Config/Release.xcconfig`：Developer ID、`--timestamp`、`CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`（缺它公证必拒）
- `Makefile`：`build-release` / `notarize-app` / `dmg` / `notarize` / `release-local`
