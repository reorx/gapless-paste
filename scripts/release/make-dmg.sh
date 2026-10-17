#!/bin/bash
# 把 .app 打成拖拽安装的 dmg：<dist>/<Name>-<version>.dmg，内含 app 与 /Applications 软链。
# 版本读产物 Info.plist（CI 构建时已按 git tag 覆盖）。dmg 的签名与公证在 notarize.sh。
# 用法：make-dmg.sh <path/to/App.app> <dist-dir>   成功后 stdout 只输出 dmg 路径
set -euo pipefail

app=${1:?usage: make-dmg.sh APP DIST}
dist=${2:?usage: make-dmg.sh APP DIST}
[[ -d "$app" ]] || { echo "app 不存在：${app}（先 make build-release）" >&2; exit 1; }

name=$(basename "$app" .app)
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
# ditto 保留符号链接与扩展属性；cp -R 在个别 framework 上会破坏签名
ditto "$app" "$staging/$name.app"
ln -s /Applications "$staging/Applications"

mkdir -p "$dist"
dmg="$dist/$name-$version.dmg"
rm -f "$dmg"
hdiutil create -volname "$name" -srcfolder "$staging" -ov -format UDZO "$dmg" >&2
echo "$dmg"
