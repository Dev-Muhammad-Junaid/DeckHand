# Lane: Audio — S17 the Mac's sound on the iPad while mirroring

Branch `claude/pixelhand-lane-audio`, from `origin/claude/pixelhand-integration`
and merged with it up to `5a001fe`. `git diff origin/claude/pixelhand-integration`
shows only this lane's work. Scope: item S17 of the upstream comparison (§4).
Re-implemented from Sill's documented behaviour; no Sill code copied.

Written in a Linux container: PixelHandCore built and tested with Swift 6.2,
and the Mac audio service, its subscriber and the iPad stream reader
type-checked against stubs (§3). **The apps were not compiled.** The Mac
session must run §6 and §7.

## 1. Decisions

**Transport: a separate Loom stream, `pixelhand.audio`** (`PixelHandStream.audio`),
using the existing `BinaryFrameHeader` with two new kinds. It does not use
the mirror stream. Why:

- **Head-of-line blocking.** The mirror stream sends HEVC frames in order,
  with up to two un-acked frames, and a key frame can be hundreds of KB.
  A 20 ms audio packet queued behind one would arrive late and the buffer
  would run dry. On its own stream, audio has its own send queue and drop
  policy.
- **Independent lifecycle.** The mirror's stream and capture are rebuilt
  when the remote picks another display or window (S14) or changes codec.
  Audio would click or stall each time.
- The framing code (`BinaryFrameReader`, header layout and tests) is reused
  unchanged.

**Capture: a separate, audio-only `SCStream`** (`DeckHandMac/Audio/MirrorAudioCapture.swift`).
It is not the mirror's `SCStream`, for the same lifecycle reason. Also, the
mirror's window filter (S14) would capture only that window's app sound. The
audio stream's filter is the main display with nothing excluded, so it
captures every app. `excludesCurrentProcessAudio` leaves out Pixel Hand's own
sound. The format is 48 kHz stereo. The stream also asks for a 2×2 picture
once a second, which is thrown away, because ScreenCaptureKit always
captures video.

**Codec: AAC-LC** through `AVAudioConverter`: 1024 frames a packet
(21.3 ms), 128 kb/s stereo, with the magic cookie in the format frame.
If no AAC encoder can be made, it falls back to 16-bit PCM in 960-frame
(20 ms) packets, about 1.5 Mb/s. For an A/B test by ear, the Mac can be
forced to PCM with
`defaults write com.widgetsflow.pixelhand.mac MirrorAudioCodec pcm16`.
Opus wasn't used: Apple's AudioToolbox Opus *encoder* isn't documented or
guaranteed, and AAC-LC is.

**Audio follows the mirror.** It is off by default. The remote sends
`mirror.audio(enabled: true)` when the mirror opens with the setting on, and
`false` when the mirror closes, the setting goes off, or the app goes to the
background. The Mac also stops audio for a remote in
`MirrorStreamService.stop` (on `mirror.stop`, on disconnect, and off
console), so no audio outlives the mirror.

## 2. What changed

### Protocol 10 (Core)

| Change | Where |
| --- | --- |
| `mirror.audio(enabled: Bool)` (remote → Mac) | `Protocol/MirrorMessage.swift` |
| `mirror.audioError(message:)` (Mac → remote; the mirror carries on) | `Protocol/MirrorMessage.swift` |
| `PixelHandStream.audio = "pixelhand.audio"`; `BinaryFrameHeader.Kind.audioFormat = 7`, `.audioPacket = 8` | `Protocol/BinaryFrame.swift` |
| `MirrorHostStats.audio: MirrorAudioHostStats?` (packets sent/dropped, kb/s) and `MirrorClientStats.audio: MirrorAudioClientStats?` (received, lost, late, underruns, buffer ms, target ms, jitter ms). Both default to `nil`, so existing initialisers compile and existing fixtures' JSON is unchanged apart from `v`. `sanitized()` also cleans the audio fields. | `Mirror/MirrorStats.swift`, `Audio/MirrorAudioStats.swift` |
| The stats line gains `Audio AAC 128 kb/s, 64/60 ms, 2 lost, 1 late, 1 gap` while audio plays | `MirrorStatsLine` |
| Lock gate: `audio(enabled: true)` refused off console (the same as a display `mirror.start`); `audio(false)` and `audioError` allowed | `System/LockPolicy.swift` (§4) |
| Version 9 → **10**, 5 new samples, 2 new cases (`expectedCaseCount` 52 → 54), fixtures re-recorded, history line, domain table, binary-stream paragraph | `PixelHandProtocol.swift`, `MANIFEST`, `PROTOCOL.md`, `ProtocolContractTests.swift` |

