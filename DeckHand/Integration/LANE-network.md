# Lane: Network (S1 AWDL off + keep-alive, S13 Wired)

Branch `claude/pixelhand-lane-network`, from `claude/pixelhand-integration`
at `f97b40f`, merged up to `17e2f7a` (latest integration at handoff).
S15 (VPN) isn't started: it waits for Pairing's trust list.

Written in a Linux container. PixelHandCore was built and tested here
(Swift 6.2). The apps were **not** compiled; §4 lists what was type-checked
against stubs and what wasn't.

## 1. What changed

### Protocol: version 3 (next free number at handoff)

| Message | Direction | What |
| --- | --- | --- |
| `session.tick` | remote → Mac | Every 0.25 s while the session is in front on a link that dozes (Wi-Fi, or not yet judged). Encodes as `{"session":{"tick":{}},"v":3}` (29 bytes). No answer. The Mac's `HeartbeatResponder` stamps it as a sign of life **off the main actor and drops it there**, so it never reaches the router or the main actor. |
| `session.link(kind: LinkKind)` | Mac → remote | The Mac's judgement of the link carrying the session: `wired` (USB cable), `ethernet`, `wifi`, `peerToPeer`, `tunnel`, `cellular`, `loopback`, `other`, `unknown`. Sent when the path is first known and whenever the judgement changes. Unknown kind names decode as `other`. |

`PixelHandProtocol.version` 2 → 3, fixtures re-recorded (every fixture's
`v` changes, plus three new ones), history line in `Core/PROTOCOL.md`. The
hard-coded `"v":2` strings in `ProtocolContractTests` and
`RemoteInputValidationTests` now interpolate `PixelHandProtocol.version`, so
the next bump doesn't have to touch them.

### PixelHandCore (all tested on Linux)

- `Network/LinkKind.swift`: the link kinds, `dozes`, display name ("Wired",
  "Wi-Fi", "Direct", "VPN", …) and SF Symbol.
- `Network/LinkJudge.swift`: `LinkObservation` → `LinkKind`. IOKit's answer
  wins on the Mac; on the remote (public API only) a wired/other interface
  to a link-local Mac is judged as the cable. `merged(local:peer:)`: either
  side's `wired` wins. `carryingInterface(...)`: the interface carrying a
  connection from the local address's `%zone`, else `getifaddrs`, else the
  path's preferred interface.
- `Network/WiredLinkPolicy.swift`: an IOKit service-plane chain is a USB
  tether when it has a CDC-NCM function (USB interface class 0x02 / subclass
  0x0D, or a driver class named `…NCM…`) with an **Apple** USB device
  (vendor 0x05AC) at or above it. Third-party NCM Ethernet adapters don't
  count. Walk bounded at 16 entries.
- `Network/KeepAlivePolicy.swift`: `tickInterval = 0.25`, `needsTick(local:peer:)`
  (no tick over the cable, Ethernet or loopback), and `KeepAliveGate` (front /
  background transitions, `isTicking`, `isPinging`, `displayedLink`).
- `Network/InterfaceAddressTable.swift`: address → interface name via
  `getifaddrs` (Darwin and Glibc).
- `Session/Liveness.swift`: `LivenessMonitor.restart(at:)` /
  `LivenessClock.restart(at:)` (resume from background),
  `HeartbeatResponder.heartbeat(in:)` (`.ping` / `.tick`), relay drops ticks.
- Tests: `NetworkLinkTests.swift` (link judge, wired policy, keep-alive gate,
  address table) and new cases in `LivenessTests.swift`. **143 tests pass**
  (was 114).

### Loom (product-agnostic, own commit `e5395f7`)

`LoomSessionNetworkPathSnapshot` used to sort interface names and drop
their categories, so the interface carrying a connection was lost. It now
also carries `interfaces: [LoomNetworkInterface]` in the transport's order
of preference (with category and index) and `primaryInterface`. Additive:
both public initializers take a trailing `interfaces:` defaulting to `nil`
(names in the given order, category `.other`); `interfaceNames` is still
sorted. `backendPath.interfaces` now keeps the real order and categories.
Tests: `Tests/LoomTests/LoomSessionNetworkPathSnapshotTests.swift` (4).
DocC: added to the Essentials topic list in `Loom.docc/Loom.md`.

### Mac

