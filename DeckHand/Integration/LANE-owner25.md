# Lane: owner testing, build 25 (owner25)

Branch `claude/pixelhand-lane-owner25`, from `claude/pixelhand-integration`
at `0d804d7`. It builds OT-6, OT-7 and OT-8 from the owner's hands-on test
of build 25 on the iPad Air 11" (M3), landscape (`STATUS.md`, "Owner
testing (build 25)"). **Protocol bump 14 → 15** (OT-8). No `project.yml` or
Info.plist change and no Loom change; new files are picked up by the folder
sources in `project.yml`.

| ID | Status | Files |
|---|---|---|
| OT-6 Panel moves and resizes (P1) | Built (needs an iPad and iPhone check) | Core `Input/TypePanelGeometry.swift` (new), `Input/TypePanel.swift` (presence: collapse, numpad toggle), `Design/PixelGlyphs+Layout.swift` (grip, collapse, resize corner); iOS `Keyboard/TypePanel.swift` (`TypePanelHost`, pill), `Keyboard/TypePanelModel.swift`, `Shell/PixelHandShell.swift` (passes the arrangement) |
| OT-7 Compact layout (P2) | Built (needs an iPad and iPhone check) | Core `Input/TypePanel.swift` (`TypePanelLayout`, `TypeKeyBlock`, `ArrowCluster`, 5 × 4 `NumpadKey`, legends), `Design/PixelGlyphs+Layout.swift` (arrow legends); iOS `Keyboard/TypePanel.swift`, `Keyboard/LiveTypingField.swift` (`onFocus`), `Clipboard/PasteToMacControl.swift` (`iconOnly`) |
| Bug 1 (build 25) Type panel behind the keyboard in portrait (P1) | Fixed (needs an iPad check: `test18` in both orientations) | iOS `Keyboard/TypePanelModel.swift` (`refreshKeyboard`, Did-change observer), `Keyboard/TypePanel.swift` (host re-measures on resize); Core `Input/TypePanelGeometry.swift` (room rule) |
| Bug 2 (build 25) Ask keeps the old request (P3) | Fixed (needs an iPad check: `test19`) | Core `Assist/AskFlow.swift` (`selectsFieldOnFocus`); iOS `Surfaces/AskSheet.swift`; `test19`'s last step |
| OT-8 Typed steps save as keys (P2) | Built (needs a Mac and iPad check) | Core `Deck/Action.swift` (`typeText`), `Deck/ActionValidation.swift`, `Deck/ActionLibrary.swift`, `Deck/DeckEditing.swift`, `Deck/DeckPresentation.swift`, `Deck/TypedTextSummary.swift` (new), `Assist/AskPlan.swift`, `Input/RemoteInputValidation.swift`, `System/LockPolicy.swift`, `Intents/WidgetDeckSnapshot.swift`, `Protocol/PixelHandProtocol.swift`, `PROTOCOL.md`, fixtures; Mac `Handlers/DeckHandler.swift`, `Input/TypingQueue.swift`; iOS `Deck/KeyInspectorSheet.swift`, `Deck/DeckKeyButton.swift`, `Surfaces/DeckSurface.swift`, `Surfaces/AskSheet.swift` |

## OT-6 · The Type panel moves, resizes and folds

**Design rationale.** On build 25 the panel was a wide card fixed bottom
centre, so it sat right over the middle of the Mac picture, which is where
the text field being typed into usually is. Rather than guess a better fixed
place, the person puts it where it doesn't cover what they're looking at,
and it stays there. Three things make that cheap:

- **Where it goes is relative, not absolute.** The place is stored as two
  fractions of the *free room* (the window's safe area, inset 8 pt, ending
  8 pt above whichever is higher of the keyboard and the dock) plus a
  width. A panel parked bottom-right rides on the keyboard when it comes
  up and drops back onto the dock when it goes, and it stays bottom-right
  when Stage Manager resizes the window or the panel grows a Compose line.
  Nothing has to be re-clamped by hand.
