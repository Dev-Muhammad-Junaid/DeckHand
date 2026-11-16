#!/usr/bin/env bash
#
# Runs a whole Mac release, up to (not including) the upload:
#
#   archive → notarize app → DMG → notarize DMG → Sparkle sign → appcast
#
#   ./DeckHand/Scripts/release/release.sh
#   CHANNEL=beta ./DeckHand/Scripts/release/release.sh
#
# Then test the DMG (RELEASING.md §3) and run publish.sh.
#
# Each step is its own script, so a failed step can be re-run alone.

set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/config.sh"
require_macos

log "Releasing Pixel Hand for Mac $VERSION ($BUILD_NUMBER)${CHANNEL:+ on channel $CHANNEL}"
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain -- DeckHand Sources Package.swift Package.resolved)" ]]; then
    warn "Uncommitted changes in the app or Loom; the build won't match a commit."
fi

"$here/archive.sh"
"$here/notarize.sh" app
"$here/make-dmg.sh"
"$here/notarize.sh" dmg
"$here/sign-update.sh"
"$here/update-appcast.sh"

cat <<MSG

Built, notarized and signed:
  $DMG_PATH

Next:
  1. Install it on a clean Mac (or a new user account) and run the
     update test in RELEASING.md §3.
  2. ${here#"$REPO_ROOT"/}/publish.sh
MSG
