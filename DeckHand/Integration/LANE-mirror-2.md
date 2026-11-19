# Lane: Mirror 2 — desktop dots, S5 HEVC

Branch `claude/pixelhand-lane-mirror-2`. Up to date with
`origin/claude/pixelhand-integration` at `d6f2d76` (contains `10a79e3`).
Done: **desktop dots** (mirror-dots) and **S5 HEVC** (mirror-hevc). Not done:
**S14 single window**, handed to a follow-up lane (§8).

Written in a Linux container: PixelHandCore built and tested with Swift
6.2; the Mac and iOS app files were type-checked against stubs where
possible (§3). **The apps were not compiled.** The Mac session must run §6.

How this branch started: when the lane began, integration didn't have the
lane merges yet, so I merged `pixelhand-lane-network`, `-mac-system` and
`-mirror` locally (protocol 3/4/5, the same numbering and conflict
resolutions the coordinator used in `10a79e3`), then merged the real
integration branch on top. `git diff origin/claude/pixelhand-integration`
shows only this lane's work.

## 1. What changed

### Protocol 6 (Core)

| Change | Where |
| --- | --- |
| `mirror.start` gains a **required** `codec: MirrorCodec` (`jpeg` / `hevc`) | `Protocol/MirrorMessage.swift` |
| New `mirror.requestKeyFrame` (remote → Mac) | `Protocol/MirrorMessage.swift` |
| The reserved binary kinds `hevcParameterSets` / `hevcKeyFrame` / `hevcDeltaFrame` now carry video. Parameter-set payload `[u8 nalLen][u8 count]{[u16 len][bytes]}`; frame payloads are length-prefixed NAL units as VideoToolbox writes them | `Protocol/BinaryFrame.swift` (docs), `Mirror/MirrorVideo.swift` |
| Version 5 → **6**, fixtures re-recorded (42 cases), history line | `PixelHandProtocol.swift`, `MANIFEST`, `PROTOCOL.md` |
| Lock gate: `requestKeyFrame` allowed (only affects a mirror the gate already let start) | `System/LockPolicy.swift` (one `case`, see §4) |
| `RemoteInputValidation.sanitize` passes `codec` through (enum, nothing to clamp) | `Input/RemoteInputValidation.swift` |

### New pure logic (Core, all tested)

- `Mirror/MirrorSpaceStrip.swift`: the dots and ‹ › states for the
  mirrored display from `DisplayLayout` (dimmed at an end, hidden with a
  single Space, everything enabled and no dots when `spacesKnown` is
  false), short full-screen labels ("Safari & Notes" → "Safari", 10
  characters max), the VoiceOver summary, and
  `MirrorDisplayChrome.cursorDisplayID(stream:layout:)` (badge source).
  Chevron states come from `SpaceNavigation.decide`, so the iPad dims
  exactly when the Mac would refuse.
- `Mirror/MirrorVideo.swift`:
  - `MirrorHEVCParameterSets` codec, `MirrorHEVCNALUnits.isWellFormed`;
  - `MirrorKeyFramePolicy` (Mac): first frame is a key frame, requests are
    served but forced key frames are ≥ 0.5 s apart, the encoder's own
    ~2 s key frames satisfy waiting requests;
  - `MirrorVideoBackpressure` (Mac, per remote): deltas dropped while > 2
    sends are un-acked; after a drop, nothing until the next key frame,
    which is requested once the link has room; key frames dropped only
    when 4 are un-acked;
  - `MirrorVideoWatchdog` (iPad): deltas before a key frame are dropped and
    a key frame asked for; a decode failure → recovering + key frame
    request; frames arriving with nothing shown for 2 s → request, again
    2 s later, then **fall back to JPEG** for the session. An idle screen
    (no frames) is not a stall;
  - `MirrorCodecChoice`, `MirrorVideoBitrate` (0.12 bit/pixel/frame,
    1–12 Mb/s; even dimensions).

### Mac

- `Mirror/MirrorHEVCEncoder.swift` (new): `VTCompressionSession`, HEVC Main
  AutoLevel, hardware encoder preferred, `RealTime`, no frame reordering,
  `MaxKeyFrameIntervalDuration` 2 s, expected rate and average bit rate,
  `PrioritizeEncodingSpeedOverQuality`. Fed the capture's `CVPixelBuffer`
  directly; recreated when the buffer size changes (new key frame). Every
  key frame carries the parameter sets. At most 2 frames inside the
  encoder; extra capture frames are skipped and counted. No encoder → every
  remote silently switched to JPEG.
