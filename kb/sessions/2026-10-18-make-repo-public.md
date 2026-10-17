---
created: 2026-10-18
tags:
  - release
  - homebrew
  - open-source
  - privacy-audit
---

# 仓库公开：私密信息审查，cask、Release 正文与文档切到公开口径，补 README 和 LICENSE

## 概要

公开仓库前审查了当前 101 个文件、全部 31 个提交的 diff（含已删除文件和本地 `feat/svg-preview` 分支）、两个 Release 的正文与附件、5 次 release CI 日志和图标 PNG 元数据。没有任何真实凭据：secrets 只以变量名出现，`Config/Local.xcconfig` 从未入库，CI 日志里 secrets 全是 `***`。剩下的是个人环境信息（Team ID、本机关锁屏 + 开远程登录、私有项目名与本地路径、作者邮箱），用户决定都不动。用户把仓库改为 public 后，处理私有模式的遗留：重跑 v0.1.1 那次运行的 homebrew job，它按当前可见性把 tap 里的 cask 重渲染成普通版本化下载地址（同版本不算降级，不用发新版）；`release-notes.sh` 去掉「本仓库是私有的」，改为 `brew trust` 提示，并用 `tmp/fix_release_notes.sh` 同步改了 v0.1.0 / v0.1.1 已发布的正文；release.md、AGENTS.md、脚本注释、tap README 去掉私有口径；新增中文 README、MIT LICENSE，设置仓库 description。验证：无凭据 curl 下载 dmg 得 200 且 sha256 与 cask 一致，`env -u HOMEBREW_GITHUB_API_TOKEN brew fetch --cask --force reorx/tap/gapless-paste` 通过。

## 修改的文件

- `README.md`（新增）— 用途、两条回传通道、功能、安装（brew / dmg / `brew trust`）、使用前提（免密 ssh、macOS 远端剪贴板）、配置格式、从源码构建
- `LICENSE`（新增）— MIT，`Copyright (c) 2026 Xiao Meng`，与 reorx 其他公开仓库（如 httpstat）一致
- `scripts/release/release-notes.sh` — 私有仓库安装说明换成 `brew trust --tap reorx/tap` 提示
- `kb/docs/release.md` — 「私有仓库的 cask」改为「cask 的下载地址」：现为公开地址；私有模式作为可见性回退保留说明；改可见性后重跑 homebrew job 即可
- `scripts/release/render-cask.sh` — 头注释注明本仓库已公开、CI 不传 asset-id
- `.github/workflows/release.yml` — homebrew job 的注释去掉「私有仓库 macOS 分钟 10 倍计费」
- `AGENTS.md` — 文档索引加 README，release.md 条目去掉「私有仓库 cask」
- 仓库外：`reorx/homebrew-tap` 的 `Casks/gapless-paste.rb`（CI bot 重渲染）与 README（删私有 cask 一节）；GitHub 上 v0.1.0 / v0.1.1 的 Release 正文、仓库 description

## 注意事项

- Team ID 和 Developer ID 证书上的真实姓名本来就嵌在每个签名二进制里（`codesign -dv` 可见），dmg 一公开就公开了，从文档里删它们没有实际意义
- 只改当前文件，历史里仍能翻到；要从历史里清掉早于 tag 的内容，得 filter-repo 并重打 tag，Release 也会受牵连
- 公开前要看的不只是代码：仓库公开后 Actions 历史日志、Release 正文与附件都会跟着公开。workflow 只由 tag push 和 workflow_dispatch 触发，没有 `pull_request` / `pull_request_target`，fork 的 PR 拿不到 secrets
- `gh release edit --notes-file` 只改正文，不动 Latest 标记

## 遗留问题

无

## 相关文档

- [发布](../docs/release.md) — 本次更新 cask 下载地址一节
- [发布自动化 session](./2026-10-17-release-automation.md) — 私有模式 cask 与 homebrew job 可见性检测的来历
