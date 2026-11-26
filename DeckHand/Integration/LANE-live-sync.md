# Lane: live text sync, Phase 1 (live-sync)

Branch `claude/pixelhand-lane-live-sync`, from `claude/pixelhand-integration`
at `1fbd090` ("Record the owner's live sync decisions"). It builds Phase 1
of `Product/Design/RD-live-sync-and-caret.md` (§1, §3 items 1–4 and 6, §4,
§5, §6) as the owner approved it (`DECISIONS.md`, "2026-11-27 — Live text
sync and caret gestures"). Board: https://claude.ai/artifact/GWCG3cn1GAqmD2Dyg37fq5.

**Protocol bump 16 → 17.** No `project.yml`, Info.plist, entitlement or Loom
change; new files are picked up by the folder sources. Written in a Linux
container: Core built and tested here (Swift 6.2); the Mac handlers,
`FocusTextSync`, `TrackpadSender` and the iPad's `LiveTextSync` are
type-checked against stubs. **The Mac and iOS apps were not compiled.**

**Not in this lane:** the arrow joystick (parallel lane
`claude/pixelhand-lane-caret-joystick`; the arrow cluster's gesture code is
untouched), Phase 2 (web/Electron opt-in, "Allow for Claude",
`system.allowTextReading`, the blind floating-cursor trackpad) and Phase 3
(loupe tap).

| Item | Status | Files |
|---|---|---|
| 1 Mac `FocusTextObserver` | Built (needs a Mac check) | Mac `FocusTextObserver.swift` (new) |
| 2 Mac `textState` | Built (needs a Mac check) | Core `Models/FocusedTextState.swift` (new), `System/TextSyncPolicy.swift` (new); Mac `FocusTextSync.swift` (new), `FocusTracker.swift`, `FocusReader.swift` |
| 3 Applying edits (select, then type; MAC WINS) | Built (needs a Mac check) | Core `Input/TextEdit.swift` (new); Mac `FocusTextSync.swift`, `Input/TypingQueue.swift`, `Handlers/InputHandler.swift` |
| 4 Protocol 17 | Built, fixtures recorded | Core `Protocol/InputMessage.swift`, `Protocol/SystemMessage.swift`, `Protocol/PixelHandProtocol.swift`, `System/LockPolicy.swift`, `System/DisplayWakePolicy.swift`, `Input/RemoteInputValidation.swift`, `PROTOCOL.md`, fixtures; Mac `Handlers/SystemHandler.swift` |
| 5 iPad synced Live field | Built (needs an iPad check) | Core `Input/TextSyncReconciler.swift` (new); iOS `Keyboard/LiveTextSync.swift` (new), `Keyboard/LiveTypingField.swift`, `Keyboard/TypePanel.swift`, `Control/ControlSessionModel.swift`, `+MacSystem.swift`, `+Mirror.swift`, `TrackpadSender.swift` |
| 6 Keyboard settings in synced Live | Built (needs an iPad check) | iOS `Keyboard/LiveTypingField.swift` |
| 7 Sync badge | Built (needs an iPad check) | Core `SyncBadge` (in `TextSyncReconciler.swift`); iOS `SyncBadgeView` in `Keyboard/TypePanel.swift` |
| 8 Tab-accept | Kept; the accepted text now shows from the Mac's next value change | iOS `Keyboard/TypePanel.swift` (comment only) |

## What changed

### Protocol 17 (`Core/PROTOCOL.md`, history line 17)

- `system.watchFocus(on:wantsText:)`: `wantsText` is true while the Type
  panel's Live field is open on screen. **Nothing reads text without it.**
  The loupe alone sends `wantsText: false` (geometry only, as in 16).
- Mac → remote: `system.textState(state: FocusedTextState)` and
  `system.textEditResult(result: TextEditResult)`.
- Remote → Mac: `input.textEdit(edit: TextEditRequest)`,
  `input.textSelect(selection: TextSelectRequest)`,
  `input.caretMove(move: CaretMove)`.
- All offsets UTF-16 and **absolute in the field**. `FieldToken` encodes
  as a bare number.
- One deliberate addition to the doc's §4 sketch: `TextEditContext` carries
  `beforeLength` and `afterLength` next to the two hashes (`beforeHash` =
  FNV-1a of ≤ 10 units before the range plus the replaced units,
  `afterHash` = ≤ 10 units after). Near a window's edge the iPad has less
  context than the Mac; with explicit lengths both hash the same units.
- `TextReadability.unsupported` carries the app's name (`unsupported(app:)`),
  like `webOff(app:)`, so the reason line can say "Chrome doesn't share its
  text".
- `input.caretMove` is in 17 as the doc's §4 has it, and **the Mac handles
  it** (coalesced arrow chords through `TypingQueue`, refused under secure
  input or while locked), so the joystick lane can send it without another
  protocol bump. See "Coordination" below.
- Fixtures: `input.textEdit`, `input.textSelect`, `input.caretMove`,
  `system.watchFocus` (now with `wantsText`), `system.watchFocus.loupeOnly`,
  `system.textState` (+ `.webOff`, `.secure`, `.locked`),
  `system.textEditResult` (+ `.conflict`, `.refused`); every fixture and
  `MANIFEST` re-recorded for `v: 17`. 64 cases.
- Lock gate: `textEdit`, `textSelect`, `caretMove` refused while locked or
  off console (the password still types as keys); `watchFocus` admitted.
  `LockPolicy.withholdsText`: one `.locked` state, nothing read.
- `RemoteInputValidation`: a `textState` / `textEditResult` from a remote
  is dropped; `textEdit` needs a sane range, context lengths ≤ 10, and a
  replacement ≤ 4 KiB that cleaning leaves unchanged (`\n`/`\t` only; an
  empty replacement is a deletion and passes); `textSelect` a sane range;
  `caretMove` count clamped to 1…60 (0 dropped).
- `DisplayWakePolicy`: the new Mac → remote cases aren't person actions;
  the new input cases are (like all input).

### Core (pure, tested here)

- `Models/FocusedTextState.swift`: `TextRange`, `FieldToken`,
  `TextReadability` (+ `reasonLine`, the doc's §1.3 copy),
  `TextWindow`, `FocusedTextState`, `TextEditContext`, `TextEditRequest`,
  `TextSelectRequest`, `TextEditRefusal`, `TextEditOutcome`,
  `TextEditResult`, `CaretMove` (+ `chord`).
- `Input/TextEdit.swift`: `TextEdit.between(old, new)` (common prefix and
  suffix by whole characters compared on exact UTF-16 units, reported in
  UTF-16; never splits an emoji, flag or combining sequence);
  `TextUnits` (substring, replace, character boundaries, character counts,
  surrogate-safe window alignment); `TextHash.fnv1a`;
  `TextEditContext.make`; `TextEditCheck` (the Mac's decision: apply where
  sent, rebase within ±64 units where the context moved, conflict, or
  refuse: secure, locked, field changed, not editable, invalid).
- `System/TextSyncPolicy.swift`: `readability(…)` (locked → secure input →
  no focus → password → terminal bundle → web/Electron (`webOff`) or
  Chromium (`unsupported`) → native text roles; an `AXTextArea` > 100 k
  units without `AXInsertionPointLineNumber` is a terminal), the window
  (1 000 units, a third before the caret, kept still until the caret comes
  within 150 units of an edge that isn't the field's own),
  `arrowChords` (selection by arrow keys where AX can't set it; counts
  characters, not units), `chords(for: CaretMove)`, `TextSyncPacer`
  (leading edge, ≤ 1 per 33 ms, one trailing), `TextRevisionTracker`
  (token per focus epoch, revision per change), `TextSyncLog` (log lines
  with offsets and sizes only; **text never reaches a log**).
- `Input/TextSyncReconciler.swift` (the iPad's rules) and `SyncBadge`:
  - shows the Mac's window with the caret at its selection;
  - local echo; one edit in flight; changes meanwhile go as one edit after
    the answer, merged with what the Mac did meanwhile when the two don't
    touch, else MAC WINS;
  - the Mac's intermediate states (it types key by key) never touch the
    field while an edit is in flight (echo suppression);
  - after the answer: the Mac's text shows only if it differs (its
    autocorrect, a Tab-accepted suggestion), never typed back; a caret the
    person moved meanwhile goes out as `textSelect`;
  - `conflict` → the Mac's text, the refused haptic, MAC WINS for 1.4 s;
  - composition hold: nothing goes and Mac updates wait while marked text
    is up, applied at commit;
  - `textSelect` for local caret moves; the Mac's states still showing the
    old selection are ignored for 0.5 s;
  - an unanswered edit is given up after 3 s (the Mac's text shows);
  - a replacement over 4 KiB goes in parts;
  - unreadable → `becameBlind` (the field returns to the blind buffer).

### Mac

- **`FocusTextObserver.swift`** (new, Accessibility glue, parse-checked
  only): a dedicated thread with its own run loop (never the main actor or
  the concurrency pool); one `AXObserver` per front pid, re-created on
  `NSWorkspace.didActivateApplicationNotification`;
  `kAXFocusedUIElementChangedNotification` on the app, value / selected
  text / destroyed on the focused element (moved when focus moves);
  callbacks only note the change, Core's pacer gives ≤ 30 reads a second;
  0.1 s messaging timeout on every element. Reads: secure input
  (`IsSecureEventInputEnabled`) and the lock are checked before any AX call;
  role, subrole and `AXWebArea` ancestry before any value; the value only
  for fields ≤ 20 000 units, else `AXStringForRange` for the window;
  windows cut through a surrogate pair are trimmed. `canSetSelection` =
  `AXSelectedTextRange` settable; `canEdit` = `AXValue` settable (used as
  the editable signal only: **`AXValue` is never set**) and enabled.
  Writing: only `AXSelectedTextRange`, read back to confirm.
- **`FocusTextSync.swift`** (new, main actor, type-checked): text watchers
  (`wantsText`), the revision tracker, `textState` to every text watcher on
  change; the observer's notifications and the geometry poll
  (`FocusTracker` calls `pollTick`, the safety net) both trigger reads;
  reads are numbered so a stale one never follows a fresh one.
  `textEdit`: one at a time after any queued typing; fresh read;
  `TextEditCheck`; select (AX, else arrow keys from the known caret);
  **type** the replacement through `TypingQueue` (a deletion is one Delete
  over the selection; over 200 characters as Unicode strings, 20 units an
  event, so a long paste takes a fraction of a second and the clipboard
  isn't touched); wait for the typing; read; send `textState` (if changed)
  then `textEditResult`. Conflict and refusals type nothing.
  `textSelect`: the same selection step. `caretMove`: arrow chords.
- `FocusTracker.swift`: `watch(_:wantsText:connection:)` hands text
  watching to `FocusTextSync`; `pollTick` after each look; disconnect and
  lock forwarded.
- `FocusReader.swift`: `Frontmost` gains `bundleID`.
- `Handlers/SystemHandler.swift`, `Handlers/InputHandler.swift`: the new
  cases.
- `Input/TypingQueue.swift`: `type(_:preferKeys:)` (default `true`, so
  every existing caller is unchanged).

### iPad

- **`Keyboard/LiveTextSync.swift`** (new, type-checked): one per session
  (`ControlSessionModel.liveText`); runs the reconciler's effects: sends
  edits (an edit typing Return goes through the panel's Return guard) and
  selections, shows text in the field, plays the refused haptic
  (`GestureHaptic.double`), publishes `badge`, `isSynced`, `reasonLine` and
  refreshes the badge when MAC WINS ends.
- `Control/ControlSessionModel+MacSystem.swift`: `textState` /
  `textEditResult` routed to it; `setLiveTextWanted(_:)` and
  `updateFocusWatch()` (one `watchFocus(on: loupe || live, wantsText:
  live)`); `+Mirror.swift`'s loupe uses it; `ControlSessionModel.swift`
  re-asks when the session (re)starts.
- `TrackpadSender.swift`: `watchFocus(_:wantsText:)`, `sendTextEdit`,
  `sendTextSelect`, `sendCaretMove`.
- `Keyboard/LiveTypingField.swift`, **synced Live** (when `sync.isSynced`):
  the Mac's text, multi-line, caret at the Mac's selection, scrolled to it;
  local edits → `sync.localChange` (composing while marked text is up);
  caret moves → `sync.localSelection` (no snap to the end: taps, the
  space-bar trackpad and the selection handles all send `textSelect`);
  the Mac's text is applied with a guard so it never counts as an edit;
  a latched modifier still turns the next letter into a chord. **Keyboard**
  (owner decision 2): autocorrect and predictions on, smart quotes, dashes
  and insert/delete off (as before), spell-check underline off
  (`spellCheckingType = .no`), **no local undo**: `undoManager` is a
  `MacUndoManager` whose undo / redo (shake, three-finger swipe, edit menu)
  send ⌘Z / ⇧⌘Z; hardware ⌘Z already went to the Mac. **Blind** (not
  readable, the classic layout, Compose): exactly as before.
- `Keyboard/TypePanel.swift`: `liveSync` and `onLiveTextWanted` (the host
  passes the session's); Live open on screen → `setLiveTextWanted(true)`,
  Compose / closed / folded → `false`; the badge overlay; the reason line
  as the field's placeholder when blind ("Password field: the text stays
  on the Mac", "Web text is off for Claude", "Terminal: keys only", "No
  text field", "Mac is locked"); Accept ⇥ unchanged.
- **`SyncBadgeView`** (in `TypePanel.swift`): dot-matrix (pitch 1.3) with a
  3 pt pixel, top-trailing in the field: SYNC + mint pixel, SENDING +
  phosphor pixel with a glow, MAC WINS amber on the warning tint (1.4 s),
  BLIND dim at 60 %. Takes no touches; VoiceOver: "In sync with the Mac" /
  "Sending to the Mac" / "The Mac's text won" / "Typing blind: …" with the
  reason as its value. Identifier `ph.type.sync`.

## Tests

- **Core**: `swift test --package-path DeckHand/Core`: **1371 / 1371 pass**
  (245 suites); 1305 before, so 66 new, in `LiveTextSyncTests.swift`:
  `TextEditBetweenTests` (11: append, delete, autocorrect mid-text, insert,
  equal, emoji and skin tones, flags and combining marks, canonical
  equivalence, CJK, RTL, repeats), `TextUnitsTests` (5),
  `TextEditCheckTests` (7: applied, rebased, conflict, past the radius,
  absolute offsets deep in a field, refusals, outcomes),
  `TextSyncPolicyTests` (14: readability rules and reason copy, the window
  slider, pacer and a 5 ms burst ≈ 30/s, tokens and revisions, arrow
  plans through emoji, `caretMove` chords and clamping),
  `TextSyncReconcilerTests` (23: shows the Mac's text, Tab-accept, applied,
  echo suppression, one in flight, answer before state, rebased, Mac
  autocorrect never typed back, conflict and the 1.4 s badge, merge,
  merge collision, composition hold, selection and stale-selection grace,
  Mac moves the caret, select after an edit, absolute offsets, new field,
  blind, timeout, refused, > 4 KiB in parts, the iPad's context matches
  the Mac's check, badge labels), `LiveTextSyncGateTests` (5: lock,
  Mac → remote only, edit validation, `caretMove` validation, display
  wake), `TextSyncLogTests` (no text or app name in any log line). Plus
  `ProtocolContractTests` (64 cases) and `FocusReadingTests` updated for
  `wantsText`.
- `DeckHand/Scripts/linux-typecheck/run.sh`: passes; it now also checks
  `DeckHandMac/FocusTextSync.swift` and `DeckHandiOS/Keyboard/LiveTextSync.swift`
  (stubs: `FocusTextObserver`, `GestureHaptic`, `FocusReader.Frontmost.bundleID`).
- `swiftc -parse` clean: `FocusTextObserver.swift`, `FocusReader.swift`,
  `LiveTypingField.swift`, `TypePanel.swift`, the session model files,
  `PixelHandUITests.swift`.
- **UI walks** (`PixelHandUITests`), only with `PH_QA_LIVE_SYNC=1` and
  TextEdit in front on the Mac with an empty plain-text document (they
  type into the Mac):
  - `test28_LiveSyncTypeOnMac`: the badge reaches SYNC; the QA script types
    `PH_QA_LIVE_SYNC_MARKER` on the Mac; the field shows it within 30 s.
  - `test29_LiveSyncTabAccept`: type, tap Accept ⇥, the field's value
    changes (TextEdit inserts a tab) within 3 s.
  - `test30_LiveSyncEditFromIPad`: type "pixel hand" on the iPad (shows,
    badge back to SYNC), tap at the field's start and type "X" (the caret
    is free: the field starts with "X"); with `PH_QA_LIVE_SYNC_OUT` the
    expected text is written for the script to compare with TextEdit's
    document.
  The doc's `test25`/`test26` names were already taken by other walks,
  hence 27–29. The joystick lane should take the next free number.

## Mac measurement checklist ([measure] items, RD §1, §6)

Report each with the app and macOS version.

1. **Observer latency per app**: TextEdit, Notes, Mail (compose body is
   WebKit: expect `webOff`), Xcode's editor, a Pages field, Messages.
   Time from a keystroke on the Mac to `textState` on the iPad (Console
   filter `Focus text`, plus a stopwatch video at 240 fps if possible).
   Target p95 under 80 ms on Wi-Fi.
2. **Round trip from the iPad**: type on the iPad in TextEdit; time from
   the key to the SYNC badge. Same target.
3. **Undo**: after iPad edits in TextEdit and Notes, ⌘Z on the Mac (and the
   iPad's shake / three-finger swipe) undoes them as typed text, in typing
   groups.
4. **Selection settable**: `AXSelectedTextRange` settable in TextEdit,
   Notes, `NSTextField`s (Finder rename, Spotlight-like fields), Xcode.
   Then **Safari `<input>`/`<textarea>`** with Accessibility Inspector
   (Phase 2 input; today Safari reads `webOff`).
5. **Arrow fallback**: a native field whose selection isn't settable (if
   any is found): a caret tap on the iPad moves the Mac caret correctly
   with ←/→, including across emoji.
6. **CPU**: a 5 000-line TextEdit document, type steadily for a minute
   with Live open: Pixel Hand under ~5 % (Activity Monitor / Instruments);
   only the 1 000-unit window is read.
7. **Secure input**: a password field in Safari or System Settings, and
   `sudo` in Terminal: the badge says BLIND, "Password field: the text
   stays on the Mac"; typing still reaches the field as keys; an edit or a
   caret tap from the iPad does nothing.
8. **Terminals**: Terminal.app and iTerm2 say "Terminal: keys only".
   Chrome: "Google Chrome doesn't share its text". Claude, Slack: "Web text
   is off for Claude" (Phase 2 opt-in).
9. **Lock**: lock the Mac with Live open: "Mac is locked", nothing read
   (no `Focus text` read lines); unlock: text returns.
10. **Conflict**: type on the Mac and the iPad at the same place at once:
    the iPad shows the Mac's text with MAC WINS (amber, ~1.4 s) and the
    refused haptic; nothing doubled on the Mac.
11. **Observer leaks**: switch apps 50 times with Live open; the Mac's
    memory and thread count stay flat; one `Focus text` thread.
12. **Mac autocorrect**: let TextEdit autocorrect a word typed from the
    iPad: the iPad shows the corrected word and doesn't type it back.
13. Carried over from the doc (Phase 2 spike, not needed for this lane):
    Claude's and Slack's text-marker windows; floating-cursor callbacks
    with empty text; `AXManualAccessibility` cost.

## iPad checks (iPad Air 11" M3, portrait and landscape; then iPhone)

1. Open the Type panel in Live with TextEdit in front on the Mac: the
   field shows the document's text around the Mac's caret, the caret where
   the Mac's is; badge SYNC (mint pixel).
2. Type on the iPad: the text appears at once (SENDING flickers, then
   SYNC) and on the Mac at the same place. QuickPath, dictation and
   autocorrect ("teh " → "the ") work; autocorrect's fix lands as one small
   edit.
3. **Tab-accept**: in an app with inline suggestions (Mail's native
   fields, Xcode), Accept ⇥: the accepted text appears in the field from
   the Mac (the owner's "shows empty" complaint).
4. **Caret**: tap mid-text, drag the selection handles, hold the space bar
   (iPhone and iPad), two fingers on the iPad keyboard, the floating
   keyboard, Stage Manager: the Mac's caret follows. A hardware keyboard:
   no gesture (arrows go to the Mac as before).
5. **IME**: Japanese and Pinyin: nothing reaches the Mac until the
   candidate is committed; a Mac change during composition doesn't break
   it.
6. **No spell-check underline** in synced Live; still there in blind Live
   and Compose. Smart quotes and dashes off.
7. **Undo**: shake / three-finger swipe left: the Mac undoes (⌘Z);
   three-finger swipe right: redo.
8. **Blind fallback**: Terminal, a password field, Chrome, Claude: badge
   BLIND, the reason as the placeholder; typing works exactly as before
   (blind diff at the end).
9. Switch to Compose and back: Compose is unchanged; Live comes back
   synced. Close or fold the panel: the Mac stops reading
   (`Focus text: sync stopped`).
10. The loupe with Live open: both work; closing the loupe keeps Live's
    text sync.

## Compile risks (most likely first)

1. **`FocusTextObserver.swift`** (Mac, parse only, Swift 6):
   - the `AXObserverCallback` closure literal (C convention, no captures)
     and `Unmanaged<FocusTextObserver>` refcon;
   - `Thread { }` capturing `self` and setting `runLoop`;
   - `CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)`
     with a `@Sendable` block; `CFRunLoopTimerCreateWithHandler(nil, at, 0, 0, 0) { _ in }`;
   - `CFRunLoopSourceCreate(nil, 0, &context)` with an empty context (the
     keep-alive source);
   - `kAXInsertionPointLineNumberAttribute` / `kAXEnabledAttribute` as
     `String`; `AXUIElementIsAttributeSettable` with `DarwinBoolean`;
   - `import Carbon` for `IsSecureEventInputEnabled()`;
   - `withCheckedContinuation` in a generic `onThread<T: Sendable>`.
2. **`LiveTypingField.swift`**: `override var undoManager: UndoManager?`
   on a `UITextView` subclass; `MacUndoManager: UndoManager` overriding
   `canUndo`, `canRedo`, `undoActionName`, `redoActionName`, `undo()`,
   `redo()` (UIKit's own text undo registrations go into it and are never
   run; `removeAllActions` after each change keeps it empty); the
   `LiveTextDisplay` conformance (a `@MainActor` protocol on a UIKit
   class); `weak var sync`.
3. **`TypePanel.swift`**: `.onChange(of: presence.mode) { _, mode in }`
   (iOS 17; `TypeMode` must be `Equatable`); `liveSync?.confirmReturn =
   { send in guardReturn(if: true, send: send) }` captures the view
   struct; `SyncBadgeView` uses `PixelHandTheme.Radius.badge`, `fill2`,
   `warningTint`, `Brand.mint`, `Brand.glow`.
4. **`LiveTextSync.swift`**: `@Observable` with `@ObservationIgnored weak
   var display`; `Task.sleep(for: .seconds(Double))`.
5. **`FocusTextSync.swift`** (type-checked against stubs): the real
   `LoomConnectionHandle.send` and `DeckHandLog.input` signatures.

## Coordination

- **Joystick lane** (`claude/pixelhand-lane-caret-joystick`): protocol 17
  already has `input.caretMove(move: CaretMove)` (`Models/FocusedTextState.swift`)
  and the Mac runs it (`FocusTextSync.caretMove`: ⇧ for `extend`, ⌥ for
  `word`/`paragraph`, `count` clamped 1…60, refused under secure input
  and while locked). The iPad sender has `sendCaretMove`. If that lane
  merges after this one it needs no protocol change; if it bumped to 17
  itself, it rebases, drops its own `caretMove`/`CaretMove` and takes 18
  only if it still changes the wire. The arrow cluster's code here is
  untouched. In synced fields the iPad caret follows the Mac's reported
  selection, so the joystick's moves show in the field.
- The UI tests append `test27`–`test29` before the private helpers;
  expect a textual conflict with any other lane appending tests there.

## Out-of-lane edits

- Mac system lane: `FocusTracker.swift`, `FocusReader.swift` (one field),
  `Handlers/SystemHandler.swift`; Core `System/LockPolicy.swift`,
  `System/DisplayWakePolicy.swift`.
- iOS interaction lane: `Handlers/InputHandler.swift`,
  `Input/TypingQueue.swift` (`preferKeys`), `TrackpadSender.swift`,
  `Keyboard/LiveTypingField.swift`, `Keyboard/TypePanel.swift`.
- Mirror lane: `Control/ControlSessionModel+Mirror.swift` (the loupe's
  `watchFocus` now goes through `updateFocusWatch()`).
- `Core/PROTOCOL.md` (version 17) and the re-recorded fixtures;
  `Scripts/linux-typecheck/Stubs.swift` and `run.sh`.

## Behaviour notes

- The loupe's one-line text readout (`focusState.text`, protocol 16) is
  unchanged: it still reads native text while the loupe watches, with or
  without `wantsText`.
- Live in the classic layout (`TrackpadView`) stays blind (no `liveSync`).
- Text goes over the wire only while Live is open on screen, only over the
  authenticated Loom session, and is never logged.

Lane: READY TO MERGE
