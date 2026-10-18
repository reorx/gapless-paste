#!/bin/bash
# 对最终已 staple 的 dmg 签名，生成单项 appcast 并用同一密钥自校验。
# SPARKLE_PRIVATE_KEY_FILE 未设置时使用钥匙串 account gapless-paste。
set -euo pipefail
app=${1:?usage: render-appcast.sh APP DMG OUTPUT}
dmg=${2:?usage: render-appcast.sh APP DMG OUTPUT}
output=${3:?usage: render-appcast.sh APP DMG OUTPUT}
plist="$app/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build" =~ ^[0-9]+$ && "$minimum" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
    || { echo '非法版本号、构建号或最低系统版本' >&2; exit 1; }
[[ "$(basename "$dmg")" == "GaplessPaste-$version.dmg" ]] || { echo 'dmg 名称与 app 版本不一致' >&2; exit 1; }
sign_update=${SIGN_UPDATE:-$("$(dirname "$0")/sparkle-tools.sh")/sign_update}
key_args=(--account gapless-paste)
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then key_args=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE"); fi
signature=$("$sign_update" "${key_args[@]}" -p "$dmg")
length=$(stat -f%z "$dmg")
"$sign_update" "${key_args[@]}" --verify "$dmg" "$signature" >&2
cat > "$output" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>GaplessPaste</title>
    <link>https://github.com/reorx/gapless-paste</link>
    <description>GaplessPaste 正式版更新</description>
    <item>
      <title>GaplessPaste $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <description><![CDATA[
        <h2>GaplessPaste $version</h2>
        <p>支持在应用内检查更新。正式版每天检查一次，安装前会征求你的同意。</p>
        <p>更新包适用于 macOS 14 及以上，Apple Silicon 与 Intel 通用，已通过 Apple 公证。</p>
        <p><a href="https://github.com/reorx/gapless-paste/releases/tag/v$version">查看完整更新记录</a></p>
      ]]></description>
      <enclosure url="https://github.com/reorx/gapless-paste/releases/download/v$version/GaplessPaste-$version.dmg"
        sparkle:edSignature="$signature" length="$length" type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML
xmllint --noout "$output"
echo "✓ appcast：$version ($build)，$length bytes → $output" >&2
