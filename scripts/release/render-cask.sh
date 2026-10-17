#!/bin/bash
# 按已发布的 dmg 生成 reorx/homebrew-tap 的 Casks/gapless-paste.rb，输出到 stdout。
# 纯渲染：不联网、不改仓库；CI 的 homebrew job 负责下载核验、提交推送。
# 用法：render-cask.sh <version> <sha256> [<asset-id>]
#   给 asset-id 即私有仓库模式：网页下载地址对私有仓库带 token 也是 404，只能走
#   GitHub API 的 asset 地址 + Authorization header（重定向到预签名地址后 brew 自动丢掉 header）。
#   token 取 brew 自带的 GitHub::API.credentials：HOMEBREW_GITHUB_API_TOKEN → `gh auth token` → 钥匙串，
#   装过 gh 并登录的机器零配置可装。不给 asset-id 就是普通的版本化 URL；本仓库已公开，CI 不传它。
set -euo pipefail

CASK_TOKEN=gapless-paste
APP_NAME=GaplessPaste
REPO=reorx/gapless-paste
BUNDLE_ID=com.reorx.gaplesspaste
DESC="Menu bar tool to send clipboard images, files and text to SSH hosts"
MIN_MACOS=sonoma   # 与 project.yml 的 deploymentTarget（14.0）一致

version=${1:?usage: render-cask.sh VERSION SHA256 [ASSET_ID]}
sha256=${2:?usage: render-cask.sh VERSION SHA256 [ASSET_ID]}
asset_id=${3:-}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid version: $version" >&2; exit 1; }
[[ "$sha256" =~ ^[a-f0-9]{64}$ ]] || { echo "invalid sha256: $sha256" >&2; exit 1; }
[[ -z "$asset_id" || "$asset_id" =~ ^[0-9]+$ ]] || { echo "invalid asset id: $asset_id" >&2; exit 1; }

if [[ -n "$asset_id" ]]; then
    url_stanza=$(cat <<RUBY
  # 私有仓库：经 GitHub API 带 token 下载（gh auth login 或 HOMEBREW_GITHUB_API_TOKEN）
  url "https://api.github.com/repos/$REPO/releases/assets/$asset_id",
      header: [
        "Accept: application/octet-stream",
        "Authorization: Bearer #{GitHub::API.credentials}",
      ]
RUBY
)
else
    url_stanza="  url \"https://github.com/$REPO/releases/download/v#{version}/$APP_NAME-#{version}.dmg\""
fi

cat <<RUBY
cask "$CASK_TOKEN" do
  version "$version"
  sha256 "$sha256"

$url_stanza
  name "$APP_NAME"
  desc "$DESC"
  homepage "https://github.com/$REPO"

  depends_on macos: :$MIN_MACOS

  app "$APP_NAME.app"

  uninstall quit: "$BUNDLE_ID"

  zap trash: [
    "~/Library/Application Support/$APP_NAME",
    "~/Library/Caches/$APP_NAME",
    "~/Library/Logs/$APP_NAME",
    "~/Library/Preferences/$BUNDLE_ID.plist",
  ]
end
RUBY
