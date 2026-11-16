#!/usr/bin/env bash
#
# Step 2: put the exported app in a signed DMG with an Applications link.
#
#   ./make-dmg.sh
#
# Uses create-dmg (brew install create-dmg) when installed, for the window
# layout; otherwise plain hdiutil. Either way the result is a compressed,
# Developer ID–signed DMG at DeckHand/build/release/<v>-<b>/PixelHand-<v>.dmg.
#
# Run notarize.sh on the app first (release.sh does), so the copy inside the
# DMG carries its own stapled ticket and opens offline.

set -euo pipefail
source "$(dirname "$0")/config.sh"
require_macos
[[ -d "$APP_PATH" ]] || die "$APP_PATH not found. Run archive.sh first."

rm -f "$DMG_PATH"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
# ditto keeps the signature, extended attributes and the stapled ticket.
ditto "$APP_PATH" "$staging/$APP_NAME.app"

background="$RELEASE_SCRIPTS_DIR/dmg-background.png"

if command -v create-dmg >/dev/null 2>&1; then
    log "Building the DMG with create-dmg"
    bg_args=()
    [[ -f "$background" ]] && bg_args=(--background "$background")
    # create-dmg exits 2 when it couldn't prettify the window (no Finder
    # session, e.g. over SSH); the DMG is still fine.
    set +e
    create-dmg \
        --volname "$DMG_VOLUME_NAME" \
        --window-size 560 340 \
        --icon-size 112 \
        --icon "$APP_NAME.app" 150 170 \
        --app-drop-link 410 170 \
        --hide-extension "$APP_NAME.app" \
        ${bg_args[@]+"${bg_args[@]}"} \
        "$DMG_PATH" "$staging"
    status=$?
    set -e
    [[ $status -eq 0 || $status -eq 2 ]] || die "create-dmg failed ($status)"
else
    log "Building the DMG with hdiutil (brew install create-dmg for a laid-out window)"
    ln -s /Applications "$staging/Applications"
    hdiutil create \
        -volname "$DMG_VOLUME_NAME" \
        -srcfolder "$staging" \
        -fs HFS+ \
        -format ULFO \
        -ov "$DMG_PATH"
fi
[[ -f "$DMG_PATH" ]] || die "No DMG produced"

log "Signing the DMG"
codesign --force --sign "$DEVELOPER_ID_IDENTITY" --timestamp "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

size=$(stat -f%z "$DMG_PATH")
log "Built $DMG_PATH ($((size / 1024 / 1024)) MB)"
if (( size > 25 * 1024 * 1024 )); then
    echo "    Over Cloudflare Pages' 25 MiB per-file limit; it goes to R2 (publish.sh) as planned."
fi
