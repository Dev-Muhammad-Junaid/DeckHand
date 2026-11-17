# shellcheck shell=bash
#
# Shared settings for the Mac release scripts. Sourced, not run.
#
# Every value can be overridden from the environment, e.g.
#   NOTARY_PROFILE=other-profile ./DeckHand/Scripts/release/release.sh
#
# Nothing secret lives here: the notary credentials are in the login keychain
# (a `notarytool store-credentials` profile), the Sparkle private key is in the
# login keychain (`generate_keys`), and the Cloudflare login is wrangler's.
# See DeckHand/Release/RELEASING.md.

set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────────
RELEASE_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$RELEASE_SCRIPTS_DIR/../../.." && pwd)"
APP_PROJECT_DIR="$REPO_ROOT/DeckHand"            # project.yml lives here
WEBSITE_PUBLIC="$REPO_ROOT/website/public"
BUILD_ROOT="${BUILD_ROOT:-$APP_PROJECT_DIR/build/release}"
# SwiftPM checkouts for the release build. A fixed path, so the Sparkle tools
# (sign_update, generate_keys) are always at $SPARKLE_BIN.
SOURCE_PACKAGES_DIR="${SOURCE_PACKAGES_DIR:-$BUILD_ROOT/SourcePackages}"
SPARKLE_BIN="${SPARKLE_BIN:-$SOURCE_PACKAGES_DIR/artifacts/sparkle/Sparkle/bin}"

# ── App identity ───────────────────────────────────────────────────────
SCHEME="${SCHEME:-DeckHandMac}"
APP_NAME="${APP_NAME:-Pixel Hand}"                 # PRODUCT_NAME → "Pixel Hand.app"
BUNDLE_ID="${BUNDLE_ID:-com.widgetsflow.pixelhand.mac}"
TEAM_ID="${TEAM_ID:-DD5AWPLT2V}"
# The certificate the DMG is signed with (export signs the app itself).
DEVELOPER_ID_IDENTITY="${DEVELOPER_ID_IDENTITY:-Developer ID Application: Mega Creations LLC ($TEAM_ID)}"
# File-name stem for the DMG: PixelHand-<version>.dmg
DMG_STEM="${DMG_STEM:-PixelHand}"
DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-Pixel Hand}"

# ── Notarization ───────────────────────────────────────────────────────
# Name of the `xcrun notarytool store-credentials` profile in the keychain.
NOTARY_PROFILE="${NOTARY_PROFILE:-pixelhand-notary}"
# Optional: a keychain other than the default search list (used by CI).
NOTARY_KEYCHAIN="${NOTARY_KEYCHAIN:-}"

# ── Hosting ────────────────────────────────────────────────────────────
# Public base URL the DMGs are served from (an R2 bucket's custom domain;
# Cloudflare Pages caps a single file at 25 MiB, so DMGs don't go in Pages).
DOWNLOAD_BASE_URL="${DOWNLOAD_BASE_URL:-https://downloads.pixelhand.app/mac}"
# R2 bucket and key prefix that DOWNLOAD_BASE_URL maps to.
R2_BUCKET="${R2_BUCKET:-pixelhand-downloads}"
R2_PREFIX="${R2_PREFIX:-mac}"
# Where the appcast lives on the website; must match SPARKLE_FEED_URL in
# project.yml (Info.plist SUFeedURL).
APPCAST_PATH="${APPCAST_PATH:-$WEBSITE_PUBLIC/mac/appcast.xml}"
REDIRECTS_PATH="${REDIRECTS_PATH:-$WEBSITE_PUBLIC/_redirects}"
# Release notes pages are published next to the appcast:
#   website/public/mac/notes/<version>.html
RELEASE_NOTES_DIR="${RELEASE_NOTES_DIR:-$WEBSITE_PUBLIC/mac/notes}"
SITE_BASE_URL="${SITE_BASE_URL:-https://pixelhand.app}"

# ── Helpers ────────────────────────────────────────────────────────────
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

require_macos() {
    [[ "$(uname -s)" == "Darwin" ]] || die "This script runs on macOS only."
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || die "$1 not found. $2"
}

# Reads MARKETING_VERSION / CURRENT_PROJECT_VERSION of the Mac target from
# project.yml (both apps carry the same numbers; bump-version.sh keeps them
# in step).
project_marketing_version() {
    awk '/^  DeckHandMac:/{t=1} t && /MARKETING_VERSION:/{gsub(/"/,"",$2); print $2; exit}' "$APP_PROJECT_DIR/project.yml"
}
project_build_number() {
    awk '/^  DeckHandMac:/{t=1} t && /CURRENT_PROJECT_VERSION:/{gsub(/"/,"",$2); print $2; exit}' "$APP_PROJECT_DIR/project.yml"
}

VERSION="${VERSION:-$(project_marketing_version)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(project_build_number)}"
[[ -n "$VERSION" && -n "$BUILD_NUMBER" ]] || die "Couldn't read the version from project.yml"

RELEASE_DIR="$BUILD_ROOT/$VERSION-$BUILD_NUMBER"
ARCHIVE_PATH="$RELEASE_DIR/$SCHEME.xcarchive"
EXPORT_DIR="$RELEASE_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
DMG_NAME="$DMG_STEM-$VERSION.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
DMG_URL="$DOWNLOAD_BASE_URL/$DMG_NAME"
SIGNATURE_FILE="$RELEASE_DIR/sparkle-signature.txt"   # sign_update output
