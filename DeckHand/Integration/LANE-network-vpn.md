# Lane: Network VPN (S15: remote access over Tailscale or another VPN)

Branch `claude/pixelhand-lane-network-vpn`, cut from
`claude/pixelhand-integration` at `cfa4b0f` and merged with it again at
`5a001fe` (tick 4, S14 merged) right before hand-off. Written in a Linux
container: PixelHandCore was built and tested with Swift 6.2, and the Mac
and iOS files that can be stubbed were type-checked (§6). The apps and the
Loom package were **not** compiled: Loom's `Loom` target needs Apple's
`Security` module, so it doesn't build on Linux (this was already true).

## 1. What it does

- **Reach a paired Mac off the LAN.** Each paired Mac can have saved
  addresses: up to 4 that the Mac itself reports while the two are
  connected (its Tailscale/VPN addresses), and up to 6 the user types
  (Tailscale IP, MagicDNS name, or any VPN address). The iPad hands them
  to Loom's overlay directory, which probes them on Loom's overlay probe
  port; a Mac that answers shows up in the device list as "Remote".
- **Pinned keys.** An off-LAN Mac is dialled only if it is on the iPad's
  pairing list, and Loom's handshake is pinned to the identity key stored
  when it paired (`PairedMacsStore`), never the key the probe answer
  advertised. After the handshake the proven key **and** Loom device ID are
  checked against the pin again. A device ID that advertises a different
  key is refused before dialling ("forget it and pair again").
- **Unpaired devices never get in remotely.** iPad side: an unpaired Mac
  that isn't on Bonjour is refused before any connection. Mac side: a
  connection whose path is a tunnel (`utun`, `wg`, `ipsec`…), comes from a
  Tailscale address (100.64/10, fd7a:115c:a1e0::/48), cellular, or
  loopback (SSH port forward) is admitted only if the device is already
  paired: no Allow prompt, no pairing code from outside the LAN.
- **"Away" quality.** Over a VPN/cellular link, or when the smoothed
  ping/pong round trip reaches 120 ms (back home below 70 ms), the mirror
  request is capped at 15 fps and 1280 px wide with HEVC (960 px if the
  device must use JPEG). Lower user settings are never raised. A running
  mirror re-negotiates when this changes.
- **Shown as "VPN".** `LinkJudge` now also judges a Tailscale peer address
  as `tunnel`; the iPad header badge shows "VPN" (it showed only "Wired"),
  Settings › Connection says so in the footer.
- **Settings › Remote Access** (iOS): one row per paired Mac → its saved
  addresses ("From the Mac" / "Added by you"), swipe to delete, add with
  inline validation, and **Test Connection**, which probes each address and
  reports Reachable / Another Mac / No answer.

## 2. What changed

### Protocol 10 (next free number; integration was at 9)

| Message | Direction | What |
| --- | --- | --- |
| `session.remoteHosts(hosts: [String])` | Mac → paired remote | The Mac's tunnel/Tailscale addresses, at most 4, first ping and then every 5th ping if they changed. Sent only when the connection is paired. The remote re-validates every host and keeps them only for a paired Mac; an empty list clears earlier reports. |

Version 9 → 10, fixtures re-recorded (all `v` change, 2 new samples),
history line in `Core/PROTOCOL.md`, case count 52 → 53. Nothing a remote
sends changed, so `RemoteInputValidation` and `LockPolicy` are untouched.

### PixelHandCore `Network/` (all tested on Linux)

