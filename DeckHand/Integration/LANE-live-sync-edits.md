# Lane: live sync edits land where they're typed (build 29 bug 9)

Branch `claude/pixelhand-lane-live-sync-edits`, from
`origin/claude/pixelhand-integration` at `bcf6c2a` ("Record build 29 Mac
and live-sync walks"). It already contains `build28-fixes` (build 30).

**Bug 9 (P1):** edits from the iPad land in the wrong place on the Mac
(`STATUS.md`, "Mac walks (build 29)").
- **iPad:** "X", typed after a tap at the start of the Live field, landed
  at the end of the document.
- **iPhone:** "pixel hand", "accept⇥" and "X" interleaved after the first
  word: "Pixel pixel XhandHandaccept⇥ QA scratch…".

**Protocol unchanged (17).** No `project.yml`, Info.plist, entitlement,
fixture or Loom change. Written in a Linux container (Swift 6.2): Core is
built and tested here; the Mac and iOS files are type-checked against stubs
(`FocusTextSync`, `InputHandler`, `LiveTextSync`) or parse-checked
(`FocusTextObserver`, `LiveTypingField`, `TypePanel`, the UI tests).
**The Mac and iOS apps weren't compiled.**

## Root causes

Reading the walks: on the iPhone, `openSyncedLiveField` taps the field's
centre to focus it. The narrow field wraps, so that tap lands mid-text and
moves the caret: after "Pixel Hand" (accept⇥, correct) and then after
"Pixel " ("pixel ", correct). So the bug is not the first edit. It's what
happened after it: the tap at the start was lost, and later text ("hand")
landed after "X", although it was typed 3 s earlier. Five defects in the
code explain that.

1. **The Mac typed without confirming the selection** (`FocusTextSync`,
   `FocusTextObserver.select`):
   - `select` returned *success* when the read-back failed.
   - `placeSelection` typed right after `AXUIElementSetAttributeValue`,
     with no fresh read.
   - `TypingQueue.idle()` only means the keys were *posted*. Keys still in
     the app's queue could land after the new selection, or the next
     edit's selection could be set before them.
   - The answer went after a fixed 40 ms sleep.

   All of this makes text land at the old caret: the end of the document
   on the iPad, after the last typed text on the iPhone.
2. **A guessed caret.** When the app didn't report `AXSelectedTextRange`,
   `FocusTextObserver.look` reported the caret at the **end of the
   field**. The arrow-key fallback then moved from that guess.
3. **Keys bypassed the edit queue.** Accept ⇥, the key row, the joystick,
   numpad text and hardware arrows went straight to the Mac
   (`sender.sendShortcut`). On the Mac they went into `TypingQueue` at
   once, beside `FocusTextSync`'s serial edit work. A Tab pressed while
   "accept" was in flight could land before or inside it.
4. **Unordered sends and stray selections on the iPad.**
   - `LiveTextSync` sent each edit and selection in its own `Task`, and
     separate tasks into the sender actor aren't ordered.
   - UIKit calls `textViewDidChangeSelection` *before* `textViewDidChange`
     for a typed character. Every keystroke therefore sent a
     `textSelect`, for the caret in text the Mac didn't have yet, at the
     old revision. It could arrive after a later edit and pull the Mac's
     caret back to a stale offset.
5. **A tap during an edit could be lost, and timeouts could hang.**
   - `localSelection` dropped a caret move whenever the field differed
     from the Mac's last text, which included the moments around each
     answer.
   - The 3 s "give up" ran only when a state happened to arrive. A lost
     answer with a quiet field kept SENDING and blocked every later edit
     and tap.

Checked and found correct, so unchanged:
- **Offsets:** window offset (`edit.range.shifted(by: window.start)`) and
  UTF-16 counting by whole characters (`TextEdit.between`).
- **CRLF:** one Swift `Character`, its units counted.
- **Revisions:** they go up on every reading that differs, and
  `TextEditCheck` rebases by context within ±64 units.

## Fix

### Core

**`Input/TextSyncReconciler.swift`: one ordered queue for everything the
synced field sends.** It sends one edit at a time, as before. It adds:
- **Raw input** (`TextSyncRawInput`: `.keys`, `.text`; `localRaw`). It
  waits behind the edit in flight. When its turn comes, three things go
  in order:
  1. the text typed *before* the key (a snapshot taken at the press);
  2. a `textSelect` to the field's caret at the press, if the Mac's caret
     differs;
  3. the keys, all at once.

  Then a **raw flight** runs until a Mac state at least 0.15 s after the
  keys, or 0.6 s with none:
  - With nothing typed meanwhile, the field follows the Mac's states live
    (the joystick's caret, a Tab's indent).
  - Text typed meanwhile is merged after the keys' effect (two inserts at
    one point: the Mac's first).
- **`localSelection(_:fieldText:)`** ignores a selection callback whose
  field text differs from the reconciler's. That's the caret of a text
  change, and `localChange` carries it.
- A caret moved at any time is kept and goes out when the queue is idle.
  It's never dropped.
- **`tick(now:)` and `nextDeadline(now:)`:**
  - an unanswered edit is given up after 3 s even with no state;
  - raw flights settle on their own.
- **States from an older revision of the same field are ignored.**
- **`note(now:)`** (`TextSyncNote`):
  - `.caretNotPlaced`: a `refused(notEditable)` while the field is
    readable and editable, meaning the Mac couldn't place its caret and
    typed nothing;
  - `.noAnswer`: the Mac didn't answer in time.

  Each note shows for 4 s.
- MAC WINS (`conflict`, a collision while merging) drops the unsent queue
  and shows the Mac's text **and caret**. This is unchanged, and now
  tested end to end.

**`Input/TextSelectionPlacement.swift` (new).** This is the Mac's
placement plan. Each step counts only when a **fresh read** shows the
caret there:
1. Accessibility, up to 2 tries.
2. Otherwise ←/→ (⇧→ to select) from the caret the Mac **read**, up to 2
   rounds, so a round that drifts is corrected.
3. Otherwise `fail`: nothing is typed, ever at a guessed caret.

`landed(range:replacement:lengthBefore:after:)` is how the Mac tells its
typing has reached the field: the length, the caret and the typed units
match.

### Mac

- **`FocusTextSync`:**
  - **Reading:** `readStable()` reads until two readings agree, so keys
    already posted have been consumed.
  - **`applyEdit`:** idle, then a stable read, then `TextEditCheck`. Then
    `placeSelection`, the `TextSelectionPlacement` loop confirmed by
    reads. Then it types, then `waitUntilLanded` (≤ 20 reads, 25 ms
    apart), then sends the state, then the result.
  - **When the caret can't be placed,** the edit is answered
    `refused(notEditable)` and nothing is typed.
  - **`applySelect`:** the same placement.
  - **New `inOrder(_:)`:** while a remote watches text and an edit or
    selection job is pending, `keyboardShortcut`, `typeText` and
    `caretMove` wait behind it. Otherwise they go at once, as before.
- **`FocusTextObserver`:**
  - `Reading.selectionKnown` is false when the app didn't report its
    selection, so the end-of-field stand-in is never used for arrows;
  - `select` returns false without a read-back.
- **`Handlers/InputHandler`:** `keyboardShortcut` and `typeText` go
  through `FocusTextSync.inOrder`.

### iPad

- **`LiveTextSync`:**
  - **One ordered outbox** (edits, selections, keys and text), drained by
    one task.
  - **`sendRaw(_:)`.**
  - **`localSelection(_:fieldText:)`.**
  - **Timers:** the next deadline runs `tick`.
  - **`note`.**
- **`LiveTypingField`:** the selection delegate passes the field's text.
- **`TypePanel`:** these go through `sendKeys` / `sendText` and wait in
  the sync queue when Live is synced, and go as before when blind:
  - Accept ⇥;
  - the key row;
  - the joystick and caret steps;
  - numpad text and keys;
  - hardware keys (`onKey`);
  - chords (`onChord`).

  The note shows bottom-leading in the field (`ph.type.syncNote`, the
  warning tint). Return keys are still guarded once, by the panel.

### Walks

- **`test30_LiveSyncEditFromIPad`** is build 29's `test29`; the walks were
  renumbered in `61c69c3`. It now:
  1. needs a scratch document under 900 units;
  2. taps the field's start and types "pixel hand", and asserts the field
     is exactly `"pixel hand" + start`;
  3. taps the start again and types "X", and asserts exactly
     `"X" + "pixel hand" + start`, with no sync note;
  4. closes Live and opens it again, so the field shows a fresh read of
     the Mac's document, and asserts it is **exactly** that text;
  5. writes the expected text to `PH_QA_LIVE_SYNC_OUT`, for the QA script
     to compare with TextEdit's text.
- **Duplicate `test27`:** already fixed by `61c69c3`
  (`test27_ArrowJoystick`, then `test28`–`test30` for live sync). No
  number is used twice. The header comment now names `test28` and
  `test30`.

## Tests

`swift test --package-path DeckHand/Core`: **1445 / 1445 pass** (264
suites; 1418 before, 27 new). `DeckHand/Scripts/linux-typecheck/run.sh`
passes. The UI tests and the changed iOS/Mac files parse.

`LiveSyncEditsTests.swift` runs the iPad reconciler against a **simulated
Mac field**. The simulated Mac applies edits as `FocusTextSync` now does:
`TextEditCheck`, the `TextSelectionPlacement` loop, typing key by key with
intermediate states, then the state and the answer. It runs over an
in-order link with latency. Most cases run under three Mac behaviours
(`SimAX`): Accessibility works; it says yes but ignores the set (arrow
fallback); it can't be set (arrows from the read caret).

- **Repro sequences, exact final documents (×3 each):**
  - iPad walk: accept⇥ and "pixel hand" at the end, then X at the tapped
    start → `"X" + scratch + "accept\tpixel hand"`.
  - iPhone walk: the centre taps at 10 and 6 →
    `"XPixel pixel handHandaccept\t QA scratch\ntyped on the Mac"`.
  - The same walk with no pauses and a slow Mac: the result is the same,
    and there's never more than one edit in flight.
- **Caret:**
  - A tap at the field's start deep in a 2 990-unit document (window
    offset); ×3.
  - Typing sends no `textSelect`.
  - The space-bar trackpad: 16 steps, the last wins; ×3.
  - A caret moved during an edit goes after it.
  - A handle selection is replaced by typing; ×3.