### New pure logic (Core, `Audio/`, all tested)

- `MirrorAudio.swift`: `MirrorAudioCodec` (`aacLC`, `pcm16`). It also holds
  the payload layouts, all big-endian:
  - `MirrorAudioFormat`: 12 bytes plus the cookie. Decoding checks the
    codec, 1–2 channels, a rate of 8–96 kHz, 64–4096 frames per packet and
    a cookie of at most 1 KB.
  - `MirrorAudioPacket`: 14 bytes plus the data. It carries the sequence
    number, the sample time and the frame count. Data must be non-empty and
    at most 16 KB.
  - `MirrorAudioPCM16`: encode and decode, with clipping.
- `MirrorAudioJitterBuffer.swift`:
  - `MirrorAudioSequenceTracker`: in order, after a gap (counts the lost
    packets; the decoder resets), or late (dropped). Safe at wrap-around.
  - `MirrorAudioJitterEstimator`: the RFC 3550 interarrival jitter
    estimator, with a pause capped at 1 s.
  - `MirrorAudioJitterPolicy`: the target is one packet plus 3 × jitter,
    clamped to **60–150 ms**. It goes up at once and comes down at 20 ms a
    second. Headroom is 60 ms. Fades last 96 frames.
  - `MirrorAudioJitterBuffer`: a fixed PCM ring that never grows and never
    allocates on push or pull. It prebuffers to the target, then plays
    with a fade-in. When it runs dry it fades out, counts an underrun and
    prebuffers again. A burst above target + headroom is cut back to the
    target from the oldest end and counted as late.
- `MirrorAudioSending.swift`:
  - `MirrorAudioChunker`: turns any capture chunk size into exact packets
    with sample times; a backlog over 1 s is dropped.
  - `MirrorAudioSendQueue`: one send at a time; waiting packets go together;
    at most 4 wait (about 85 ms), and the oldest is dropped beyond that.
- `MirrorAudioStats.swift`: the stats types, `MirrorAudioHostCounter`, and
  `MirrorAudioClientStats.make`, which converts trimmed frames to late
  packets.

### Mac (`DeckHandMac/Audio/`, new)

- `MirrorAudioService` (main actor):
  - Keeps the listening remotes. Start and stop are serialised with
    `SerialTaskQueue`.
  - Starts one capture for the first remote and stops it after the last.
  - Delivers packets in order through `DispatchQueue.main.async` +
    `MainActor.assumeIsolated`.
  - If the capture fails to start or stops, every remote gets
    `mirror.audioError` and its stream is closed.
  - `takeStats(subscriberID:elapsed:)` supplies the audio part of the
    mirror's per-second stats.
- `MirrorAudioSubscriber`: one remote's `pixelhand.audio` stream and its
  send queue. The format frame goes ahead of the next batch whenever it
  changed, and is never dropped.
- `MirrorAudioCapture`: the audio-only `SCStream` (§1). Planar or
  interleaved Float32 `CMSampleBuffer` → interleaved stereo (mono is
  doubled, extra channels are dropped) → encoder → packets, all on its own
  queue.
- `MirrorAudioEncoder`: `MirrorAudioChunker` → `AVAudioConverter` (AAC-LC),
  or PCM16.
- `Handlers/MirrorHandler.swift`: the `.audio(enabled:)` case; `.audioError`
  is Mac → remote only.
- `MirrorStreamService.swift`: `stop(subscriberID:)` also stops that remote's
  audio, and `sendStatsIfDue` fills `stats.audio`.

### iPad

- `DeckHandiOS/Audio/MirrorAudioReceiver.swift`: its own reader for
  `pixelhand.audio` streams, one task per stream, drained to the end.
  Packets before a valid format are ignored. Overlapping streams are told
  apart by `ObjectIdentifier`.
- `DeckHandiOS/Audio/MirrorAudioDecoder.swift`: AAC-LC through
  `AVAudioConverter` (cookie set on the compressed `AVAudioFormat`), or PCM16.
  `reset()` after a gap.
- `DeckHandiOS/Audio/MirrorAudioPlayer.swift`:
  - The sequence check, jitter estimate and decode happen under
    `decodeLock`.
  - `MirrorAudioJitterBuffer` is guarded by an `os_unfair_lock`.
  - Playback is an `AVAudioEngine` with an `AVAudioSourceNode` that pulls
    from the buffer into a preallocated scratch buffer. The render thread
    doesn't allocate.
  - The audio session is `.playback` with `.mixWithOthers` and a preferred
    IO buffer of 10 ms. It is active only while sound is wanted and a
    stream is open.
  - After an interruption ends, the engine restarts. A route change
    (`AVAudioEngineConfigurationChange`) rebuilds the engine.