| File | What |
| --- | --- |
| `RemoteHost.swift` | Strict host validation and normalisation: one IPv4/IPv6 literal or DNS name; refuses schemes, ports, paths, users, zones, spaces, non-ASCII, leading-zero octets, loopback, link-local, multicast, broadcast, unspecified. Classifies Tailscale v4/v6, MagicDNS, private, ULA, public, hostname. Own IPv4/IPv6 parser (same answer on every platform). Decoding re-validates. `isOverlayAddress(_:)`. |
| `RemoteHostBook.swift` | Saved hosts per paired Mac (keyed on identity key + device ID): user hosts, Mac reports (replace previous report, never override a user host), limits, `prune`, `seeds(pairedMacs:)` (only Macs still paired), versioned storage. |
| `RemoteAccessPolicy.swift` | `dialPlan` (local / remote pinned / refuse not-paired or key-changed), `verify` (proven key + device ID vs pin), `isRemotePath` and `admission` (Mac), `reportableHosts` (Mac's tunnel addresses), `probeVerdict` (Settings test). |
| `AwayQualityPolicy.swift` | `AwayQualityPolicy` (link + RTT with hysteresis → caps, HEVC preferred) and `RoundTripEstimator` (ping/pong matching, SRTT α = 1/8, bounded). |
| `LinkJudge.swift` | A Tailscale peer address is `tunnel` even when the interface name doesn't say so. |
| Tests | `RemoteAccessTests.swift`: 49 tests in 8 suites (validation, book, pinning, unpaired refusal, Mac admission, reportable hosts, probe verdicts, overlay link judging, away quality). **438 Core tests pass.** |

### Loom (product-agnostic; commit `f78b7fd`)

- New `LoomPeerIdentityPin` (`Sources/Loom/Public/Remote/`): key ID plus
  optional public key; failable init refuses empty/whitespace values;
  `matches(identityKeyID:identityPublicKey:)`.
- `LoomConnectionTarget.pinned(to:)`, `LoomConnectionPlan.pinned(to:)`.
- `LoomConnectionCoordinator.makePlan` and `connect` gain a trailing
  `pinnedPeerIdentity: LoomPeerIdentityPin? = nil` (source compatible):
  every target expects the pin instead of the advertised key; the existing
  handshake check (`validateExpectedPeerIdentity`) enforces it.
- LoomKit: `LoomContext.connect(_:pinnedIdentity:)`. `LoomStore` keeps the
  pin on the managed connection, retries keep it, an existing connection is
  reused only if dialled with the same pin, the proven identity is checked
  once more after connect, and the shared-host runtime refuses pins.
- **Bug fix needed for S15:** `LoomStore` resolved an overlay peer but
  never passed it to the coordinator, so overlay-only peers couldn't be
  dialled at all. It is passed now.
- Tests: `LoomConnectionCoordinatorTests` +4 (pinned plan replaces the
  advertised key on every overlay target; no pin keeps it; pinned connect
  hands the pin to every attempt; pin validation), and
  `LoomAuthenticatedSessionTests` +2 (real loopback handshake: pinned to
  the responder's key succeeds; pinned to another key fails with
  `authenticationFailed`).
- DocC: `LoomPeerIdentityPin` in `Loom.md` topics; new "Pin the identity
  you already trust" section in `UseTailscaleAndCustomOverlays.md`; "Pin
  Identities For Off-LAN Peers" in LoomKit's
  `EnableCloudPeersAndRemoteAccess.md`.

### Mac

- `DeckHandMac/Network/RemoteAccessGate.swift` (new): judges a new
  connection's path (first Loom path snapshot, 2 s cap; peer address
  fallback), narrows the pairing decision with `RemoteAccessPolicy`,
  logs `🔑 Refusing … arrived over a remote path`; the overlay probe
  listener configuration (no seeds); reporting the Mac's VPN addresses.
- `Handlers/SessionHandler.swift`: sends `remoteHosts` to paired sessions
  (first ping, then every 5th if changed); `.remoteHosts` ignored inbound.
- `Network/HostLinkMonitor.swift`: forgets a connection's last report.
- `MacHostApp.swift`: `overlayDirectory: RemoteAccessGate.overlayProbeConfiguration`.

### iPad / iPhone

- `Network/RemoteHostsStore.swift` (new): the book on disk
  (`Application Support/RemoteHosts.json`, complete-until-first-unlock,
  unreadable file → set aside, start empty), overlay seeds (only paired
  Macs; prunes forgotten Macs), `overlayConfiguration` (30 s refresh, 2 s
  probe, 2 attempts).
- `Network/RemoteConnect.swift` (new): the picker's dial (§1).
- `Network/RemoteHostTester.swift` (new): Settings test via a one-off
  `LoomOverlayDirectory` per host.
- `Network/RemoteLinkStatus.swift`: `isAway`; the badge shows "VPN".
- `Control/ControlSessionModel+Network.swift`: RTT samples from pings and
  pongs (reset on resume), away policy fed by the link and RTT,
  `applyRemoteHosts`, `sendMirrorStart` (the away-adjusted `mirror.start`,
  resets the HEVC watchdog if the away policy switches codec).
- `Settings/SettingsConnectionSection.swift`: footer for VPN / slow link,
  and the Remote Access section + per-Mac page.
- `DeckHandApp.swift`: `overlayDirectory: RemoteHostsStore.overlayConfiguration`.

## 3. Out-of-lane edits (all small)

