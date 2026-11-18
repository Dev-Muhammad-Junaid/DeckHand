# Lane: Mac system control (S7, S8, S9, Spaces monitor)

Branch: `claude/pixelhand-lane-mac-system`, cut from
`origin/claude/pixelhand-integration` at `f97b40f`, with the latest
integration (`17e2f7a`) merged in before hand-off. Written in a Linux
container: PixelHandCore was built and tested here (Swift 6.2), the Mac
handlers, `ControlReceiver` and `LockGate` were type-checked against stubs.
**The Mac and iOS apps were not compiled.** Everything was re-implemented
from Sill's documented behaviour (`docs/locked-mac-plan.md`,
`docs/DEVELOPMENT.md` "A sleeping display", `docs/trackpad-gestures-plan.md`
§2.3); no Sill code was copied.

## 1. Commits

| Commit | What |
| --- | --- |
| `36823a5` | `RefusalReason.macLocked` (Core `Deck/Action.swift`, integration-owned: one case, announced here) |
| `677c681` | Core: hot-key table and resolver, lock policy, display-wake throttle, `DisplayLayout`, Spaces parser and edge rules, menu-read budget; protocol 3 |
| `3288fb8` | S9: `MenuShortcutDiscovery` bounded reads |
| `fc43331` | Mac: `SymbolicHotKeys`, `SystemActionTrigger`, `SystemHandler`, `SpacesMonitor`, `LockState`, `LockGate`, `DisplayWake`, the gate call in `ControlReceiver`, context withholding, type-check stubs |
| `b22daee` | iOS: lock banner, `displayLayout` / `macLockState` on the session model |
| `9a6c3b3` | Wait for the first lock reading before telling a new remote |
| (merge) | latest `claude/pixelhand-integration` |
| (last two) | Stop the mirror when another user takes the console; this doc |

## 2. What changed

### Protocol 3 (`PixelHandProtocol.version = 3`)

Mac → remote only; nothing a remote sends changed.

- `system.displayState(layout: DisplayLayout)`: every display (main first,
  then left to right) with `displayID`, `name`, `isMain`, global `bounds`,
  its Spaces in Mission Control order (`desktop` / `fullScreen` with the
  app name), `currentSpaceIndex`, plus `cursorDisplayID`, `spacesKnown`
  and `separateSpaces`. Sent on connect, on Space change, on a display
  change, when the pointer crosses displays (≤ 10 checks/s), and after a
  refused Space switch. Identical snapshots aren't re-sent. While the Mac
  is locked it is sent without Space data.
- `system.lockState(state: MacLockState)`: `unlocked | screenLocked |
  offConsole`, on connect (after the first reading) and on every change.
- `RefusalReason.macLocked` in `deck.receipt`.
- Fixtures re-recorded (`system.displayState`, `.noSpaces`,
  `system.lockState`, `.offConsole`, `deck.receipt.refused.macLocked`; 37
  cases). The hostile-input tests now use `PixelHandProtocol.version`
  instead of a literal `2`.
- **Renumbering:** the Network lane is also bumping. Whoever merges
  second takes the next number: change `PixelHandProtocol.version`, the
  history line in `Core/PROTOCOL.md`, then
  `PH_RECORD_FIXTURES=1 swift test --package-path DeckHand/Core --filter ProtocolContractTests`.

### S7: the user's own system shortcuts (no more `osascript`)

- Core `System/SymbolicHotKeys.swift`: ids and Apple's defaults
  (32 Mission Control ⌃↑, 33 App windows ⌃↓, 36 Show Desktop F11, 79/81
  Spaces ⌃←/⌃→, 108/110/115 the Mission Control key alone / ⌘ / ⌃,
  160 Show Launchpad, 173 the Launchpad key), and `SymbolicHotKeyResolver`:
  the first candidate that is on and bound is posted as is (dedicated keys
  first, since ⌃ fn arrows are also the window-tiling shortcuts); if every
  one is off, the primary is switched on for ~1.2 s (bound to its default,
  or ⌃⌥⇧⌘F19 for Launchpad) and restored; if the CGS read calls are
  missing, Apple's default chord is posted.
