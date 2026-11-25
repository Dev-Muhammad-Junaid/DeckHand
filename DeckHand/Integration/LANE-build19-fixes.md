# Lane: build 19 fixes

Branch `claude/pixelhand-lane-build19-fixes`, from
`origin/claude/pixelhand-integration` at `8b1c250` (build 20 queued). It
fixes the 5 bugs in "Mac build results (build 19)" in `STATUS.md`.

Linux checks on this branch:
- `swift test --package-path DeckHand/Core`: **992 / 992 pass** (179
  suites; 22 new tests, so 970 before this lane).
- `DeckHand/Scripts/linux-typecheck/run.sh`: **Build complete**, no errors.
  Two new files are added to its list (`Mirror/CaptureFailure+Mac.swift`,
  `Network/LoomPeerSnapshot+Role.swift`). The stubs gained
  `LoomPeerAdvertisement.metadata` and `LoomPeerSnapshot.deviceType`.
- Loom (`swift test --scratch-path .build-local`) was not run. This lane
  changes no Loom code.

## 1. VQ-001 (P1): simulators on this Mac refused as "remote path (loopback)"

**Cause.** The Simulator dials the Mac's Bonjour-resolved Wi-Fi address
(`192.168.0.121`). The kernel carries that over `lo0`, from that same
address. `RemoteAccessPolicy.pathClass` returned `.remote` for a `.loopback`
link whose `remoteHost` was routable and not a loopback literal. An unpaired
simulator was therefore refused before the Allow prompt or the code.

**Fix** (`Core/Network/RemoteAccessPolicy.swift`, `DeckHandMac/Network/RemoteAccessGate.swift`).
`pathClass(link:remoteHost:ownAddresses:)` (and `isRemotePath`) take this
Mac's interface addresses. The order is now:
1. A loopback literal is `.sameMachine`.
2. One of the Mac's **own addresses** is `.sameMachine` on any link. This
   compares the address without zone, brackets, case or the `::ffff:`
   prefix. Link-local addresses never match, because another device can
   hold the same one. It is safe because replies to the Mac's own address
   never leave the Mac, so a handshake from elsewhere can't complete.
3. Any other overlay (Tailscale) address is `.remote`, whatever the link.
4. A **`.loopback` link** is `.sameMachine`, because only this Mac can put
   a packet on `lo0`.
5. Tunnel and cellular are `.remote`. Everything else is `.localNetwork`.

The gate reads `InterfaceAddressTable.current()` off the main actor for
each new connection and logs "on this Mac (loopback or its own address)".
`.sameMachine` still gets the usual Allow prompt and pairing code.

**Tests** (`RemoteAccessTests.swift`, `RemoteAdmissionTests`):
- a loopback link is the same machine, even from a routable address;
- an own address is the same machine on every link;
- link-local addresses are never treated as own addresses;
- other devices' overlay and VPN addresses stay remote, and LAN devices stay
  local;
- the exact build 19 case (`.loopback` link, `192.168.0.121`) gets
  `.askUser`.

Two old expectations encoded the bug and were changed: `.loopback` with
`203.0.113.9` → remote, and `.loopback` with `fe80::3%en0` → local network.

## 2. Floating screen tile covers the deck header on iPhone (P2)

**Cause.** Only the Pointer surface reported keep-out areas. On the Deck
tab the tile had no anchor and no keep-outs. Its home was the canvas's
top-trailing corner, on the header's counter, pin and Edit.

**Fix.**
- Core `MirrorTilePlacement.surfaceLayout(bounds:pad:clickStrip:caption:keyboard:deckHeader:)`
  combines the pointer keep-outs with the deck header.
- Without a pad, the tile's home anchor is the canvas **below** the header.
  The tile rests 12 pt under it, like the pad's corner, and every drag,
  pinch or remembered layout is clamped clear of it (8 pt gap).
- With a pad (iPad, deck in the right column), the pad stays the anchor and
  the header is avoided too.
- `DeckSurface` reports the header row (normal and edit mode) as
  `.deckHeader`, at the deck's full width (`.frame(maxWidth: .infinity)`,
  centred as before), so the tile doesn't move when the counter appears or
  the header goes to two rows at AX3.

**Tests** (`MirrorTileDeckTests.swift`):
- home is under the header and clear of it, at Standard and at AX3 (two
  rows);
- the build 19 spot is moved clear;
- a big tile narrows until it fits clear of the header;
- iPad with both the pad and the deck: the pad stays the anchor;
- the Pointer-only layout is unchanged.

## 3. AX3 Mac pill hyphenates the name (P2, VQ-065)

**Cause.** At the Huge band the pill gave one `Text` two lines. iOS
hyphenated "Muhammad’s" when it didn't fit the line.

