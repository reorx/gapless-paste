#!/bin/bash
# 公证前自查 Release 产物，任何一项不满足都会被 Apple 拒绝或在用户机器上出问题：
# Developer ID 签名、hardened runtime、安全时间戳、无 get-task-allow、Universal（arm64 + x86_64）。
# 用法：verify-app.sh <path/to/App.app>
# REQUIRE_UNIVERSAL=0 时跳过架构检查
set -euo pipefail

app=${1:?usage: verify-app.sh APP}
fail() { echo "✗ $*" >&2; exit 1; }

codesign --verify --deep --strict "$app" || fail "codesign --verify 未通过"

while IFS= read -r -d '' code; do
    codesign --verify --strict "$code" || fail "嵌套签名无效：$code"
    info=$(codesign -dvv "$code" 2>&1)
    grep -q '^Authority=Developer ID Application' <<<"$info" || fail "不是 Developer ID Application 签名：$code"
    grep -qE '^CodeDirectory .*flags=.*runtime' <<<"$info" || fail "未开启 hardened runtime：$code"
    grep -q '^Timestamp=' <<<"$info" || fail "签名缺安全时间戳：$code"
    entitlements=$(codesign -d --entitlements - --xml "$code" 2>/dev/null || true)
    if grep -q 'get-task-allow' <<<"$entitlements"; then
        fail "含 get-task-allow：$code"
    fi
    echo "✓ Developer ID；runtime；timestamp：$code"
done < <("$(dirname "$0")/list-code.sh" "$app")

exe="$app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
archs=$(lipo -archs "$exe")
if [[ "${REQUIRE_UNIVERSAL:-1}" == 1 ]]; then
    [[ " $archs " == *" arm64 "* && " $archs " == *" x86_64 "* ]] || fail "不是 Universal 二进制：$archs"
fi

echo "✓ $(grep -m1 '^Authority=Developer ID Application' <<<"$info")；runtime；timestamp；archs: $archs"
