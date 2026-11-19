# Lane: Pairing (S4: persistent pairing with a code or QR, and "Forget device")

Branch `claude/pixelhand-lane-pairing`, cut from
`claude/pixelhand-integration` and merged with it again at `d6f2d76` (tick 2)
right before hand-off. Written in a Linux container: PixelHandCore was built
and tested with Swift 6.2; the apps were not compiled, but the Mac pairing
files, the iOS pairing store and the session-model extension were
type-checked on Linux against stubs (§5). The Mac build must run §6.

## 1. What changed

### How trust works now

- **Trust anchor: the Loom identity key** that the peer proved in the
  handshake (`LoomPeerIdentity.identityKeyID`, read from
  `handle.session.context`, never from Bonjour or a message).
- **A record is matched on the key and the Loom device ID together.** The
  device ID is signed by that key in Loom's hello, so it is as proven as the
  key. This matters because Loom's account key lives in iCloud Keychain by
  default: one owner's iPad and iPhone can present the same key, and pairing
  or forgetting one must not pair or forget the other. A device that shows a
  known device ID with another key is a stranger; re-pairing a device with a
  new key (reinstall) replaces its old record.
- **Mac decision per connection** (`PairingAdmission`): paired → no prompt;
  allowed earlier this launch → no prompt; otherwise Allow / Deny **or a
  pairing code**; no verified key → refused (Loom's handshake already
  refuses these through `DeckHandHandshakeTrustProvider`).