- `MacHostApp.swift`: `enablePeerToPeer: false` (S1).
- `DeckHandMac/Network/USBNetworkProbe.swift`: IOKit walk from
  `IOBSDNameMatching(bsdName)` up the service plane, reading class names and
  `idVendor`, `bInterfaceClass`, `bInterfaceSubClass`, `bDeviceClass`. Public
  IOKit only; no private API, no entitlement.
- `DeckHandMac/Network/HostLinkMonitor.swift`: `@MainActor @Observable`
  singleton. Per connection it reads `LoomConnectionHandle.networkPathUpdates`
  (nobody else reads that stream), judges off the main actor, sends
  `session.link` on change, and keeps `kinds[connectionID]` for the UI. Ends
  with the path stream.
- `DeckHandMac/Network/HostLinkBadge.swift`: the "Wired" / "Wi-Fi" label in
  the menu bar's connection row (accent colour when wired).
- `Handlers/SessionHandler.swift`: starts `HostLinkMonitor` on each ping
  (idempotent, so only authorized sessions are judged); `tick` and `link`
  cases.

### iPad / iPhone

- `DeckHandApp.swift`: `enablePeerToPeer: false` (S1).
- `Control/ControlSessionModel+Network.swift` (new): the heartbeat moved here
  unchanged in behaviour, plus the tick loop, background pause
  (`didEnterBackground` / `willEnterForeground`: ticks and pings stop; on
  return the liveness clock restarts and a ping goes out at once), and local
  link judging from `connection.networkPathUpdates` merged with the Mac's
  report.
- `Network/RemoteLinkStatus.swift` (new): the live session's link for views
  without the model, and `RemoteLinkBadge` ("Wired" in the header, shown only
  over the cable).
- `Network/LinkObservation+Loom.swift` (new).
- `Settings/SettingsConnectionSection.swift`: a "Link" row while a session
  runs; the footer mentions the cable only when wired.

## 2. Out-of-lane edits (all small, announced)

| File | Owner | Edit |
| --- | --- | --- |
| `DeckHandiOS/Control/ControlSessionModel.swift` | shared hot spot | Followed the §2.7 rule: stored props under `// MARK: Network`; the heartbeat block in `run` replaced by `startNetwork` / `defer stopNetwork()`; one `case .session(.link)` in `handleOnMain`. `onAuthStatusChanged` and `lastAuthStatus` lost `private` so the extension file can use them (the heartbeat already used both). |
| `DeckHandiOS/Control/ControlToolbar.swift` | Integration | One line: `RemoteLinkBadge()` after the header subtitle. |
| `DeckHandMac/MacMenuBarView.swift` | Pairing (device list) | One line: `HostLinkBadge(connectionID: connection.id)` in `ConnectionRow`. |
| `Scripts/linux-typecheck/run.sh`, `Stubs.swift` | tool | Two Mac network files added to the default list, `IOKit` imports stripped, stubs for the Loom path types and `USBNetworkProbe`. |
| `Core/Tests/.../ProtocolContractTests.swift`, `RemoteInputValidationTests.swift` | protocol hot spot | New samples / case names (PROTOCOL.md step 2) and `"v":2` → interpolated version. |

`project.yml`, Info.plists, entitlements: **no changes needed**. IOKit is
auto-linked by `import IOKit`; no sandbox (Developer ID app). No new
usage-description keys (the remote reads its own path through Loom; no
Local Network change because Bonjour was already declared).

## 3. Mac checks for the owner's build

