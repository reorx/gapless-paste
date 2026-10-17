---
created: 2026-10-17
tags:
  - release
  - signing
  - notarization
  - homebrew
  - ci
---

# 发布自动化：tag 触发签名公证、发布到本仓库 Release、自动更新 Homebrew cask

## 概要

原来的 `build.yml` 只出无签名 zip，从没跑过。本次参照 vocalflow-mac（xcodebuild 签名公证链路）、mdnotate（同仓库 Release + tap 自动 bump）、feishu-lite（独立 cask job + 防降级），接成全自动发布：push `vX.Y.Z` tag → Universal Release 构建 → Developer ID 签名 → 公证 + staple → 发布到本仓库 Release → homebrew job 渲染 cask 推到 `reorx/homebrew-tap`。版本号只来自 tag。签名公证的脚本本地与 CI 共用，`make release-local` 在本机一分钟出已公证的 dmg。secrets 由脚本从 `~/Sync/apple-developer/secrets.env` 全自动配置，tap 写权限用一把只对 tap 可写的 deploy key。本仓库是私有的，Release 资源的网页下载地址带 token 也是 404（实测），cask 改走 GitHub API 的 asset 地址 + brew 自带的 `GitHub::API.credentials`（`gh auth token` 兜底，零配置）。v0.1.0 发布后以用户身份从 tap 安装检查，发现 Homebrew 装的 app 没有票据（只钉了 dmg），离线首次启动会被拦，于是改成 app 和 dmg 两轮公证；v0.1.1 的 CI 两次在 stapler 访问 Apple CloudKit 时断连（Error 68，一次在 staple、一次在 validate，本机从未出现），于是所有 stapler 调用统一退避重试并去掉多余的 validate，删 tag 后在修复提交上重打。最终 v0.1.1 的两个 job 一次通过，tap 由 bot 更新到 0.1.1；从 `reorx/tap` 安装后 app 带 quarantine、Gatekeeper 为 `source=Notarized Developer ID`、`syspolicy_check distribution` 全部通过。整套方案同时沉淀为 devblocks 的 `macos-app-release` skill，供其他项目照做。

## 修改的文件

- `.github/workflows/release.yml`（替换 `build.yml`）— release job：单测、临时 keychain 导入证书、`make build-release`、`make notarize-app dmg notarize`、`SHA256SUMS`、artifact、`gh release create --notes --generate-notes`、清理凭据；homebrew job（ubuntu）：下载已发布 dmg 核验、私有仓库取 asset id、渲染 cask、`ruby -c`、防降级、deploy key 推 tap。workflow_dispatch 只出 artifact
- `scripts/release/verify-app.sh` — 构建后自查 Developer ID、runtime、timestamp、无 get-task-allow、Universal
- `scripts/release/make-dmg.sh` — ditto + /Applications 软链 + UDZO，`dist/GaplessPaste-<version>.dmg`
- `scripts/release/notarize.sh` — 接受 .app（zip 提交、钉票据进 app）或 .dmg（签名、提交、staple、挂载后终验 app 的 Gatekeeper 与票据）；未 Accepted 自动打印 `notarytool log`；所有 stapler 调用退避重试 5 次
- `scripts/release/render-cask.sh` — 生成 cask；给 asset id 即私有模式
- `scripts/release/release-notes.sh` — Release 正文开头的安装说明
- `Makefile` — `build-release` / `notarize-app` / `dmg` / `notarize` / `release-local`；凭据从 secrets.env 加载，CI 用同名 env
- `Config/Release.xcconfig` — 补 `--timestamp`、`CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`
- `project.yml` / `GaplessPaste/Info.plist` — `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` 及引用
- `.gitignore` — `dist/`
- `kb/docs/release.md`（新增）、`AGENTS.md` — 发布文档与索引、命令、签名、CI 小节
- 仓库外：`reorx/homebrew-tap` 的 README（列出全部 cask、trust 与私有 cask 说明），`Casks/gapless-paste.rb` 由 CI 创建；GitHub 上配置了 7 个 secrets 与 tap 的 deploy key `release: reorx/gapless-paste`；新建 `~/Code/devblocks/macos-app-release/`

## 注意事项

- 只钉 dmg 不够：Homebrew 安装的是拷出来的 app。`syspolicy_check distribution <app>` 能直接看出票据缺失，Gatekeeper 的 `spctl` 在线时照样 accepted，看不出问题
- 私有仓库的 Release 资源：网页地址带 token 也 404，API asset 地址 + `Accept: application/octet-stream` 才行；brew 跨 host 重定向时自动丢 header
- Homebrew 7：第三方 tap 要 `brew trust`；cask 必须在 tap 里，不能 `brew fetch ./x.rb`；求值 cask 时屏蔽 `HOMEBREW_*` 里像密钥的变量，只有 `HOMEBREW_GITHUB_API_TOKEN` 豁免，自定义变量的占位符会让 curl 禁止重定向
- 验证安装时另一个 checkout（`gapless-paste-svg`）的 Debug 实例正在跑，同 bundle ID。cask 的 `uninstall quit` 会把它也退出，所以装到 `--appdir` 临时目录，验完手工删 app 和 Caskroom 记录，没走 `brew uninstall`
- bash 里中文全角标点紧跟变量（`$tap：`）会被当成变量名的一部分，报 unbound variable，本次踩了 4 次。一律写 `${var}`
- `Config/Local.xcconfig`（Debug 用，不入库）里的 Team 还是已弃用的免费 Team `QFW98B7VB4`。Debug 构建照常成功，没有改它；Release 已不依赖它

## 遗留问题

- brew 安装的 app 只做了 Gatekeeper 评估和 `syspolicy_check`，没有真实启动（当时另一个同 bundle ID 实例在跑）。下次本机没有其他实例时 `brew install --cask reorx/tap/gapless-paste` 后启动一次即可，属于低风险项，未登记 known-issues
- `Config/Local.xcconfig` 的 Debug Team 可换成 `YU3FMV36N2`（会让 Debug 签名身份变一次）。app 目前不用 TCC 能力，不急

## 相关文档

- [发布](../docs/release.md) — 本次新建
- `~/Sync/apple-developer/AGENTS.md`、`macos-signing-guide.md` — 凭据与签名的通用依据
- `~/Code/devblocks/macos-app-release/SKILL.md` — 本次沉淀的通用 skill
