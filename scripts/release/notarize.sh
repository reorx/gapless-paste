#!/bin/bash
# 签名 dmg → 提交公证 → staple → 终验。顺序不可换：签名会改 cdhash，staple 之后再签会作废票据。
# 用法：notarize.sh <dmg>
#
# 凭据（env）：ASC_PRIVATE_KEY_PATH / ASC_KEY_ID / ASC_ISSUER_ID
#   本地：make notarize 从 ~/Sync/apple-developer/secrets.env 加载
#   CI：release.yml 把 ASC_PRIVATE_KEY（p8 的 base64）解码成临时文件
# 不用 notarytool store-credentials 的 keychain profile：非交互环境下会拒绝访问且报 "not found"。
# 可选：SIGN_IDENTITY（默认 "Developer ID Application"）、NOTARY_TIMEOUT（默认 30m）
set -euo pipefail

dmg=${1:?usage: notarize.sh DMG}
: "${ASC_PRIVATE_KEY_PATH:?}" "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}"
auth=(--key "$ASC_PRIVATE_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")

codesign --sign "${SIGN_IDENTITY:-Developer ID Application}" --timestamp "$dmg"
codesign --verify --strict "$dmg"

# --wait 阻塞到出结果。新账号首单可能要 45 分钟，之后通常 2~5 分钟
result=$(xcrun notarytool submit "$dmg" "${auth[@]}" --wait --timeout "${NOTARY_TIMEOUT:-30m}" --output-format json) || true
echo "$result"
if [[ "$(jq -r '.status // empty' <<<"$result")" != "Accepted" ]]; then
    id=$(jq -r '.id // empty' <<<"$result")
    [[ -n "$id" ]] && xcrun notarytool log "$id" "${auth[@]}" || true
    echo "✗ 公证未通过" >&2
    exit 1
fi

xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"

# 用户视角的终验：挂载后对里面的 app 做 Gatekeeper 评估，期望 source=Notarized Developer ID
mnt=$(mktemp -d)
hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$dmg" >/dev/null
trap 'hdiutil detach "$mnt" >/dev/null 2>&1 || true; rmdir "$mnt" 2>/dev/null || true' EXIT
assess=$(spctl --assess --type execute --verbose=2 "$mnt"/*.app 2>&1) || true
echo "$assess"
grep -q 'source=Notarized Developer ID' <<<"$assess" || { echo "✗ dmg 内的 app 未通过 Gatekeeper" >&2; exit 1; }
echo "✓ 已公证并 staple：$dmg"