- **A soft magnet, not a grid.** When a drag ends, an edge within 24 pt of
  the room's leading or trailing edge, the centre line, the top or the
  bottom snaps to it, so two at once make a corner. Anywhere else, it stays
  exactly where it was dropped. While dragging it only clamps (no snapping
  mid-drag, which feels sticky).
- **One place per arrangement and orientation**
  (`pixelhand.type.place.<form>.<portrait|landscape>`, JSON
  `{x, y, width}`), because a good spot in the landscape columns is a bad
  one in portrait's stacked form.

The panel never moves the shell and the keyboard never moves the
arrangement (OT-2 holds): the host still ignores the keyboard's safe area
and places the panel itself.

**What changed.**
- Header: a **⠿ grip** (pixel glyph, 44 pt target) at its leading end, and
  **–** (collapse) before close. Dragging the grip moves the panel
  (`DragGesture` in global space, so the moving grip doesn't feed back into
  its own translation). On drop, `TypePanelGeometry.placement(droppedAt:…)`
  clamps, snaps and stores it, with a short spring (none under Reduce
  Motion).
- **Resize** from either bottom corner: the other edge holds, the width is
  clamped to 360…760 and to the room; the layout reflows live as you drag
  (OT-7). The 44 pt handles straddle the card's corners, mostly outside, so
  they never take a tap meant for ⌫ or fn in the key block's corners.
- **Collapse** folds the panel to a pill, "⌨ Safari · Live", in the same
  corner (same fractions, measured size). One tap opens it on the tab it
  had; it drags like the grip; its context menu has Open and Hide keyboard.
  Folding lets the system keyboard go and drops latched modifiers.