- `MirrorStreamService.swift`: the capture is NV12 (`420v`) while any
  remote wants HEVC, BGRA otherwise (changed in place with
  `updateConfiguration`); even capture sizes; the frame output runs the
  JPEG path, the HEVC path or both, per the remotes' codecs; HEVC frames
  reach the main actor through `DispatchQueue.main` (keeps encode order);
  stats report each remote's own codec (`HEVC 1440×900 · …`);
  `requestKeyFrame(subscriberID:)`.
- `Mirror/MirrorSubscriber.swift`: per-remote `codec`; HEVC goes through one
  ordered send loop with `MirrorVideoBackpressure` (JPEG unchanged:
  newest-frame-wins); key frame + parameter sets in one Loom payload;
  `afterDrop` / `formatChanged` flags.
- `Handlers/MirrorHandler.swift`: `start` passes `codec`;
  `requestKeyFrame` → service.

### iPad

- **Desktop dots:** `Mirror/MirrorOverlay.swift` draws `MirrorSpaceDots`
  just under the mirror (white filled dot = current, faint dots = other
  desktops, capsule labels = full-screen apps; nothing when Spaces are
  unknown). `MirrorThumbnailView` gained `belowAccessory` (outside the clip,
  not part of layout) and `previousChevron` / `nextChevron`
  (`.enabled` / `.dimmed` = 30 % and disabled / `.hidden`).
  `ControlSessionModel+Mirror.swift`: `mirrorSpaceStrip` from
  `displayLayout` (the Mac system lane's stored property, read only), and
  the badge now falls back to `displayLayout.cursorDisplayID` until the
  cursor stream has said where the pointer is.
- **HEVC:**
  - `Mirror/MirrorHEVCSampleBuilder.swift` (new): parameter sets →
    `CMVideoFormatDescriptionCreateFromHEVCParameterSets`; frame →
    `CMBlockBuffer` → `CMSampleBufferCreateReady`, marked
    `DisplayImmediately` (and `NotSync` for deltas). Damaged payloads give
    no sample.
  - `Mirror/MirrorVideoRenderer.swift` (new): `AVSampleBufferDisplayLayer`
    (via its iOS 17 `sampleBufferRenderer`) + `MirrorVideoLayerView`
    (`UIViewRepresentable`, no touches). Decode failures
    (`didFailToDecodeNotification`, `.failed`) go to the watchdog.
  - `Mirror/MirrorStreamReceiver.swift`: HEVC kinds handled in order on the
    stream's reader (one builder per stream), handed to the main actor
    one by one (JPEG keeps its mailbox).
  - `ControlSessionModel+Mirror.swift`: codec asked for in `mirror.start`
    (`MirrorCodecChoice`: setting on, `VTIsHardwareDecodeSupported`, no
    fallback yet); watchdog fed on every frame and ticked every 0.25 s by
    the stats loop (which now wakes 4×/s and still reports once a second);
    `requestKeyFrame` sent / JPEG restart on its decisions; a JPEG frame
    arriving switches the picture back to the image.
  - `MirrorThumbnailView`: `videoLayer` / `videoSize`; when set the layer is
    drawn instead of the image, the cursor layer stays on top.
  - Settings › Live mirror › **Efficient video (HEVC)** (default on;
    `mirrorPrefersHEVC`); changing it re-negotiates the running mirror.

## 2. Commits

| Commit | What |
| --- | --- |
| `74ea1e0` and earlier merges | Local merge of the three lanes (superseded by `10a79e3`, same result) |
| `48865af` | Desktop dots, chevron states, badge fallback |
| `335a9b4` | Core: HEVC rules, protocol 6, tests |
| `c29cbae` | Mac: HEVC encoder, NV12 capture, backpressure, `requestKeyFrame` |
| `0ddbdad` | iPad: sample builder, display layer, watchdog, setting |
| `f1a17eb` | Main-actor callback types |
| `3229bc8` | Merge of integration `d6f2d76`, protocol kept at 6 |
| (this doc) | `LANE-mirror-2.md` |

## 3. Tests (Linux)

```sh
swift test --package-path DeckHand/Core     # ✔ 249 tests in 41 suites (integration: 222)
DeckHand/Scripts/linux-typecheck/run.sh     # Build complete, no errors
```

New suites: `MirrorSpaceStripTests`, `MirrorHEVCPayloadTests`,
`MirrorKeyFramePolicyTests`, `MirrorVideoBackpressureTests`,
`MirrorVideoWatchdogTests`, `MirrorCodecChoiceTests`. Contract tests cover
`mirror.start.hevc` and `mirror.requestKeyFrame`.

Type-checked: `MirrorHandler`, `MirrorSubscriber`, `MirrorStreamReceiver`,
`TrackpadSender` (with new stubs for `MirrorHEVCEncodedFrame`,
`MirrorHEVCSampleBuilder`, `MirrorVideoEvent`, `CMSampleBuffer`). **Not**
type-checked (VideoToolbox, CoreMedia, AVFoundation, SwiftUI):
`MirrorHEVCEncoder`, `MirrorStreamService`, `MirrorHEVCSampleBuilder`,
`MirrorVideoRenderer`, `MirrorOverlay`, `MirrorThumbnailView`,
`ControlSessionModel+Mirror`, settings.

## 4. Out-of-lane edits

| File | Owner | Edit |
| --- | --- | --- |
| `Core/System/LockPolicy.swift` | Mac system control | `.requestKeyFrame` added to the mirror `allow` case (with a comment). Announced as required by the brief. |
| `Core/Protocol/PixelHandProtocol.swift`, `MANIFEST`, `PROTOCOL.md`, every fixture's `v` | hot spot | version 6, history line |
| `Core/Input/RemoteInputValidation.swift` | iOS interaction | `mirror.start` case passes `codec` through |
| `Core/Tests/…/ProtocolContractTests.swift`, `LockPolicyTests.swift`, `RemoteInputValidationTests.swift` | shared | `codec:` added to existing `mirror.start` samples; two samples, one case name, count 42 |
| `DeckHandiOS/TrackpadSender.swift` | iOS interaction | `startMirror(…, codec: MirrorCodec = .jpeg)` |
| `DeckHandiOS/DeckHandSettings.swift` | hot spot | one key, one `@Published`, one init line under `// MARK: Mirror (lane)` |
| `DeckHandiOS/Control/ControlSessionModel.swift` | hot spot (Mirror section) | five stored properties under `// MARK: Mirror`; no new message cases, no new loop |
| `Scripts/linux-typecheck/Stubs.swift` | integration | stubs listed in §3 and the new `start`/`requestKeyFrame` signatures |

No `project.yml`, Info.plist, entitlement or Loom changes. VideoToolbox,
CoreMedia and AVFoundation are system frameworks, linked automatically by
`import`.

## 5. Protocol version at merge

Integration is at 5; this lane takes **6**. If another lane lands a bump
first: keep both sides' cases, take the next number, merge the history
lines, set `expectedCaseCount` to the sum, then
`PH_RECORD_FIXTURES=1 swift test --package-path DeckHand/Core --filter ProtocolContractTests`
and `swift test --package-path DeckHand/Core`.

## 6. Mac build: compile risks (most likely first)

1. **`MirrorStreamService.swift`** `MirrorFrameOutput(fps:) { … } onHEVCFrame: { … } onHEVCUnavailable: { … }`:
   multiple trailing closures, the first non-`@Sendable`, the others
   `@Sendable`; inside, `DispatchQueue.main.async { MainActor.assumeIsolated { MirrorStreamService.shared.… } }`
   calls `fileprivate` methods. If the region checker objects, make the two
   methods `nonisolated` wrappers that hop with `MainActor.assumeIsolated`.
2. **`MirrorHEVCEncoder.swift`**: `VTCompressionSessionEncodeFrame(…, outputHandler:)`
   closure capturing `[weak self]` (class is `@unchecked Sendable`);
   `VTSessionSetProperty` with `kCFBooleanTrue` / `NSNumber` values;
   `CMVideoFormatDescriptionGetHEVCParameterSetAtIndex` argument labels;
   `MirrorHEVCEncoder { … } onUnavailable: { … }` trailing-closure init in
   `MirrorFrameOutput.hevcEncoder()`.
3. **`MirrorHEVCSampleBuilder.swift`** (iOS):
   `CMVideoFormatDescriptionCreateFromHEVCParameterSets(parameterSetPointers:)`
   takes `UnsafePointer<UnsafePointer<UInt8>>` — built from
   `[UnsafePointer<UInt8>].withUnsafeBufferPointer`; `CMBlockBufferReplaceDataBytes(with:…)`;
   `CMTimeValue(clamping:)`; the `unsafeBitCast(…, to: CFMutableDictionary.self)`
   attachment idiom.
4. **`MirrorVideoRenderer.swift`**: `AVSampleBufferVideoRenderer.didFailToDecodeNotification`,
   `sampleBufferRenderer.requiresFlushToResumeDecoding`,
   `flush(removingDisplayedImage:completionHandler:)` (all iOS 17);
   `nonisolated(unsafe) private var observer` read in `deinit`.
5. **`MirrorThumbnailView`** memberwise init: new properties appended in
   order `belowAccessory, previousChevron, nextChevron, videoLayer,
   videoSize`; `MirrorOverlay` passes them in that order. `.aspectRatio(1 / frameAspect, …)`
   on an `AnyView`.
6. **`ControlSessionModel`**: `@ObservationIgnored let mirrorVideoRenderer = MirrorVideoRenderer()`
   (main-actor init in a main-actor class); `mirrorDidReceiveVideo` added to
   the `@MainActor` `MirrorStreamSink` protocol.
7. `MirrorStreamService.configuration(for:)` now writes `currentPixelFormat`
   (a stored property) from a method that used to be pure; fine on the main
   actor.
8. `MirrorOverlay`: `let strip = …` at the top of `body`; `.onChange(of:)`
   with a zero-argument closure (iOS 17).

## 7. What the owner's Mac build must check

```bash
git fetch origin claude/pixelhand-lane-mirror-2   # or the integration merge
cd DeckHand && xcodegen generate                  # new files in existing Mirror/ folders
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandMac -destination 'platform=macOS' -allowProvisioningUpdates build
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandiOS -destination 'generic/platform=iOS' -allowProvisioningUpdates build
swift test --package-path Core                    # expect 249 (more after other lanes)
```

Both devices must run this build (protocol 6; older builds don't talk).
Turn on Settings › Live mirror › Show stream stats for the HEVC checks.

| Area | Check |
| --- | --- |
| Dots, 2 displays, uneven desktops | e.g. built-in with 3 desktops, external with 1. Mirror the built-in: three dots under the mirror, the current one filled; switch Spaces on the Mac with ⌃→: the filled dot moves within a second. On the first desktop ‹ is dim and does nothing; on the last, › is dim. Mirror the external (picker): one dot, **no** chevrons. |
| Full-screen app | Put Safari in full screen on the mirrored display: a "Safari" capsule appears in its place in the strip, filled while it's showing; split view shows the first app's name. |
| Spaces unknown | (Hard to force; if the Mac logs that `CGSCopyManagedDisplaySpaces` is missing) no dots, both chevrons usable. |
| Badge | Start the mirror with the pointer already on the *other* display and don't move it: "Cursor on <name>" appears without waiting for a mouse move (from the display snapshot). |
| HEVC starts | Stats line starts with **`HEVC`** (both ends show frames). The picture looks like the JPEG one but sharper, text crisp; Mac log: no `no HEVC encoder` line. |
| HEVC under change | Scroll a long web page and play a YouTube video on the Mac: smooth, no grey/green smearing, no frozen picture. Data rate in stats well below JPEG's at the same size. |
| Pinch / sharpness / frame rate / display switch | All still work with HEVC; after each, the picture recovers within a second (new key frame). |
| Backpressure | Throttle the link (Network Link Conditioner "Very Bad Network" on the Mac, or walk away from Wi-Fi): stats show drops on the Mac side; the picture may freeze briefly but **never shows corrupted blocks**, and recovers when the link does. Mac log: no send errors piling up. |
| Key-frame request | (Optional) background and foreground the iPad app while mirroring: the picture comes back within ~0.5 s. |
| Fallback | Settings › Efficient video (HEVC) off while mirroring: the stats switch to `JPEG` within a second and the picture keeps going; on again: back to `HEVC`. |
| Cursor | With HEVC the Mac's pointer is still drawn on top, moving at 60 Hz, correct shapes; Bring Here / Show work. |
| Two remotes | iPad on HEVC and iPhone with HEVC off: both get pictures; each stats line shows its own codec. |
| Idle | Leave the Mac screen still for a minute: no fallback to JPEG (stats stay `HEVC`). |

## 8. Follow-up lanes

Follow-up lanes: mirror-window (S14)

- **mirror-window (S14).** Not started, to keep this lane's uncompiled
  surface reviewable. Plan unchanged from `LANE-mirror.md` §8:
  `mirror.start` gains an optional `windowID` (protocol bump; it now sits
  next to `codec`); Mac capture with `SCContentFilter(desktopIndependentWindow:)`,
  capture size following the window's frame (each resize → new HEVC
  session → key frame, already handled by `MirrorHEVCEncoder`); the cursor
  mapped into window bounds; on the iPad a "Window…" entry in the display
  picker reusing `WindowPickerView`; window closed → `mirror.error` then
  back to its display. Dots and chevrons should hide while a window is
  mirrored (`MirrorSpaceStrip.unknown`).
- Possible polish, not a lane: the iPad's decode time for HEVC isn't
  measured (the display layer decodes internally), so the stats show
  `0 ms` decode on that end for HEVC.

Not done: S16 virtual display (deferred by the owner).

Lane: READY TO MERGE
