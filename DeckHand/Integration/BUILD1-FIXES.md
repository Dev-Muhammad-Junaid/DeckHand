# Pixel Hand build 1 fixes

Branch: `claude/pixelhand-build1-fixes`, cut from `origin/claude/pixelhand-integration` at `7c67585`. The numbering follows the build-1 fix brief. The brief's 7 and 8 are bugs 9 and 7 in `STATUS.md`.

This was written in a Linux container with no Swift toolchain. **Nothing here has been compiled or run.** The Mac session must:

1. run `xcodegen generate`, because there are new files in `Shared/`, `DeckHandMac/` and `DeckHandTests/`;
2. build both apps;
3. run `DeckHandTests` and `swift test --scratch-path .build-local`;
4. do the checks below.

There is one commit per bug. Bugs 1 and 2 share the new files, so commit 1 adds them with Launchpad still on `open -a`, and commit 2 changes the Launchpad plan.

| # | Commit | Bug |
| --- | --- | --- |
| 1 | `9a977f8` Show the desktop on macOS 27 without the user's shortcut | STATUS 1 |
| 2 | `db3dd22` Open Apps on macOS 27 through its hot key | STATUS 2 |
| 3 | `87061a9` Say the approval request timed out instead of declined | STATUS 3 |
| 4 | `a1a7087` Stop the header saying Connected before the Mac allows the iPad | STATUS 4 |
| 5 | `a2534dc` Keep scrolled Settings rows from showing through the title | STATUS 5 |
| 6 | `0b52ade` Report real iCloud recognition status in Settings | STATUS 6 |
| 7 | `4870fee` Keep the iPad connected through short stalls on either side | STATUS 9 |
| 8 | `75cf437` Keep Bonjour advertiser backoff growing while it flaps (Loom) | STATUS 7 |

## New files

| File | What it is |
| --- | --- |
| `Shared/SystemActionPlan.swift` | The order of mechanisms for Show Desktop and Launchpad, per macOS version, plus symbolic hot key ids and fallback chords |
| `DeckHandMac/SystemActionTrigger.swift` | Runs the plan. This is the only file with the new private API calls. |
| `Shared/ApprovalStatusCopy.swift` | Approval card copy, the timed-out mapping, and the header subtitle |
| `Shared/CloudRecognitionStatus.swift` | The "Recognize my own devices" row's states and copy |
| `Shared/Liveness.swift` | `LivenessMonitor`, `LivenessPolicy`, `LivenessClock`, `HeartbeatResponder` |
| `DeckHandTests/SystemActionPlanTests.swift`, `ApprovalStatusCopyTests.swift`, `CloudRecognitionStatusTests.swift`, `LivenessTests.swift` | XCTest, like the target's other tests |

Loom: `LoomNode.swift` and `LoomNodeAdvertisementTests.swift` (Swift Testing).

No wire format change. `ControlMessage.swift` is untouched. `ControlReceiver`, `ControlView` and `ContentRootView` changes are line-level.

**Private API, to record in DECISIONS.md if the owner agrees.** The brief allows private API in the Mac app for bugs 1 and 2. Bug 1 uses these calls, all through `dlsym` and all skipped if missing:

- `CGSGetSymbolicHotKeyValue` and `CGSIsSymbolicHotKeyEnabled` read the binding. This is already approved.
- `CGSSetSymbolicHotKeyEnabled` and `CGSSetSymbolicHotKeyValue` switch the hot key on, or bind a spare chord, for about 1.2 s. They then put the user's setting back.
- `CoreDockSendNotification`.

---

## 1. Show Desktop does nothing on macOS 27

**Root cause.** Show Desktop ran `Mission Control.app/Contents/MacOS/Mission Control 1`. On macOS 27 that does nothing; run by hand it exits 137, which looks like a launch-constraint kill. The F11 fallback had two problems:

- it only ran when the binary was *missing*, so on 27 it never ran;
- it posts F11 through System Events, so it only works if the user's Show Desktop shortcut is on and set to F11. On the test Mac, `com.apple.symbolichotkeys` key 36 is off.

