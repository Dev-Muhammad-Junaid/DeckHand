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
- Domains, one file each in `Sources/PixelHandCore/Protocol/`:

| Domain | File | What | Lane |
| --- | --- | --- | --- |
| `input` | `InputMessage.swift` | pointer, scroll, clicks, chords, media keys | iOS interaction (remote), Mac system control (`InputHandler`) |
| `system` | `SystemMessage.swift` | Mission Control, Spaces, Show Desktop, Launchpad, Locate | Mac system control |
| `apps` | `AppsMessage.swift` | app list, running and frontmost app, dialog context | Mac system control (context side) |
| `deck` | `DeckMessage.swift` | menu-shortcut import, `run` / `receipt` | deck (later), iOS interaction for now |
| `mirror` | `MirrorMessage.swift` | mirror start/stop/frames, display list | Mirror |
| `capture` | `CaptureMessage.swift` | screenshots, window list | Mirror |
| `pairing` | `PairingMessage.swift` | approval handshake; S4 pairing | Pairing |
| `session` | `SessionMessage.swift` | ping/pong, `hostStatus` | Network |
| `sharing` | `SharingMessage.swift` | reserved: clipboard (S10), files | iOS interaction (S10) |
| `diagnostics` | `DiagnosticsMessage.swift` | mirror stats both ways (S6) | Mirror |

- Bulk binary data never goes in the envelope. Mirror video and the
  Mac's cursor ride their own Loom stream, `PixelHandStream.mirror`, which
  the Mac opens towards a remote after `mirror.start`, framed by
  `BinaryFrameHeader` (`Protocol/BinaryFrame.swift`; cursor payloads in
  `Mirror/MirrorCursor.swift`). The host announces it with
  `ProtocolFeature.binaryMirrorStream` in `HostStatus`. Adding a frame
  kind or changing a payload layout is a protocol change like any other:
  bump the version and add a history line.

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
| 3 | Mirror frames leave the control stream: `mirror.frame` removed; JPEG frames, the cursor position (`cursor`) and pointer images (`cursorShape`) travel on `PixelHandStream.mirror` in `BinaryFrameHeader` frames, and the Mac captures without the pointer (S3). `diagnostics` domain activated: `mirrorStats` (Mac → remote) and `mirrorClientStats` (remote → Mac) (S6). `binaryMirrorStream` announced in `hostStatus`. |
