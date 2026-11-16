#!/usr/bin/env bash
#
# Step 4: EdDSA-sign the DMG for Sparkle.
#
#   ./sign-update.sh
#
# Writes the `sparkle:edSignature="…" length="…"` attributes to
# DeckHand/build/release/<v>-<b>/sparkle-signature.txt for update-appcast.sh.
#
# The private key is read from the login keychain, where `generate_keys`
# stored it (RELEASING.md §1.3). In CI, set SPARKLE_ED_PRIVATE_KEY to the
# base64 key `generate_keys -x` exported; it goes to a temporary file that
# is deleted on exit.
#
# Sign AFTER stapling: stapling changes the DMG's bytes, and Sparkle checks
# the signature against the exact file it downloads.

set -euo pipefail
source "$(dirname "$0")/config.sh"
require_macos
[[ -f "$DMG_PATH" ]] || die "$DMG_PATH not found. Run make-dmg.sh first."
sign_update="$SPARKLE_BIN/sign_update"
[[ -x "$sign_update" ]] || die "sign_update not found at $sign_update. Run archive.sh first (it resolves Sparkle into $SOURCE_PACKAGES_DIR), or set SPARKLE_BIN."

xcrun stapler validate -q "$DMG_PATH" || die "The DMG isn't stapled yet. Run notarize.sh dmg first."

key_args=()
if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
    key_file="$(mktemp)"
    trap 'rm -f "$key_file"' EXIT
    chmod 600 "$key_file"
    printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > "$key_file"
    key_args=(--ed-key-file "$key_file")
fi

log "Signing $DMG_NAME with Sparkle's EdDSA key"
attrs="$("$sign_update" ${key_args[@]+"${key_args[@]}"} "$DMG_PATH")"
[[ "$attrs" == *'sparkle:edSignature="'* && "$attrs" == *'length="'* ]] \
    || die "Unexpected sign_update output: $attrs"
printf '%s\n' "$attrs" > "$SIGNATURE_FILE"

# The signature must verify, and the key that made it must be the one the
# app ships with, or installed copies refuse the update.
signature="$(sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/' <<<"$attrs")"
"$sign_update" ${key_args[@]+"${key_args[@]}"} --verify "$DMG_PATH" "$signature" \
    || die "sign_update could not verify its own signature"
plist="$APP_PATH/Contents/Info.plist"
app_pubkey="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")"
if [[ -z "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
    keychain_pubkey="$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null || true)"
    [[ "$keychain_pubkey" == "$app_pubkey" ]] \
        || die "Keychain public key ($keychain_pubkey) differs from the app's SUPublicEDKey ($app_pubkey). Installed apps would refuse this update."
    log "Signing key matches the app's SUPublicEDKey"
else
    warn "CI key: can't compare it with SUPublicEDKey here; the update test in RELEASING.md §3 does."
fi
echo "$attrs"