- Mac `SymbolicHotKeys.swift`: `dlsym` for `CGSGetSymbolicHotKeyValue`,
  `CGSIsSymbolicHotKeyEnabled` (required) and `CGSSetSymbolicHotKeyValue`,
  `CGSSetSymbolicHotKeyEnabled` (optional, for the temporary switch-on),
  plus `CoreDockSendNotification`. The key up carries the modifiers that
  were down before, so ⌃/fn don't leak into the next click.
- `SystemActionPlan`: Mission Control = `symbolicHotKey`, then
  `open -a "Mission Control"`; App Exposé = `symbolicHotKey` only (the
  System Events path and its Automation prompt are gone). Show Desktop and
  Launchpad keep the build-1 plans; their `symbolicHotKey` step now uses
  the resolver, so a user binding of ⌘+Mission Control key or the Launchpad
  key is used before any temporary switch-on. New overrides:
  `PixelHandMissionControlMechanism`, `PixelHandAppExposeMechanism`.
- `SystemHandler.handleSwitchSpace` posts 79/81 through the same path.
  `osascript` is now only the last-resort F11 for Show Desktop.

### Spaces monitor and edge rules

- Mac `SpacesMonitor.swift`: `CGSMainConnectionID` +
  `CGSCopyManagedDisplaySpaces` via `dlsym`, UUIDs via
  `CGDisplayCreateUUIDFromDisplayID` (ColorSync), names from `NSScreen`,
  full-screen app names from `TileLayoutManager.TileSpaces[].appName` or
  the Space's `pid`. Symbols missing → displays without Space fields.
- Core `SpaceNavigation.decide`: `switchTo(index)`, `refused(singleSpace |
  atFirstSpace | atLastSpace)`, `unknown` (no data: try and watch).
  `handleSwitchSpace` refuses past either end without moving the pointer
  and sends that remote a fresh snapshot; the 800 ms wait and pointer
  restore stay as the backstop.
- "Displays have separate Spaces" off (one managed entry, several displays)
  → every display carries the shared strip, `separateSpaces == false`.

### S8: locked-Mac gate and display wake

- Core `LockPolicy`: witnesses → one reading (off console beats locked
  beats unlocked; any locked witness wins), `LockReader` (a lock at once,
  an unlock after 2 s settled; first reading taken as is), and
  `decide(message, state)`:

  | | screen locked | off console |
  | --- | --- | --- |
  | session, pairing, mirror stop | allowed | allowed |
  | input (type the password, click) | allowed | refused |
  | Locate | allowed | refused |
  | other system actions, Space switches | refused | refused |
  | launch, app shortcut, dialog press, menu import | refused | refused |
  | app list | deferred: sent at the unlock | deferred |
  | `deck.run` | judged as its action; refused → receipt `.refused(.macLocked)` | same |
  | mirror start | allowed (shows the lock screen) | refused |
  | full-screen / region screenshot | allowed | refused → `screenshotError` |
  | window screenshot, window list | refused → error / empty list | same |

  Frontmost app, running apps, dialog context and full-screen app names are
  withheld while locked and sent again at the unlock.
- Mac `LockState.swift` (`MacLockMonitor`): witnesses are the public
  `CGSessionCopyCurrentDictionary` (`kCGSSessionOnConsoleKey`, plus the
  undocumented `CGSSessionScreenIsLocked` key), notify(3)
  `com.apple.sessionagent.screenIsLocked`, `SCDynamicStoreCopyConsoleUser`,
  and the lock/unlock and session switch notifications. No private
  *symbols*, so no `dlsym` needed; an undocumented key/name that goes away
  just drops that witness. The session read is bounded to 0.5 s off the
  main actor; no answer counts as locked. If no witness answers at all for
  three looks the gate turns itself off with an error line.