| File | Owner | Edit |
| --- | --- | --- |
| `DeckHandMac/DeviceAuthorizationManager.swift` | Pairing | In `handleIncomingConnection`'s task: 2 lines + comment. `RemoteAccessGate.allows(...)`; when it says no, `admit` is called with `identity: nil`, which takes the existing refusal path (denied + disconnect). |
| `DeckHandiOS/PeerPickerView.swift` | Pairing | One line: `loomContext.connect(peer)` → `RemoteConnect.connect(peer, using: loomContext)`. |
| `DeckHandiOS/Control/ControlSessionModel+Mirror.swift` | Mirror | The one `mirror.start` line, at its two call sites (`toggleMirror`, `restartMirror`): `sender.startMirror(…)` → `sendMirrorStart(sender, …)`, same arguments. Nothing else. |
| `DeckHandiOS/Control/ControlSessionModel.swift` | hot spot | §2.7 rule: 3 stored props under `// MARK: Network`; the pong case binds `seq` and calls `notePong`; one `case .session(.remoteHosts)` in `handleOnMain`. |
| Protocol hot spot | | `PixelHandProtocol.version` 10, `MANIFEST`, fixtures, `PROTOCOL.md` table + history, `ProtocolContractTests` samples/case name/count. |
| `Scripts/linux-typecheck/run.sh`, `Stubs.swift` | tooling | 4 files added to the list; stubs for `LoomAuthenticatedSession`, `makePathObserver`, overlay types, `LoomPeerSnapshot`, `LoomPeerIdentityPin`, `LoomContext.connect`. |

`project.yml`, entitlements: no changes (new files are in existing folders).

## 4. Info.plist (integration applies)

None needed. Both apps already declare `NSLocalNetworkUsageDescription` and
`NSBonjourServices`; the overlay probe and the VPN dial are ordinary
unicast TCP. If iOS shows no Local Network prompt for a 100.x address,
that's expected (Tailscale addresses aren't "local network").

## 5. Mac and iPad checks (owner's build)

