# Lane: PiP (UX-041), the live mirror in Picture in Picture

Branch `claude/pixelhand-lane-pip`, merged with
`origin/claude/pixelhand-integration` at `785d970`. Approved in
`DECISIONS.md` (2026-11-17). Specs: `05-Implementation-Plan.md` UX-041,
`03-Layout-Strategy.md` § Picture in Picture, `04-Interaction-Model.md`
§ Screen and § 8.4.

Written in a Linux container: PixelHandCore built and tested with Swift
6.2. **The iOS app was not compiled**: every new iOS file uses AVKit,
VideoToolbox, Core Video or SwiftUI, none of which the Linux type-check
can stub. The Mac session must build it (§4).

**No protocol change** (stays 12): pausing PiP re-sends `mirror.start`
with `fps: 1`, which the Mac already handles in place. No Mac change.

## 1. Plist key (integration session applies it)

Add to `DeckHand/DeckHandiOS/Info.plist` (the target uses
`INFOPLIST_FILE`, not generated keys), inside the top-level `<dict>`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

This is Xcode's "Audio, AirPlay, and Picture in Picture" background mode.
Without it PiP still opens, but the app is suspended in the background
and the connection dies. No entitlement, no `project.yml` change.

App Review note (risk in `04-Interaction-Model.md` §8.4): PiP is
user-facing ("Keep watching in Picture in Picture"), off until turned on,
and only starts from the PiP button or by leaving the app with the
mirror open.

## 2. What changed

### Core (`Mirror/MirrorPictureInPicture.swift`, tested)