- Mac `LockGate.swift`: the one call in `ControlReceiver.consumeMessages`;
  answers refusals; does display wake and the pointer-display check for
  messages it admits. `MacSystemSession` fans connection start/end and
  lock changes out to this lane's monitors (hooked from
  `ActiveAppMonitor.addConnection/removeConnection`, so `ControlReceiver`
  has no other edit). Going off console stops every mirror stream and sends
  `mirror.error` with an explanation.
- Mac `DisplayWake.swift`: `IOPMAssertionDeclareUserActivity(…,
  kIOPMUserActiveLocal, …)` on connect (not while locked) and for a person's
  action (input, system actions, launches, runs, screenshots; never pings,
  list requests or mirror starts), at most every 5 s; never off console.

### S9: hardened menu reading

`MenuShortcutDiscovery`: `AXUIElementSetMessagingTimeout` 0.25 s on the app
and every element; one `AXUIElementCopyMultipleAttributeValues` per
element; Core `MenuReadBudget` caps depth 5, 3000 elements, 400 shortcuts,
250 children per menu, 4 s, and stops after 3 time-outs in a row; runs on
its own serial `DispatchQueue`. Partial results are kept; early stops are
logged (`category: context`).

### iOS (minimal, announced)

- `ControlSessionModel`: `// MARK: Mac system` with `macLockState` and
  `displayLayout`; one `case .system` in `handleOnMain`; logic in
  `Control/ControlSessionModel+MacSystem.swift`.
- `ControlView`: one `HostCapabilityBanner` with
  `MacLockState.bannerText(macName:)` when locked.

### For the Mirror lane

Read `session.displayLayout` (`DisplayLayout`, Core `Models/DisplayLayout.swift`):
`display(id)`, `cursorDisplay`, `spaceCount`, `currentSpaceIndex`,
`fullScreenSpaces`. Use `SpaceNavigation.canMove(_:on:)` to dim/hide ‹ ›
(it already says "hide both" for one desktop via `.refused(.singleSpace)`);
`spacesKnown == false` means hide the dots and keep the chevrons.

## 3. Tests (Linux)

```
swift test --package-path DeckHand/Core      # ✔ 165 tests in 23 suites
DeckHand/Scripts/linux-typecheck/run.sh      # Build complete (ControlReceiver, Handlers/*, LockGate, TrackpadSender)
```

New suites: `SymbolicHotKeyResolverTests` (defaults table, preference
order, rebound and masked chords, temporary enable, unbound spare chord,
unreadable keys, symbols missing), `LockPolicyTests` (witness rules,
public-only fallback, settle and flap, every decision row),
`DisplayWakePolicyTests`, `DisplayLayoutTests` (round trip with and
without Spaces, hostile index, 1 desktop, 3 desktops at either end,
full-screen Spaces, the owner's two-display layout parsed from raw
dictionaries, split view, "Main", shared strip, symbol missing, garbage
input), `MenuReadBudgetTests`. `SystemActionPlanTests` updated for the new
Mission Control / App Exposé plans.

## 4. Mac checks (owner's Mac, macOS 27, two displays)

Build: `xcodegen generate` (new files only, no `project.yml` change), both
apps, `DeckHandTests`, `swift test --package-path Core` (expect 165).
**Both devices must run protocol 3.** Console filter:
`subsystem:com.widgetsflow.pixelhand`.

