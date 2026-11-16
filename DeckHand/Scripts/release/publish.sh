#!/usr/bin/env bash
#
# Step 6: upload the DMG to R2 and point the website at it.
#
#   ./publish.sh
#
# 1. Uploads PixelHand-<version>.dmg to the R2 bucket (wrangler, logged in
#    with `npx wrangler login`, or CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID
#    in CI).
# 2. Checks the public URL serves the same bytes.
# 3. Points /download/mac at it in website/public/_redirects (stable releases
#    only; CHANNEL=beta leaves the download button alone).
#
# The appcast and _redirects go live when the website deploys, i.e. when you
# commit and push them to the Pages production branch. Upload first, deploy
# second, so the appcast never names a DMG that isn't there yet.

set -euo pipefail
source "$(dirname "$0")/config.sh"
[[ -f "$DMG_PATH" ]] || die "$DMG_PATH not found"
require_tool npx "Install Node.js (brew install node) for wrangler."
require_tool curl ""

key="$R2_PREFIX/$DMG_NAME"
log "Uploading $DMG_NAME to r2://$R2_BUCKET/$key"
npx --yes wrangler@4 r2 object put "$R2_BUCKET/$key" \
    --file "$DMG_PATH" \
    --content-type application/x-apple-diskimage \
    --cache-control "public, max-age=31536000, immutable" \
    --remote

log "Checking $DMG_URL"
local_size=$(stat -f%z "$DMG_PATH")
remote_size=$(curl -fsSIL "$DMG_URL" | awk 'tolower($1)=="content-length:"{v=$2} END{gsub(/\r/,"",v); print v}')
[[ "$remote_size" == "$local_size" ]] \
    || die "Public URL returned length '$remote_size', expected $local_size. Check the bucket's custom domain (RELEASING.md §1.4)."

if [[ -z "${CHANNEL:-}" ]]; then
    log "Pointing /download/mac at $DMG_NAME"
    touch "$REDIRECTS_PATH"
    tmp="$(mktemp)"
    grep -v '^/download/mac ' "$REDIRECTS_PATH" > "$tmp" || true
    printf '/download/mac %s 302\n' "$DMG_URL" >> "$tmp"
    mv "$tmp" "$REDIRECTS_PATH"
fi

cat <<MSG

Uploaded. Now deploy the website:

  git add website/public/mac website/public/_redirects
  git commit -m "Release Pixel Hand for Mac $VERSION ($BUILD_NUMBER)"
  git push        # to the Pages production branch

Then check:
  curl -s $SITE_BASE_URL/mac/appcast.xml | head -20
  curl -sI $SITE_BASE_URL/download/mac | grep -i location
MSG
