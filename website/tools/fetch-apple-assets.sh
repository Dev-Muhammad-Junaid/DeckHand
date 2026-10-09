#!/bin/bash
# Downloads Apple's official device bezels and the App Store artwork for the
# apps shown in the website mockups. Run on a Mac from the repository root:
#
#   ./website/tools/fetch-apple-assets.sh
#
# Bezels come from Apple Design Resources
# (https://developer.apple.com/design/resources/#product-bezels), which Apple
# licenses for showing your app in marketing. App icons come from the App
# Store's public lookup API.
#
# Afterwards, fit the bezels to the site:
#   python3 website/tools/fit_bezels.py --ipad <landscape iPad png> --iphone <portrait iPhone png>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BEZELS="$ROOT/website/brand/apple-bezels"
ICONS="$ROOT/website/public/assets/apps"
mkdir -p "$BEZELS" "$ICONS"

# ---------- Bezels ----------
CDN="https://devimages-cdn.apple.com/design/resources/download"
for dmg in "Bezel-iPad-Pro-(M5).dmg" "Bezel-iPhone-17.dmg"; do
  name="${dmg%.dmg}"
  dest="$BEZELS/$name"
  if [ -d "$dest" ]; then echo "✓ $name already downloaded"; continue; fi
  tmp="$(mktemp -d)"
  echo "↓ $dmg"
  curl -fL --progress-bar "$CDN/$dmg" -o "$tmp/bezel.dmg"
  hdiutil attach -nobrowse -readonly -mountpoint "$tmp/mnt" "$tmp/bezel.dmg" >/dev/null
  mkdir -p "$dest"
  find "$tmp/mnt" -iname '*.png' -exec cp {} "$dest/" \;
  hdiutil detach "$tmp/mnt" >/dev/null
  rm -rf "$tmp"
  echo "  $(ls "$dest" | wc -l | tr -d ' ') PNGs in $dest"
done

# ---------- App icons ----------
# slug:App Store ID (Mac App Store apps, so the artwork is the macOS icon)
APPS=(
  "xcode:497799835"
  "keynote:409183694"
  "pages:409201541"
  "numbers:409203825"
  "final-cut-pro:424389933"
  "logic-pro:634148309"
  "pixelmator-pro:1289583905"
  "slack:803453959"
)
for entry in "${APPS[@]}"; do
  slug="${entry%%:*}"; id="${entry##*:}"
  out="$ICONS/$slug.png"
  url="$(curl -fsS "https://itunes.apple.com/lookup?id=$id" \
    | python3 -c 'import sys,json; r=json.load(sys.stdin)["results"]; print(r[0]["artworkUrl512"] if r else "")')"
  if [ -z "$url" ]; then echo "✗ $slug ($id): not found"; continue; fi
  # Ask for a PNG so the macOS icon keeps its transparent margin.
  url="${url%/*}/512x512bb.png"
  curl -fsSL "$url" -o "$out"
  sips -Z 256 "$out" >/dev/null 2>&1 || true
  echo "✓ $slug"
done

echo
echo "Next: pick a landscape iPad and a portrait iPhone PNG from $BEZELS and run"
echo "  python3 website/tools/fit_bezels.py --ipad <file> --iphone <file>"
