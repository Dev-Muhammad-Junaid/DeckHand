#!/usr/bin/env bash
#
# Notarizes and staples one item: the exported .app or the .dmg.
#
#   ./notarize.sh app      # the exported Pixel Hand.app (zipped for upload)
#   ./notarize.sh dmg      # the DMG from make-dmg.sh
#   ./notarize.sh <path>   # anything else notarytool accepts
#
# Credentials come from a keychain profile, never a file in the repo:
#   xcrun notarytool store-credentials pixelhand-notary \
#       --apple-id <you@example.com> --team-id DD5AWPLT2V   # asks for an app-specific password
# or, with an App Store Connect API key:
#   xcrun notarytool store-credentials pixelhand-notary \
#       --key AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer-uuid>
# (RELEASING.md §1.2). NOTARY_PROFILE picks another profile name.

set -euo pipefail
source "$(dirname "$0")/config.sh"
require_macos

case "${1:-}" in
    app) target="$APP_PATH" ;;
    dmg) target="$DMG_PATH" ;;
    "")  die "usage: $0 app|dmg|<path>" ;;
    *)   target="$1" ;;
esac
[[ -e "$target" ]] || die "$target not found"

keychain_args=()
[[ -n "$NOTARY_KEYCHAIN" ]] && keychain_args=(--keychain "$NOTARY_KEYCHAIN")

upload="$target"
if [[ "$target" == *.app ]]; then
    upload="$RELEASE_DIR/$(basename "$target" .app)-notarize.zip"
    rm -f "$upload"
    ditto -c -k --sequesterRsrc --keepParent "$target" "$upload"
fi

log "Submitting $(basename "$upload") to Apple's notary service (usually 1–10 minutes)"
result_json="$RELEASE_DIR/notary-$(basename "$upload").json"
set +e
xcrun notarytool submit "$upload" \
    --keychain-profile "$NOTARY_PROFILE" \
    ${keychain_args[@]+"${keychain_args[@]}"} \
    --wait --timeout 45m \
    --output-format json > "$result_json"
submit_status=$?
set -e
cat "$result_json"; echo

submission_id="$(/usr/bin/plutil -extract id raw -o - "$result_json" 2>/dev/null || true)"
status="$(/usr/bin/plutil -extract status raw -o - "$result_json" 2>/dev/null || true)"
if [[ $submit_status -ne 0 || "$status" != "Accepted" ]]; then
    if [[ -n "$submission_id" ]]; then
        warn "Notarization status: ${status:-unknown}. Apple's log:"
        xcrun notarytool log "$submission_id" \
            --keychain-profile "$NOTARY_PROFILE" \
            ${keychain_args[@]+"${keychain_args[@]}"} || true
    fi
    die "Notarization failed for $target"
fi
[[ "$upload" != "$target" ]] && rm -f "$upload"

log "Stapling"
xcrun stapler staple "$target"
xcrun stapler validate "$target"

log "Gatekeeper check"
if [[ "$target" == *.dmg ]]; then
    spctl --assess --type open --context context:primary-signature -vv "$target"
else
    spctl --assess --type execute -vv "$target"
fi
log "Notarized and stapled: $target"
