# Pixel Hand M0 crash and correctness fixes

Branch: `claude/pixelhand-m0-fixes`, cut from `origin/claude/pixelhand-integration`
at `a5ea533`. Merge it into the integration branch once the Mac build there is green.

Written in a Linux container with no Swift toolchain. **Nothing here has been
compiled or run.** The Mac session must build both apps, run `DeckHandTests`,
and do the device checks below.

There is one commit per bug, in this order:

| # | Commit subject | Ticket |
| --- | --- | --- |
| 1 | Validate every number the Mac receives from a remote | PH-031 |
| 2 | Make Show Desktop work from the Quick Actions bar | §0 #6 (PH-022 later) |
| 3 | Open the real Launchpad instead of Spotlight | §0 #6 |
| 4 | Stop the iOS app crashing on duplicate bundle IDs | PH-035 |
| 5 | Fix the mirror start race that froze every remote's mirror | §0 #5 (PH-020 later) |
| 6 | Drop input sent while an approval request is pending | PH-036 (part) |
| 7a | Revoke every connection of a removed device | §1.2 |
| 7b | Title live-mirror errors as mirror errors | PH-035 (part) |
| 7c | Keep fn when editing a shortcut | PH-035 (part) |

## New files

All the new logic is in `Shared/`, because the `DeckHandTests` target compiles
`Shared/` and nothing from the app folders. XcodeGen picks the files up from the
folder groups, so `project.yml` is unchanged. No Info.plist changed.

| File | What it is |
| --- | --- |
| `Shared/RemoteInputValidation.swift` | Checks and clamps every number from a remote |
| `Shared/SystemMacro.swift` | Maps every macro id a remote may send for a system action |
| `Shared/SerialTaskQueue.swift` | Runs the mirror's start, stop and display changes one at a time |
| `Shared/PreApprovalGate.swift` | Drops a connection's messages until the user clicks Allow |
| `DeckHandTests/RemoteInputValidationTests.swift`, `SystemMacroTests.swift`, `DuplicateBundleIDTests.swift`, `SerialTaskQueueTests.swift`, `PreApprovalGateTests.swift` | Regression tests. They use XCTest, as the target's existing tests do. |

## 1. A remote could crash the Mac host (PH-031)

**Root cause.** `InputInjector.scroll` passed `Int32(-dy * 3)` straight to
`CGEvent`. That conversion traps on NaN, on ±∞ and on anything outside about
±7.2e8. JSON can't carry NaN or ∞, but any finite float decodes, so one
`mouseScroll` with `dy: 1e30` killed the host. No number from the remote was
checked anywhere.

**Fix.** `RemoteInputValidation.sanitize(_:)` is the one layer. `ControlReceiver`
calls it on every message right after decoding and before dispatch. If it
returns `nil`, the message is logged and dropped.

