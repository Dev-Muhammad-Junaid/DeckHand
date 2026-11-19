# Lane: Deck 2 model (D1)

Branch: `claude/pixelhand-lane-deck2-model`, cut from
`origin/claude/pixelhand-integration` at `d38f34e`, with the latest
integration (`f1af21b`) merged in before hand-off. Written in a Linux
container: PixelHandCore was built and tested here (Swift 6.2, **536 tests
pass**), and the Mac handler, the Shortcuts runner, `DeckStore`,
`ShortcutStore` and `TrackpadSender` were type-checked against stubs.
**The Mac and iOS apps were not compiled.**

## 1. What changed

### Core (`Core/Sources/PixelHandCore/Deck/`)

| File | What |
| --- | --- |
| `Action.swift` | Three Deck 2 cases: `menuCommand(bundleID:path:)`, `macShortcut(name:)`, `sequence(steps: [SequenceStep])`. `SequenceStep` = `run(action:)` or `delay(milliseconds:)`; its decoder refuses a nested `sequence` *before* decoding it, so hostile JSON can't nest (bounded decoder depth). `message` is now `ControlMessage?` (`nil` for the three new cases, which only run tracked). `needsAccessibility` is false for `macShortcut`; `kindName` for logs. |
| `ActionOutcome.swift` | `ActionOutcome` and `RefusalReason` moved here unchanged. |
| `ActionValidation.swift` | `ActionLimits` (bundle ID ≤ 255 B, key name ≤ 32 B, menu path ≤ 6 titles of ≤ 256 B, Shortcut name ≤ 256 B and no leading `-`, sequence 1…20 steps, pause 0…10 000 ms, ≤ 30 000 ms in all, receipt deadline 1.2 s, 40 ms gap between action steps) and `ActionValidation.issues(in:storable:)`. Dialog presses are never storable and never a sequence step. |
| `DeckDocument.swift` | Schema **2**: `schemaVersion`, `pages`, `followFrontApp` (default on), `pinnedPageID`, `hiddenAppBundleIDs`. `DeckPage.kind`: `home`, `app(bundleID:)`, `context`, `shortcuts`, `custom`; `hiddenCuratedIDs` per page. `DeckKey`: `appearance` (`label`, `glyph`, `tint` palette token), `action`, `confirm` ("Ask before running"), `pinnedToFirstRow`, `category`. `KeyGlyph`: `symbol(name:)`, `pixel(id:)` (the Design lane's 9 × 9 set, by ID), `custom(bitmap: PixelGlyphData)`, `appIcon(bundleID:)`. `PixelGlyphData`: 8 × 8 or 9 × 9 rows as bit masks plus an optional accent dot; `isWellFormed`, `hasThickStroke` (design rule 1, a warning). |
| `DeckValidation.swift` | Limits (2 MB document, 50 pages, 64 keys a page, labels and titles ≤ 64 characters, IDs ≤ 512 B, tokens ASCII `[A-Za-z0-9._-]`), `issues(in:)` and `repaired(_:)`, which keeps the good parts (drops bad keys and pages, later duplicates, a second Home/Context/Shortcuts or a second page for one app; trims labels and titles; clears a bad glyph, tint or pin). |
| `DeckMigration.swift` | `decode(_:)`: schema 2 as is, schema 1 (the skeleton) migrated (first general page → Home), newer → `.newerVersion`, anything else `.unreadable`, > 2 MB `.tooLarge`; always repaired. `encode(_:)` with sorted keys. `LegacyChips` + `fromLegacy(_:appName:)`: the chips' `customShortcuts.v1` / `hiddenCuratedShortcuts.v1` and the grid's `pinnedBundleIDs` / `hiddenBundleIDs` become a Home page (launch keys for pinned apps), one app page per app (custom and imported chips as `appShortcut` keys with their IDs, hidden presets as `hiddenCuratedIDs`) and `hiddenAppBundleIDs`. Deterministic. |
| `DeckDocument+Chips.swift` | The chip adapter: `chipBindings(for:)` (curated minus hidden, then the page's shortcut keys), `customChipBindings`, `hiddenCuratedIDsByApp`, `addChip`, `updateChip`, `deleteChip`, `restoreCurated`, `importChips` (same dedupe as before). |
| `DeckFollower.swift` | Follow-front-app state for UX-020: 400 ms debounce, returns to the user's page when the followed app goes, a pin or Follow off stops switching. |
| `DeckLoadPlan.swift` | What the store does at launch (stored / migrated / damaged → kept aside / newer → kept aside / first launch from chips / fresh). |
| `MenuPath.swift` | Title matching (case, diacritics, trailing `…`/`...`), exact title first; path from an imported chip's "File › New Tab". |
| `MacShortcutRun.swift` | `shortcuts run <name>` arguments (one argument, never a shell), 15 s timeout, exit status → `completed` / `failed`. |

Also in Core: `LockPolicy.allows(_:state:)` (below),
`RemoteInputValidation.isAcceptable(_ action:)`, protocol **12**.

### Protocol 12

No message cases added or removed; `Action` gained the three cases, so a
`deck.run` can carry them. Samples and fixtures `deck.run.menuCommand`,
`deck.run.macShortcut`, `deck.run.sequence`; every fixture re-recorded for
`v: 12`; history line in `Core/PROTOCOL.md`. The coordinator renumbers if
another lane takes 12 first.

### Validation and the lock gate

- `RemoteInputValidation.sanitize(.deck(.run))` now checks the action with
  `isAcceptable(_:)`: `ActionValidation` for every new string and number,
  and the old six as the message they stand for (also inside a sequence).
  A bad run is dropped whole, never partly run. Stricter than before for
  old actions in a run: an empty chord or a bundle ID with characters
  outside `[A-Za-z0-9._-]` is now dropped.
- `LockPolicy.decide(.deck(.run))` judges the action it runs
  (`LockPolicy.allows`): `menuCommand` and `macShortcut` refused while
  locked (receipt `refused(macLocked)`); a `sequence` runs only if every
  step may; old actions unchanged. The Mac asks again before **each** step,
  so a lock that comes mid-sequence stops the rest.

### Mac

- `Handlers/DeckHandler.swift`: old actions exactly as before. Deck 2
  actions run in a `SerialTaskQueue` (two macros never interleave), with
  **one receipt**: `completed` / `failed(reason)` when known within 1.2 s,
  else `delivered` at 1.2 s and the run finishes on its own (a late
  failure is logged to `DeckHandLog.input`). Sequence steps are awaited in
  order: `appShortcut` waits for its app (`activateAndWait`), `launchApp`
  awaits the launch, `shortcut`/`system`/`media` go through the router
  (`TypingQueue` keeps chords in order with typed text), 40 ms between
  action steps, stop at the first failure ("Step 3 of 5: …").
- New `DeckHandMac/Deck/MenuCommandPresser.swift`: activates the app, then
  follows the path one menu at a time (AXMenuBar → item → its AXMenu →
  …) with the same S9 hardening as `MenuShortcutDiscovery` (0.25 s
  messaging timeout, `MenuReadBudget` with a 1 s limit, its own serial
  queue), checks `AXEnabled`, then `AXPress`. Public AX API only.
- New `DeckHandMac/Deck/MacShortcutRunner.swift`: `Process` on
  `/usr/bin/shortcuts` (no shell), output to `/dev/null`, terminated after
  15 s.

### iOS

- New `DeckHandiOS/Deck/DeckStore.swift`: `DeckStore.shared`, the deck in
  `Application Support/Deck/deck.json` (atomic, file protection until
  first unlock), `update(_:)` repairs before saving and skips unchanged
  writes. A damaged or newer file is copied to `deck.damaged.json` /
  `deck.schema<N>.json` before the rebuild. The legacy `UserDefaults` keys
  are **left in place** (an older build still finds its chips; nothing
  writes them any more).
- `ShortcutStore.swift`: same API, now an adapter over `DeckStore`
  (`customBindings` / `hiddenCuratedIDs` are derived and still
  `@Published`). No view changed.
- `TrackpadSender.sendConfirmed`: see out-of-lane edits.

## 2. Mac / iPad checks

Install both builds (protocol 12 on both sides).

1. **Chips survive migration.** Before installing, note an app's chips in
   the Quick Actions bar and its shortcuts sheet (add a custom one, import
   menu shortcuts, hide a curated one, pin an app in the grid). Install,
   open: the same chips in the same order, the hidden preset still hidden,
   "Restore" brings it back, re-importing adds nothing. Console:
   `Deck loaded (legacyChips): N pages`; second launch `(stored)`.
2. **Chip edits persist.** Add, rename and delete a custom chip, force-quit,
   reopen: as left. `deck.json` appears under the app's Application Support
   (Xcode → Devices → Download Container).
3. **Menu-command key.** No UI yet: from a debug build, run
   `await sender.sendConfirmed(.menuCommand(bundleID: "com.apple.Safari", path: ["File", "New Private Window"]))`
   (or `["Window", "Merge All Windows"]`). Safari comes forward and the
   item is pressed; delivery dots show confirmed. A wrong title
   (`["File", "Nope"]`) shows failed; Console on the Mac: nothing logged
   unless the walk was slow. Try with the shortcut rebound in System
   Settings: still pressed.
4. **Sequence key.**
   `.sequence(steps: [.run(action: .launchApp(bundleID: "com.apple.TextEdit")), .delay(milliseconds: 800), .run(action: .appShortcut(bundleID: "com.apple.TextEdit", keys: ["cmd", "n"])), .run(action: .menuCommand(bundleID: "com.apple.TextEdit", path: ["Format", "Make Plain Text"]))])`:
   TextEdit opens, a new document, plain text. Receipt: `delivered` (it
   outlasts 1.2 s). Lock the Mac halfway through a long one: the rest
   doesn't run (log line "failed after its receipt … the Mac is locked").
5. **Mac Shortcut.** `.macShortcut(name: "<an existing shortcut>")` runs
   it; a name that doesn't exist reports failed (if it exits within
   1.2 s). A shortcut that hangs is stopped after 15 s.
6. **Locked Mac.** Lock the Mac; a menu-command or Shortcut run shows
   refused at once; a sequence of only key presses still types at the lock
   screen (as plain shortcuts do).

## 3. Compile risks (most likely first)

1. `DeckHandler.swift`: the `runs.enqueue { [weak self] in … }` closure
   (`@MainActor @Sendable`) captures `LoomConnectionHandle` and the
   `@MainActor` `Receipt` class; fine against the stubs, but if the real
   `LoomConnectionHandle` isn't `Sendable` it needs `nonisolated(unsafe)`
   or a capture through `self`.
2. `ShortcutStore.swift`: `deck.$document.dropFirst().sink { … }` with
   `MainActor.assumeIsolated` inside (the stubbed Combine can't check the
   real publisher's types).
3. `MenuCommandPresser.swift` (not type-checked: AX): `ref as? Bool` for
   `kAXEnabledAttribute` (a `CFBoolean`; bridges on macOS), and
   `kAXPressAction as CFString`.
4. `MacShortcutRunner.swift`: Swift 6 sendability of the termination
   handler closure (captures the `@unchecked Sendable` boxes only).
5. `DeckStore.swift`: `.completeFileProtectionUntilFirstUserAuthentication`
   under `#if os(iOS)`.
6. Anything that switched exhaustively over `Action` or used
   `action.message` as non-optional (none found in the apps; Core updated).
7. Not new: `Scripts/linux-typecheck/run.sh` fails on integration too, in
   `SubscriptionStore.swift` (`StoreKit` stubs). Without that file every
   listed file type-checks clean.

## 4. Out-of-lane edits

- `DeckHandiOS/TrackpadSender.swift` (iOS interaction): in
  `sendConfirmed`, a host without receipts gets `.failed` for an action
  with no domain message instead of calling `send(action.message)` (5
  lines).
- `Core/System/LockPolicy.swift` (Mac system): the `deck.run` case now
  calls the new `LockPolicy.allows(_:state:)`, added next to it.
- `Core/Input/RemoteInputValidation.swift` (shared): the `deck.run` case
  and the new `isAcceptable(_ action:)`.
- `Core/Protocol/PixelHandProtocol.swift`, `Core/PROTOCOL.md`, fixtures and
  `ProtocolContractTests` samples: protocol 12 (PROTOCOL.md process).
- `Scripts/linux-typecheck/run.sh` and `Stubs.swift`: three files added to
  the list; stubs for `MenuCommandPresser`, and `Published.projectedValue`
  / `AnyCancellable` for `ShortcutStore`.
- **No edits** to `QuickActionsBar.swift`, `StreamDeckGridView.swift`,
  `QuickActions/**` or `AppShortcutsSheet.swift`.

## 5. Notes for UX-020 (Deck 2 UI)

- Read and write through `DeckStore.shared.document` / `update(_:)`; it
  repairs on save, so the UI can't store a bad deck. Use
  `DeckValidation.keyIssues` to show inline errors in the key inspector.
- `DeckFollower` is the Follow-front-app state: feed it
  `activeAppUpdate`, call `update(document:now:)` at `nextDeadline`, show
  `effectivePageID(in:)`. `followedBundleID` drives the title's app badge.
  The pin is `document.pinnedPageID` (stored; clear it at launch if it
  should last only a session, as the spec says).
- Keys: `appearance.glyph` order of preference for drawing is `custom` →
  `pixel(id:)` (unknown ID → draw a fallback, never drop the key) →
  `appIcon` → `symbol`. The 8 × 8 editor can save 9 × 9 later without a
  schema change (`PixelGlyphData.size`).
- Curated presets aren't stored; they appear at show time minus
  `hiddenCuratedIDs`. The grid's pinned/hidden apps still live in
  `StreamDeckGridView`'s `@AppStorage`; the deck has a copy from
  migration (Home's launch keys, `hiddenAppBundleIDs`). When the grid
  moves onto the deck, drop the `@AppStorage` keys.
- Receipts: a Deck 2 run answers once; `delivered` means "still running
  after 1.2 s". A per-step progress receipt would be a protocol change.
- `MenuPath.path(fromDisplayName:)` turns an imported chip into a
  `menuCommand` ("press the menu item instead"), for the action library.
- The Shortcuts page needs a Mac list of shortcuts (`shortcuts list`), D4,
  not in this lane.

Lane: READY TO MERGE