- **iPhone** (and any window under 500 pt in either direction: Slide Over,
  the narrowest Stage Manager windows): the panel is **docked**, full
  width, to the top or the bottom of the free room; a grip drag moves it
  between the two (whichever half it's dropped in). In landscape, where
  there's room, the corners narrow it from the centre.
- **VoiceOver:** the grip has the actions Move to the top, bottom, left,
  centre and right; each resize handle is adjustable in 40 pt steps and
  reads its width; the pill reads "Keyboard panel, collapsed: Safari ·
  Live" and opens on activate.
- **Kept:** Live and Compose, "Typing into <App>", the Return guard, the
  hardware-keyboard body, the clipboard line, and OT-2 (the panel is still
  one child of the shell's `ZStack`, outside the per-form `switch`).

**Minimum width: 360 pt.** The stacked layout at its narrowest is 12 pt
padding, a 192 pt field (about 18 characters of body text: the least that
still reads back what you typed), 12 pt, the 132 pt arrow cluster, 12 pt
padding = **360**. The same 336 pt inside also holds:
- the 308 pt key block (seven 44 pt cells);
- the 220 pt numpad, stacked under the keys;
- the header: grip 44, mode switch about 144, numpad 44, collapse 44,
  close 44 and four 4 pt gaps = 336 at the default text size. Larger text
  sizes fall back to a two-line header (`ViewThatFits`).

Narrower than 360 and the field would drop under 192 pt or the keys would
have to shrink below 44 pt targets. The one window narrower than that is
an iPad's 320 pt Slide Over (room 304 pt): the docked panel takes the
room, and only there do the key cells shrink (`cellPitch`, 40 pt, so the
seven columns fit) and the field drop under 192 pt. Every iPhone that
runs iOS 17 is at least 375 pt wide (room 359 pt), so it keeps 44 pt
cells.

**Tests.** `TypePanelGeometryTests` (12): style per window; the room above
the dock or the keyboard; width range, default and clamping (iPad, a small
Stage Manager window, iPhone SE); default place on the dock; a
bottom-parked panel riding the keyboard and returning; a too-tall panel
keeping its header in view; clamping and snapping to edges, the centre
and corners; resizing from either edge (holds the other, never under the
minimum or past the room) and the place after a resize; docked top/bottom
on iPhone and centred resizing in landscape; storage keys, round trip and
junk; a remembered place surviving a window resize; the pill in the same
corner. `TypePanelPresenceTests` gained collapse/expand, the numpad toggle
and field focus, and the pill caption.

## OT-7 · A compact layout

**Design rationale.** Build 25 stretched one row across the panel: the
field, then fifteen keys in a line. Most of that width was the field, and
the keys were in the order they were added, not the order hands use them.
The new layout groups keys the way a Mac keyboard does:

- The **arrows** are an inverted T beside the field (↑ over ← ↓ →): you
  find them by shape, and they're next to the text they move through.
- The other keys are **two rows**, 7 cells wide: modifiers with the two
  keys you most often chord them with (⌘ ⌥ ⌃ ⇧ esc tab, tab two cells wide
  as on a real keyboard), then editing and navigation (⌫ ⏎ home end pg↑
  pg↓ fn). fn swaps the second row for a scrolling strip of F1–F12, so
  ⌘F5 is still one reach.
- Every key is a **40 pt cap on a 44 pt cell**: smaller caps than build 25
  (which drew 40 pt chips with 6–8 pt spacing in 44 pt rows), but every
  target is still 44 × 44 and none overlap.
- The **layout follows the panel's width**, not the window's, so resizing
  (OT-6) reflows it: **one block** (field | arrows | keys) from 680 pt,
  **stacked** (field and arrows, then the keys) below. At the default 720
  pt the field is 232 pt; at 760 pt it's 272 pt, against about 640 pt on
  build 25: well over the asked-for 30 % narrower, which is what makes room
  for the arrows and keys beside it.
- The **numpad** is a 5 × 4 grid of the same 44 pt cells (7 8 9 ÷ ⌫ / 4 5
  6 × / 1 2 3 − / 0 . = +, Enter three rows tall in the last column), 220
  × 176 pt instead of build 25's 4 × 5 grid of up to 64 pt keys (up to 280
  × 352 pt). It **docks beside the keys** in the same panel (from 564 pt)
  or under them, and the field stays. The header's numpad button toggles
  it; tapping the field brings the system keyboard back (and the numpad
  goes, so focus and the button agree).
- **Dot-matrix legends** for word keys (ESC TAB HOME END PGUP PGDN FN,
  F1–F12) at pitch 1.4, and the numpad numerals at 2; pixel-glyph arrows
  (new `keyUp/Down/Left/Right`, a stem and a 45° head); ⌘ ⌥ ⌃ ⇧ ⌫ ⏎ stay in
  the rounded chord face, which the font can't draw. The dot-matrix-on-
  buttons exception is recorded in `06-Pixel-Identity.md` §2 and
  `DECISIONS.md`.
- Under the field, a short **action row**: Paste (now icon-only, the
  system paste control), and in Compose +⏎ and Send. The field column is
  then about as tall as the two key rows.

```
one block (≥ 680 pt)
┌───────────────────────────────────────────────────────────────┐
│ ⠿ [Live│Compose] ⌨ Typing into Safari         [▦] [–] (×)     │
│ ┌──────────────────┐      ↑      ⌘  ⌥  ⌃  ⇧  ESC TAB──        │
│ │ field            │   ←  ↓  →   ⌫  ⏎ HOME END PGUP PGDN FN   │
│ └──────────────────┘ [📋][+⏎][Send]                           │
└◢─────────────────────────────────────────────────────────────◣┘

stacked, numpad on (360 pt)          stacked, numpad beside (≥ 564 pt)
┌──────────────────────────────┐     ┌─────────────────────────────────────┐
│ ⠿ [Live│Compose] [▦] [–] (×) │     │ …header…                           │
│ ⌨ Typing into Safari         │     │ ┌──────────────┐    ↑              │
│ ┌──────────────┐    ↑        │     │ │ field        │ ←  ↓  →           │
│ │ field        │ ←  ↓  →     │     │ [📋]                               │
│ [📋]                         │     │ ⌘ ⌥ ⌃ ⇧ ESC TAB─  7 8 9 ÷ ⌫        │
│ ⌘ ⌥ ⌃ ⇧ ESC TAB──            │     │ ⌫ ⏎ HM END ↑ ↓ FN 4 5 6 × E        │
│ ⌫ ⏎ HOME END PGUP PGDN FN    │     │                   1 2 3 − N        │
│ 7 8 9 ÷ ⌫                    │     │                   0 . = + T        │
│ 4 5 6 × E …                  │     └─────────────────────────────────────┘
└──────────────────────────────┘
```

**Field identity.** The four parts (field column, arrows, keys, numpad) are
laid out by one SwiftUI `Layout` (`PanelBodyLayout`), so changing
arrangement while resizing or toggling the numpad never rebuilds the
`UITextView`: the keyboard doesn't drop (OT-2's lesson, applied to
reflow).

