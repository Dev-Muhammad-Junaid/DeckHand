# Pixel Hand wire protocol

The Mac and every remote exchange `ControlMessage`s: JSON objects with the
protocol version and exactly one domain key.

```json
{"input":{"mouseDelta":{"dx":1.5,"dy":-2.25}},"v":2}
```

- Envelope: `Sources/PixelHandCore/Protocol/ControlMessage.swift`.
- Version: `PixelHandProtocol.version`, also advertised in the Bonjour TXT
  key `ph-proto` so `PeerCompatibility` can say "Please update" before
  dialling.
- Role: the TXT key `ph-role` (`mac` or `remote`, `PeerRole`) says which
  app is advertising, so a remote lists only Macs. Additive (no version
  bump): a peer without it falls back to Loom's advertised device type.
- Domains, one file each in `Sources/PixelHandCore/Protocol/`:

| Domain | File | What | Lane |
| --- | --- | --- | --- |
| `input` | `InputMessage.swift` | pointer, scroll, clicks, drags (`mouseDown`/`mouseUp`), chords, typed text, media keys | iOS interaction |
| `system` | `SystemMessage.swift` | Mission Control, Spaces, Show Desktop, Launchpad, Locate; Mac → remote: display/Spaces snapshot, lock state | Mac system control |
| `apps` | `AppsMessage.swift` | app list, running and frontmost app, dialog context | Mac system control (context side) |
| `deck` | `DeckMessage.swift` | menu-shortcut import, `run` / `receipt`; the `Action` model in `Deck/Action.swift` | Deck 2 model |
| `mirror` | `MirrorMessage.swift` | mirror start/stop, display list, single-window mirror (S14), the Mac's sound on/off (S17) | Mirror |
| `capture` | `CaptureMessage.swift` | screenshots, window list | Mirror |
| `pairing` | `PairingMessage.swift` | approval handshake; S4 pairing | Pairing |
| `session` | `SessionMessage.swift` | ping/pong, keep-alive `tick`, `link`, `remoteHosts`, `hostStatus` | Network |
| `sharing` | `SharingMessage.swift` | clipboard text sync (S10); transfer status (S1: refused why, saved where) | iOS interaction (S10), Sharing (S1) |
| `diagnostics` | `DiagnosticsMessage.swift` | mirror stats both ways (S6), with audio fields (S17) | Mirror |

- Bulk binary data never goes in the envelope. Mirror video and the
  Mac's cursor ride their own Loom stream, `PixelHandStream.mirror`, which
  the Mac opens towards a remote after `mirror.start`, framed by
  `BinaryFrameHeader` (`Protocol/BinaryFrame.swift`; cursor payloads in
  `Mirror/MirrorCursor.swift`). The host announces it with
  `ProtocolFeature.binaryMirrorStream` in `HostStatus`. Adding a frame
  kind or changing a payload layout is a protocol change like any other:
  bump the version and add a history line.
- Transfers (S1) use Loom's transfer engine (`LoomConnectionHandle.transferEngine`):
  its own control stream and one data stream per transfer, chunked,
  windowed, resumable from a contiguous offset and SHA-256 checked. The
  offer's metadata carries a `TransferManifest` (`ph.kind`, `ph.m`;
  `Transfer/TransferManifest.swift`); the receiver answers in
  `sharing.transferStatus`. Changing the manifest keys or kinds is a
  protocol change.
- The Mac's sound (S17) rides a second stream, `PixelHandStream.audio`,
  which the Mac opens after `mirror.audio(enabled: true)`. Same header;
  `audioFormat` then `audioPacket` frames (payloads in
  `Audio/MirrorAudio.swift`), so a 20 ms packet never waits behind a
  video key frame.

## Changing the protocol

1. Add or change the case in **your domain's file only**. Label every
   associated value (`case foo(bar: Int)`), so the JSON keys are names, not
   `_0`.
2. Name the case in `ProtocolContractTests.caseName(_:)` (the compiler
   stops you until you do), add a sample to `samples`, and update
   `expectedCaseCount`.
3. Bump `PixelHandProtocol.version` by one and add a line to the history
   below.
4. Record the fixtures and review the JSON in the diff:

   ```sh
   PH_RECORD_FIXTURES=1 swift test --package-path DeckHand/Core --filter ProtocolContractTests
   swift test --package-path DeckHand/Core
   ```

5. Handle it on both sides: the Mac's handler for the domain
   (`DeckHandMac/Handlers/`) and the remote's session model.