**Fix.** `SystemActionTrigger` runs a plan from `SystemActionPlan`. Nothing can tell whether the Dock reacted, so the first mechanism that is *able* to run wins. On every macOS the order is:

1. **`symbolicHotKey`.**
   - It reads hot key 36 with `CGSGetSymbolicHotKeyValue`.
   - If the hot key is off, it switches it on. If it is unbound, it binds Apple's default, fn F11.
   - It waits 60 ms, then posts the chord at the HID tap.
   - After 1.2 s it restores the user's on/off state and binding. Repeated taps push the restore back instead of stacking.
   - This needs Accessibility, which the app already requires, and the CGS symbols.
   - It doesn't depend on the user's binding: on the test Mac it uses the disabled fn F11 binding by switching it on for a moment.
2. **`dockNotification`:** `CoreDockSendNotification("com.apple.showdesktop.awake")`.
3. **`dedicatedKey`:** ⌘ + Mission Control key (virtual key 0xA0), Apple's fixed Show Desktop shortcut.
4. **`missionControlBinary`:** the old path. Only on macOS 26 and earlier.
5. **`systemEventsKey`:** the old F11 through System Events.

Every run logs which mechanism ran: `showDesktop: ran via …`.

**Testing hook.** Each mechanism can be forced without rebuilding, either as one name or as a comma-separated list:

```sh
defaults write com.widgetsflow.pixelhand.mac PixelHandShowDesktopMechanism dockNotification
defaults delete com.widgetsflow.pixelhand.mac PixelHandShowDesktopMechanism
```

**Why the hot key route is likely to work on 27.** STATUS bug 8 showed that synthesized ⌃→ through System Events changed Spaces on this Mac. Synthesized key events do reach the hot-key matcher on 27 when the hot key is on. That isn't proven for key 36 yet, so the override exists to try the others quickly.

**Tests.** `SystemActionPlanTests` checks that:

- on 27, the binary is never used and F11 is last;
- 14, 15 and 26 keep the binary as a fallback;
- binding-independent mechanisms come before F11;
- overrides are parsed, and a bad override falls back to the default;
- hot key ids and fallback chords are right, and a bound hot key uses the user's chord.

**Verify on the Mac (macOS 27, two displays)** and on the iPad:

1. Confirm key 36 is still off: `defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys | grep -A8 '"36"'` shows `enabled = 0`.
2. Open some windows. On the iPad, tap Show Desktop in the Quick Actions bar (`macwindow`). The windows slide away. Tap it again and they come back.
3. Do the same from Desktop in the trackpad gesture bar.
4. Console, `subsystem:com.widgetsflow.pixelhand category:input`, shows `showDesktop: ran via symbolicHotKey` and a `Symbolic hot key 36: posting key 103 flags 0x800000 (was off, bound)` line.
5. About 2 s later, run step 1 again. Key 36 is still `enabled = 0`. The user's setting is restored, not persisted. Also check that pressing fn F11 on the Mac keyboard still does nothing.
6. **If step 2 does nothing:**
   - Set the override to `dockNotification` and retry, then `dedicatedKey`.
   - Report which one works. The default order should then be changed in `SystemActionPlan.defaultMechanisms`; it is a one-line change, with a test update.
7. On macOS 14, 15 or 26, if available, steps 2 and 3 work, and the log says `symbolicHotKey`.

## 2. Launchpad / Apps does nothing on macOS 27

**Root cause.** The host ran `open -a Apps`. On 27, LaunchServices accepts it, exits 0, logs "Asking CSUI to launch 0 items", and nothing opens. `open -b com.apple.apps.launcher` does the same. Apps on 27 isn't something LaunchServices will open from another app.

**Fix.**

- On **macOS 27 and later**, the plan is:
  1. `symbolicHotKey`: hot key 160, "Show Launchpad", which shows Apps on 26 and later. It has no default binding, so when it's unbound the trigger binds ⌃⌥⇧⌘F19 for about 1.2 s, posts it, and restores the hot key. The same restore logic as bug 1 applies.
  2. `dedicatedKey`: the Launchpad key, virtual key 0x83.
  3. `dockNotification`: `com.apple.launchpad.toggle`.