| Field | Rule |
| --- | --- |
| `mouseDelta` dx, dy | Non-finite → drop. Clamp to ±2,000. |
| `mouseScroll` dx, dy | Non-finite → drop. Clamp to ±10,000. |
| `requestScreenshot` region x, y, width, height | Non-finite or width/height ≤ 0 → drop. Intersect with 0…1. Empty after that → drop. |
| `startMirror` fps, maxWidth | Clamp to 1…30 and 120…1920 (the mirror service's own caps). |
| `tracked(command)` | The inner command is checked the same way. If it's dropped, the whole message is dropped. |

There is also a second line of defence. `InputInjector.scroll` converts with
`RemoteInputValidation.wheelUnits(forScrollDelta:)`, which can't trap, and
`moveCursor` drops non-finite deltas.

The other numbers needed no change. Window IDs and display IDs are `UInt32`;
an unknown one already falls back (`display(matching:)`) or is caught by the
`bounds.width > 0` guards. `ping` seq is a `UInt64` that is only echoed back.

**Test.** `RemoteInputValidationTests`: NaN, ±∞, ±`greatestFiniteMagnitude`
and ±1e9 for every field; normal values unchanged, and `wheelUnits` equals the
old formula for them; region clipping; mirror clamps; tracked commands; a
decoded `{"dy":1e30}` message end to end.

**Verify on a Mac.** Build a debug iPad app with a temporary button that sends
`.mouseScroll(dx: 0, dy: 1e30, phase: .changed)`, then
`.mouseDelta(dx: 1e9, dy: 0)` and
`.requestScreenshot(requestID: "x", mode: .region(x: 5, y: 5, width: 1, height: 1))`.
The host must stay up. Console (`subsystem:com.widgetsflow.pixelhand`) logs
"Dropped a message with an invalid number" for the region request. Normal
scrolling and pointer speed must feel exactly as before.

## 2. "Show Desktop" in the Quick Actions bar never worked

**Root cause.** The bar sent `macroButton("showdesktop")`. The host matched its
own `*_trigger` ids, then looked the id up in `MacroItem.defaultDeck`, whose
ids are prefixed (`shortcut-showdesktop`). Nothing matched, so nothing happened.
The default-deck entry would have posted fn+F11 anyway, which is a symbolic hot
key that CGEvent posts never fire. The trackpad's Desktop button sent that same
fn+F11 shortcut.

**Fix.** `SystemMacro(macroID:)` resolves every id a remote sends for a system
action (`showdesktop`, `showdesktop_trigger`, `shortcut-showdesktop`, and the
same for Mission Control and Launchpad). `ControlReceiver.dispatchMacro` checks
it before the default-deck lookup. Show Desktop runs
`/System/Applications/Mission Control.app/Contents/MacOS/Mission Control 1`
(or the `/Applications` path on older systems). If neither exists, it falls
back to System Events `key code 103` (F11). Both remote buttons now send
`showdesktop_trigger`. Process launch failures are logged instead of being
swallowed by `try?`.

**Test.** `SystemMacroTests`: every spelling resolves, every id the remote
sends resolves, and non-system ids are left for the default deck.

**Verify on a Mac and an iPad.** Open some windows. Tap the Show Desktop
icon (`macwindow`) in the Quick Actions bar: the windows slide away. Tap it
again: they come back. Do the same with Desktop in the trackpad gesture bar.
**Needs checking:** the Mission Control binary's `1` argument is a long-standing
behaviour but isn't documented. Confirm it on macOS 14, 15 and 26. If it fails,
check that the F11 fallback works with the default Show Desktop binding.

## 3. "Launchpad" was mapped to ⌘Space

**Root cause.** The default deck's Launchpad entry was a shortcut with keys
`["cmd", "space"]`, which opens Spotlight. Launchpad has no default shortcut.

**Fix.** That entry now has no keys. `launchpad` and `shortcut-launchpad` resolve
to `SystemMacro.launchpad`, as `launchpad_trigger` already did. The host opens
`Launchpad`, or `Apps` when `/System/Applications/Launchpad.app` is missing
(macOS 26 replaced Launchpad with Apps).

**Test.** `SystemMacroTests.testLaunchpadNeverMapsToSpotlight`.

**Verify.** Tap the Launchpad icon (`square.grid.3x3.fill`) in the Quick
Actions bar. Launchpad opens on macOS 14 and 15, and Apps on macOS 26. Spotlight
must not open. **Needs checking:** the app name `Apps` on macOS 26.

## 4. Duplicate bundle IDs crashed the iOS app

**Root cause.** `QuickActionsBar.otherRunningApps` and
`WindowPickerView.orderedWindows` built dictionaries with
`Dictionary(uniqueKeysWithValues:)`, which traps on a repeated key. That
happens when two copies of an app are installed (`/Applications` and
`~/Applications`), or when the running-apps list repeats an id.

**Fix.** `InstalledAppInfo.byBundleID(_:)` and `InstalledAppInfo.recencyRank(of:)`
use `uniquingKeysWith` and keep the first entry. Both views call them. The two
Mac-side `uniqueKeysWithValues` calls in `ScreenCaptureService` are keyed by
display ID and PID, which are unique, so they were left alone.

**Test.** `DuplicateBundleIDTests`.

**Verify.** On the Mac, copy an app to a second location, for example
`cp -R /System/Applications/Calculator.app ~/Applications/`. Run both copies.
On the iPad, open the running-apps menu in the Quick Actions bar and open the
window picker. Neither crashes, and the app appears once in the menu.

## 5. The mirror start race froze the mirror for every remote

**Root cause.** There were three faults in `MirrorStreamService`:

1. `start` is a `@MainActor` method that awaits, so two `startMirror`s
   interleaved. Both saw `stream == nil`, both built an `SCStream`, and the
   orphan kept capturing with nothing to stop it.
2. A frame's completion cleared the busy flag on `self.output`, the *current*
   output, not the one that made the frame. An old stream's frame could
   unblock the new stream, or leave it stuck.
3. `broadcast` awaited each subscriber's send in turn, and the encoder stayed
   busy until all of them finished. One hung `send` (a peer that had gone
   away but wasn't yet timed out) stopped frames for everyone.

**Fix.**

- Start, stop and display changes run through a `SerialTaskQueue`, one at a
  time and in order. `stop` is queued behind a pending start, so a start can't
  re-add a subscriber that has already left. `stop` doesn't wait for the queue,
  so connection cleanup never blocks on ScreenCaptureKit.
- `MirrorFrameOutput` passes itself to the frame callback, and the callback
  clears *that* output's flag. Frames from a replaced or stopped output are
  dropped.
- Each subscriber has at most one frame send in flight (`sendingTo`). A
  subscriber still sending skips the frame. The encoder is freed as soon as
  the frame is handed off.

Out of scope, left for PH-020: per-remote fps, width and display (one remote
still retargets the shared stream), and a dedicated binary frame stream.

**Test.** `SerialTaskQueueTests`: operations never overlap, they run in
submission order, and check-then-create builds exactly one stream.

**Verify with two remotes (an iPad and an iPhone).**

1. Start the mirror on both at once (tap both within about half a second).
   `log stream --predicate 'subsystem == "com.widgetsflow.pixelhand"'` shows one
   "Mirror stream started", and Activity Monitor shows one capture.
2. With both mirroring, put one device in Airplane Mode. The other device's
   mirror keeps updating, without a freeze of up to 8 s while liveness times
   out.
3. Stop and start the mirror quickly on one device about ten times. It always
   ends live, never frozen on a stale frame.
4. Unplug an external display while mirroring it. Both remotes fall back to the
   main display.

## 6. Approval replayed queued input

**Root cause.** Nothing read a pending connection's messages, so everything the
remote sent while waiting for Allow (up to 45 s) buffered in the handle's
`AsyncStream`. When the user clicked Allow, `ControlReceiver` started reading
and ran the whole backlog at once.

**Fix.** `DeviceAuthorizationManager.handleIncomingConnection` wraps every
connection in a `PreApprovalGate` as soon as it arrives. The gate reads
`handle.messages` right away. Until `open()`, it drops everything except up to
four `requestAuthorizationStatus` queries, which are still answered "granted"
right after approval, as before. `authorize` opens the gate at the click, logs
how many messages it dropped, and hands `gate.messages` to
`ControlReceiver.observeConnection(_:messages:)`, which reads that stream
instead of `handle.messages`. Denial, expiry, dismissal and pruning release the
gate, and that ends its read. Already-approved repeat connections get a gate
that is opened at once, so their behaviour is unchanged.

**Test.** `PreApprovalGateTests`: pending input is dropped (clicks, keys,
launches, tracked commands, pings, garbage); status queries are kept up to the
cap; everything passes once the gate is open; the gate drops a backlog and
forwards only what comes after `open()`; the gate finishes when the connection
ends.

**Verify.** Restart the Mac app, so the iPad isn't yet approved. Connect from
the iPad. While "Waiting for approval" shows, swipe the trackpad and tap a few
Quick Actions (Mission Control, a shortcut chip). Wait about 5 s, then click
Allow on the Mac. Nothing happens on the Mac at that moment: the cursor
doesn't jump and Mission Control doesn't open. Console shows "Dropped N
message(s) sent before approval". The iPad leaves the waiting card within
about 3 s, and input works normally from then on.

## 7. Other small M0/M1 bugs taken

| # | Bug (source) | Root cause | Fix | Test |
| --- | --- | --- | --- | --- |
| 7a | Removing a device left its other connections running (inventory §1.2) | `removeAndDisconnect` cancelled and disconnected only the clicked row's connection | It now ends every connection in `loomContext.connections` with the same peer ID, cancelling consumption before it disconnects | Manual. Connect, force-quit the iPad app and reconnect quickly, so two rows show for one device. Click ✕ on one: both rows go and input stops. |
| 7b | Mirror errors titled "Screenshot Failed" (PH-035) | Mirror failures arrive on the screenshot error channel, and the remote reused the screenshot alert title | When `requestID == "mirror"`, the alert is titled "Live Mirror Unavailable". The wire format is unchanged. | Manual. Turn off Screen Recording for Pixel Hand and start the mirror. |
| 7c | Shortcut editor dropped `fn` (PH-035) | The editor read cmd, shift, option and control from a binding but not fn, and had no fn toggle | Added a "fn Function" toggle, read on open and written on save | Manual. Create a shortcut with fn and F11, edit it and save: the glyphs still show `fn`. |

### Left for later sessions

These need the protocol reset, the file splits or a Mac to design against:

- Typed `SystemAction`, `mirrorError` and `hello` messages (PH-003).
- Symbolic hot keys read from the user's bindings, replacing `osascript` and
  `open -a` (PH-022).
- Per-remote mirror settings and a binary frame stream (PH-020).
- Pending-request caps, the rate-limit policy and key fingerprints (the rest of
  PH-036).
- Capture concurrency limits and a display choice for captures (PH-031 and
  PH-034).
- The rest of PH-035: icon caching, connect, app-list and import timeouts,
  the stale CloudKit row, the FAB manual toggle, and SF Symbol and key
  validation.
- `switchSpace` with an unknown display ID still posts the Space key on the
  display under the cursor. That is harmless; tidy it in the handler split
  (PH-005).
- The `ControlMessage.requestAuthorizationStatus` doc comment still says
  pending queries "buffer in the handle". The gate now keeps them instead.
  Left as is because the file is reserved for PH-003.

## Build notes for the Mac session

Things most likely to need a touch when compiling with Swift 6:

- `SerialTaskQueue.run` and `enqueue` take
  `@escaping @MainActor @Sendable () async -> Void`. The call sites capture
  `[weak self]` on `@MainActor` classes and the `LoomConnectionHandle` actor.
- `PreApprovalGate` is `@unchecked Sendable`, and its state is behind an
  `NSLock`. Its pump `Task` captures only Sendable values: `AsyncStream`, its
  continuation, and the lock-guarded state.
- `SerialTaskQueueTests` is a `@MainActor` `XCTestCase` that shares state
  through a `@MainActor` probe class.