- `Control/ControlSessionModel+Audio.swift`:
  - Audio is wanted while the mirror is open, the setting is on and the
    app is not in the background.
  - `syncMirrorAudio()` sends `mirror.audio(enabled:)` and arms the player
    when that changes: the mirror is toggled, the Mac stops the mirror,
    the setting changes, or the app goes to the background or returns.
  - `mirror.audioError` stops the player and shows the passing mirror
    notice. The next change retries.
  - The reader runs next to the mirror's (`runMirrorReceiver` uses
    `async let`). Disconnecting stops playback.
- `ControlSessionModel+Mirror.swift`:
  - `toggleMirror` and the stop path of `handleMirrorError` call
    `syncMirrorAudio()`.
  - The stats loop adds `stats.audio`.
  - `showMirrorNotice` is now internal.
- `Mirror/MirrorOverlay.swift`: `.onChange(of: settings.mirrorPlaysMacAudio)`
  → `syncMirrorAudio()`.
- `Mirror/MirrorStreamReceiver.swift`: the switch covers the two audio kinds
  and ignores them on the video stream.
- Settings › Live mirror: a new **Play the Mac's sound** toggle, off by
  default (`mirrorPlaysMacAudio`, key `settings.mirrorPlaysMacAudio`), and
  a footer sentence.

## 3. Tests (Linux)

```sh
swift test --package-path DeckHand/Core     # ✔ 417 tests in 74 suites (integration: 389)
DeckHand/Scripts/linux-typecheck/run.sh     # Build complete, no errors
```

New: `MirrorAudioTests.swift` has 7 suites and 28 tests:

- framing: round trips and refusals;
- sequence tracking: gaps, late packets, wrap-around, restart;
- the jitter estimator and target;
- the jitter buffer: prebuffer, fade, underrun, burst trim, bounded,
  order across the ring's wrap, adaptive target, reset;
- the chunker and its backlog;
- the send queue: batching, drop-oldest;
- the stats and stats line;
- the lock gate: same as `mirror.start` in every state;
- validation pass-through.

There are also 5 new contract samples.

Type-checked: `MirrorAudioService`, `MirrorAudioSubscriber` (Mac),
`MirrorAudioReceiver`, `MirrorStreamReceiver` (iPad), plus the handlers.
Only parsed (`swiftc -parse`), because AVFoundation, ScreenCaptureKit,
CoreMedia and SwiftUI can't be stubbed sensibly: `MirrorAudioCapture`,
`MirrorAudioEncoder`, `MirrorAudioDecoder`, `MirrorAudioPlayer`,
`ControlSessionModel(+Audio, +Mirror)`, `MirrorOverlay`,
`MirrorStreamService`, the settings files.

## 4. Out-of-lane edits

| File | Owner | Edit |
| --- | --- | --- |
| `Core/System/LockPolicy.swift` | Mac system control | One `case let .audio(enabled): return enabled && offConsole ? .refuse(reply: .none) : .allow` in the mirror switch, and `.audioError` added to the existing allow list (`.stop, .requestKeyFrame, .displayList, .error`). Announced in the brief. |
| `Core/Protocol/PixelHandProtocol.swift`, `MANIFEST`, every fixture's `v`, `PROTOCOL.md` | hot spot | Version 10, doc comment lines for 9 and 10, history line, domain-table wording, binary-stream paragraph |
| `Core/Tests/…/ProtocolContractTests.swift` | shared | 5 samples, 2 case names, `expectedCaseCount` 54 |
| `DeckHandiOS/Control/ControlSessionModel.swift` | hot spot (Mirror section) | One stored property under `// MARK: Mirror` (`@ObservationIgnored let mirrorAudio = MirrorAudioPlayer()`); one new case in `handleOnMain`: `.mirror(.audioError(message))` → `handleMirrorAudioError`. No new loop: the audio stream is a separate Loom stream read in this lane's own code. |
| `DeckHandiOS/DeckHandSettings.swift` | hot spot | `mirrorPlaysMacAudio` under `// MARK: Mirror (lane)`, its key, and its load (`defaults.bool`, so off by default) |
| `Scripts/linux-typecheck/Stubs.swift`, `run.sh` | integration | A `MirrorAudioCapture` stub; three audio files added to the default list |