- On **macOS 26 and earlier**, `open -a Launchpad` (or `Apps`) stays first, because it is the known-good path on 14 and 15. The same fallbacks follow it.
- It never maps to ⌘Space.

**Testing hook.**

```sh
defaults write com.widgetsflow.pixelhand.mac PixelHandLaunchpadMechanism dedicatedKey
```

**Tests.**

- `SystemActionPlanTests.testLaunchpadOnMacOS27NeverUsesOpenApp`
- `testLaunchpadOnOlderSystemsKeepsOpenAppFirst`
- `testLaunchpadNeverFallsBackToShowDesktopPaths`
- the fallback-chord test, which checks it is never ⌘Space and never a bare F19

**Verify on the Mac (27).**

1. On the iPad, tap Launchpad in the Quick Actions bar (`square.grid.3x3.fill`). Apps opens. Spotlight's search field must not open.
2. Tap it again, or press Esc on the Mac, and Apps closes.
3. Console shows `launchpad: ran via symbolicHotKey` and `Symbolic hot key 160: posting key 80 …`.
4. About 2 s later, `defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys | grep -A8 '"160"'` shows the original value, or no entry if there was none.
5. **If step 1 does nothing**, try the overrides in turn: `dedicatedKey`, then `dockNotification`. Report which works so the default order can be changed.
6. On 26 or earlier, the log says `ran via openApp`, and Launchpad or Apps opens as before.

## 3. A 45 s timeout read as "was declined"

**Root cause.** The Mac sends `authorizationStatus("denied")` both when the user clicks Deny and when its 45 s pending window expires (`DeviceAuthorizationManager.schedulePendingExpiry`). The iPad couldn't tell the two apart.

**Fix.**

- On the iPad only, with no wire change: `ApprovalStatusCopy.displayStatus` maps a "denied" that arrives after at least 40 s of waiting (45 s minus 5 s of slack for connect and handshake) to a local `timed_out` status.
- The card says **"Request Timed Out"**: "Nobody allowed the request on ‹Mac› within 45 seconds. Connect again, then click Allow on the Mac."
- The Mac's expiry and the iPad's copy share `ApprovalStatusCopy.pendingRequestTimeout`.
- `timed_out` is terminal, so the button reads Dismiss. A later heartbeat loss doesn't replace it with "Disconnected".
- The card shows the "disconnected" glyph, not the red cross.

**Tests.** `ApprovalStatusCopyTests`:

- a quick denial stays denied;
- a denial at 44.2 s, 45 s or 47 s reads as a timeout;
- the timeout copy says it timed out and doesn't say "declined";
- terminal and final states are right.

**Verify on the iPad** (simulator is fine):

1. Connect, and leave the Mac's prompt unanswered. At 45 s the card says "Request Timed Out", with the 45-second copy and a Dismiss button.
2. Connect again and click Deny on the Mac within a few seconds. The card says "Access Denied … was declined."

## 4. Header said "Connected" behind the waiting and denied cards

**Root cause.** `ControlView`'s toolbar showed `activeAppName ?? "Connected"` and the breathing live pixel whatever the approval state was. `ControlView` didn't know the state.

**Fix.**

- `ContentRootView` passes its `authStatus` into `ControlView`.
- The subtitle comes from `ApprovalStatusCopy.headerSubtitle`:

  | State | Subtitle |
  | --- | --- |
  | pending | "Waiting for approval" |
  | denied | "Not allowed" |
  | timed out | "Request timed out" |
  | disconnected | "Disconnected" |
  | granted | the frontmost app's name, or "Connected" |

- The live pixel shows only when granted.

**Tests.** `ConnectionHeaderStatusTests`: no state other than granted shows "Connected" or the app name, and the live pixel shows only when granted.

**Verify on the iPad.**

- While waiting for approval, the header under the Mac's name reads "Waiting for approval", with no mint pixel.
- After Deny it reads "Not allowed".
- After Allow it reads "Connected", then the frontmost app's name, with the pixel breathing.

