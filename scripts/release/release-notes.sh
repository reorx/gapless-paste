#!/bin/bash
# GitHub Release 正文开头的安装说明（CI 用 --notes 传入，gh 会把自动生成的变更列表接在后面）
set -euo pipefail

cat <<'MD'
## 安装

```sh
brew install --cask reorx/tap/gapless-paste
```

Homebrew 7 默认只加载信任过的第三方 tap，提示无法加载 cask 时先运行 `brew trust --tap reorx/tap`。也可以直接下载下方的 dmg，把 GaplessPaste 拖进「应用程序」。

适用于 macOS 14 及以上，Apple Silicon 与 Intel 通用；已使用 Developer ID 签名并经 Apple 公证。
MD