**Tests.** `TypePanelLayoutTests` (rewritten, 11): hardware body; layout
from the panel's width (one block at 720, stacked at 360, the window's cap
without a width, a given width used as is); field widths (30 % narrower;
192 pt at the minimum); 44 pt cells and block sizes; numpad beside or
below, and fitting the minimum; everything fitting 360; the short-room
header; Compose lines; every test window × numpad on/off fitting the
panel; cells shrinking only in a 320 pt Slide Over window; bottom
padding. `TypeKeyBlockTests` (4): the two rows in order;
each row fills 7 columns once (tab spans 2); every key in `KeyTable`,
identifiers kept from build 25, and the block plus arrows covering build
25's row; the inverted T. `NumpadTests.grid`: the 5 × 4 grid covers each
cell once, Enter three tall. `TypeKeyLegendTests`: every legend draws in
the font and fits a 40 pt cap.

## OT-8 · Ask plans with a typed step save as keys

**Design rationale.** Ask already typed through `input.typeText`, and the
Mac already typed for Live and Compose; only the deck's `Action` model had
no way to say "type this". So the fix is one new action, `typeText(text:)`,
whose domain message *is* `input.typeText`: a key that only types goes
through exactly the same Mac path as Live typing (input handler,
`TypingQueue`, the layout-aware `TypingPlanner`), and inside a sequence it
runs in order with the steps around it. A separate "typed step" kind only
inside sequences was the alternative; a full action is simpler and also
gives single "snippet" keys (type an address, a signature) for free.

