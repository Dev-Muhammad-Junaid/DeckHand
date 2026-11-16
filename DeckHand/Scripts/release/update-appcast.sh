#!/usr/bin/env bash
#
# Step 5: add this release to website/public/mac/appcast.xml.
#
#   ./update-appcast.sh                 # stable channel
#   CHANNEL=beta ./update-appcast.sh    # only apps opted into "beta" see it
#
# Needs sparkle-signature.txt from sign-update.sh. Release notes, if present,
# come from website/public/mac/notes/<version>.html and are linked from the
# update alert; write that file before running this (RELEASING.md §2.3).
#
# Re-running for the same build replaces its entry, so a bad signature can be
# fixed by signing again and re-running. Older entries stay, so anyone on any
# older build still finds the newest one.

set -euo pipefail
source "$(dirname "$0")/config.sh"
[[ -f "$SIGNATURE_FILE" ]] || die "$SIGNATURE_FILE not found. Run sign-update.sh first."

min_system="$(awk '/^  DeckHandMac:/{t=1} t && /MACOSX_DEPLOYMENT_TARGET:/{gsub(/"/,"",$2); print $2; exit}' "$APP_PROJECT_DIR/project.yml")"
notes_file="$RELEASE_NOTES_DIR/$VERSION.html"
notes_url=""
if [[ -f "$notes_file" ]]; then
    notes_url="$SITE_BASE_URL/mac/notes/$VERSION.html"
else
    warn "No release notes at $notes_file; the update alert will show none."
fi

mkdir -p "$(dirname "$APPCAST_PATH")"
/usr/bin/env python3 - "$APPCAST_PATH" <<PY
import sys, re, html, email.utils, pathlib

path = pathlib.Path(sys.argv[1])
attrs = pathlib.Path("""$SIGNATURE_FILE""").read_text().strip()
sig = re.search(r'sparkle:edSignature="([^"]+)"', attrs).group(1)
length = re.search(r'length="(\d+)"', attrs).group(1)
version = "$VERSION"
build = "$BUILD_NUMBER"
channel = "${CHANNEL:-}"
notes_url = "$notes_url"
min_system = "$min_system"
url = "$DMG_URL"

header = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Pixel Hand for Mac</title>
    <link>$SITE_BASE_URL/mac/appcast.xml</link>
    <description>Updates for Pixel Hand on the Mac.</description>
    <language>en</language>
"""
footer = """  </channel>
</rss>
"""

lines = [
    "    <item>",
    f"      <title>Version {html.escape(version)}</title>",
    f"      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>",
    f"      <sparkle:version>{build}</sparkle:version>",
    f"      <sparkle:shortVersionString>{html.escape(version)}</sparkle:shortVersionString>",
    f"      <sparkle:minimumSystemVersion>{min_system}</sparkle:minimumSystemVersion>",
]
if channel:
    lines.append(f"      <sparkle:channel>{html.escape(channel)}</sparkle:channel>")
if notes_url:
    lines.append(f"      <sparkle:releaseNotesLink>{html.escape(notes_url)}</sparkle:releaseNotesLink>")
lines += [
    f'      <enclosure url="{html.escape(url)}" length="{length}" type="application/octet-stream" sparkle:edSignature="{sig}" />',
    "    </item>",
]
new_item = "\n".join(lines) + "\n"

items = []
if path.exists():
    existing = path.read_text()
    items = re.findall(r"    <item>.*?</item>\n", existing, flags=re.S)
    # Drop an earlier entry for this same build (a re-run).
    items = [i for i in items if f"<sparkle:version>{build}</sparkle:version>" not in i]

def build_of(item):
    m = re.search(r"<sparkle:version>(\d+)</sparkle:version>", item)
    return int(m.group(1)) if m else 0

items.append(new_item)
items.sort(key=build_of, reverse=True)   # newest first
path.write_text(header + "".join(items) + footer)
print(f"appcast: {len(items)} item(s), newest build {build_of(items[0])}")
PY

xmllint --noout "$APPCAST_PATH" 2>/dev/null || warn "xmllint not available or appcast isn't well-formed; check $APPCAST_PATH"
log "Updated $APPCAST_PATH"
