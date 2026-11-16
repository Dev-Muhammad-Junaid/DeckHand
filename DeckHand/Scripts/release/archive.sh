#!/usr/bin/env bash
#
# Step 1: archive the Mac app and export it signed with Developer ID.
#
#   ./archive.sh
#
# Output: DeckHand/build/release/<version>-<build>/export/Pixel Hand.app
#
# Signing is automatic (project.yml), so Xcode needs to be signed in to an
# account on team DD5AWPLT2V that can use the Developer ID certificate, or
# APP_STORE_CONNECT_KEY_PATH / _KEY_ID / _ISSUER_ID must be set (CI).

set -euo pipefail
source "$(dirname "$0")/config.sh"
require_macos
require_tool xcodebuild "Install Xcode."
require_tool xcodegen "brew install xcodegen"

mkdir -p "$RELEASE_DIR"
log "Pixel Hand $VERSION ($BUILD_NUMBER) → $RELEASE_DIR"

# Optional App Store Connect API key, for -allowProvisioningUpdates without
# an Xcode account (CI). Locally, Xcode's signed-in account is used.
auth_args=()
if [[ -n "${APP_STORE_CONNECT_KEY_PATH:-}" ]]; then
    auth_args=(
        -authenticationKeyPath "$APP_STORE_CONNECT_KEY_PATH"
        -authenticationKeyID "${APP_STORE_CONNECT_KEY_ID:?}"
        -authenticationKeyIssuerID "${APP_STORE_CONNECT_ISSUER_ID:?}"
    )
fi

log "Generating the Xcode project"
(cd "$APP_PROJECT_DIR" && xcodegen generate --quiet)

log "Archiving $SCHEME (Release)"
rm -rf "$ARCHIVE_PATH"
xcodebuild \
    -project "$APP_PROJECT_DIR/DeckHand.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
    -allowProvisioningUpdates \
    ${auth_args[@]+"${auth_args[@]}"} \
    archive \
    | { if command -v xcbeautify >/dev/null; then xcbeautify; else cat; fi; }
[[ -d "$ARCHIVE_PATH" ]] || die "Archive failed"

log "Exporting with Developer ID"
export_options="$RELEASE_DIR/ExportOptions.plist"
cat > "$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
PLIST
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$export_options" \
    -allowProvisioningUpdates \
    ${auth_args[@]+"${auth_args[@]}"}
[[ -d "$APP_PATH" ]] || die "Export failed: $APP_PATH missing"

log "Checking the exported app"
plist="$APP_PATH/Contents/Info.plist"
got_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
got_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
got_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
feed="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist" 2>/dev/null || true)"
edkey="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist" 2>/dev/null || true)"
[[ "$got_id" == "$BUNDLE_ID" ]] || die "bundle ID is $got_id, expected $BUNDLE_ID"
[[ "$got_build" == "$BUILD_NUMBER" && "$got_version" == "$VERSION" ]] \
    || die "app says $got_version ($got_build), project.yml says $VERSION ($BUILD_NUMBER)"
[[ "$feed" == https://* ]] || die "SUFeedURL missing or not https: '$feed'"
[[ -n "$edkey" ]] || die "SUPublicEDKey is empty. Set SPARKLE_PUBLIC_ED_KEY in project.yml (RELEASING.md §1.3)."

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
sig="$(codesign -dvv "$APP_PATH" 2>&1)"
grep -q "Authority=Developer ID Application" <<<"$sig" || die "not signed with Developer ID:\n$sig"
grep -q "TeamIdentifier=$TEAM_ID" <<<"$sig" || die "wrong team:\n$sig"
grep -q "flags=.*runtime" <<<"$sig" || die "hardened runtime is off"
archs="$(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")"
[[ "$archs" == *arm64* && "$archs" == *x86_64* ]] \
    || warn "Not a universal binary ($archs); the website says Apple silicon and Intel."
# Sparkle's helpers must be signed by us too, or notarization rejects them.
sparkle_fw="$APP_PATH/Contents/Frameworks/Sparkle.framework"
[[ -d "$sparkle_fw" ]] || die "Sparkle.framework is not embedded"
codesign -dvv "$sparkle_fw/Versions/B/Autoupdate" 2>&1 | grep -q "TeamIdentifier=$TEAM_ID" \
    || die "Sparkle's Autoupdate isn't signed with team $TEAM_ID"
# No sandbox, matching the existing Mac setup (Sparkle needs no XPC services then).
if codesign -d --entitlements - --xml "$APP_PATH" 2>/dev/null | grep -q "com.apple.security.app-sandbox"; then
    warn "The app is sandboxed; Sparkle then needs its installer XPC services (SUEnableInstallerLauncherService)."
fi

log "Exported $APP_PATH ($got_version, build $got_build)"
