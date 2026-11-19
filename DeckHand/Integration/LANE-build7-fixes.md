# Lane: build 7 fixes

Branch `claude/pixelhand-lane-build7-fixes`, from
`origin/claude/pixelhand-integration` at `7404f08`. Fixes the two open bugs
in "Mac build results (build 7)" in `STATUS.md`, plus a type-check harness
break that build 7's StoreKit fix caused.

## What changed

### 1. The iOS app no longer opens the overlay probe listener (38450)

**Loom (product-agnostic):**
- `LoomOverlayDirectoryConfiguration` has a new `public var listensForProbes: Bool`
  (default `true`, so behaviour is unchanged) and `func dialOnly() -> Self`, which
  returns a copy with it set to `false`. A dial-only directory still probes
  remote seeds on `probePort`. It just doesn't make the local node listen there.
- `LoomContainer` passes `overlayProbePort: nil` to its `LoomNode` when the
  directory is dial-only (`LoomContainer.localOverlayProbePort(for:)`), so
  `LoomNode.startOverlayProbeServer` never binds the port.
- `LoomContainer.resolvedOverlayDirectoryConfiguration` used to drop
  `retainedPeerExpiration` and `directConnectionPolicy` when it filled in the
  default probe port. It now keeps them, along with the new flag.
- DocC: "Dial without answering probes" in `Loom.docc/UseTailscaleAndCustomOverlays.md`,
  and one paragraph in `LoomKit.docc/EnableCloudPeersAndRemoteAccess.md`.
- Tests: `LoomOverlayDirectoryConfigurationTests` (the default listens;
  `dialOnly()` keeps every probing setting), plus two tests in
  `LoomKitPortConfigurationTests` (a container listens by default; a dial-only
  container gets no local probe port but keeps the probe port, attempts and
  retention).

**iOS app:**
- `RemoteHostsStore.overlayConfiguration` is now `.dialOnly()`. The Mac's
  `RemoteAccessGate.overlayProbeConfiguration` is unchanged, so the Mac still
  answers on 38450.
- **Start failure is now visible.** `ContentRootView` keeps the
  `LoomContext.start()` error. `PeerPickerView` then shows "Can't look for Macs"
  with the error text and a **Try Again** button, which reruns the start task
  (`.task(id:)`), instead of "Looking for your Mac" forever. `LoomStore.start`
  already calls `stop()` when it fails, so a retry starts from a clean state.
- **Settings gear:** I found no code path that ties the gear to the failed
  start. The gear is the top layer of the picker's `ZStack`, with its own hit
  area, and `SettingsView` doesn't read `loomContext`. With bug 1 fixed, the
  start no longer fails in the Simulator, so check it again (Mac check 3). If
  it still doesn't respond, it's a separate bug.

### 2. Flaky "Restarting authenticated advertising closes every previous listener generation"

The test checked that a TCP connection to the old port failed. In a parallel
run, another test's listener could bind that freed ephemeral port first, so
the connection succeeded. The test now builds the node with a
`ListenerRecordingNetworkBackend`. This wrapper around the platform backend
records every listener object it hands out and whether `cancel()` was called.
The test asserts that:
- after the restart, every first-generation listener object was cancelled and
  the new generation's listeners are new objects that are still live;
- the replacement port accepts a connection, which is safe because the port
  is still bound;
- after `stopAdvertising()`, every recorded listener was cancelled.

The test isn't skipped or disabled, and no Loom source changed for this fix.

### 3. Linux type check (existing break)
`6284081` (build 7) names `StoreKit.Transaction` by module, but the type-check
harness strips `import StoreKit` and stubs StoreKit in its own module, so
`run.sh` failed with "cannot find type 'StoreKit'". `run.sh` now strips the
`StoreKit.` prefix from the copies it checks. `Stubs.swift` gains
`listensForProbes` / `dialOnly()`.

## Tests run here (Linux, Swift 6.2)
- `swift test --package-path DeckHand/Core`: **497 / 497 pass** (87 suites).
- `DeckHand/Scripts/linux-typecheck/run.sh`: **Build complete**. It checks
  `RemoteHostsStore.swift` with `.dialOnly()`.
- **Loom tests can't run on Linux.** The `Loom` target imports `Security`
  (`LoomSessionSecurity.swift`), and `CLoomShellSupport` needs BSD `util.h`.
  All changed Swift files pass `swiftc -parse`, but they aren't type-checked
  against real Loom. The Mac build must run them.

## Mac checks
1. `swift test --scratch-path .build-local`. Watch the new
   `Loom Overlay Directory Configuration` suite, the two new
   `LoomKit Port Configuration` tests, and the restart test in a **full parallel
   run** (run it 2–3 times; it failed 2 of 2 before).
2. iPad simulator with the Mac host running: the app starts Loom (no
   `NWError 48`), and the Mac appears in the picker. `lsof -iTCP:38450 -sTCP:LISTEN`
   shows only the Mac host.
3. In the simulator, tap the Settings gear on the picker. It should open
   Settings. If it doesn't, the gear bug isn't caused by the start failure:
   report it separately.
4. Force a start failure to see the new state (for example, temporarily
   revert `.dialOnly()` in the simulator build): the picker shows
   "Can't look for Macs", the error, and **Try Again**. The gear still works.
5. Tailscale away from home: the iPad still finds the Mac through the overlay,
   because dial-only still probes seeds on 38450.

## Compile risks
- `LoomContainer.init` calls `Self.localOverlayProbePort(for:)` (a new
  `static`, internal) before `store`/`mainContext` are set, the same way it
  already calls `Self.resolvedOverlayDirectoryConfiguration`. This should be
  fine.
- `listensForProbes` is a stored `public var` with a default on a struct that
  otherwise has only `let`s and explicit inits. The inits don't assign it, so
  it keeps its default.
- In the test file, `RecordingNetworkListener` / `ListenerRecordingNetworkBackend`
  are `@unchecked Sendable` classes that use `NSLock.withLock` (macOS 13+ / iOS
  16+). They use the `package` type `LoomNetworkFrameworkBackend` through
  `@testable import Loom`.
- `PeerPickerView` gained two leading defaulted properties (`startError`,
  `onRetryStart`) before `onConnected`. Its one call site uses labels for
  these and a trailing closure for `onConnected`.

Lane: READY TO MERGE