**Safety.** Typed text lands in whatever app is in front, so a key that
types **always asks first** (`DeckKey.asksFirst = confirm || typesText`),
the same as Ask's plans ("types on the Mac") and in the spirit of the Type
panel's Return guard. The confirmation names where the text will land:
"Run “YouTube”? Open Safari, then … Types into Safari, then presses
Return." (`KeyRunConfirmation`: the app the key brings forward before it
types, else the Mac's front app now). The inspector shows "Ask before
running" on and disabled, with the reason under it; the deck's context
menu doesn't offer "Run without asking" for it. Widgets leave such keys
out (a widget button can't ask); Shortcuts and Siri list them, and the
Run Deck Key intent asks first (`WidgetKey.confirm` now carries
`asksFirst`).

**What changed.**
- **Core.** `Action.typeText(text:)` (message `input.typeText`,
  `kindName` "typeText", needs Accessibility). `ActionValidation`: 1 …
  4 096 UTF-8 bytes, not only spaces, already normalized
  (`TypingText.normalized`: `\n` and `\t` are the only control
  characters), with plain-words messages. `ActionKind.typeText` ("Type
  text", the `type` glyph, template "Hello"). Presentation: summary "Type
  “youtube” then Return", key face line "“youtube” ⏎", new-key label
  "youtube", widget glyph `type`. `LockPolicy` and `RemoteInputValidation`
  judge it as `input.typeText`. `Action.typesText` / `pressesReturn`.
- **Ask.** `AskPlan.savedAction` keeps typed steps (normalized) and pauses
  in order; a single typed step saves as a `typeText` key. The refusal
  (`SaveBlocker.typesText`, "Keys can't type text yet…") is gone. In its
  place, `SaveBlocker.step(index:reason:)` and
  `AskPlanValidation.saveReason(for:)`: a step that runs but can't be kept
  on a key says so **next to that step** in the plan ("Can't be saved on a
  key: Type the text the key should type."), in plain words. Today the only
  such step is typed text made only of control characters (it would type
  nothing); every other runnable step saves.
- **Mac.** `DeckHandler`: a top-level `typeText` runs as its domain
  message (receipt `delivered`). Inside a sequence it routes
  `input.typeText` and then awaits the new `TypingQueue.idle()`, so the next
  step (an app shortcut or a launch, which don't go through the queue)
  can't overtake the text. Lock gate per step as before.
- **Protocol 15.** `PixelHandProtocol.version` 15, `PROTOCOL.md` history,
  new fixtures `deck.run.typeText` and `deck.run.sequence.typeText`, all
  fixtures and `MANIFEST` re-recorded (the envelope's `v`). A 14 and a 15
  can't talk; `PeerCompatibility` already says "Please update" from the
  advertised `ph-proto`.
- **iOS key editor.** "Type text" in the action library and the sequence
  step menu; its fields are a multi-line text field and "Press Return
  after" (`TypedTextEditing` splits the trailing line break into the
  switch). Works the same for a sequence step.
- **Deck.** The face shows the quoted text and ⏎; tapping asks first with
  `KeyRunConfirmation`'s message.

**Tests.** `TypedKeyTests` (15): JSON round trip (alone and in a sequence,
and the exact JSON); a deck with a typing key round-trips and validates;
the owner's plan saves as open → type → Return on Home, asking first; pauses
and typed steps keep their order; a lone step saves normalized; a step that
can't be saved names itself; the old refusal is gone; validation; the
Mac's `RemoteInputValidation` accepts good runs and drops bad ones whole;
the lock gate; asks first and the inspector's reason; Return detection;
presentation; the library kind; widgets vs Shortcuts. Also
`TypedTextEditingTests`, `KeyRunConfirmationTests` and `OwnersRequestTests`
(the parser's plan for "Open Safari and type youtube and press return"
runs and saves). Updated: `AskPlannerTests` (typing plans save),
`DeckUITests.everyKind`, `ProtocolContractTests` samples.

## Build 25 bugs (routed to this lane by the coordinator)

**Bug 1 · Type panel behind the keyboard in portrait (P1).** After
`test18` rotated back to portrait with the keyboard up, the panel sat
behind the keyboard and `ph.type.close` wasn't hittable. **Cause:** the
panel's keyboard top came only from `keyboardWillChangeFrame`, measured
against the key window's bounds at that moment. On rotation that
notification can arrive before the window has turned, so the portrait
keyboard's top read as below a landscape-sized window: no overlap, no
keyboard, and the panel went to the bottom, under the keyboard. **Fix:**
- `TypePanelModel` keeps the keyboard's last end frame in screen space and
  re-measures it (`refreshKeyboard()`); it also listens to
  `keyboardDidChangeFrame`, which carries the same end frame after the
  window has turned.
- `TypePanelHost` calls `refreshKeyboard()` whenever the window's size
  changes (rotation, Stage Manager), after that layout pass.
- The panel's place is always inside the free room above the keyboard
  (`TypePanelGeometry`, OT-6), so once the keyboard is measured right the
  panel can't sit behind it. A keyboard reaching above the window's top
  now leaves no room (the panel pins to the top, header in view) instead
  of being ignored.

`TypePanelKeyboardRotationTests`: every test window × keyboard height ×
place × panel height ends above the keyboard with its header in view; and
the rotation case (bottom-parked, landscape → portrait with the keyboard
up) rides on the portrait keyboard. `test18` is unchanged and must pass in
both orientations.

**Bug 2 · Ask keeps the old request (P3, OT-5).** After Save as key ›
Cancel the field still held "Take a screenshot", and tapping it put the
caret at the start, so the next request became "nowTake a screenshot".
**Fix:** while a plan or result shows (`AskFlow.selectsFieldOnFocus`:
plan, editing, running, result, naming), focusing the field **selects
its text**, so typing starts a new request; editing it is still one tap
away. New request still clears it. `AskFieldSelectionTests` covers the
stages. `test19`'s last step now types a whole new request and asserts
the field holds only it (it typed " now" to append before).

## Linux results

- `swift test --package-path DeckHand/Core`: **1180 / 1180 pass** (215
  suites). There were 1133 before, so 47 tests are new.
- `DeckHand/Scripts/linux-typecheck/run.sh`: passes. It covers
  `DeckHandler` and `TypingQueue` (Mac) and `Assist/*` (iOS `AskModel`).
- `swiftc -parse` is clean on every changed app file that can't be
  type-checked here: iOS `TypePanel`, `TypePanelModel`, `LiveTypingField`,
  `KeyInspectorSheet`, `DeckKeyButton`, `DeckSurface`, `AskSheet`,
  `PasteToMacControl`, `PixelHandShell`; and the UI tests.

## iPad checks (iPad Air 11" M3, landscape first; then portrait, iPhone)

1. **OT-6 move:** open the Type panel. It's bottom centre, 720 pt. Drag the
   grip toward the top-left: it follows, then snaps to the corner within
   24 pt. Drop it mid-screen: it stays. Bring the keyboard up with the
   panel parked bottom-right: it rides on the keyboard; dismiss the
   keyboard (hardware Esc on the iPad keyboard, or the keyboard's hide
   key): it drops back onto the dock. Close and reopen: same place. Rotate:
   portrait has its own place; rotate back: the landscape place returns.
   Switch arrangement (the columns vs a preset): each remembers its own.
2. **OT-6 resize:** drag the bottom-right corner left: the panel narrows,
   stops at 360 pt, and reflows to stacked at 680 pt. Bottom-left corner:
   the right edge holds. Neither corner handle steals taps from ⌫ or fn.
3. **OT-6 collapse:** – folds to "⌨ <App> · Live" in the same corner, the
   keyboard drops; tap opens it on the same tab with the keyboard back;
   drag the pill; long-press → Hide keyboard.
4. **OT-7:** the field has the inverted T beside it; two key rows; ⌘ then
   C; ⌘ locked; fn then F5; esc, tab, arrows, home/end, page up/down. The
   numpad button docks the 5 × 4 pad beside the keys (≥ 564 pt) or under
   them; type 7 8 9 into Numbers, Enter; tap the field: keyboard back,
   numpad gone. Compose: +⏎ and Send under the field.
5. **Sizes:** Stage Manager at the smallest and a mid width (the panel
   floats; under 500 pt it docks); ½ Split View; iPhone portrait (docked,
   drag top ↔ bottom) and landscape (docked, narrow from the corners; no
   header with the keyboard up: grip and close beside the field); AX3 (the
   header goes to two lines at narrow widths); light and dark; Increase
   Contrast.
6. **Hardware keyboard (Magic Keyboard):** keys-only body; ⌘C and arrows go
   to the Mac; the panel still moves, resizes and folds.
7. **OT-8:** in Ask, "Open Safari and type youtube and press return": Run
   (asks first), then Save as key with a name. The key is on Home with
   "“youtube” ⏎"-style face text (a sequence shows "3 steps"). Tap it: "Run
   “…”?" naming Safari; Run: Safari comes forward and YouTube's search
   loads. Edit the key: "Ask before running" is on and locked with the
   reason; step 2 shows the text and "Press Return after". Make a new key
   with "Type text" from the library. A Shortcuts "Run Deck Key" of it asks
   first; the widget doesn't list it.
8. **Mac (protocol 15):** a 15 iPad and a 15 Mac connect; an older Mac
   shows "Please update". A typed sequence step finishes typing before the
   next step's app shortcut fires.

## PixelHandUITests changes

- **`test20_TypePanelMovesAndResizes`** (new, asserts): the inverted T
  (↑ over ↓, ← and → either side, 44 pt targets); modifiers and esc on the
  first row; a grip drag moves the panel and snaps it to the leading edge;
  a corner drag narrows it, never under 360, and stacks the keys under the
  field; the numpad docks inside the panel (≤ 222 pt wide) with the field
  still there, then goes; collapse to the pill and back; the place is
  remembered across close and open. Honours `PH_QA_FULLSCREEN=1`.
- **`test21_AskTypedPlanSavesAsKey`** (new, asserts): Ask "Open Safari and
  type youtube and press return" → Run → Save as key with a name → "Saved
  as a key" → the key on the deck → tap → asks first with "Types into …" →
  Run → the inspector shows "Ask before running".
- `test20` taps the ↑ key and numpad 7 only when the coordinator's
  `ensureScratchFrontmost()` passes. `test21` runs the plan and the key
  (which type "youtube" and Return into Safari on the Mac) only with
  `PH_QA_TYPE_IN_SAFARI=1`; without it, it saves from the plan and cancels
  the key's confirmation after checking it.
- `test19`: the last step types a new request and asserts it replaced the
  old one (bug 2).
- `test18`: the numpad is a toggle now (`ph.type.tab.numpad` twice; the
  `ph.type.tab.keys` button is gone).
- New identifiers: `ph.type.grip`, `ph.type.collapse`, `ph.type.pill`,
  `ph.type.resize.leading` / `.trailing`, `ph.type.arrows`, `ph.type.keys`;
  `ph.inspector.asksFirst`, `ph.inspector.typeText`,
  `ph.inspector.typeReturn`; `ph.ask.step.<n>.saveNote`. Kept:
  `ph.type.key.<wire>`, `ph.type.modifier.<name>`, `ph.type.fn`,
  `ph.type.numpad.<key>`, `ph.type.tab.numpad`, `ph.type.field`,
  `ph.type.panel`.

## Compile risks (most likely first)

1. **`TypePanel.swift`** was written without an iOS SDK (it parses, but
   SwiftUI can't be type-checked here). Watch for:
   - `PanelBodyLayout` (a `Layout`) called with a `@ViewBuilder` body that
     has an `if` (the numpad);
   - `KeyGrid`'s `@ViewBuilder let content: Content` memberwise init, and
     the file-private `View.keyCell(…)` extension;
   - the `GeometryReader` closure in `TypePanelHost` with several `let`s
     (tuples with labels: `size`, `(width:height:)` passed to
     `geometry.frame(for:size:)` in a ternary);
   - `accessibilityAction(named:)`, `accessibilityAdjustableAction`,
     `hoverEffect(.highlight)`, `.snappy(duration:)` (iOS 17);
   - `ForEach(TypeKeyBlock.cells.filter { … }, id: \.item)` and
     `ForEach(ArrowCluster.cells, id: \.key)`.
2. **`KeyInspectorSheet.swift`:** the `Toggle` with a computed `Binding`
   and `.disabled`, the `Section { } footer: { if … }` form, and
   `TypedTextFields` (`TextField(axis: .vertical)` with `lineLimit(1...4)`).
3. **`LiveTypingField`:** the `becomeFirstResponder()` override calls
   `onFocus` synchronously; if SwiftUI warns about state changes during an
   update, wrap it in `DispatchQueue.main.async`.
4. **`DeckKeyButton`:** `KeyRunConfirmation.message(…)` reads
   `TypingTarget.shared.frontApp` (main actor) inside the dialog's message
   builder.
5. **`PasteToMacControl(iconOnly:onPaste:)`**: trailing-closure call with
   the new first parameter.

## Behaviour notes

- A sequence that types waits on the Mac until the text is typed (at about
  2 ms a key), so a long typed step can push the receipt past 1.2 s; the
  remote then reads `delivered`, as for other slow Deck 2 runs.
- The resize handles reach 18 pt below the card; over the dock that's a
  small dead spot while the panel sits on it.
- The panel's place is per window size class, not per Mac.
- Downgrading to a build before 15 after saving a typing key: the older
  build can't decode that deck key. No deck schema bump was made (no users
  yet; `DeckMigration` keeps a file it can't read).

## Out-of-lane edits

- `Product/Design/04-Interaction-Model.md` §2 "Keyboard" (moving,
  resizing, folding, the compact layout) and a new "Keys that type".
- `Product/Design/06-Pixel-Identity.md` §1 (the new layout glyphs) and §2
  (the dot-matrix key-cap exception). `07-Polish-Spec.md` §4 (key caps
  on 44 pt cells, the resize handles).
- `Integration/DECISIONS.md`: a 2026-11-26 entry for build 25's findings.
  `STATUS.md`: a line under "Owner testing (build 25)".
- `Core/PROTOCOL.md` (version 15) and the re-recorded protocol fixtures.

Lane: READY TO MERGE
