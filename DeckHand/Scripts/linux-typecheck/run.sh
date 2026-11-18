#!/usr/bin/env bash
#
# Type-checks Mac and iOS app files that depend only on PixelHandCore and a
# few app services, against Stubs.swift, on Linux. It catches wrong message
# labels, missing cases and Swift 6 concurrency errors in the files listed
# below; it does not replace the Mac build (AppKit, SwiftUI and Loom are
# stubbed, not real).
#
#   DeckHand/Scripts/linux-typecheck/run.sh            # the default list
#   DeckHand/Scripts/linux-typecheck/run.sh FILE...    # extra files too
#
# Files that use SwiftUI, UIKit or most of AppKit can't be checked here.
# A file whose dependencies aren't stubbed fails with "cannot find X in
# scope": add a stub with the real signature, or leave the file out.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
app="$(cd "$here/../.." && pwd)"
work="$here/Work"
rm -rf "$work"
mkdir -p "$work"
cp "$here/Stubs.swift" "$work/"

files=(
  "$app/DeckHandMac/ControlReceiver.swift"
  "$app"/DeckHandMac/Handlers/*.swift
  "$app/DeckHandMac/Mirror/MirrorSubscriber.swift"
  "$app/DeckHandiOS/TrackpadSender.swift"
  "$app/DeckHandiOS/Mirror/MirrorStreamReceiver.swift"
  "$app/Shared/LoomConnectionHandle+ControlMessage.swift"
  "$@"
)
for file in "${files[@]}"; do
  sed -E '/^import (AppKit|LoomKit|Loom|CoreGraphics|os|QuartzCore|SwiftUI|UIKit)$/d' "$file" > "$work/$(basename "$file")"
done

cd "$here"
swift build 2>&1 | grep -E "error:|warning:|Build complete" | sort -u