| Area | Check |
| --- | --- |
| Mission Control | Quick Actions → Mission Control opens it. Log: `missionControl: posting the user's shortcut 108 (fn key 160)` then `ran via symbolicHotKey`. No Automation prompt. Rebind Mission Control in System Settings to e.g. ⌥⌘M, turn off the Mission Control key shortcut, tap again: still opens, log names 32 and the new chord. |
| App Exposé | Opens from the remote; log `applicationWindows: posting … 115` (or 33). No System Events. |
| Show Desktop (27) | As in `BUILD1-FIXES.md` §1: with key 36 off, tap → windows slide away, log `Symbolic hot key 36 for showDesktop: posting fn key 103 (was off, bound)`; 2 s later `defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys` shows 36 still `enabled = 0`. If nothing happens, `defaults write com.widgetsflow.pixelhand.mac PixelHandShowDesktopMechanism dockNotification` (then `dedicatedKey`) and report which works. |
| Launchpad / Apps (27) | As in `BUILD1-FIXES.md` §2. With the Launchpad-key shortcut (173) on, the log shows `posting the user's shortcut 173 (fn key 131)`; with it off, `Symbolic hot key 160 … (was off, unbound)` and 160 restored after ~2 s. Spotlight must not open. |
| Modifiers | Right after Mission Control or a Space switch, a tap on the trackpad is a plain click, not a ⌃-click (no context menu). |
| Spaces, two displays | HP main with 1 desktop, built-in with 3. Mirror the HP, press ›: nothing moves, the pointer stays, log `Space switch next on display … refused: singleSpace`. Mirror/point at the built-in on desktop 1: ‹ refused (`atFirstSpace`), › goes to 2 and the pointer centres there with Locate; on 3, › refused (`atLastSpace`). Add a full-screen app on the built-in: it counts as a Space. |
| Snapshot | iPad log or a debugger on `session.displayLayout`: displays named, HP `spaceCount 1`, built-in `3`, `currentSpaceIndex` follows ⌃→ pressed on the Mac's own keyboard; moving the pointer to the other display updates `cursorDisplayID` within ~0.1 s; plug/unplug a display updates the list. |
| Locked Mac | Lock the Mac (⌃⌘Q). iPad banner "… is locked. Type its password …". Mac log `Locked: this Mac's screen is locked …`. From the iPad: typing the password + Return unlocks it; Mission Control, app launch, an app chip (dot turns red), dialog chips, menu import, window list (empty) and a window screenshot (error "The Mac is locked.") are refused; a full-screen screenshot shows the lock screen. ~2 s after unlocking: banner gone, `Unlocked:` line, front app / running apps / dialog chips back, an app list asked for while locked arrives. |
| Fast user switch | Switch to another user (or the login window): banner "Another user is using …", log `Locked: another user …`, a running mirror stops with the explanation, trackpad input does nothing, mirror start refused. Switch back and unlock: everything returns. |
| Test hook | DEBUG only: `defaults write com.widgetsflow.pixelhand.mac PixelHandTestLockState screenLocked` (or `offConsole`) forces a locked reading within a second; `defaults delete …` to undo (unlock still settles 2 s). |
| Display wake | Let the Mac's display sleep, connect the iPad: the display turns on (log `Display wake: woke the display …`). Let it sleep again with the iPad connected and idle: it sleeps per the Mac's setting. Move the trackpad: it wakes. `pmset -g assertions` shows `UserIsActive named: "Pixel Hand: a remote is using this Mac"`. While locked the connection alone doesn't wake it; typing does. |
| Menu import (S9) | Import shortcuts for Safari, Xcode and a big app (Chrome, Excel): chips arrive, menus load in < 4 s; no `AX recompute slow` storms. Hang an app (e.g. a busy script editor) and import: returns quickly with what it read, log `Menu read … stopped early (appNotAnswering)`. |
| Unchanged | Locate, media keys, chips, capture, mirror, approval Allow/Deny still work unlocked. |

## 5. Compile risks (most likely first)

1. `LockState.swift`: `notify_register_dispatch` / `notify_get_state` /
   `NOTIFY_STATUS_OK` are expected from `import Darwin`; if not found, add
   `import notify`. `NOTIFY_STATUS_OK` is compared as `UInt32(…)`; if the
   SDK imports it as an enum, use `.rawValue`. The notify handler closure
   uses `MainActor.assumeIsolated` (it is delivered on the main queue).