## 5. iPad Settings: scrolled content showed through the title in dark mode

**Root cause.** The Settings sheet's inline navigation bar has no background until content scrolls under it. On iOS 26 its soft scroll-edge effect let glass controls show through the "Settings" title, the appearance segmented control in particular. Light mode hid it.

**Fix.** The `OpaqueSettingsBar` modifier on the sheet's `Form`:

- `.toolbarBackground(.visible, for: .navigationBar)` on all versions;
- `.scrollEdgeEffectStyle(.hard, for: .top)` on iOS 26, gated with `#if compiler(>=6.2)` and `#available`, as elsewhere in the app.

**Tests.** None; this is visual.

**Verify on the iPad, in dark mode:**

1. Open Settings and scroll so the Appearance section's segmented control passes under the title. The title stays on a solid bar, and nothing shows through.
2. Repeat in light mode.
3. Repeat in portrait and landscape.

## 6. Stale "needs a CloudKit container" copy

**Root cause.** The "Recognize my own devices" row was a hard-coded `UnavailableRow`, from before `iCloud.com.widgetsflow.pixelhand` was registered. `DeckHandCloud.isCloudEnabled` has been `true` since then. The copy also promised that own Macs connect "without the approval prompt", which the Mac doesn't do: `DeviceAuthorizationManager` prompts for every connection. Recognition gives the "My Mac" badge and sorts own Macs first.

**Fix.**

- The row asks `CKContainer(identifier:).accountStatus()`, and only when `isCloudEnabled` is on.
- `CloudRecognitionStatus` maps the result to a badge:

  | Result | Badge |
  | --- | --- |
  | iCloud account available | **On** |
  | no iCloud account | **Sign in to iCloud** |
  | restricted, temporarily unavailable, or couldn't be read | **Unavailable** |
  | CloudKit off in the build | **Off** |

- Each badge has an accurate one-line detail.
- New footer: "Your devices recognize each other through your private iCloud database. The Mac still asks you to allow each new connection."
- A stale comment in `PeerPickerView` was fixed the same way.

**Tests.** `CloudRecognitionStatusTests`:

- the build switch wins;
- each account state maps correctly;
- this build has CloudKit on, with the right container;
- no copy mentions "paid developer account" or "registered";
- no copy promises skipping approval.

**Verify on the iPad.**

1. When signed in to iCloud, Settings → Connection shows "Recognize my own devices — **On**" in mint, with the new detail and footer.
2. Sign out of iCloud on a test device, or use a simulator with no account. The badge reads "Sign in to iCloud".
3. With both devices on the same iCloud account, the Mac shows "My Mac" in the peer picker, and the Mac still prompts for approval.

## 7. The iPad disconnects after a couple of minutes (STATUS bug 9)

### The heartbeat path before

| | iPad (`ControlView`) | Mac (`ControlReceiver`) |
| --- | --- | --- |
| Sends | `ping(seq)` every 2 s, through the `TrackpadSender` actor | `pong(seq)` from the message loop's `.ping` case |
| Runs on | heartbeat `Task` and message loop: **main actor** (View `.task`) | message loop, sweep and pong send: **main actor** (`@MainActor` class) |
| Counted as alive | **only pongs**, stamped inside the main-actor message loop | any message, stamped when the **main-actor** loop dequeued it; enforced after the first ping |
| Gives up after | 6 s with no pong (checked every 2 s) | 8 s with nothing (swept every 3 s) |
| Other main-actor work | mirror-frame JPEG decode, up to 20 per second, in the same loop | AX dialog walks (40–50 ms each), cursor injection at 120 Hz, capability checks |

**Root cause.** Each side's liveness ran through a busy main actor.

- On the Mac, a pong could only go out after everything queued ahead of the ping on the main actor: the AX walks and all the input.
- On the iPad, a pong was only counted after the frames queued ahead of it were decoded on the main actor.
- The iPad's 6 s window was three missed beats, so a few seconds of contention on either side, or a pong stuck behind mirror frames, read as a dead Mac.
- The build-1 logs fit this. The "Cursor delta gap 33–86 ms" lines are main-actor stalls. In the second drop, the iPad's message loop ended first, with the simulator's liveness timeout 5 s later. That is the iPad giving up first and the Mac then timing out on the closed connection.