- **Queue:**
  - Typing while an edit is in flight: one edit at a time, batched,
    nothing sent raw.
  - Accept ⇥ behind text in flight.
  - Text typed right after Accept ⇥ goes after the Tab.
  - Text, Return, text.
  - Joystick arrows go straight out and the field follows.
  - Blind raw input goes at once.
- **Concurrent Mac edit:**
  - The Mac types elsewhere: both land.
  - The Mac types where the next edit goes: MAC WINS, the field equals the
    Mac's text and caret, nothing doubled.
  - An insert whose context still matches lands beside the Mac's.
  - A stale edit is rebased.
- **UTF-16:** a tap between CJK characters, typing there, ⌫ over a
  family emoji, typing before a skin-toned emoji; ×3.
- **Never guess:**
  - An unknown caret with a selection that can't be set: nothing typed,
    the edit refused.
  - The planner's steps.
  - The `landed` check (partial typing, typed elsewhere, deletion, emoji).
- **Reconciler details:**
  - A selection callback with a text change.
  - The tick timeout and its note.
  - The caret-not-placed note.
  - The Mac's text first when merging after keys.
  - Raw input waits for a composition to commit.

The 67 existing live-sync tests pass unchanged.

## Mac re-check (the next Mac build, with the owner's OK)

With `PH_QA_LIVE_SYNC=1`, use a **short** scratch document (a few lines)
in front.

