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
cp "$here/Stubs.swift" "$here/StoreKitStubs.swift" "$work/"

files=(
  "$app/DeckHandMac/ControlReceiver.swift"
  "$app"/DeckHandMac/Handlers/*.swift
  "$app/DeckHandMac/Network/HostLinkMonitor.swift"
  "$app/DeckHandMac/Network/LinkObservation+Loom.swift"
  "$app/DeckHandMac/Network/RemoteAccessGate.swift"
  "$app/DeckHandMac/LockGate.swift"
  "$app/DeckHandMac/UI/MenuBarActivity.swift"
  "$app/DeckHandMac/Deck/MacShortcutRunner.swift"
  "$app/DeckHandMac/Input/DragGuard.swift"
  "$app/DeckHandMac/Input/TypingQueue.swift"
  "$app/DeckHandMac/Mirror/MirrorSubscriber.swift"
  "$app/DeckHandMac/Audio/MirrorAudioService.swift"
  "$app/DeckHandMac/Audio/MirrorAudioSubscriber.swift"
  "$app/DeckHandMac/DeviceAuthorizationManager.swift"
  "$app/DeckHandMac/DeckHandHandshakeTrustProvider.swift"
  "$app/DeckHandMac/Pairing/PairedDeviceStore.swift"
  "$app/Shared/Pairing+Loom.swift"
  "$app/DeckHandiOS/Pairing/PairedMacsStore.swift"
  "$app/DeckHandiOS/Network/RemoteHostsStore.swift"
  "$app/DeckHandiOS/Network/RemoteConnect.swift"
  "$app/DeckHandiOS/Network/RemoteHostTester.swift"
  "$app/DeckHandiOS/TrackpadSender.swift"
  "$app/DeckHandiOS/Deck/DeckStore.swift"
  "$app/DeckHandiOS/Deck/DeckSurfaceModel.swift"
  "$app/DeckHandiOS/Deck/DeckSuggestionsModel.swift"
  "$app"/DeckHandiOS/Assist/*.swift
  "$app/DeckHandiOS/ShortcutStore.swift"
  "$app/DeckHandiOS/Clipboard/RemoteClipboard.swift"
  "$app/DeckHandiOS/Mirror/MirrorStreamReceiver.swift"
  "$app/DeckHandiOS/Audio/MirrorAudioReceiver.swift"
  "$app/DeckHandiOS/Store/SubscriptionStore.swift"
  "$app/Shared/LoomConnectionHandle+ControlMessage.swift"
  "$@"
)
for file in "${files[@]}"; do
  # StoreKit is stubbed inside this module, so `StoreKit.Transaction` (the
  # app names it by module where SwiftUI makes it ambiguous) loses its prefix.
  sed -E -e '/^import (AppKit|Combine|LoomKit|Loom|CoreGraphics|IOKit|os|QuartzCore|StoreKit|SwiftUI|UIKit|UserNotifications)$/d' \
    -e 's/\bStoreKit\.(Transaction|Product|VerificationResult|AppStore)\b/\1/g' \
    "$file" > "$work/$(basename "$file")"
done

cd "$here"
swift build 2>&1 | grep -E "error:|warning:|Build complete" | sort -u