### Fix

| Area | Change |
| --- | --- |
| Liveness rule | `LivenessMonitor` counts **any** message from the peer as alive. It is still only enforced after the first ping or pong. |
| Stall tolerance | If the checker's own check runs late (iPad: more than 5 s between checks; Mac: more than 8 s between sweeps), that side was stalled, suspended or asleep. The silence clock restarts instead of blaming the peer. |
| Timeouts | iPad 10 s (was 6 s); Mac 15 s (was 8 s). The Mac outlasts the iPad, so in a symmetric failure the iPad, which has the UI, notices first. All values are in `LivenessPolicy`. |
| Mac pong off the main actor | `HeartbeatResponder.relay` sits between `PreApprovalGate` and the main-actor loop, in a detached task. For each message it stamps the clock. For a ping (decoded only if ≤ 96 bytes) it sends the pong at once from its own task. Everything, pings included, is still passed on in order. The main loop's `.ping` case keeps its every-5th capability report. |
| Mac AX walk off the main actor | `ContextObserver.recompute` runs `buildSnapshot` and its helpers, now `nonisolated`, in a detached task. AX calls are thread-safe. Only the result hops back. A generation counter drops a walk that finishes after a newer one started. "AX recompute slow" now says "(off the main actor)". |
| iPad | Every inbound message is stamped as the loop reads it. Pongs are stamped before the main-actor hop. Mirror frames are decoded in a detached task. |
| Logging | The side that gives up logs it with numbers, and the other side's end-of-stream log names who closed (see below). |

**Log lines.** The side that gives up logs:

- iPad: `Heartbeat: IPAD GAVE UP on the Mac: nothing received for X s (last pong Y s ago, N messages total, last ping seq S, timeout 10 s)`
- Mac: `Liveness: MAC GAVE UP on <id>: nothing received for X s (last ping Y s ago, N messages total, timeout 15 s) — dropping`

When a stream ends, each side says who closed it:

- iPad: `Host message stream ended: the Mac closed the connection (MAC GAVE UP, quit or revoked; …)`, or `… after the iPad gave up`.
- Mac: `📪 message loop ended for <id>: the iPad closed the connection (IPAD GAVE UP or left; …)`, or `the Mac dropped it for silence`, or `revoked or replaced on the Mac`.

Stalls are logged as `… ran X s late (… stalled …); restarting …`.

**Not changed:** the wire format; `ping` and `pong` are as before. `TrackpadSender` is unchanged.

**Tests.**

- `LivenessMonitorTests`:
  - no enforcement before the first heartbeat;
  - any traffic keeps the peer alive with no pong for 30 s;
  - the old 6–8 s pong gap no longer kills;
  - real silence dies at 12 s with checks every 2 s;
  - a 20 s local stall gives a fresh full timeout;
  - clock stamps never move back;
  - policy invariants (the Mac outlasts the iPad, and stall thresholds sit between the interval and the timeout);
  - the "gave up" flag.
- `HeartbeatResponderTests`:
  - only pings are recognised;
  - an encoded ping fits the size cap;
  - the relay answers both pings, passes all four messages on in order, and stamps the clock four times.

### Verify on the Mac and the real iPad

1. Stream the Mac's logs: `log stream --predicate 'subsystem == "com.widgetsflow.pixelhand"' --level info`. On the iPad, use Console.app with the iPad selected, filtered to the same subsystem.
2. Connect and Allow. Use the trackpad continuously for 5 minutes with the mirror on. Open and close a few dialogs, for example ⌘S in TextEdit then Cancel, to drive AX walks.
   - The iPad must stay connected.
   - There must be no `GAVE UP` line on either side.
   - "AX recompute slow" lines, if any, say "(off the main actor)".
   - "Cursor delta gap" lines should be rarer than in build 1.