`RemoteInputValidation` was **not** edited: `mirror.audio(enabled:)` has
only a Bool and goes through the `default` pass-through (a test checks
this), and the audio stats are cleaned in `MirrorClientStats.sanitized()`.
There are no `project.yml`, Info.plist, entitlement or Loom changes. The
new folders `DeckHandMac/Audio/` and `DeckHandiOS/Audio/` are picked up by
folder, but need `xcodegen generate`.

**Info.plist keys: none.** No `UIBackgroundModes` audio: sound stops in the
background on purpose (the brief prefers this, and a backgrounded mirror
shows nothing). On the Mac, ScreenCaptureKit audio uses the existing
Screen Recording permission; it doesn't need the microphone.

## 5. Protocol version at merge

Integration is at 9; this lane takes **10**. The **Network VPN lane
(`claude/pixelhand-lane-network-vpn`) also took 10.** Whichever merges
second: keep both sides' changes, take 11, merge the history lines and the
`PixelHandProtocol` doc comment, set `expectedCaseCount` to integration's
count + the new cases (this lane adds 2: `mirror.audio`,
`mirror.audioError`), then
`PH_RECORD_FIXTURES=1 swift test --package-path DeckHand/Core --filter ProtocolContractTests`
and `swift test --package-path DeckHand/Core`. Also watch for another lane
adding a `BinaryFrameHeader.Kind`: the next free raw values are 9 and up,
and the switches in `MirrorStreamReceiver` and `MirrorAudioReceiver` are
exhaustive.

## 6. Mac build: compile risks (most likely first)

1. **`MirrorAudioEncoder`, `converter.magicCookie`**: if
   `AVAudioConverter` has no `magicCookie` on this SDK, use `Data()`
   instead. An AAC-LC decoder works from the stream description alone.
   - `AVAudioCompressedBuffer(format:packetCapacity:maximumPacketSize:)`.
   - `output.packetDescriptions` (`UnsafeMutablePointer<AudioStreamPacketDescription>?`).
   - `output.data.advanced(by:)` (`UnsafeMutableRawPointer`).
   - The input block captures a local `var supplied`. If Swift 6 calls
     `AVAudioConverterInputBlock` `@Sendable`, wrap the flag in a small
     final class.
2. **`MirrorAudioDecoder` (iOS)**, the same input-block point, plus:
   - `input.byteLength = …` (settable since iOS 11);
   - `input.packetDescriptions?.pointee = …`;
   - `compressed.magicCookie = …` on a `let` `AVAudioFormat`.
3. **`MirrorAudioCapture`**:
   - `CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer` with
     `bufferListSizeNeededOut:`, then with `bufferListOut:` (the labels
     the Swift overlay imports);
   - `kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment` (`UInt32`
     flags);
   - `CMAudioFormatDescriptionGetStreamBasicDescription(…)?.pointee`;
   - `sampleBuffer.isValid`;
   - `config.sampleRate`, `channelCount`, `excludesCurrentProcessAudio`
     (macOS 13+);
   - `queue.async { [self] in encoder = nil }` from `stop()`.
4. **`MirrorAudioPlayer`**:
   - The `AVAudioSourceNode(format:renderBlock:)` closure signature
     `(UnsafeMutablePointer<ObjCBool>, UnsafePointer<AudioTimeStamp>,
     AVAudioFrameCount, UnsafeMutablePointer<AudioBufferList>) -> OSStatus`,
     with `[unowned self]`.
   - `os_unfair_lock` through an allocated pointer.
   - `interleaved.update(repeating: 0)`.
   - `.AVAudioEngineConfigurationChange` (`Notification.Name`).
   - The `@unchecked Sendable` class's notification closures capture
     `self` strongly after `guard let self`.
5. **`ControlSessionModel+Audio`**: `MainActor.assumeIsolated { self?… }`
   inside `addObserver` blocks; `observers.forEach(center.removeObserver)`
   in a `defer` of an `async` main-actor method; `async let audio: Void =
   runMirrorAudio()` in `runMirrorReceiver`.
6. **`MirrorAudioService`**: the `capture.onFailure = { [weak capture]
   message in guard let capture … }` closure; `DispatchQueue.main.async {
   MainActor.assumeIsolated { … } }`.
7. `MirrorStatsLine` and the stats initialisers: the new defaulted `audio:`
   parameter is last, so existing call sites are unchanged.

## 7. What the owner's Mac build must check