| Type | What |
| --- | --- |
| `MirrorPiPState` | Available = Pro + mirror open; auto start also needs the setting. `didStart`/`didStop`, `setPaused`, `tick` and the close triggers return `Effects` (`sessionHoldChanged`, `renegotiate`, `close`, `audioChanged`). `holdsSession` while PiP shows; `requestedFPS` = 1 while paused; `allowsBackgroundAudio` while live. Closes after **10 min paused**, mirror stop, session end, device lock, Pro ending. |
| `MirrorPiPFrameMath` | Pointer rect in frame pixels, sized for the PiP window (mirror's scale rule, floor 0.75× so it stays visible in a small window); Core Graphics flip; JPEG redraw size (≤ 1920, even); whole-pixel `CursorStamp` to skip sub-pixel redraws. |
| `MirrorPiPPacer` | `.off` / `.warm` (2 frames/s while PiP could start, so its layer always has a picture) / `.live(fps)` (≤ 30) / `.frozen`; one trailing frame so the last pointer position lands. |
| `MirrorPiPDecodeHealth` | PiP decoder recovery: wait for a key frame after a failure; 3 in a row → passthrough (compressed stream straight to PiP, no pointer). |

New suite `MirrorPictureInPictureTests` (20 tests). Total **801 tests**.

### iOS (new files)

| File | What |
| --- | --- |
| `Mirror/MirrorPiPController.swift` | `AVPictureInPictureController` with `ContentSource(sampleBufferDisplayLayer:playbackDelegate:)` on its own `AVSampleBufferDisplayLayer`; `requiresLinearPlayback`, infinite time range, no skip, background audio allowed; KVO on `isPictureInPicturePossible`; `MirrorPiPLayerView` hosts the layer. |
| `Mirror/MirrorPiPCompositor.swift` | HEVC samples → `VTDecompressionSession` (BGRA) / JPEG `UIImage` → BGRA buffer; copy + pointer sprite drawn in (Core Graphics) → `CMSampleBuffer` (display immediately) → PiP layer. Paced by `MirrorPiPPacer`; decodes even while paused so references stay whole; recreates the decoder on `kVTInvalidSessionErr`. |
| `Mirror/ControlSessionModel+PiP.swift` | Wiring: callbacks, Effects, lifecycle (background / foreground / `protectedDataWillBecomeUnavailable`), feeding frames and the pointer, audio session hold. Posts `.mirrorPiPRestoreScreen` when the person taps PiP to return. |
| `Mirror/MirrorPiPViews.swift` | `.mirrorPiPSync(session:)` (Pro from `\.entitlements`, the setting, frame rate), `MirrorPiPBackground` (PiP's layer under the picture), `MirrorPiPToolButton` (`.requiresPro(.mirror)`). |
| `Audio/MirrorAudioSessionHold.swift` | Holds `.playback` + `.mixWithOthers` active while PiP could start; `MirrorAudioPlayer` doesn't deactivate the session while it's held. |

### iOS (edits in lane files)

- `ControlSessionModel+Mirror.swift`: stats loop starts/stops PiP and ticks it; frames, JPEG images and pointer updates go to PiP too; **in the background HEVC frames go only to PiP** (the inline layer can't decode there) and the inline watchdog isn't fed or ticked; back in front the watchdog restarts and a key frame is requested; `mirror.start` uses `requestedFPS` (1 while paused); clear/reset paths reset PiP's stream.
- `ControlSessionModel+Audio.swift`: the Mac's sound is wanted in the background while PiP is live (not paused).
- `MirrorThumbnailView.swift`: `pictureBackground` (after `cursorLayer` in the memberwise init), drawn under the picture.
- `MirrorOverlay.swift`: passes PiP's layer, `.mirrorPiPSync`, "Picture in Picture" in the display menu (the tile's PiP button).
- `MirrorPane.swift`: PiP button in the toolbar (between sound and stop), `.mirrorPiPSync`. `MirrorPixelChrome.swift` (`MirrorPicture`): PiP's layer under the picture.
- `MirrorAudioPlayer.swift`: one guard before deactivating the session.
- Settings › Live mirror: **Keep watching in Picture in Picture** (off by default, `.requiresPro(.mirror)`, hidden where PiP isn't supported), footer text.

## 3. Out-of-lane edits

| File | Owner | Edit |
| --- | --- | --- |
| `DeckHandiOS/Control/ControlSessionModel+Network.swift` | Network lane | **Announced hook**, first line of `setForeground(_:)`: `let foreground = foreground \|\| mirrorPiPHoldsSession` (+ comment). PiP calls `setForeground(applicationState != .background)` when it starts or stops. |
| `DeckHandiOS/Control/ControlSessionModel.swift` | hot spot (Mirror section) | five stored properties under `// MARK: Mirror` |
| `DeckHandiOS/DeckHandSettings.swift` | hot spot | one key, one `@Published` (`mirrorPiPAutoStart`), one init line, under `// MARK: Mirror (lane)` |

Not done, suggested for the integration/Shell owner (Duo lane's file):
"tap PiP to return to the app **on the Screen surface**" needs one line in
`Shell/PixelHandShell.swift`:

```swift
.onReceive(NotificationCenter.default.publisher(for: .mirrorPiPRestoreScreen)) { _ in
    surfaceRawValue = ControlSurface.screen.rawValue
}
```

Without it, tapping PiP returns to whatever surface was showing.
No Loom, Mac, protocol, `project.yml` or entitlement changes. Sharing and
Duo files untouched.

## 4. Compile risks (most likely first)

1. **`MirrorPiPController` delegate conformances**: `nonisolated` witnesses
   on a `@MainActor` class with `MainActor.assumeIsolated` inside. If the
   SDK marks `AVPictureInPictureControllerDelegate` /
   `AVPictureInPictureSampleBufferPlaybackDelegate` `@MainActor`, drop
   `nonisolated` and the `assumeIsolated` wrappers. The skip method is the
   completion-handler form (`skipByInterval:completion:`); if Xcode
   prefers the `async` form, either works. `pictureInPictureControllerIsPlaybackPaused`
   returns `MainActor.assumeIsolated { isPaused }`.
2. **`MirrorPiPCompositor.decode`**: `VTDecompressionSessionDecodeFrame(_:sampleBuffer:flags:infoFlagsOut:outputHandler:)`
   with a 5-argument closure `{ status, _, imageBuffer, _, _ in }`; the
   `PiPUnchecked` box carries the `CVImageBuffer?` to the main queue;
   `Int(status) == Int(kVTInvalidSessionErr)`.
3. **Core Video/Core Media calls**: `CMVideoFormatDescriptionMatchesImageBuffer(_:imageBuffer:)`,
   `CMVideoFormatDescriptionCreateForImageBuffer(allocator:imageBuffer:formatDescriptionOut:)`,
   `CMSampleBufferCreateReadyWithImageBuffer(allocator:imageBuffer:formatDescription:sampleTiming:sampleBufferOut:)`,
   `memcpy` on `UnsafeMutableRawPointer + Int`, attribute dictionaries
   `[CFString: Any] as CFDictionary`.
4. **KVO** `controller.observe(\.isPictureInPicturePossible, options: [.initial, .new])`
   closure hopping to main with `[weak self]`.
5. **`MirrorAudioSessionHold`**: `OSAllocatedUnfairLock.withLock { state -> Bool in … }`
   with an inferred `inout` parameter (annotate `(state: inout Bool)` if
   needed).
6. **`MirrorThumbnailView` memberwise init**: `pictureBackground` inserted
   after `cursorLayer`; `MirrorOverlay` passes it in that order.
7. `MirrorPiPController.isSupported` is a main-actor static, read from view
   bodies and the session model (all main actor).
8. `ControlSessionModel+PiP.swift` sits in `DeckHandiOS/Mirror/`; xcodegen
   picks it up (group source), run `xcodegen generate`.

## 5. Checks on device

```bash
git fetch origin claude/pixelhand-lane-pip   # or the integration merge
cd DeckHand && xcodegen generate             # new files in Mirror/ and Audio/
# apply the plist key from §1 first
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandiOS -destination 'generic/platform=iOS' -allowProvisioningUpdates build
swift test --package-path Core               # expect 801
```

PiP needs a real iPhone or iPad (the simulator's PiP is unreliable). Turn
on Settings › Live mirror › Show stream stats for the codec checks.

| Area | Check |
| --- | --- |
| Setting | Settings › Live mirror: "Keep watching in Picture in Picture", **off** on a fresh install. |
| Start from the mirror | Mirror on (pane on the Screen surface): tap the PiP button in the toolbar → PiP opens with the Mac's screen. On the floating tile: display menu (top left) › Picture in Picture. Button dimmed for the first second until the picture arrives. Tap again (or PiP's close) → closes. |
| Start by going Home | Turn the setting on, open the mirror, swipe Home: PiP opens by itself. Setting off: going Home doesn't start PiP. Mirror closed: going Home never starts PiP. |
| Cursor in PiP | Move the Mac's pointer: it moves in PiP (smooth at the stream's frame rate, also over a still screen), right shape (arrow, I-beam, hand), visible size in a small PiP window; resize PiP (pinch): pointer keeps its size relative to the window. Pointer on another display: not drawn. |
| Pause / play | Pause in PiP: picture freezes, the Mac's log shows the mirror reconfigured to **1 fps**, sound stops. Play: live again within a second, full frame rate back in the Mac log. Leave it paused 10 min: PiP closes by itself. |
| HEVC | Stats `HEVC`: PiP picture sharp, no green/grey blocks, pointer drawn. Back in the app after a minute in PiP: inline mirror shows a picture within ~0.5 s, stats stay `HEVC` (no fallback to JPEG). |
| JPEG | Settings › Efficient video off, then PiP: same checks, pointer drawn. Toggle HEVC while PiP is open: picture continues. |
| Window mirror | Mirror one window (display menu › Window…), then PiP: shows the window with the pointer over it; close the window on the Mac: PiP continues on the display. Display picker: switching displays while PiP is open updates PiP. |
| Audio | "Play the Mac's sound" on, PiP open, app in the background: sound keeps playing; pause PiP: silence; play: sound back. Sound off: PiP still works, other apps' audio (Music) keeps playing alongside. |
| 10-minute background run | PiP open, app in background, Mac idle and active in turns for **10 minutes**: picture stays live, the iPhone log never shows `IPAD GAVE UP` or `In the background: keep-alive ticks and pings paused`; it shows `PiP: holding the connection in the background`. Close PiP while in the background: log shows `released the connection` and `keep-alive ticks and pings paused`. Reopen the app: reconnects/continues as before. |
| Lock | PiP open, lock the device: PiP closes (`PiP: closing (deviceLocked)`). |
| Session end | Quit Pixel Hand on the Mac while PiP is open: PiP closes. |
| Free tier lock | Without Pro (StoreKit config, no purchase): mirror locked as before; Settings toggle shows the lock and opens the paywall; no PiP anywhere. Let Pro expire while PiP is open: PiP closes. |
| Back to the app | Tap PiP's "return" button: app comes back to the front (Screen surface only after the Shell hook in §3). |

## 6. Follow-ups

- Shell hook for the Screen surface on restore (§3).
- The inline mirror and PiP decode HEVC twice while PiP could start (both
  in hardware; PiP's copy is composited only 2×/s until it shows). If
  battery matters, warm only after the setting is on or the button is
  first used.

Lane: READY TO MERGE
