#!/bin/bash
# 发布数据与签名校验的行为测试；不接触真实钥匙串或网络。
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/GaplessPaste.app/Contents" "$work/bin"
app="$work/GaplessPaste.app"
plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 0.2.0' "$plist" >/dev/null
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 42' "$plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 14.0' "$plist"
printf 'final stapled dmg bytes' > "$work/GaplessPaste-0.2.0.dmg"
cat > "$work/bin/sign_update" <<'SH'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$SIGN_LOG"
if [[ " $* " == *' --verify '* ]]; then exit 0; fi
printf 'test-signature\n'
SH
chmod +x "$work/bin/sign_update"
export SIGN_UPDATE="$work/bin/sign_update" SIGN_LOG="$work/sign.log"
if [[ "${1:-all}" != verify ]]; then
scripts/release/render-appcast.sh "$app" "$work/GaplessPaste-0.2.0.dmg" "$work/appcast.xml"
xml="$work/appcast.xml"
xmllint --noout "$xml"
expect_xml() {
    [[ "$(xmllint --xpath "$1" "$xml")" == "$2" ]] || { echo "FAIL: $1" >&2; exit 1; }
}
expect_xml 'count(/rss/channel/item)' 1
expect_xml 'string(/rss/channel/item/*[local-name()="version"])' 42
expect_xml 'string(/rss/channel/item/*[local-name()="shortVersionString"])' 0.2.0
expect_xml 'string(/rss/channel/item/*[local-name()="minimumSystemVersion"])' 14.0
expect_xml 'string(/rss/channel/item/enclosure/@url)' 'https://github.com/reorx/gapless-paste/releases/download/v0.2.0/GaplessPaste-0.2.0.dmg'
expect_xml 'string(/rss/channel/item/enclosure/@length)' "$(stat -f%z "$work/GaplessPaste-0.2.0.dmg")"
expect_xml 'string(/rss/channel/item/enclosure/@*[local-name()="edSignature"])' test-signature
expect_xml 'boolean(/rss/channel/item/description)' true
grep -q -- '--verify' "$SIGN_LOG"
echo 'PASS: appcast 使用 bundle 版本、最终 dmg 大小、版本化 URL、签名并自校验'

/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion invalid' "$plist"
if scripts/release/render-appcast.sh "$app" "$work/GaplessPaste-0.2.0.dmg" "$xml" >/dev/null 2>&1; then
    echo 'FAIL: 接受了非法构建号' >&2; exit 1
fi
echo 'PASS: 拒绝非法构建号'

scripts/release/render-cask.sh 0.2.0 "$(printf '%064d' 0)" > "$work/cask.rb"
grep -q '^  auto_updates true$' "$work/cask.rb"
echo 'PASS: cask 声明 auto_updates'
fi

# 只有外层 app 合格、嵌套代码不合格时，旧版 verify-app.sh 会错误通过。
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks/Helper.app/Contents/MacOS"
cp /usr/bin/true "$app/Contents/MacOS/GaplessPaste"
cp /usr/bin/true "$app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string GaplessPaste' "$plist"
cat > "$work/bin/codesign" <<'SH'
#!/bin/bash
if [[ " $* " == *' --verify '* ]]; then exit 0; fi
if [[ " $* " == *' --entitlements '* ]]; then exit 0; fi
if [[ "$*" == *Helper* ]]; then
    case "${BAD_NESTED:-}" in
        identity) echo 'Authority=Apple Development: Wrong' ;;
        *) echo 'Authority=Developer ID Application: Test' ;;
    esac
    [[ "${BAD_NESTED:-}" == runtime ]] || echo 'CodeDirectory flags=0x10000(runtime)'
    [[ "${BAD_NESTED:-}" == timestamp ]] || echo 'Timestamp=Oct 18, 2026'
else
    echo 'Authority=Developer ID Application: Test'
    echo 'CodeDirectory flags=0x10000(runtime)'
    echo 'Timestamp=Oct 18, 2026'
fi
SH
chmod +x "$work/bin/codesign"
export PATH="$work/bin:$PATH" REQUIRE_UNIVERSAL=0
for bad in identity runtime timestamp; do
    if BAD_NESTED="$bad" scripts/release/verify-app.sh "$app" > "$work/verify.log" 2>&1; then
        echo "FAIL: 未拒绝嵌套代码缺失 $bad" >&2; exit 1
    fi
done
scripts/release/verify-app.sh "$app" > "$work/verify.log" 2>&1
echo 'PASS: 逐一拒绝嵌套代码错误身份、缺 runtime、缺 timestamp，接受合格签名'