1. **TextEdit:**
   - Run `test28`, `test29` and `test30` on the iPad Pro 11" (full screen)
     and the iPhone 17 Pro, with `PH_QA_LIVE_SYNC_OUT`.
   - After `test30`, compare
     `osascript -e 'tell application "TextEdit" to get text of document 1'`
     with the out file. They must be **equal**.
   - `test30`'s own read-back assertion must pass.
2. **Notes:** open a new note with a short line, and repeat `test30` with
   Notes in front (the walk doesn't care which app). Then compare the
   note's text by hand with the out file.
3. **By hand, in TextEdit and Notes:**
   - Tap mid-word, type: the text lands there.
   - Hold the space bar and drag, then type.
   - Type fast, then tap Accept ⇥: the Tab lands after the text.
   - Type on the Mac and the iPad at once: MAC WINS, nothing doubled.
4. **Console** (filter `Focus text`): no "caret not placed" or "typing
   not seen" lines in TextEdit or Notes. If any appear, note the app.
5. **Arrow fallback:** where a field's selection isn't settable, the
   caret still lands. If a field reports no selection at all, the note
   "The Mac couldn't move its caret there, so nothing was typed" shows
   and nothing is typed.

## Compile risks (most likely first)

1. **`FocusTextSync.swift`:**
   - The `defer` inside the `enqueue` task closure, using `self` (main
     actor).
   - `Duration.milliseconds` with `Task.sleep(for:)`.
   - The private nested `Observed` struct holding `FocusedTextState`.
2. **`LiveTextSync.swift`:**
   - `confirmReturn { [weak self] in self?.enqueue(.edit(edit)) }`: a
     single-expression `Void?` closure passed as `() -> Void`.
   - The private `Outgoing` enum inside an `@Observable` class, with
     `@ObservationIgnored` on the arrays.
3. **`TypePanel.swift`:**
   - `syncedLive` reads `model.presence.mode`.
   - `PixelHandTheme.warning`, `warningTint` and `Radius.badge` in the
     note overlay (all three are already used by `SyncBadgeView`).
4. **`FocusTextObserver.swift`:**
   - The `Reading(…, selectionKnown:)` memberwise initializer, which has a
     defaulted `var`.

## Behaviour notes

- **Wire:** unchanged. `refused(notEditable)` for a readable, editable
  field now means "the caret couldn't be placed". The iPad shows the note
  for it.
- **The joystick** in synced Live goes through the queue. With nothing
  pending it goes at once (no added delay). Behind a pending edit, it
  waits for that edit.
- **Not in this lane:** the Paste button (`pasteToMac`) and the quick
  actions bar still send directly. On the Mac, `inOrder` orders their
  keys behind a running edit, but the clipboard paste itself isn't
  ordered.

Lane: READY TO MERGE
