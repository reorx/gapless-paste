---
created: 2026-10-17
tags: [release, signing, notarization, homebrew, ci]
---

# 发布

> 写给要发新版本、排查发布失败、或在新机器上本地出包的人。这套方案的通用版（换项目照做）是 devblocks 的 `macos-app-release` skill；Apple 凭据的权威说明在 `~/Sync/apple-developer/AGENTS.md`。

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
1. 跑 Core 单测
2. 临时 keychain 导入 Developer ID Application 证书
3. `make build-release`：Universal（arm64 + x86_64）Release 构建，签名设置来自 `Config/Release.xcconfig`；末尾 `scripts/release/verify-app.sh` 自查签名身份、hardened runtime、时间戳、无 `get-task-allow`、双架构
4. `make notarize-app dmg notarize`，公证两轮：
   - app 打 zip 公证，票据钉进 app。Homebrew 安装的是从 dmg 里拷出来的 app，只钉 dmg 的话装好的 app 没票据，离线首次启动会被 Gatekeeper 拦（v0.1.0 就是这样，`syspolicy_check distribution` 判 Fatal）
   - 用已带票据的 app 打 dmg → 签 dmg → 公证 → staple → 终验：挂载后对 app 评估要求 `source=Notarized Developer ID`，且 app 自带票据
5. staple 之后算 `SHA256SUMS`，上传 artifact，在本仓库创建 Release（安装说明 + 自动生成的变更列表）

**homebrew**（ubuntu，只在 tag 触发时跑）
1. 从刚发布的 Release 下载 dmg 与 `SHA256SUMS` 并核验
2. 仓库是私有的，取 dmg 的 asset id，`scripts/release/render-cask.sh` 生成 `Casks/gapless-paste.rb`
3. 拒绝降级（tap 里已有更高版本就失败），用 deploy key 推到 `reorx/homebrew-tap`

`workflow_dispatch` 手动触发只跑 release job 到 artifact 为止（版本 0.0.0），不发 Release、不动 tap，用来验证链路。

## 私有仓库的 cask

私有仓库的 Release 资源，网页下载地址（`github.com/…/releases/download/…`）带 token 也是 404，只能走 API：`api.github.com/repos/reorx/gapless-paste/releases/assets/<id>` + `Accept: application/octet-stream` + `Authorization`，API 302 到预签名地址，brew 跨 host 重定向时自动丢掉 header。

cask 里的 token 取自 brew 自带的 `GitHub::API.credentials`：`HOMEBREW_GITHUB_API_TOKEN` → `gh auth token` → 钥匙串。装了 gh 并登录（且有本仓库权限）的机器零配置可装。副作用：`brew info --json --cask gapless-paste` 的输出里能看到这个 token，只在本机可见。

asset id 每次上传都不同，所以 cask 由 CI 每版重新渲染，不要手改。仓库将来公开的话，homebrew job 检测到 `PUBLIC` 会自动改为普通的版本化下载地址。

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

全部由 skill 脚本一次配好（可重复执行，deploy key 会轮换）：

```sh
~/Code/devblocks/macos-app-release/scripts/setup-secrets.sh --repo reorx/gapless-paste
```

## 本地出包

```sh
make build-release     # Release 构建 + 自查（DEVELOPMENT_TEAM 从 secrets.env 读）
make notarize-app      # 公证 app 并钉票据
make dmg               # → dist/GaplessPaste-<version>.dmg
make notarize          # 签 dmg + 公证 + staple + 终验
make release-local     # 以上四步连跑，不上传、不改 tap（本机约 1 分钟）
```

需要本机钥匙串里有 Developer ID Application 证书和 `~/Sync/apple-developer/secrets.env`。

## 失败了怎么办

- **只有 homebrew job 失败**（deploy key 失效、tap 冲突）：修好后在 Actions 页面 Re-run failed jobs。它只读已发布的 Release，不会重新签名公证
- **release job 失败**：看日志里的步骤。公证被拒时脚本会自动打印 `notarytool log`。修好后删掉 tag 重打：`git push --delete origin vX.Y.Z && git tag -d vX.Y.Z`，前提是 Release 还没建出来
- **staple 报 Error 68 / network connection was lost**：从 Apple CloudKit 取票据时的网络抖动，`notarize.sh` 已重试 5 次；仍失败就 Re-run failed jobs
- Release 已发布后发现问题，发新版本，不要替换已发布的 dmg：tap 里的 sha256 和 asset id 都绑定旧文件

## 相关文件

- `.github/workflows/release.yml`
- `scripts/release/`：`verify-app.sh`、`make-dmg.sh`、`notarize.sh`、`render-cask.sh`、`release-notes.sh`
- `Config/Release.xcconfig`：Developer ID、`--timestamp`、`CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`（缺它公证必拒）
- `Makefile`：`build-release` / `notarize-app` / `dmg` / `notarize` / `release-local`
