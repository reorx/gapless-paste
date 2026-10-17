#!/bin/bash
# GitHub Release 正文开头的安装说明（CI 用 --notes 传入，gh 会把自动生成的变更列表接在后面）
set -euo pipefail

cat <<'MD'
## 安装

```sh
brew install --cask reorx/tap/gapless-paste
```

本仓库是私有的：安装机器需要已 `gh auth login` 且有本仓库访问权限，或设置 `HOMEBREW_GITHUB_API_TOKEN`。也可以直接下载 dmg，把 GaplessPaste 拖进「应用程序」。

适用于 macOS 14 及以上，Apple Silicon 与 Intel 通用；已使用 Developer ID 签名并经 Apple 公证。
MD