- **"Allow" still lasts one launch**, but is now remembered per verified
  identity instead of per `LoomPeerID` (a stranger reusing an allowed
  device's ID used to be let in for the rest of the launch).

### Pairing code (all rules in Core, tested)

- Six random digits + a **Damm check digit**, shown `123-4567`
  (`PairingCode`, `DammCheck`). The remote checks the digit while typing, so
  a typo never costs one of the Mac's tries.
- `PairingCodeWindow`: valid **5 minutes**, **pairs one device** (used up on
  the first right answer; replays by any device find no code), **5 wrong
  answers across all devices burn the code and lock pairing for 60 s** (no
  new code until then), malformed codes on the wire count as wrong, a clock
  jumping backwards ends the code, constant-time compare.
- QR: `PairingInvite` payload
  `pixelhand://pair?v=1&code=…&mac=<device ID>&key=<identity key ID>`. The
  iPad dials the Mac with that device ID and sends the code **only if the
  Mac proved that key**.
- Codes sent while the request is pending go through `PreApprovalGate` to
  the Mac's pairing logic (capped at 8 per pending connection), not the
  message loop.

### Protocol 6 (`PairingMessage`)

`submitCode(code:)` remote → Mac; `codeResult(result:)` Mac → remote
(`accepted`, `wrongCode(attemptsLeft:)`, `lockedOut(retryAfter:)`, `expired`,
`noActiveCode`); `pairedStatus(paired:)` Mac → remote with every grant and on
change; `forget` remote → Mac. Fixtures re-recorded, `PROTOCOL.md` history
line added, `RemoteInputValidation` drops a `submitCode` longer than 32
bytes. `LockPolicy` unchanged (the whole `pairing` domain stays allowed).

**Version clash:** `claude/pixelhand-lane-ios-interaction` and
`claude/pixelhand-lane-mirror-2` also took 6. Whoever merges second
renumbers (version, MANIFEST, history line; `PH_RECORD_FIXTURES=1 swift test
--package-path DeckHand/Core --filter ProtocolContractTests`).

### Files

| Area | File | What |
| --- | --- | --- |
| Core | `Pairing/DammCheck.swift`, `PairingCode.swift`, `PairingCodeWindow.swift`, `PairingInvite.swift`, `TrustList.swift`, `PairingAdmission.swift` (also `RemotePairingBook`) | new |
| Core | `Pairing/PreApprovalGate.swift` | `take(_:)` → `.pass / .drop / .pairingCode`, `onPairingCode` callback |
| Core | `Protocol/PairingMessage.swift`, `Copy/ApprovalStatusCopy.swift` | 4 cases + `PairingCodeResult`; `forgotten` status, code-result and typing copy |
| Core tests | `PairingCodeTests`, `PairingCodeWindowTests`, `TrustListTests`, `PairingGateAndCopyTests` | 56 new tests (278 total) |
| Shared | `Pairing+Loom.swift` (new) | `TrustCandidate(identity:)` (verified key only), `PairedDeviceKind(DeviceType)`, `handle.verifiedPeerIdentity()` |
| Shared | `DeckHandCloud.swift` | comment only: same iCloud is not trust |
| Mac | `Pairing/PairedDeviceStore.swift` (new) | persisted trust list, `~/Library/Application Support/Pixel Hand/PairedDevices.json`, 0600; unreadable file → set aside, start empty (fail closed) |
| Mac | `DeckHandHandshakeTrustProvider.swift` | backed by the store; `grantTrust` pairs, `revokeTrust(for:)` forgets |
| Mac | `DeviceAuthorizationManager.swift` | admission, code window, pending/allowed code handling, Forget (menu and remote), live-session bookkeeping |
| Mac | `Handlers/PairingHandler.swift` | `submitCode`, `forget`; resync also re-sends `pairedStatus` |
| Mac | `Pairing/PairingMenuSection.swift` (new), `MacMenuBarView.swift` | "PAIRED DEVICES" section (Pair a Device…, code + QR + countdown, lockout, list with Forget…), "Pair…" on pending rows, clearer help on the session ✕ |
| iOS | `Pairing/PairedMacsStore.swift`, `PairingCodeEntryView.swift`, `PairingQRScannerView.swift` (new) | paired-Mac book + live session state; code sheet; AVFoundation QR scanner |
| iOS | `Control/ControlSessionModel+Pairing.swift` (new) | approval status + resync poll (moved here), Mac identity, QR invite, `pairedStatus` / forgotten |
| iOS | `AuthorizationOverlay.swift`, `PeerPickerView.swift` | "Enter Pairing Code" while waiting; QR button and "Paired" badge in the picker |
| iOS | `Settings/SettingsPairingSection.swift` (new) | "Paired Macs" with Forget (confirmation) |
| App tests | `DeckHandTests/PairingLoomTests.swift` (new) | 3 Swift Testing tests on the Loom adapter (real P-256 keys) |
| Tooling | `Scripts/linux-typecheck/run.sh`, `Stubs.swift` | the pairing files join the type check (Combine and UserNotifications stubbed) |

No Loom changes: every hook needed already exists.

## 2. Out-of-lane edits

| File | Owner | Edit |
| --- | --- | --- |
| `Core/Input/RemoteInputValidation.swift` | iOS interaction | one `case .pairing(.submitCode)` before `default` (5 lines). Conflicts with that lane's new cases resolve by keeping both. |
| `Core/Protocol/PixelHandProtocol.swift`, fixtures `MANIFEST` + all fixtures (`v` 6), `Core/PROTOCOL.md`, `ProtocolContractTests.swift` | hot spot | version 6, 9 new samples, 4 case names, count 41 → 45 |
| `DeckHandiOS/Control/ControlSessionModel.swift` | hot spot | `// MARK: Pairing` stored properties (the two existing auth fields moved under it, `private` dropped); the resync poll in `run` replaced by `startPairing` / `defer stopPairing()`; the `authorizationStatus` case now calls `handleAuthorizationStatus`, plus `codeResult` and `pairedStatus` cases. Nothing reordered. |
| `DeckHandiOS/SettingsView.swift` | integration | one line: `SettingsPairingSection()` after Connection |
| `DeckHandiOS/PixelMorph.swift` | integration | one line: `forgotten` uses the disconnected glyph |
| `Scripts/linux-typecheck/run.sh`, `Stubs.swift` | shared tooling | 5 files added to the list; strip `Combine` and `UserNotifications` imports; stubs appended |

`ContentRootView.swift`, `MacHostApp.swift`, `MacHandlers.swift`,
`ControlReceiver.swift`, `project.yml` and `TrackpadSender.swift`: untouched.

## 3. Info.plist (integration applies)

iOS `DeckHandiOS/Info.plist`, for the QR scanner:

```xml
<key>NSCameraUsageDescription</key>
<string>Pixel Hand uses the camera only to scan the pairing code your Mac shows.</string>
```

Nothing for the Mac app (it doesn't use the camera; Core Image draws the QR
code). No entitlement changes.

## 4. Mac and iPad checks (owner's Mac build)

Both devices on this build. Watch
`log stream --predicate 'subsystem == "com.widgetsflow.pixelhand"' | grep -E "🔑|🔐"`.

| # | Check | Expect |
| --- | --- | --- |
| 1 | Fresh install, iPad connects | Allow / Deny prompt as before. Waiting card has **Enter Pairing Code**. Menu bar: "PAIRED DEVICES — None yet". Allow connects; Settings › Paired Macs is empty. |
| 2 | Pair with the code while waiting | Mac: pending row **Pair…** shows `123-4567`, a QR code and "Expires in 4:59". iPad: Enter Pairing Code, type it → card turns to Approved without clicking Allow. Mac list shows the iPad ("Connected"); iPad Settings lists the Mac; picker card shows **Paired**. |
| 3 | Reconnect | Disconnect and reconnect: no prompt. Quit and relaunch the **Mac** app: still no prompt. `~/Library/Application Support/Pixel Hand/PairedDevices.json` exists, mode `-rw-------`. |
| 4 | QR from the picker | Forget first (check 9), then Mac: Pair a Device…; iPad picker: QR button → camera prompt (first time) → scan. It dials that Mac and pairs; the waiting card flashes, then Approved. |
| 5 | Typo | Change one digit: the sheet says "Check the code: a digit looks mistyped", **Pair** stays disabled, nothing is sent (Mac attempts unchanged). |
| 6 | Wrong codes | Enter four valid-but-wrong codes (any 6 digits + the right check digit, e.g. `111111` + its digit): "That code didn’t match. 4/3/2 tries left", then "One try left…"; Mac panel shows "N wrong code(s) entered". The 5th: "Too many wrong codes… in 1 minute"; Mac shows "Pairing is paused"; Pair a Device… does nothing until it ends. |
| 7 | Expiry | Leave a code up 5 minutes: the panel clears; a code typed after that → "isn’t showing a pairing code". |
| 8 | One device per code | Pair device A with a code; device B (or A again) enters the same code → "isn’t showing a pairing code". |
| 9 | Forget on the Mac, connected | Paired list → Forget… → Forget. iPad: card **Device Forgotten**; the Mac leaves its Settings list. Reconnect → prompt again. |
| 10 | Forget on the iPad, connected | Settings › Paired Macs → Forget → confirm: same as 9; the Mac's list loses it. |
| 11 | Forget on the iPad, Mac away | Quit the Mac app, Forget in Settings: footer says "One forgotten Mac will be told…". Start the Mac app, connect: it connects, then **Device Forgotten**; the Mac's list loses it; the next connect prompts. |
| 12 | Allow once | Allow (not paired), then ✕ on the connected row: disconnects; reconnect prompts. Allow then reconnect within the same Mac launch: no prompt (as before). |
| 13 | Shared iCloud key | Pair the iPad; the owner's iPhone (same Apple ID) still gets the prompt; forgetting one leaves the other. |
| 14 | Camera off | Deny the camera: the scanner shows "Pixel Hand can’t use the camera" with Open Settings. |
| 15 | Wrong Mac's QR | With two Macs: connect to Mac A, Enter Pairing Code → Scan the QR Code Instead → scan Mac B's QR: "That QR code is from a different Mac". |
| 16 | Locked Mac | Lock the Mac with a paired iPad: it still connects without a prompt; Forget from the iPad still works. |
| 17 | Logs | No "Dropped an undecodable message" lines; `🔐 Paired …`, `🔐 Forgot …` lines as you go. |

Tests:

```sh
swift test --package-path DeckHand/Core          # 278 (56 new); confirms fixtures on Apple's Foundation
xcodebuild … -scheme DeckHandTests … test         # +3 (PairingLoomTests)
```

## 5. Linux verification

```sh
swift test --package-path DeckHand/Core     # ✔ 278 tests in 45 suites passed
DeckHand/Scripts/linux-typecheck/run.sh      # Build complete (now includes DeviceAuthorizationManager,
                                             # DeckHandHandshakeTrustProvider, PairedDeviceStore,
                                             # Pairing+Loom, PairedMacsStore, PairingHandler)
```

`ControlSessionModel+Pairing.swift` was also type-checked once against a
stub of the model (not committed; the stub would drift from the real class).

## 6. Compile risks (most likely first)

1. **`PairingQRScannerView.swift`**: Swift 6 and AVFoundation. The
   delegate method is `nonisolated` and hops with `MainActor.assumeIsolated`
   (delegate queue is `.main`); the session sits in an `@unchecked Sendable`
   box for its start/stop queue. If the SDK marks the delegate protocol
   `@MainActor`, drop `nonisolated` and `assumeIsolated`.
2. **`DeviceAuthorizationManager`**: `override init()` became
   `init(store: PairedDeviceStore = .shared)`; `static let shared =
   DeviceAuthorizationManager()` relies on the default. The gate's
   `onPairingCode` closure is `@Sendable` and hops with
   `Task { @MainActor in … }`. Type-checked only against stubs of
   UserNotifications/Combine.
3. **`PairingMenuSection.swift`**: `CIFilter.qrCodeGenerator()` needs
   `import CoreImage.CIFilterBuiltins` (present); `correctionLevel` is a
   `String`; `Image(nsImage:)`; `Date.formatted(.relative(presentation:))`.
4. **`@Observable` `PairedMacsStore`** read through `private let store =
   PairedMacsStore.shared` in views (Overlay, Settings, code sheet, picker),
   like `RemoteLinkStatus`. `.onChange(of: store.codeResultCount)` uses the
   zero-argument closure (iOS 17).
5. **`SettingsPairingSection`**: `confirmationDialog(_:isPresented:titleVisibility:presenting:actions:message:)`.
6. **`PairedDevice.id` is `PairedDeviceRef`** (Hashable) in `ForEach`.
7. **`Data.WritingOptions.completeFileProtectionUntilFirstUserAuthentication`**
   in `PairedMacsStore.save()` (iOS only; fine on iOS).
8. **`DeckHandTests/PairingLoomTests`** builds `LoomPeerIdentity` with the
   memberwise-style public init (default `advertisementMetadata`) and
   CryptoKit P-256.
9. **Merge conflicts**: `ControlSessionModel.swift` (the resync-poll block
   and the `authorizationStatus` case are now one line each), the protocol
   files (version 6 taken three times), `RemoteInputValidation.swift`.

## 7. Behaviour notes and limits

- **Pending expiry still 45 s.** A device that waits for its code past that
  is answered "timed out"; connect again and enter the same code (it lives
  5 minutes). Scanning the QR from the picker avoids the wait.
- **Code burning.** Any device with a verified Loom key on the network can
  spend the 5 tries and pause pairing for a minute. That is the price of
  the cross-device count; the Mac shows the count so the user can tell.
- **Forgotten while away** (check 11): the Mac auto-grants that one
  connection, hears `forget`, then ends it. The remote can't send anything
  before the Mac decides, so this is the earliest point.
- The Mac's own "Allow" notification is unchanged; pairing is only offered
  in the menu bar panel (a notification can't show a code).

## 8. Notes for S15 (remote access over VPN)

- **Trust store API** (Mac, `PairedDeviceStore.shared`, main actor):
  `admission(for: LoomPeerIdentity?) -> PairingAdmission` (`.autoGrant`,
  `.askUser`, `.refuse`), `isPaired(_ ref:)`, `devices` (published),
  `pair(_:method:)`, `forget(_:)`, `forgetAll(deviceID:)`. The rules are in
  Core `TrustList` / `PairingAdmission` with tests; add VPN policy there
  (for example "remote links admit only `.autoGrant`") and test it on Linux.
- A connection that arrives over a VPN/remote path should be admitted only
  when `admission` is `.autoGrant`: no Allow prompt and no code entry from
  outside the LAN. `DeviceAuthorizationManager.admit(...)` is the one place
  to branch on the link (the Network lane's `HostLinkMonitor` knows it).
- **Pinning the Mac from the remote:** Loom's handshake checks an expected
  peer key (`validateExpectedPeerIdentity` in `LoomAuthenticatedSession`),
  and `LoomConnectionCoordinator` fills it from the key the peer
  *advertised* (`advertisement.identityKeyID`). Over a VPN the
  advertisement may come from elsewhere, so S15 should pin the **stored**
  key from `PairedMacsStore.macs` instead. LoomKit's `connect` takes no
  caller-supplied expected key yet: that is the Loom change S15 would need
  (product-agnostic, with Loom tests).
- Loom's identity key is iCloud-Keychain-synchronizable by default, so a
  key ID can stand for several of one owner's devices; keep matching on
  `(identityKeyID, deviceID)` (`PairedDeviceRef`).

Lane: READY TO MERGE