Both devices on this build (protocol 10 doesn't talk to 9). Watch
`log stream --predicate 'subsystem == "com.widgetsflow.pixelhand"' | grep -E "🔑|📡|Remote access|Mirror quality|Link"`.

```bash
cd DeckHand && xcodegen generate
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandMac -destination 'platform=macOS' -allowProvisioningUpdates build
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandiOS -destination 'generic/platform=iOS' -allowProvisioningUpdates build
swift test --package-path Core                                    # 438
cd .. && swift test --scratch-path .build-local --filter "LoomConnectionCoordinatorTests|LoomAuthenticatedSessionTests"
swift test --scratch-path .build-local                            # full Loom suite, previous count + 6
```

| # | Check | Expect |
| --- | --- | --- |
| 1 | LAN regression | Same Wi-Fi, unpaired iPad: Allow prompt and pairing code work as before. Paired: no prompt. Header shows no badge on Wi-Fi. |
| 2 | Tailscale setup | Install Tailscale on both, same tailnet, both online. Pair on the same Wi-Fi first. While connected, iPad Settings › Remote Access › the Mac shows its `100.x.y.z` (and `fd7a:…`) "From the Mac". Mac log: `Remote access: told conn=… about N VPN address(es)`. |
| 3 | **Tailscale test** | Put the iPad on cellular (Wi-Fi off) with Tailscale on. Settings › Remote Access › Mac › Test Connection → "Reachable". Device list shows the Mac as **Remote** within ~30 s. Tap it: connects with **no prompt**; header shows **VPN**; Settings › Connection › Link: VPN. Mac log: `🔑 Remote path (tunnel) from a paired device`. iPad log: `📡 Dialling paired … over a VPN, pinned to its stored key`. |
| 4 | Away quality | During check 3, turn on the mirror: iPad log `Mirror quality: away`; Mac's mirror stats show ≤ 15 fps, ≤ 1280 px, HEVC. Back on Wi-Fi (reconnect): full settings again. |
| 5 | MagicDNS | Add `<mac>.<tailnet>.ts.net` by hand, delete the reported addresses, Test → Reachable; connect works. |
| 6 | Unpaired over VPN (Mac side) | Forget the iPad on the Mac (menu bar). On cellular + Tailscale, tap the still-listed Mac: iPad shows the "Remote access works only with a paired Mac" error **without dialling** (its record was also removed when the Mac said unpaired, so the Mac may simply drop off the list). To test the Mac gate directly, from a second unpaired device on the tailnet: `nc -vz 100.x.y.z <Mac's Loom port>` is fine, but a Pixel Hand connect is refused: Mac log `🔑 Refusing conn=…: not paired, and it arrived over a remote path (tunnel)`, no notification, no pending row. |
| 7 | Wrong Mac at a saved address | Save another tailnet Mac's address (running Pixel Hand, paired or not) for Mac A. Test → "Another Mac answered at this address"; it never connects as Mac A. |
| 8 | Key changed | Reinstall the Mac app with a fresh Loom key (or delete its keychain item), keep the iPad's record: tapping the remote Mac → "answered with a different identity…". |
| 9 | Validation | Add `http://x`, `100.1.1.1:22`, `fe80::1`, `127.0.0.1`, `256.1.1.1`: each shows its inline error and isn't saved. |
| 10 | Forget prunes | Forget the Mac on the iPad: its saved addresses disappear and the overlay stops probing them (no "Remote" Mac in the list). |
| 11 | SSH tunnel (optional) | `ssh -L 9849:127.0.0.1:9849 mac` style forwards arrive on the Mac from loopback. Since VQ-001 loopback counts as this same machine (simulators), so an unpaired device gets the Allow prompt a person at the Mac must answer. (Needs fixed ports; not wired in the UI.) |

## 6. Linux verification

```sh
swift test --package-path DeckHand/Core     # ✔ 438 tests in 75 suites passed
DeckHand/Scripts/linux-typecheck/run.sh      # Build complete (now includes RemoteAccessGate,
                                             # RemoteHostsStore, RemoteConnect, RemoteHostTester)
swiftc -typecheck Sources/Loom/Public/Remote/LoomPeerIdentityPin.swift   # ok
```

## 7. Compile risks (most likely first)

1. **Loom (never compiled here).** `LoomStore.swift`: the new
   `pinnedPeerIdentity` field on the private `ManagedConnection` (memberwise
   init, defaulted `var`), `await session.context?.peerIdentity` on the
   concrete `LoomAuthenticatedSession`, the extra `overlayPeer:` argument.
   `LoomConnectionCoordinator.swift`: `makePlan` now forwards to a private
   `makeAdvertisedPlan`. Tests: `LoomPeerAdvertisement(identityKeyID:deviceType:directTransports:)`
   argument order, `#require` on the failable pin init, `ExpectedIdentityRecorder` actor.
2. **`ControlSessionModel+Network.swift` (UIKit, not type-checked):**
   `sendMirrorStart` uses `MirrorVideoRenderer.hevcDecodeAvailable`,
   `mirrorHEVCFellBack`, `mirrorWatchdog.reset(now: CACurrentMediaTime())`,
   `mirrorLastRequestedCodec` and `sender.startMirror(…, windowID:)` from the
   Mirror lane; `renegotiateMirror(settings:)` with the `weak` `mirrorSettings`.
3. **`RemoteAccessGate.swift`:** `await handle.session` (cross-module actor
   `let`), `session as? LoomAuthenticatedSession` then
   `await authenticated.backendRemoteEndpoint`, `withTaskGroup` over the
   path stream, a `static var` dictionary on a `@MainActor` enum.
4. **`SettingsConnectionSection.swift`:** two `Section`s in one `body`
   (fine in the `Form`), `NavigationLink` into `RemoteAccessMacView` (inside
   Settings' `NavigationStack`), `.onDelete`, `.keyboardType(.URL)`,
   `.textSelection(.enabled)`, `AnyShapeStyle(.red)`.
5. **`RemoteHostsStore.overlayConfiguration`**: a `static let` on a
   `@MainActor` class whose `@Sendable` seed closure does
   `await MainActor.run { … }`; read from `DeckHandApp.init`.
6. **Overlay probe listener on both apps.** Setting `overlayDirectory`
   makes LoomKit open Loom's overlay probe listener (default port) on the
   Mac **and** the iPad. If the port is busy the container may log a probe
   listener error; Loom keeps running without it.

## 8. Notes and limits

- No relay: both devices must reach each other on the VPN (Tailscale
  direct or DERP-relayed is fine). Remote signaling stays inert.
- The probe answer isn't proof; the pinned handshake is. "Reachable" in the
  test means the right Mac *advertises* there.
- The Mac reports addresses only to paired sessions. A Mac without a VPN
  sends an empty list, which clears earlier reports (user hosts stay).
- "Away" by RTT alone needs a few pings (SRTT), so it settles in ~10–20 s;
  a VPN link switches at once.
- Multi-Mac (1.3) can reuse `RemoteHostBook` as is (keyed per Mac).

Lane: READY TO MERGE