6. If a remote can send it, check its numbers and strings in
   `RemoteInputValidation.sanitize(_:)`.

**Protocol changes merge one at a time.** Rebase on the integration
branch, take the next version number, re-record, run the Core tests, merge.
Two branches that both bumped to the same version conflict in
`PixelHandProtocol.swift`, `MANIFEST` and this file; the second one rebases,
takes the next number and re-records.

A new **domain** is the only change that touches `ControlMessage.swift`:
one case, one key, one decode line.

## History

| Version | Change |
| --- | --- |
| 1 | The flat `ControlMessage` of builds up to the foundation work: no envelope, no version, never advertised. |
| 2 | Envelope with `v` and one domain key; messages split into ten domains. `macroButton(id:)` → `system.run(action: SystemMacro)`; `mediaCommand(action: String)` → `input.media(key: MediaKey)`; `authorizationStatus(status: String)` → `pairing.authorizationStatus(state: AuthState)`; `hostCapabilities` + `hostFeatures` → `session.hostStatus`; `tracked`/`commandReceipt` → `deck.run(requestID, Action)` / `deck.receipt(requestID, ActionOutcome)`; mirror errors get `mirror.error` instead of `screenshotError("mirror")`; `startMirror`/`stopMirror`/`mirrorFrame`/`displayListUpdate` → `mirror.start`/`stop`/`frame`/`displayList`. Every field is required (no back-compat defaults). `ph-proto` advertised in Bonjour TXT. |
| 3 | `session.tick` (remote → Mac, every 0.25 s while in front on a link that dozes; no answer, stamped and dropped by `HeartbeatResponder`) and `session.link(kind: LinkKind)` (Mac → remote, the Mac's link judgement, for example `wired` over a USB cable). Network lane, S1 and S13. |
| 4 | `system.displayState(layout: DisplayLayout)`: displays, their Spaces (current index, full-screen apps) and the pointer's display, sent on connect and on every change; `system.lockState(state: MacLockState)`, sent on connect and on every change; `RefusalReason.macLocked` for runs the locked-Mac gate refuses. Mac → remote only; nothing a remote sends changed. |
| 5 | Mirror frames leave the control stream: `mirror.frame` removed; JPEG frames, the cursor position (`cursor`) and pointer images (`cursorShape`) travel on `PixelHandStream.mirror` in `BinaryFrameHeader` frames, and the Mac captures without the pointer (S3). `diagnostics` domain activated: `mirrorStats` (Mac → remote) and `mirrorClientStats` (remote → Mac) (S6). `binaryMirrorStream` announced in `hostStatus`. New `mirror.moveCursor(displayID:)` brings the pointer to a display. |
| 6 | HEVC mirror (S5): `mirror.start` gains a required `codec: MirrorCodec` (`jpeg` or `hevc`); new `mirror.requestKeyFrame` (remote → Mac). On the binary stream the `hevcParameterSets` / `hevcKeyFrame` / `hevcDeltaFrame` kinds now carry video (payloads in `Mirror/MirrorVideo.swift`). |
| 7 | iOS interaction lane. `input.typeText(text:)` (Unicode text, ≤ 4 KB a message, cleaned of control characters by `RemoteInputValidation`); `input.mouseDown(button:)` / `input.mouseUp(button:)` for click-drag (a held button is refreshed by repeating `mouseDown`; the Mac releases it on disconnect or after 5 s unrefreshed). `sharing` domain activated: `clipboardSync(enabled:)` and `setClipboard(text:paste:)` (remote → Mac), `macClipboard(text:)` (Mac → remote), text only, ≤ 64 KB. Lock gate: `mouseUp` always allowed, typed text and drags follow `input`, `setClipboard` refused while locked. S11 gestures use the existing `system.run` / `system.switchSpace`. |
| 8 | Persistent pairing (S4): `pairing.submitCode(code:)` (remote → Mac, accepted while the request is pending: the pre-approval gate hands it to the pairing logic), `pairing.codeResult(result: PairingCodeResult)` (`accepted`, `wrongCode(attemptsLeft:)`, `lockedOut(retryAfter:)`, `expired`, `noActiveCode`), `pairing.pairedStatus(paired:)` (Mac → remote, with every grant and on change) and `pairing.forget` (remote → Mac). Trust is keyed on the Loom identity key, never on message content. |
| 9 | Single-window mirror (S14): `mirror.start` gains `windowID` (optional `CGWindowID`; `nil` mirrors a display); `mirror.displayList` gains `window: MirroredWindow?` (what the stream shows; sent again when the window is resized); `mirror.error` gains `fallbackDisplayID` (optional; set when a mirrored window closed, was minimised, left the screen or the Mac locked, and the mirror carries on with that display instead of stopping). The cursor's fractions and `isOnMirroredDisplay` then refer to the window. Lock gate: a window mirror is refused while locked. |
| 10 | Remote access over a VPN (S15): `session.remoteHosts(hosts: [String])`, Mac → paired remote only, the Mac's own addresses on tunnel interfaces and Tailscale's ranges (at most 4), for reaching it when Bonjour can't. The remote re-validates each host (`RemoteHost.parse`) and keeps them only for a paired Mac. `session.link` reports `tunnel` for a Tailscale peer address too. Nothing a remote sends changed. |
| 11 | The Mac's sound while mirroring (S17): `mirror.audio(enabled:)` (remote → Mac; off by default) and `mirror.audioError(message:)` (Mac → remote; the mirror carries on). Audio travels on its own Loom stream, `PixelHandStream.audio` (`pixelhand.audio`), in `BinaryFrameHeader` frames of the new kinds `audioFormat` (7) and `audioPacket` (8) (payloads in `Audio/MirrorAudio.swift`: AAC-LC, or 16-bit PCM when the Mac has no AAC encoder). `MirrorHostStats` and `MirrorClientStats` gain an optional `audio` (packets sent/dropped and data rate; packets received/lost/late, underruns, buffer depth, target and jitter). Lock gate: `audio(enabled: true)` follows `mirror.start` (refused off console). |
| 12 | Deck 2 actions (D1): `Action` gains `menuCommand(bundleID:path:)` (press a menu item by its titles through AX), `macShortcut(name:)` (run a Shortcuts.app shortcut, ≤ 15 s) and `sequence(steps:)` (`SequenceStep` = `run(action:)` or `delay(milliseconds:)`; ≤ 20 steps, no nesting, refused while decoding). They run only through `deck.run`, answered with one receipt: `completed`/`failed` when known within 1.2 s, else `delivered`. `RemoteInputValidation` bounds every new string and number (`ActionValidation`); lock gate: `menuCommand` and `macShortcut` refused while locked, a `sequence` only when every step may run, re-checked per step. No message cases added or removed. |
| 13 | Transfers (S1): `sharing.transferStatus(transferID:status:)`, both ways, from the receiver of a Loom transfer to its sender: `awaitingApproval`, `refused(reason:)` (`declined`, `macLocked`, `notPaired`, `needsPro`, `tooLarge`, `noSpace`, `unsupported`), `saved(landing:)` (`downloads`, `browser`, `clipboard`, `inbox`) or `failed(reason:)` (`integrity`, `writeFailed`, `interrupted`, `cancelled`). Files, photos, links and text travel through Loom's transfer engine with a `TransferManifest` in the offer metadata (`ph.kind` = `file`/`photo`/`link`/`text`, `ph.m` = `1`); caps and prompts in `TransferPolicy`. `RemoteInputValidation`: UUID and closed enums only, passed through; the offer's fields are checked by `TransferManifest.read`. Lock gate: `transferStatus` allowed; incoming transfers refused while locked or off console (`LockPolicy.allowsIncomingTransfer`). |
| 14 | Refusal reasons (QA flows, VQ-002): `pairing.refused(reason:)`, Mac → remote, sent just before `authorizationStatus(.denied)`: `declined` (a person clicked Deny), `timedOut`, `notPairedRemote` (not paired and from another network), `unverified` (no proven identity key), `replaced` (a newer request from the same device). Pairing codes (`pairing.submitCode`, the QR invite) are now eight digits, seven random and a Damm check digit, shown "4821 0934". Nothing a remote sends gained a case; `RemoteInputValidation` unchanged. |
| 15 | Typed text on keys (owner testing build 25, OT-8): `Action` gains `typeText(text:)`, so a deck key, or a step of a `sequence`, types text into the app in front. It stands for `input.typeText` (`Action.message`): a top-level run goes through the input handler and `TypingQueue` and is answered `delivered`; inside a sequence it is queued in order with the chords around it, and the next step waits until the Mac has typed it. `RemoteInputValidation`: the text must be 1 … 4 096 UTF-8 bytes, not only spaces, and already normalized (`TypingText.normalized`: `\n` and `\t` only, no other control characters), or the run is dropped whole. Lock gate: follows `input.typeText`. Remotes: a key that types always asks first (`DeckKey.asksFirst`). No message cases added or removed. |