```bash
git fetch origin claude/pixelhand-lane-audio   # or the integration merge
cd DeckHand && xcodegen generate                # new Audio/ folders on both apps
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandMac -destination 'platform=macOS' -allowProvisioningUpdates build
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandiOS -destination 'generic/platform=iOS' -allowProvisioningUpdates build
swift test --package-path Core                  # expect 417 (more after other lanes)
```

Both devices must run this build (protocol 10 or the renumbered one).
Turn on Settings › Live mirror › **Show stream stats** and **Play the Mac's
sound**.

| Area | Check |
| --- | --- |
| Off by default | Fresh install: the toggle is off. Open the mirror: no sound, no `Audio` part in the stats, and the Mac log shows no "Mirror audio started". |
| On | Turn the toggle on while mirroring and play music on the Mac: sound on the iPad within about 0.5 s. The stats line shows `Audio AAC ~128 kb/s, ~60/60 ms`, with lost/late/gaps at or near 0 on good Wi-Fi. The Mac log shows `Mirror audio: AAC at 48000 Hz` and `Mirror audio started`. Turn it off: silence within about 0.2 s, and the Mac logs "Mirror audio stopped". |
| Mix and silent switch | While Music plays on the iPad, the Mac's sound mixes with it (it doesn't stop it). With the silent switch on, the Mac's sound still plays, like a video. |
| Pixel Hand's own sound | Not echoed back: a Pixel Hand Mac notification sound or alert isn't in the stream. |
| Latency by ear (clap video) | Play a clap or metronome video on the Mac with the Mac's speakers on and the iPad next to them. You should hear a short echo, about 120–200 ms (AAC adds about 40–80 ms for encode and decode, plus the 60 ms buffer and the output buffer). Then force PCM (`defaults write com.widgetsflow.pixelhand.mac MirrorAudioCodec pcm16`, relaunch the Mac app): the echo should be about 40–60 ms shorter, and the stats say `Audio PCM ~1536 kb/s`. Then `defaults delete com.widgetsflow.pixelhand.mac MirrorAudioCodec`. Report both by ear; if AAC is clearly too late, PCM on a LAN is a valid default. |
| A/V sync | In the mirror, play a video with visible claps or a talking head (HEVC on). The sound should be roughly with the picture, within about ±100 ms. Audio being a little *behind* the picture is expected (the buffer); if it is clearly ahead, the video path is slower, so note the stats line. |
| Bad link | Walk away from the router or start a big download: the buffer target in the stats rises (up to 150 ms) and there are occasional gaps instead of a growing delay. Come back: within a few seconds the target settles back towards 60 ms. The delay never keeps growing (check by ear after 5 minutes of music). |
| Display / window switch | While sound plays, switch the mirrored display, pick a window (S14), toggle HEVC, pinch the mirror: the sound doesn't stop or click (separate capture and stream). |
| Background | Press Home: the sound stops at once, and the Mac logs "Mirror audio stopped" a moment later. Come back to Pixel Hand with the mirror open: the sound resumes within about 0.5 s. |
| Interruption / route | During playback, trigger Siri or an alarm: the sound pauses and comes back after it. Plug in or connect AirPods: the sound moves to them, after at most a short gap. |
| Close mirror / disconnect | Close the mirror: sound stops. Quit the Mac app or walk out of range: sound stops on the iPad. Reconnect and open the mirror: the sound comes back without touching the toggle. |
| Locked Mac | Lock the Mac (⌃⌘Q) while sound plays: sound continues (the lock screen still mirrors). Fast user switching to another account (off console): mirror and sound stop. Turning audio on while off console is refused (no sound, no error). |
| No permission | Turn off Screen Recording for Pixel Hand, then open the mirror with sound on: the mirror's own error appears. The audio may also post "The Mac's sound couldn't be played here (…)" as a notice; it must not crash. |
| Two remotes | iPad with sound, iPhone without: only the iPad plays. Both with sound: both play; turning one off keeps the other. |
| Regressions | Mirror video, cursor, stats, HEVC fallback, display picker, window mirror all as in build 6. |

## 8. Follow-up lanes

Follow-up lanes: none

- Possible polish, not a lane:
  - a speaker button on the mirror's chrome;
  - AAC-ELD (lower codec delay) if the clap test says AAC-LC is too late;
  - explicit A/V sync from the shared presentation clock (both streams'
    headers carry the Mac's uptime in µs), if the sync check shows a
    lasting offset.
- Audio could also run without the mirror (the Mac doesn't require a
  mirror subscriber). The iPad only asks for it while mirroring, as the
  brief scopes it.

Lane: READY TO MERGE