**Fix.**
- Core `ShellHeaderPlan.pillNameCandidates(_:lines:)` lists word splits,
  best first: the whole name, then the first line with as many words as fit
  (all but one, down to one).
- `MacPill` draws each line as its own one-line `Text`, which never
  hyphenates, inside `ViewThatFits(in: .horizontal)`. The last split is the
  fallback, and each of its lines truncates at the tail: "Muhammad’s /
  MacBook Pro", or "Muhammad’s / MacBook P…".
- A one-word name, or the Standard and Large bands, use one tail-truncated
  line as before. The accessibility label is unchanged (the full name).

**Tests** (`ShellChromePlanTests.swift`):
- splits are only between words, in order, never ending in "-";
- the fallback keeps the first word whole;
- one-word names, extra spaces, and hyphens inside a word ("Jean-Luc’s").

## 4. Mirror failure alert shows a raw error (P2)

**Cause.** `MirrorStreamService` sent `"Live mirror unavailable: \(error.localizedDescription)"`.
With the Mac locked, ScreenCaptureKit lists no display, so the alert read
"…Pixel_Hand.ScreenCaptureService.CaptureError error 2.". `CaptureHandler`
also sent `localizedDescription` for its catch-all and window-list paths.

**Fix.**
- Core `CaptureFailure`: one sentence-case message per cause, worded for the
  screenshot or the live screen. The causes are Mac locked, Screen
  Recording off, no display, window closed, capture failed, encode failed,
  stream couldn't open, stream stopped, and window list failed.
  `.macLocked` is `LockPolicy.lockedErrorMessage`, so the remote recognises
  it. `reported(_:macLocked:)` turns any failure into `.macLocked` while the
  Mac is locked.
- Mac: `CaptureFailure+Mac.swift` maps `ScreenCaptureService.CaptureError`
  and ScreenCaptureKit's "user declined" (-3801) to a cause and checks
  `MacLockMonitor`. `CaptureHandler` (screenshot and window list) and
  `MirrorStreamService` (open, start, stream died) now send those
  sentences. The raw error goes to the log only. The mirror-audio notice
  drops a raw reason too.
- iOS: when the remote already knows the Mac is locked (`macLockState`, the
  same state the lock banner uses), a mirror or screenshot error shows the
  locked copy, whatever an older Mac sent.
  `CaptureSheetChrome.errorMessage` passes every message through
  `UserFacingError.sentence(from:)`. That function drops an older Mac's
  "Live mirror unavailable:"-style prefix. Anything that reads as a system
  error ("operation couldn’t be completed", `Error Domain=`, "error 2",
  `code=…`, a qualified type name like `Pixel_Hand.X.Y`) is replaced by our
  own copy.
- Alert titles are sentence case: "Mac is locked", "Live screen
  unavailable", "Screenshot failed".
- The connect-failure alerts in the picker and the Mac switcher use
  `UserFacingError.connectFailure(macName:detail:)`, so they show no raw
  errors either.

**Tests** (`CaptureFailureTests.swift`, `CaptureSheetChromeTests.swift`):
- the exact build 19 string with the Mac locked gets the locked title and
  body;
- without the lock, it gets "The Mac couldn’t start the live screen. Try
  again.";