2. `LockState.swift`: `@objc nonisolated` selectors on a `@MainActor
   NSObject` subclass, hopping back with `Task { @MainActor … }`.
3. `SpacesMonitor.swift`: `import ColorSync` for
   `CGDisplayCreateUUIDFromDisplayID` (returns `Unmanaged<CFUUID>?`); the
   `@convention(c) (Int32) -> Unmanaged<CFArray>?` typealias for
   `CGSCopyManagedDisplaySpaces` (it's a Copy: `takeRetainedValue`).
4. `DisplayWake.swift`: `import IOKit.pwr_mgt`; `kIOPMUserActiveLocal`,
   `IOPMAssertionID(kIOPMNullAssertionID)`, `result == kIOReturnSuccess`.
5. `MenuShortcutDiscovery.swift`: `AXUIElementCopyMultipleAttributeValues`
   with `AXCopyMultipleAttributeOptions(rawValue: 0)`; `AXError.cannotComplete`.
   `RawMenuItem` is now `Sendable` and crosses from a `DispatchQueue` into a
   continuation.
6. `SymbolicHotKeys.swift`: `CGSHotKeyCalls` keeps the build-1 pattern
   (`@convention(c)` + `unsafeBitCast` from `dlsym`); `setValue` /
   `setEnabled` are now optional.
7. `ControlSessionModel`: two new stored `var`s (not `private(set)`, so the
   extension file can set them) under `@Observable`.

## 6. Out-of-lane edits

| File | Edit |
| --- | --- |
| `DeckHandMac/ControlReceiver.swift` (hot spot) | the allowed S8 gate call in `consumeMessages` (3 lines with comment) |
| `Core/Deck/Action.swift` (integration) | `RefusalReason.macLocked` |
| `Core/Protocol/PixelHandProtocol.swift`, fixtures + `MANIFEST`, `Core/PROTOCOL.md` (hot spot) | version 3, re-recorded, history line, `system` row |
| `Core/Tests/…/ProtocolContractTests.swift` | samples, case names, count 37, version-independent hostile JSON |
| `Core/Tests/…/RemoteInputValidationTests.swift` (iOS interaction) | one JSON literal uses `PixelHandProtocol.version` instead of `2` |
| `DeckHandiOS/Control/ControlSessionModel.swift` (hot spot) | `// MARK: Mac system` (2 properties) and one `case .system` |
| `DeckHandiOS/ControlView.swift` (integration) | one lock banner (3 lines) |
| `Scripts/linux-typecheck/Stubs.swift`, `run.sh` | stubs for this lane's types; `LockGate.swift` added to the default list |

New files: Core `System/SymbolicHotKeys.swift`, `System/LockPolicy.swift`,
`System/DisplayWakePolicy.swift`, `System/SpaceNavigation.swift`,
`System/MenuReadBudget.swift`, `Models/DisplayLayout.swift` and four test
files; Mac `SymbolicHotKeys.swift`, `SpacesMonitor.swift`,
`LockState.swift`, `LockGate.swift`, `DisplayWake.swift`; iOS
`Control/ControlSessionModel+MacSystem.swift`.

## 7. Info.plist, entitlements, project.yml

None. No new private framework is linked (everything is `dlsym`); IOKit,
ColorSync and SystemConfiguration are system frameworks found by
auto-linking. `com.apple.security.automation.apple-events` stays: the F11
System Events path is still Show Desktop's last resort.

## 8. Not done / follow-ups

- Handlers off the main actor (PH-005's suggestion) — not started; the
  S9 menu walk and the lock witnesses are off main.
- A lock-screen placeholder frame for the mirror (Sill streams a still)
  belongs to the Mirror lane; this lane only stops the mirror off console.
- S11's gestures can call `SymbolicHotKeys.shared.perform(_:)` with a
  `HotKeyAction`; ask this lane for any new action.
- The Mirror lane's chevrons/dots/badge consume `displayState` (§2).

Lane: READY TO MERGE