Both devices must run this build (protocol 3 doesn't talk to 2).

```bash
git fetch origin claude/pixelhand-lane-network   # or the integration branch after merge
cd DeckHand && xcodegen generate                  # new Network/ folders
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandMac -destination 'platform=macOS' -allowProvisioningUpdates build
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandiOS -destination 'generic/platform=iOS' -allowProvisioningUpdates build
swift test --package-path Core                    # expect 143, fixtures byte-identical on Apple Foundation
cd .. && swift test --scratch-path .build-local --filter LoomSessionNetworkPathSnapshotTests   # 4 new Loom tests
swift test --scratch-path .build-local            # full Loom suite, expect previous count + 4
```

| Area | Check |
| --- | --- |
| AWDL off | With both on the same Wi-Fi: connect works as before. `log stream --predicate 'subsystem == "com.widgetsflow.pixelhand"'` and `ifconfig awdl0` during a session: no Loom traffic over `awdl0` (Mac menu bar shows "Wi-Fi", not "Direct"). |
| Keep-alive | On Wi-Fi, iPad idle for 30 s, then move the trackpad: the cursor answers at once (no 100–300 ms lag on the first move). The Mac log has no `📥 dispatching` lines for ticks (they are dropped before the router). Optional: `sudo tcpdump -i en0 -c 40 host <iPad IP>` shows ~4 small packets a second from the iPad. |
| Background | Send the app to the Home Screen for 30 s, come back: iPad log shows "In the background: keep-alive ticks and pings paused" then "Back in front: liveness clock restarted, pinging now"; no "IPAD GAVE UP". (The Mac may drop the session after 15 s of suspension, as before; reconnecting must still work.) |
| Liveness | Five minutes of use with the mirror on: no `GAVE UP` line on either side. Quit the Mac app: the iPad shows "Disconnected" within ~10 s. |
| Wired (S13) | Plug the iPad into the Mac with a USB-C cable and connect while the session runs over the cable (if Bonjour picks Wi-Fi, turn the iPad's Wi-Fi off). The Mac menu-bar row shows **Wired** with a cable icon; the iPad header shows **Wired** next to the subtitle; Settings › Connection shows Link: Wired and the cable footer. Mac log: `Link for <id>: none → wired`. Then unplug and reconnect over Wi-Fi: both show Wi-Fi, no Wired badge. |
| Wired probe | If Wired doesn't appear over the cable, run `ioreg -r -n "<interface, e.g. en7>" -l -d 1` and `ioreg -p IOService -t -r -c IOEthernetInterface` and send the chain above the "iPad USB" interface: the policy wants an NCM driver/interface and `idVendor = 1452` (0x05AC) above it. |
| Ethernet / VPN | A Mac on Ethernet with the iPad on Wi-Fi: Mac row says "Ethernet", iPad header shows nothing extra, ticks still run (the iPad's own link is Wi-Fi). |

## 4. Compile risks (not compiled on Linux)

Type-checked here in Swift 6 mode: `HostLinkMonitor.swift`,
`DeckHandMac/Network/LinkObservation+Loom.swift`, `SessionHandler.swift`
(in `run.sh`), and, in a scratch check against hand-written UIKit stubs,
`ControlSessionModel+Network.swift`, `DeckHandiOS/Network/LinkObservation+Loom.swift`
and the non-view half of `RemoteLinkStatus.swift`. The Loom change was
compiled and its 4 tests run on Linux in a scratch package with
`LoomNetworking`; the full Loom target wasn't.

Most likely first:

1. **`USBNetworkProbe.swift` (IOKit, never compiled)**: `IOBSDNameMatching`
   returns `CFMutableDictionary!` passed to `IOServiceGetMatchingService`;
   `IORegistryEntryGetParentEntry(current, "IOService", &parent)`;
   `IOObjectCopyClass(...).map { $0.takeRetainedValue() as String }`. If the
   plane string is rejected, use `kIOServicePlane`.
2. **SwiftUI views** (`HostLinkBadge`, `RemoteLinkBadge`, the Settings row):
   `AnyShapeStyle(.secondary)` and reading a `@MainActor @Observable`
   singleton from a `let` in a `View`. If `View` isn't main-actor in the SDK
   in use, mark the views `@MainActor`.
3. **`ControlSessionModel` access levels**: `onAuthStatusChanged` and
   `lastAuthStatus` are now internal; the stored props under
   `// MARK: Network` are internal `var`s because the extension lives in
   another file (`private(set)` wouldn't be settable from there).
4. **`NotificationCenter.addObserver(... queue: .main) { MainActor.assumeIsolated { … } }`**
   in `observeLifecycle()`; a stricter checker may want the closure marked
   `@Sendable` (it already captures only `weak self`).
5. **Loom**: `LoomSessionNetworkPathSnapshot` gained a stored property; any
   memberwise use outside Loom (none in the apps) would need the new
   defaulted argument only if it passes arguments positionally after
   `backendRemoteEndpoint`.

## 5. Notes for later

- The tick is sent straight on the connection, not through `TrackpadSender`
  (iOS interaction owns it). If a later lane wants to skip ticks while input
  is flowing, `TrackpadSender` can report its last send time to
  `KeepAliveGate`.
- Loom doesn't prefer the cable when both Wi-Fi and USB reach the Mac;
  Sill moves sessions to the cable automatically. A "prefer wired" dial
  policy belongs in Loom's discovery/dial path (product-agnostic) and is a
  candidate follow-up with S15.
- S15 (VPN) can reuse `LinkKind.tunnel` and `LinkJudge` once Pairing's
  trust list lands.

Lane: READY TO MERGE