3. **Stall tolerance:** with the mirror on, press the iPad's Home gesture for 15 s, then return. The session survives. The iPad logs `Heartbeat check ran … late (iPad stalled or suspended)`, and the Mac logs nothing worse than info.
4. **Real death, Mac side:** quit Pixel Hand on the Mac. Within about 10 s the iPad shows "Disconnected". If the transport didn't report the close first, the iPad log has `IPAD GAVE UP`.
5. **Real death, iPad side:** turn on Airplane Mode on the iPad. Within about 15 s the Mac logs `Liveness: MAC GAVE UP on …` and the menu bar drops the device.
6. If a drop still happens, send both logs from 30 s before it. The `GAVE UP` line and the other side's `stream ended` line say which side gave up first, and how long it had heard nothing.

## 8. Simulator: Bonjour advertiser loops with -65563 (STATUS bug 7)

**Root cause.** The retry is in Loom, `LoomNode`. Its backoff (1, 2, 4 … up to 30 s) was already there. But `startBonjourAdvertising` reset `bonjourAdvertisingRecoveryAttempt` to 0 every time a restarted advertiser reached `.ready`. In the simulator the advertiser:

1. reaches ready;
2. fails with `-65563 ServiceNotRunning` about a second later;
3. is restarted after the minimum 1 s delay, because the count was reset to 0, so this is attempt 1.

So it retried once a second forever.

**Fix (Loom, product-agnostic).**

- The count isn't reset on ready any more. `LoomNode` records when the advertiser became ready.
- On a failure, `bonjourAdvertisingRecoveryAttempt(afterFailureFollowing:healthyDuration:)` starts again at 1 only if the advertiser had been up for at least `bonjourAdvertisingStableDuration` (30 s). Otherwise it keeps climbing.
- An explicit `startAdvertising` or stop still resets everything.
- No public API change; the helpers are `package`.

**Tests.** In `LoomNodeAdvertisementTests`:

- a flapping advertiser gets delays of 1, 2, 4, 8, 16 and 30 s;
- the backoff starts over after a stable period.

**Verify.**

1. Run `swift test --scratch-path .build-local --filter LoomNodeAdvertisementTests`.
2. In the simulator, `log stream --level info --predicate 'subsystem == "com.loom" AND eventMessage CONTAINS "Bonjour advertiser"'`. Loom's default subsystem is `com.loom`, and the app doesn't change it. "Bonjour advertiser failed after publishing" lines now come further and further apart: about 1, 2, 4, 8, 16, then 30 s.
3. On a real iPad there should be none.

---

## Compile-risk spots for the Mac session

- `SystemActionTrigger`:
  - `@convention(c)` typealiases and `unsafeBitCast` from `dlsym`. `RTLD_DEFAULT` is spelled `UnsafeMutableRawPointer(bitPattern: -2)`.
  - `nonisolated(unsafe) static let coreDockSendNotification`. If Swift 6.4 accepts C function pointers as `Sendable`, the `nonisolated(unsafe)` can go.
- `ContextObserver`: 16 static helpers are now `nonisolated private static`. `AXSnapshotResult` and the existing `AXElementBox` are `@unchecked Sendable`. If the region checker objects to `var table` captured in the detached task, collect the table through a local `AXSnapshotResult` builder instead.
- `ControlView`: `Task.detached { UIImage(data:)?.preparingForDisplay() }.value` needs `UIImage: Sendable`, which the iOS 17+ SDK provides.
- `DeviceAuthorizationManager`: `.seconds(ApprovalStatusCopy.pendingRequestTimeout)` uses the `Double` overload of `Duration.seconds`.
- `SettingsView`: `scrollEdgeEffectStyle(_:for:)` is iOS 26 SDK only. It's gated like `ToolbarSpacer`.

## Left alone, as the brief says

- Mirror display picker, desktop dots and cursor badge: STATUS 8b and 10, and the "Mirror — Spaces, displays and cursor awareness" ticket. They need a new message type, which waits for the protocol-reset session.
- No restructuring of `ControlMessage.swift`, `ControlReceiver`, `ControlView.swift` or `QuickActionsBar.swift`.