- raw errors are detected, and our own sentences (including "code 4821
  0934") pass unchanged;
- every `CaptureFailure` message is clean and sentence case;
- titles are sentence case;
- the connect alerts are covered.

## 5. The picker lists another iPad as a Mac (P3)

**Cause.** Both apps advertise the same Bonjour service. The picker's
`@LoomQuery(.peers)` listed every Pixel Hand device, so the iPad mini saw
the iPad Pro (build 18) as a Mac.

**Fix.**
- Core `PeerRole` (`mac` / `remote`) and a new TXT key `ph-role`.
  `PixelHandProtocol.advertisementMetadata(role:)` is passed by
  `MacHostApp` (`.mac`) and `DeckHandApp` (`.remote`).
- `PeerRole.isListedAsMac(metadata:deviceType:)` decides who is listed.
  Either signal can rule a peer out, and neither can rule an iOS device in:
  - Loom's advertised `deviceType` iPad, iPhone or Vision is never listed;
  - a `ph-role` other than `mac` is never listed;
  - a peer with no role and a type of `mac`, `unknown` or none is listed (a
    build 19 Mac, or a Mac seen through a source with no type).
- iOS: `LoomPeerSnapshot.isPixelHandMac` / `.macsOnly`. `PeerPickerView` and
  `ContentRootView` filter the query, and `MacSwitcher.update(peers:)`
  filters again.
- `PROTOCOL.md` documents `ph-role`. It is additive, so there is no version
  bump: an older peer without it falls back to the device type, which
  filters build 18 and 19 iPads too.

**Tests** (`PeerRoleTests.swift`):
- the advertisement carries both keys, and the role parses;
- build 18 iPads and iPhones (no role) are not listed;
- remotes with the role are not listed on any type;
- Macs with or without the role are listed;
- a `mac` role on an iPad type is still not listed, and an unknown role is
  not listed.

## Re-check on the Mac

1. Build all targets (Mac app, iOS app with both extensions, simulator
   `build-for-testing` with `PixelHandUITests`). Run the Core, Loom and
   `DeckHandTests` suites.
2. **VQ-001, pairing an unpaired simulator by code.** In the Mac panel,
   Forget the iPad Pro 11" (M5) and iPhone 17 Pro simulators, or erase
   them. Open the Mac's "Pair a device" window and have the QA script write
   its code to a file. Then run:

   ```sh
   TEST_RUNNER_PH_QA_PAIRCODE_FILE=/tmp/ph-paircode.txt \
   TEST_RUNNER_PH_QA_OUT=/tmp/shots \
   xcodebuild test-without-building -project DeckHand.xcodeproj -scheme DeckHandiOS \
     -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
     -only-testing:PixelHandUITests/PixelHandUITests/test15_PairUnpairedSimulatorByCode
   ```

   - **Expected:** the approval card appears (not a refusal), the walk
     types the code, and the screenshot reads `paired-and-connected`. The
     Mac log shows "is on this Mac (loopback or its own address…)" and no
     "arrived over a remote path (loopback)".
   - A `refused` screenshot means it still fails.
   - Then run the whole walk on each simulator. VQ-003/005/029–031/037
     (pairing by code) can now be checked there.
3. **Bug 2.** Run `test14_DeckWithMirror` on iPhone 17 Pro, light and AX3
   (`PH_QA_TAG=ax3`).
   - The tile rests under the deck header.
   - There are no `not-hittable-ph.deck.edit` / `-ph.deck.pin`
     screenshots, and `deck-edit-with-tile` shows edit mode.
   - By hand: drag the tile onto the header. It springs back below it.
   - On iPad, the tile still homes to the pad's corner.
4. **Bug 3 (VQ-065).** iPhone 17 Pro at AX3, any connected screen: the pill
   reads "Muhammad’s" / "MacBook Pro" (or a tail "…" on line 2), never
   "Muham-".
5. **Bug 4.** Lock the Mac, then on the iPad choose Show screen (and take a
   screenshot).
   - **Expected:** "Mac is locked · Unlock the Mac to see its screen. Pixel
     Hand never shows the lock screen."
   - Unlocked, turn Screen Recording off for Pixel Hand and try again. The
     alert should say how to turn it back on.
   - No alert may contain "error", "Pixel_Hand." or "operation couldn’t".
6. **Bug 5.** Run the iPad mini and iPad Pro simulators side by side, one
   of them on build 18 if available. Neither lists the other; only the Mac
   is listed, with no "Please update Pixel Hand on your Mac" row for an
   iPad.

## Compile risks

- `MacPill.nameText` is a `@ViewBuilder` computed property with a `let`
  and `ViewThatFits` over `ForEach(candidates.indices, id: \.self)`. It is
  not type-checked on Linux (SwiftUI). If the compiler struggles, move the
  candidates into a `let` outside the builder.
- `DeckSurface` wraps the header `if/else` in a `Group` and adds
  `.frame(maxWidth: .infinity)` before `.mirrorTileKeepOut(.deckHeader, owner: sender)`.
  `sender` is the surface's `TrackpadSender`, the same owner the Pointer
  surface uses. This is not type-checked on Linux.
- `MirrorTileKeepOutPart` gained `.deckHeader`. No `switch` over it exists
  today. The enum is internal to the iOS app.
- `MirrorStreamService` (not in the Linux type check) calls the
  `@MainActor` `CaptureFailure.reported(for:fallback:)` from its own
  `@MainActor` methods. It adds a `private static func stoppedFailure(for:)`.
- `ControlSessionModel` and `ControlSessionModel+Mirror` use
  `LockPolicy.lockedErrorMessage` (PixelHandCore, already imported through
  `PixelHandCoreExports`).
- `PeerPickerView` and `ContentRootView` renamed the `@LoomQuery` property
  to `discoveredPeers` and added a computed `peers`. `.onChange(of: peers)`
  now observes a computed array, which is `Equatable` as before.
- `CaptureSheetChrome.errorTitle` / `errorMessage` gained a defaulted
  `macLocked:` parameter. Existing call sites compile unchanged. Their copy
  is now sentence case, so any Mac-side test or snapshot expecting "Mac Is
  Locked" or "Live Screen Unavailable" needs updating (none found in the
  repository).
- `PixelHandProtocol.advertisementMetadata` (the static var) is kept for
  `DeckHandTests/PeerCompatibilityTests`. The apps call the new
  `advertisementMetadata(role:)`.

Lane: READY TO MERGE
