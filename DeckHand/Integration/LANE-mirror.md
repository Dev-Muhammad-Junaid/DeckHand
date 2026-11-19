# Lane: Mirror — binary stream, S3 local cursor, display picker, S6 stats

Branch `claude/pixelhand-lane-mirror`, from `claude/pixelhand-integration`
(latest merged: `17e2f7a`). Items 1–4 of the lane are done. S5 (HEVC) and
S14 (single window) are handed to follow-up lanes (§8), as the brief
allowed. Desktop dots wait for the Mac system lane (§8).

Written in a Linux container: PixelHandCore built and tested with Swift
6.2; app files type-checked against stubs where possible (§5). **The apps
were not compiled.** The Mac session must run §6.

## 1. What changed

### Protocol 3 (Core)

| Change | Where |
| --- | --- |
| `mirror.frame` **removed**. Frames travel on the Loom stream `PixelHandStream.mirror` ("pixelhand.mirror"), one `BinaryFrameHeader` frame per Loom payload | `Protocol/MirrorMessage.swift`, `Protocol/BinaryFrame.swift` |
| New frame kinds `cursor = 5` (18-byte `MirrorCursorState`) and `cursorShape = 6` (20 bytes + PNG, `MirrorCursorShape`); layouts documented and pinned by tests | `Protocol/BinaryFrame.swift`, `Mirror/MirrorCursor.swift` |
| New `mirror.moveCursor(displayID:)` (remote → Mac): the badge's "Bring Here" | `Protocol/MirrorMessage.swift` |
| `diagnostics` domain **activated**: `mirrorStats(stats: MirrorHostStats)` Mac → remote and `mirrorClientStats(stats: MirrorClientStats)` remote → Mac, once a second while mirroring | `Protocol/DiagnosticsMessage.swift`, one decode line in `ControlMessage.swift`, handler in `ControlRouter` |
| Host announces `binaryMirrorStream` in `hostStatus` | `SessionHandler.swift` (one line, §4) |
| Version 2 → **3**, fixtures re-recorded (37 cases, 57 fixtures), history line | `PixelHandProtocol.swift`, `MANIFEST`, `PROTOCOL.md` |
| `mirrorClientStats` numbers checked before the Mac logs them (non-finite → 0, clamped) | `RemoteInputValidation.sanitize`, `MirrorClientStats.sanitized()` |
| Contract tests no longer hard-code `"v":2` in hand-written JSON (they use the current version), so the next bump doesn't touch them | `ProtocolContractTests.swift`, `RemoteInputValidationTests.swift` |

New pure logic in `Core/Sources/PixelHandCore/Mirror/` (all tested):

- `MirrorCursor.swift`: cursor payload codecs, shape ids (FNV-1a), global
  point → display fraction, the pointer's sprite frame and scale limits
  (0.5×–1.5× of its Mac size), the 60 Hz / 1 s-refresh send throttle, and
  an LRU shape cache.
- `MirrorFrameMailbox.swift`: newest-frame-wins slot for the iPad decoder.
- `MirrorStats.swift`: host/client stats, the counter, and the one-line
  summary (`JPEG 1440×900 · Mac 20 fps, 6.1 ms, 1.2 Mb/s, 3 dropped · iPad 20 fps, 4.0 ms`).
- `MirrorDisplayFollower.swift`: picker/badge decision and Follow cursor
  (switch after 0.35 s on another display, at most once a second).
- `BinaryFrameReader` (in `BinaryFrame.swift`): whole frames from split or
  joined payloads; fails for good on a framing error.

### Mac

- `MirrorStreamService.swift` (rewritten around the same pipeline):
  - after `mirror.start` it opens `pixelhand.mirror` towards that remote
    (`Mirror/MirrorSubscriber.swift`), reused until `mirror.stop` or
    disconnect, which close it;
  - capture with `showsCursor = false`;
  - newest-frame-wins per remote, as before, now with drop counts;
  - a second `start` from a watching remote changes the capture in place:
    another display restarts it, another rate or width calls
    `SCStream.updateConfiguration` (falls back to a restart). The iPad's
    pinch / settings re-negotiation now sends only `start` (no `stop`, no
    new stream);
  - a 60 Hz main-actor loop while capturing: pointer position
    (`CGEvent(source:nil).location`, `CGDisplayBounds`,
    `CGGetDisplaysWithPoint`) and, every 6th tick, its shape
    (`NSCursor.currentSystem`, rendered at 2×, PNG only when it changes)
    (`Mirror/MirrorCursorSampler.swift`). Public API only. Cursor sends
    never wait behind video; a pointer image goes once per stream before
    the first position that uses it;
  - once a second, `diagnostics.mirrorStats` to each remote.
- `Handlers/MirrorHandler.swift`: `moveCursor` → `InputInjector.moveCursorToCenter`
  for displays in `CGGetActiveDisplayList` only.
- `Handlers/DiagnosticsHandler.swift` (new): logs
  `Mirror stats: …` (Mac + remote halves) at most every 10 s per remote.

### iPad

- `Mirror/MirrorStreamReceiver.swift` (new): the mirror's own reader.
  Subscribes to `connection.session.makeIncomingStreamObserver()`, drains
  every `pixelhand.mirror` stream in its own task (always, so Loom's
  buffer never fills), JPEGs go through the mailbox to one off-main
  decoder, cursor frames go straight to the model. The control stream
  still has one reader (`listenForHostMessages`).
- `Control/ControlSessionModel.swift`: mirror stored properties moved
  under `// MARK: Mirror`; the JSON frame decode is gone; two loops started
  next to the heartbeat (receiver, stats); cases for `displayList` (now
  keeps the list) and `diagnostics.mirrorStats`.
- `Control/ControlSessionModel+Mirror.swift` (new): toggle / re-negotiate
  / switch Space moved here, plus sink callbacks, picker, Follow cursor,
  Bring Here, stats loop.
- `Mirror/MirrorOverlay.swift` (new): wraps `MirrorThumbnailView` with
  - the **pointer layer** (sprite at the hot spot, scaled with the mirror;
    an SF Symbol arrow until the shape arrives; reads only the cursor
    state, so 60 Hz redraws stay in that layer);
  - the **display picker** (top left; only with 2+ displays): each display
    by name, plus **Follow Cursor**;
  - the **"Cursor on <display>" badge** with **Bring Here** / **Show**
    (from the cursor stream's display id, no Spaces data needed);
  - the **stats line** (Settings › Live mirror › Show stream stats).
- `MirrorThumbnailView.swift`: three optional layers (cursor over the
  picture, top-left and bottom chrome).
- Settings: `mirrorFollowsCursor`, `showMirrorStats` (stored in
  `DeckHandSettings.swift` under `// MARK: Mirror (lane)`), two toggles in
  `SettingsMirrorSection`.

## 2. Commits

| Commit | What |
| --- | --- |
| `78613cf` | Core: protocol 3, cursor payloads, reader, mailbox, stats, follower, tests |
| `80d11dc` | Mac: binary stream, local cursor, stats, `moveCursor`, diagnostics handler |
| `50f8740` | iPad: receiver, cursor layer, picker, badge, stats HUD, settings |
| `95cb1bd` | Bridge fix in the cursor sampler |
| `35662b6` | Merge of integration (`17e2f7a`) |
| (this doc) | `LANE-mirror.md` |

## 3. Tests (Linux)

```sh
swift test --package-path DeckHand/Core     # ✔ 142 tests in 26 suites (was 114)
DeckHand/Scripts/linux-typecheck/run.sh     # Build complete, no errors or warnings
```

New suites: `MirrorCursorStateTests`, `MirrorCursorShapeTests`,
`MirrorCursorGeometryTests`, `MirrorCursorThrottleTests`,
`BinaryFrameReaderTests`, `MirrorFrameMailboxTests`, `MirrorStatsTests`,
`MirrorDisplayPickerTests`; contract tests cover the new and removed cases.

## 4. Out-of-lane edits (all small)

| File | Owner | Edit |
| --- | --- | --- |
| `Core/Protocol/ControlMessage.swift` | hot spot | one decode line for `diagnostics` (LANES §3) |
| `Core/Routing/ControlRouter.swift` | integration | `diagnostics` property, init argument, route line (LANES §3) |
| `DeckHandMac/Handlers/MacHandlers.swift` | integration | `DiagnosticsHandler` property and init argument |
| `DeckHandMac/Handlers/SessionHandler.swift` | Network | `features: [.binaryMirrorStream, .commandReceipts]` |
| `Core/Input/RemoteInputValidation.swift` | iOS interaction | one `case` for `mirrorClientStats` |
| `Core/Tests/…/ProtocolContractTests.swift`, `RemoteInputValidationTests.swift`, `ControlRouterTests.swift` | shared | samples, case names, version-agnostic JSON literals, router argument |
| `DeckHandiOS/ControlView.swift` | integration | the `MirrorThumbnailView(…)` block → `MirrorOverlay(session:containerSize:)` |
| `DeckHandiOS/DeckHandSettings.swift` | hot spot | two keys, two `@Published`, two init lines under `// MARK: Mirror (lane)` |
| `Scripts/linux-typecheck/Stubs.swift`, `run.sh` | integration | stubs for `openStream`, `LoomMultiplexedStream`, `session`, `UIImage`, `CGGetActiveDisplayList`; `MirrorSubscriber` and `MirrorStreamReceiver` added to the default list |

No `project.yml`, Info.plist, entitlement or Loom changes. New folders
`DeckHandMac/Mirror/` and `DeckHandiOS/Mirror/` are picked up by folder.

## 5. Protocol version at merge

Integration was at version 2 when this was written, so this lane took
**3**. The Network lane also took 3 and merges first, and Mac system
control bumps too. When merging after them: keep both sides' cases, set
`PixelHandProtocol.version` to the next free number, merge the history
lines in `PROTOCOL.md` (renumber this lane's line), set
`expectedCaseCount` to the sum of both sides' additions, then

```sh
PH_RECORD_FIXTURES=1 swift test --package-path DeckHand/Core --filter ProtocolContractTests
swift test --package-path DeckHand/Core
```

Conflicts to expect: `PixelHandProtocol.swift`, `MANIFEST`, the history
table, `ProtocolContractTests.swift` (samples, case names, count, the
`"v":` literals), every fixture file (the `v` changes), `SessionHandler`'s
feature list (keep both), `ControlRouter`/`MacHandlers` if another lane
activates `sharing` at the same time.

## 6. Mac build: compile risks (most likely first)

1. **`MirrorStreamReceiver` / `MirrorStreamSink`**: a `@MainActor protocol
   …: AnyObject, Sendable` used from non-isolated task-group children with
   `await sink.…`. Type-checked on Linux with stubs; Xcode's region checker
   may still complain. If so, capture the sink as `nonisolated(unsafe)` or
   make the callbacks `nonisolated` and hop with `MainActor.run`.
2. **`await connection.session`** (actor `let` read across modules) and
   `makeIncomingStreamObserver()` on `any LoomSessionProtocol`.
3. **`MirrorThumbnailView`'s memberwise init** with the three new `AnyView`
   properties (argument order in `MirrorOverlay` follows declaration order).
4. **`MirrorOverlay`**: `let rect = …` inside a `GeometryReader` builder;
   `Toggle` inside a `Menu`; `.underline()` on `Button` (iOS 16+).
5. **`MirrorCursorSampler`**: `NSCursor.currentSystem`,
   `NSImage.cgImage(forProposedRect:…)`, `cfData as Data`,
   `NSBitmapImageRep.representation(using:properties:)`.
6. **`SCStream.updateConfiguration`** is `async throws` (macOS 12.3+).
7. **`ControlSessionModel`**: `@ObservationIgnored weak var mirrorSettings`;
   formerly `private(set)` mirror properties are now internal `var`s (the
   extension in another file writes them).
8. `MirrorSubscriber` sends from `Task { @MainActor … }` with a captured
   `LoomMultiplexedStream` (`@unchecked Sendable` in Loom).

## 7. What the owner's Mac build must check

```bash
git fetch origin claude/pixelhand-lane-mirror      # or the integration merge
cd DeckHand && xcodegen generate                    # new Mirror/ folders
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandMac -destination 'platform=macOS' -allowProvisioningUpdates build
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandiOS -destination 'generic/platform=iOS' -allowProvisioningUpdates build
swift test --package-path Core                      # expect 142 (more after other lanes)
```

Both devices must run this build (protocol 3 and older builds don't talk).

| Area | Check |
| --- | --- |
| Mirror basics | Start the mirror: the picture appears; pinch larger and smaller (picture keeps going, no blank flash); change Sharpness and Frame rate in Settings while it runs; close and reopen it. With Screen Recording off: "Live Mirror Unavailable". |
| Control stream stays light | With the mirror on, trackpad input and chips feel the same as with it off; `log stream --predicate 'subsystem == "com.widgetsflow.pixelhand"'` shows no "Dropped an undecodable message" and no heartbeat `GAVE UP` over 5 minutes. |
| S3 cursor | The mirror shows the pointer with **no** pointer baked into the video: move the Mac's mouse — the iPad pointer follows smoothly even at 15 fps. Hover a link (hand), a text field (I-beam), a window edge (resize arrows): the shape changes. Locate (Quick Actions) is visible on the iPad as the pointer moving. Pinch the mirror small: the pointer stays readable; full size: it isn't huge. |
| Display picker (2 displays) | Top-left chip names the mirrored display; the menu lists both; picking the other switches the picture within a second; the chip updates. With one display: no chip. |
| Follow cursor | Turn on in the chip's menu (or Settings): move the pointer to the other display and keep it there: the mirror follows in about half a second; sweeping across and straight back doesn't switch. |
| Badge | Follow cursor off, pointer on the other display: "Cursor on <name>" with **Bring Here** (pointer jumps to the centre of the mirrored display; badge disappears) and **Show** (mirror switches). |
| S6 stats | Settings › Live mirror › Show stream stats: a line like `JPEG 1440×900 · Mac 20 fps, 6 ms, 1.2 Mb/s · iPad 20 fps, 4.0 ms` updates every second. On the Mac, `log stream … | grep "Mirror stats"` shows a line every ~10 s. |
| Display unplugged | Unplug the mirrored display: the mirror falls back to the main display and the picker updates. |
| Two remotes | Two devices mirroring: both get pictures and pointers; closing one keeps the other going. |
| Space buttons | ‹ › still switch Spaces on the mirrored display. |

## 8. Follow-up lanes

Follow-up lanes: mirror-hevc (S5), mirror-window (S14), mirror-dots

- **mirror-hevc (S5).** Builds on this stream: `BinaryFrameHeader` kinds
  `hevcParameterSets` / `hevcKeyFrame` / `hevcDeltaFrame` are reserved and
  the iPad reader already skips them. Mac: `VTCompressionSession` (HEVC,
  real-time, no B-frames, `MaxKeyFrameInterval` ~2 s) fed from the
  existing `SCStream` (`CVPixelBuffer` straight in, NV12/`420v` capture
  format instead of BGRA); parameter sets before every key frame;
  delta-drop backpressure in `MirrorSubscriber.sendFrame` (drop deltas
  while >2 sends are un-acked, then force a key frame); a new
  `mirror.requestKeyFrame` (remote → Mac, protocol bump) after a decode
  error or a gap in `seq` for video kinds; `MirrorCodec.hevc` in the stats.
  iPad: `CMVideoFormatDescriptionCreateFromHEVCParameterSets` →
  `CMSampleBuffer` → `AVSampleBufferDisplayLayer` in a `UIViewRepresentable`
  replacing `Image(uiImage:)`; the cursor layer stays a SwiftUI overlay.
  Software fallback: if the device lacks HEVC decode or the layer reports
  `.failed`, ask the Mac for JPEG (a `codec` field on `mirror.start`).
  Watchdog: no displayed frame for 2 s with frames arriving → request a key
  frame, then fall back to JPEG. Keep the newest-frame mailbox for JPEG;
  HEVC must decode every delta after a key frame, so the mailbox becomes
  "drop to next key frame". Core logic to add with tests: keyframe policy,
  backpressure counter, watchdog state machine.
- **mirror-window (S14).** Stream one window instead of a display:
  `mirror.start` gains an optional `windowID` (protocol bump);
  `SCContentFilter(desktopIndependentWindow:)`; the capture size follows
  the window's frame; the cursor maps into window bounds (send fractions of
  the window, `isOnMirroredDisplay` → "over the window"). The iPad reuses
  `WindowPickerView` (capture) to choose the window; the display picker
  gains a "Window…" entry. Handle the window closing (`mirror.error` then
  back to its display).
- **mirror-dots (Spaces), once the Mac system lane merges** (its
  `SystemMessage.displayState(layout: DisplayLayout)` is on
  `claude/pixelhand-lane-mac-system`, not on integration yet). In
  `ControlSessionModel` add a `case .system(.displayState(layout))` storing
  the layout under `// MARK: Mirror`; under the mirror draw one dot per
  Space of the mirrored display (`layout.display(id)?.spaces`), the current
  one filled, full-screen Spaces as short app-name labels; hide or dim ‹ ›
  with `SpaceNavigation.decide`, hide both with one Space, hide the dots
  when `spacesKnown` is false. The badge can then also use
  `layout.cursorDisplayID` when the mirror is stopped (today it uses the
  cursor stream's display id, which is only sent while mirroring).

Not done: S16 virtual display (deferred by the owner).

Lane: READY TO MERGE
