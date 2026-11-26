# Lane: owner testing, build 24 (owner24)

Branch `claude/pixelhand-lane-owner24`, from `claude/pixelhand-integration`
at `6884efa`. It fixes OT-1 … OT-5 from the owner's hands-on test of build 24
on the iPad Air 11" (M3), mostly in landscape (`STATUS.md`, "Owner testing
(build 24)"). There is no protocol bump, no `project.yml` or Info.plist
change, and no Loom change. New files are picked up by the folder sources
in `project.yml`.

| ID | Status | Files |
|---|---|---|
| OT-1 Dock icons (P2) | Fixed (needs an iPad re-check) | Core `Design/AppIconPolicy.swift` (new), `Models/InstalledAppInfo.swift` (doc); Mac `AppIconEncoder.swift` (new), `InstalledAppScanner.swift`, `ScreenCaptureService.swift`; iOS `Shell/AppDock.swift`, `QuickActions/QuickActionsPills.swift`, `StreamDeckGridView.swift` |
| OT-2 Keyboard loop (P1) | Fixed (needs an iPad re-check) | Core `Input/TypePanel.swift` (new: `ShellPlanningSize`, `KeyboardKind`, `TypePanelPresence`, `TypePanelLayout`); iOS `Shell/PixelHandShell.swift`, `Keyboard/TypePanelModel.swift` (new), `Keyboard/TypePanel.swift` (new, `TypePanelHost`), `Keyboard/LiveTypingField.swift`, `Surfaces/PointerSurface.swift` |
| OT-3 Typing redesign (P2) | Built (needs an iPad and iPhone re-check) | Core `Input/TypePanel.swift`, `Design/DotMatrixFont+Table.swift` (= × ÷), `Design/PixelGlyphs+Layout.swift` (numpad glyph); iOS `Keyboard/TypePanel.swift`, `Keyboard/LiveTypingField.swift`, `TrackpadView.swift`; `Keyboard/RemoteKeyboardPanel.swift` **deleted**; `Clipboard/PasteToMacControl.swift` (`ClipboardRow` folded into the panel) |
| OT-4 Column handle (P2) | Fixed (needs an iPad re-check) | Core `Design/RightColumn.swift`, `Design/ContrastAudit.swift`, `Design/PixelGlyphs+Layout.swift` (chevron); iOS `Shell/RightColumnChrome.swift` |
| OT-5 Ask stuck (P1) | Fixed (needs an iPad re-check) | Core `Assist/AskFlow.swift` (new), `Assist/AskPlan+Deck.swift` (named keys); iOS `Assist/AskModel.swift`, `Surfaces/AskSheet.swift` |

## OT-1 · Dock icons look like the macOS Dock

**Cause.** `InstalledAppScanner.compressedIcon` drew every icon into a
64 × 64 `NSImage` and sent `NSBitmapImageRep` **JPEG** (factor 0.8). JPEG
has no alpha, so the transparent corners became white (light) or black
(dark): the square behind every icon. The window picker's icons
(`ScreenCaptureService.compressedIcon`, 48 pt) had the same bug. Running
apps and the context strip use the installed-apps catalog, so they were
fixed at the same source.

**Fix, Mac.** `AppIconEncoder` draws the icon into a clear sRGB bitmap with
premultiplied alpha at `AppIconPolicy.pixelSide` = **72 px** (2× the dock's
36 pt icon, the largest size the full list is drawn at). It writes both PNG
and HEIC. Core's `AppIconPolicy.choose` keeps the smaller one that **really
kept its alpha**: the HEIC is decoded back to check, because a writer
without alpha support drops it silently. An encode without alpha is never
chosen. Payload for about 500 apps:
- per-icon cap of 16 KB (an icon over it is drawn again at 48 px);
- a 6 MB list budget, past which non-running apps get 48 px icons (running
  apps always get 72 px, since they're the dock);
- a cache keyed by path, size and modification date (`NSCache`, 12 MB), so
  the 5-minute rescan only encodes apps that changed.

PNG icons at 72 px are typically 5–12 KB and HEIC 2–5 KB, so about 500
apps come to roughly 2–5 MB, against about 1.5 MB of JPEG before. The window
picker uses the same encoder at 96 px.

**No protocol bump.** `InstalledAppInfo.iconData` is still plain `Data`,
and the iOS side still decodes it with `UIImage(data:)`, which reads PNG and
HEIC. An older Mac's JPEGs still decode; they just keep their square.

**Fix, iOS.** `AppDock` draws each icon as its own shape with **no tile,
plate or border**. The front app gets a **4 pt accent dot** 4 pt under its
icon, which replaces the 2 pt accent ring box (`06-Pixel-Identity.md` §5
updated, and recorded in `DECISIONS.md`). A press dips the icon to 90 % with
a touch of fade (`DockIconPressStyle`); before, it faded a chip-style plate.
Sizing and spacing come from `AppIconPolicy`: 36 pt icon, 44 pt target, 8 pt
between apps. When the Mac sent no icon, the stand-in has an icon-shaped
corner radius (22 %) instead of a key radius. Elsewhere: `QuickActionsPills`
and the classic `StreamDeckGridView` no longer clip icons to a rounded rect.
The context strip's app chip and the deck keys already drew the image bare,
so they're fixed by the new data.

**Tests.** `AppIconPolicyTests`: 72 px is 2× the dock icon; the smallest
encode with alpha wins and one without alpha never does; ties go to PNG;
500 apps stay within the budget; running apps keep full size; the dot sits
on the 4 pt grid inside the 56 pt dock.

## OT-2 · Keyboard opens and closes in a loop (P1)

**Cause, confirmed in Core.** iPad Air 11" landscape is 1180 × 820, which
is the `columns` form. The on-screen keyboard (about 400 pt) shrank the
shell's safe area to about 1180 × 420. `LayoutMetrics` reads 420 as
"short", so `CanvasPlan` switched to the **rail** form. The rail has no
dock, and its keyboard panel lived in a different branch, so SwiftUI tore
down the view that held the first responder. Then:
1. the keyboard dropped;
2. the layout went back to `columns`;
3. the dock's state still said "shown", so a new `LiveTypingField` called
   `becomeFirstResponder` in `makeUIView`;
4. the keyboard came back, and the cycle repeated.

Rotating or tapping the button broke it. There were also two separate
"keyboard shown" flags: the shell's `isKeyboardShown` and the pad's own
`showKeyboard`. `ShellKeyboardTests.shortenedFrameWasTheBug` pins the cause
down: 1180 × 420 is the rail.

**Fix.**
- **The arrangement ignores the keyboard.** The shell's `GeometryReader`
  has `.ignoresSafeArea(.keyboard, edges: .bottom)`, so it measures the
  window. It plans through Core's `ShellPlanningSize`, which holds the rule
  and gives back any keyboard shortening a host reports. The keyboard
  covers the shell's foot; nothing in the shell moves.
- **One place for the panel.** `TypePanelHost` is a fixed child of the
  shell's `ZStack`, outside the `switch plan.form`, so the panel and its
  `UITextView` keep one identity through form changes, rotation, Stage
  Manager resizes and Split View. Every per-form `keyboardPanel(...)` call
  is gone, as is the tab bar and strip "stepping aside" while typing.
- **It sits above the keyboard or the dock.** The host ignores the
  keyboard's safe area too, and places the panel with Core's
  `TypePanelLayout.bottomPadding`: 8 pt above the higher of the keyboard's
  top and the dock's top. The keyboard's top comes from
  `keyboardWillChangeFrame`, converted to the window (floating and
  undocked keyboards count as none, `KeyboardKind.overlap`). The dock's top
  comes from `onGeometryChange`, used only in forms that show a dock. So
  the dock (and its keyboard button) stays usable when no keyboard covers
  it.
- **One source of truth.** `TypePanelModel` (one per window, `@State` in the
  shell, passed down the environment) wraps Core's `TypePanelPresence`. The
  dock's keyboard button, the pad's keyboard button (`PointerSurface`, where
  the dock is folded) and the lock banner's Keyboard button all go through
  it. The pad no longer draws its own panel. The field takes focus when
  `focusRequest` changes and gives it up when the Numpad tab or a close
  asks.
- **Hardware keyboard.** `GCKeyboard` (GameController, public API) plus the
  keyboard frame's overlap give `KeyboardKind`: `.software` from 120 pt of
  overlap up, `.hardware` when one is attached and at most the shortcut bar
  shows, otherwise `.none`. Hardware means the keys-only panel (OT-3).
- **iPhone, Split View, Stage Manager, rotation.** The same rules apply.
  Short rooms (iPhone landscape with the keyboard up) drop the panel's
  header (`TypePanelLayout.showsHeader`) so it fits above the keyboard.

This also protects any other text field in the shell from the same loop,
for example the Ask field in the iPad landscape column. That field used to
shrink the shell into the rail, which has a different column.

**Tests.** `ShellKeyboardTests`: across 9 window sizes and 6 keyboard
heights, the form never changes, including the regression for 1180 × 420.
Also covered: keyboard classification, and overlap for docked, Stage
Manager, floating and hidden keyboards. `TypePanelPresenceTests` covers
toggle, open twice, tabs and focus, closing clears, and the remembered
mode. UI walk **`test18_KeyboardStaysOpenInLandscape`** runs in landscape:
it opens the panel, then for 5 s (every 0.5 s) asserts the panel is still
up, the keyboard is still up (or the field still has focus on a simulator
with a hardware keyboard), and the dock hasn't moved. Then it types, tries
Compose and Numpad, rotates to portrait (the panel must stay), and closes.

## OT-3 · Typing into the Mac: the Type panel

**Design rationale.** The old bar was a stock text field over a scrolling
row of keys, and it mixed three jobs: real-time typing, "put this text into
that field", and special keys. The owner's two pains map to the first two:
typing into a Mac field without watching every keystroke land, and numbers.
So the panel separates them, in the pixel identity:

```
┌───────────────────────────────────────────────────────────────┐
│ [Live│Compose]  ⌨ Typing into Safari          [⌨│▦]     (×)    │  header
│ ┌─────────────────────────────────────────┐ [Paste] [+⏎] [Send]│  field
│ └─────────────────────────────────────────┘                    │
│ ⌘ ⌥ ⌃ ⇧ │ esc tab ⌫ ⏎ ← ↓ ↑ → home end pg up pg dn  │ fn       │  keys
└───────────────────────────────────────────────────────────────┘
 Numpad tab: the field gives way to the 4 × 5 dot-matrix keypad.
```

- **Live vs Compose.** Live keeps the build 24 behaviour exactly: each
  committed change goes as a `TypingEdit`, autocorrect and IME are safe,
  and hardware arrows and ⌘ chords go to the Mac. Compose is a local
  multi-line draft that you type or dictate, read, then **Send**, with or
  without Return (the **+⏎** toggle). This is the "fill in a Mac text field
  reliably" path: nothing reaches the Mac until Send, so typos and
  dictation fixes happen on the iPad. Return on the keyboard sends,
  ⇧Return adds a line, and ⌘Return sends from a hardware keyboard. Both
  modes share **one `UITextView`**, so switching never hands the keyboard
  to another view; that would have been a fresh OT-2. The mode is
  remembered (`pixelhand.type.mode`).
- **Paste** is the system paste control (no permission prompt). In Live it
  goes to the Mac as before (Settings decides cursor or clipboard; it's
  still Pro `.sharing`). In Compose it goes into the draft, free.
- **Keys row:** esc, tab, ⌫, ⏎ (accent), the four arrows, home, end, page
  up and page down, with **fn** swapping in F1–F12. Caps are text where a
  symbol alone is ambiguous (VQ-034). The row scrolls with the one-key fade.
- **Sticky chips** ⌘ ⌥ ⌃ ⇧: tap once and the chip is lit for the next key,
  tap again and it's locked (lit, with a 2 pt accent ring), tap a third
  time to let go. This is `04-Interaction-Model.md`'s "tap = once,
  double-tap = lock", made discoverable as a cycle. Core `ModifierLatch`
  uses up once-modifiers after a key and keeps locked ones. VoiceOver hears
  "Held for the next key" or "Locked".
- **Numpad tab:** a 4 × 5 grid of 0–9, the point, + − × ÷ =, ⌫, Enter (two
  rows tall) and 0 (two columns wide). Caps are in **dot-matrix numerals**:
  the font gained = × ÷. Operators are drawn in accent ink and Enter sits
  on the accent. The system keyboard steps down while the numpad shows.
  Digits and operators go as **typed text**, so they land the same on any
  keyboard layout and in any spreadsheet. Enter is the keypad's Enter
  (`keypadenter`) and ⌫ is Delete. In Compose, the numpad writes into the
  draft. Keys are whole points, 44–64 pt (`TypePanelLayout.numpadKeySize`).
- **"Typing into <App>"** (VQ-036) is always visible: in the header on
  medium and wide windows, on its own line on compact ones, and as the
  field's placeholder when the header is hidden. The Return guard (confirm
  before Return goes to a different app) covers keys, Live edits, Compose's
  Send with Return, and the numpad's Enter.
- **Layouts** (`TypePanelLayout`, all tested):
  - iPad landscape: a 760 pt card with the chips in the keys row and
    Compose up to 2 lines.
  - iPad portrait: chips in the row and 4 lines.
  - iPhone portrait: the target on its own line and the chips on their own
    row.
  - iPhone landscape with the keyboard up: no header, close in the field
    row, and the chips in the keys row.
  - Hardware keyboard: **keys only**. The field is one line naming the
    target (it must hold focus to take the hardware keys), then the keys
    row with the chips, then close.
- **Look.** A raised card (radius 24, 12 inset, hairline, soft shadow) with
  keys and chips at radius 8 and numpad keys at 14, on the 4 pt grid.
  Selection is by colour and fill only, and the panel fades (180 ms, none
  under Reduce Motion).
- **Accessibility.** Every control has a VoiceOver label and an
  identifier:
  - `ph.type.panel`, `.close`, `.target`, `.field`, `.paste`, `.send`,
    `.sendReturn`, `.fn`
  - `ph.type.mode.live` and `.compose`; `ph.type.tab.keys` and `.numpad`
  - `ph.type.key.<wire name>`, `ph.type.modifier.<name>`,
    `ph.type.numpad.<key>`

  The old `ph.keyboard.*` IDs are gone; no UI test used them.
- **Kept:** typing, the hardware-key mapping, ⌘-latched letters becoming
  chords, Backspace on an empty field deleting on the Mac, drag behaviour
  (untouched), and the clipboard status line ("Copied on the Mac: …").
  The classic layout's `TrackpadView` uses the same panel inline (it has
  one arrangement, so there is no loop to avoid).

**Tests.** The Core suites `TypeKeysTests`, `ModifierLatchTests`,
`NumpadTests`, `ComposeSendTests` and `TypePanelLayoutTests` check:
- every key exists in the Mac's `KeyTable`;
- the row's contents and order, and chord order;
- the latch cycle, consumption and spoken values;
- the numpad grid covers each cell exactly once, outputs are ASCII text or
  known keys, and caps draw in the dot-matrix font;
- Compose's text then Return, blank drafts, and long drafts chunked under
  the Mac's limit;
- layout per window and keyboard, whole-point numpad keys, and bottom
  padding.

### Ideas not built yet (typing)
- True keypad key codes (`keypad0` … `keypadplus`) for apps that treat the
  numpad differently (games, some CAD). That needs a `KeyTable` addition
  that older Macs would refuse, so it should wait for a protocol bump.
- "Send to field": the Mac reads the focused text field's value (the
  Accessibility API it already uses for context chips), so Compose could
  start from what's already in the Mac's field and replace it in one go.
- A clipboard history strip in Compose (the last few things copied on
  either side).
- Text snippets: saved phrases as one-tap chips, maybe synced with the
  deck.
- A trackpad strip inside the panel on iPhone portrait, so the pointer can
  move without closing the keyboard.
- Double-tap on a modifier chip to lock, as well as the tap cycle.
- Per-app default mode (for example Compose for Messages and Mail, Live
  for Terminal).

## OT-4 · Right column handle

**Cause.** The collapsed handle was a 6 × 72 capsule in `raised` with a
hairline on the `canvas`, about 1.1:1, so it vanished in both appearances.

**Fix.** A 20 × 88 capsule (`RightColumnPlan.handleHeight`) with an
`accentTint` fill, a 1.5 pt `accent` edge, and a pixel **chevron** glyph
(`PixelGlyphs.chevronLeft`, the tip lit as the action point) in `accentInk`.
The touch target is still 44 pt wide and the full column height. It gets
the press response and the phosphor focus ring.

**Tests.** The three pairs are in `ContrastAudit.rightColumnHandle` (and so
in `ContrastAudit.all`, which every token change runs through):
- accent edge on canvas;
- accentInk chevron on accentTint;
- accentInk chevron on canvas.

`RightColumnHandleContrastTests` checks each is ≥ 3:1 in light, dark and
both high-contrast appearances, that the old `raised` on `canvas` was under
3:1, and that the 44 pt target and the chevron are in place.

## OT-5 · Ask gets stuck after one use (P1)

**Cause.** The panel's state was spread across `AskModel.phase` and three
`@State` flags (`isEditing`, `isConfirming`, `saveNote`). After a run the
buttons were Run · Save as key · Edit only. There was no New request or way
back: the field still held the old text. Tapping **Edit** in the finished
state swapped the plan's typed-text steps into bare `TextField`s and hid
every action except Done. With a typing plan, which is the common case,
that looked like "only a Name field". Nothing could clear it without
re-typing the request.

**Fix.** Core's `AskFlow` is the state machine:
`request → planning → plan ⇄ editing`, `plan → running → result`, and
`plan / result → naming → back`. The flow and its actions:
- **The field always starts over** (`canSubmitRequest` everywhere except
  while planning). Submitting stops a run and leaves editing or naming.
- **Planning** has Cancel.
- **Plan:** Run, Save as key, Edit, New request.
- **Result:** the result row ("Done on Studio." or "Done on Studio: 3
  steps.", or the stop reason), then **New request** (clears the field and
  focuses it), **Run again**, **Save as key**, **Edit**.
- **Save as key** is a short flow: **Name** (the plan's own label
  suggested), **Save** (off while the name is blank) and **Cancel**. It
  returns to the plan or result it came from, with a "Saved as a key on
  Home." note. A failure (deck full) keeps the name field with the reason.
  The name becomes the key's label (`saveAskPlan(_:appName:label:)`, cut to
  the deck's label length).
- **Edit** has Done, which returns to the plan.
- **Stop** returns to the plan.
- **Recent requests:** up to 5, newest first, no repeats in any case. They
  show above "Try" under an empty field and persist in
  `pixelhand.ask.recent`.
- Late planner or run callbacks are ignored by stage, and runs carry a
  generation, so a run that ends after New request can't jump back to a
  result.

`AskModel` feeds the flow and `AskPanel` draws `flow.stage` and
`flow.actions`, the same in the sheet (iPhone, compact) and the right
column. On a narrow column the actions wrap to two rows (`ViewThatFits`).
Each action has the identifier `ph.ask.<action>`; there are also
`ph.ask.name`, `ph.ask.result`, `ph.ask.note` and `ph.ask.recent`.

**Tests.** `AskFlowTests` covers:
- the owner's walk;
- the actions after a run;
- save from the result, and a failed save;
- Edit and Done; Run again and Stop;
- the field from every stage;
- cancelling planning;
- late events;
- recent requests;
- identifiers.

`AskSaveNameTests` covers a named key, a blank name, and a long name. UI
walk **`test19_AskAgainAfterRun`** asks, runs, asserts New request, Run
again, Save as key and the result line, then New request (asserts the field
is cleared), Save as key (asserts Name and Cancel), Cancel (asserts the
plan is back), and asks again.

## Linux results

- `swift test --package-path DeckHand/Core`: **1108 / 1108 pass** (201
  suites). There were 1058 before, so 50 tests are new.
- `DeckHand/Scripts/linux-typecheck/run.sh`: passes. It includes
  `Assist/AskModel.swift`.
- `swiftc -parse` (syntax only) is clean on every changed app file that
  can't be type-checked here:
  - iOS: `TypePanel`, `TypePanelModel`, `LiveTypingField`, `AskSheet`,
    `PixelHandShell`, `AppDock`, `RightColumnChrome`, `PointerSurface`,
    `TrackpadView`, `PasteToMacControl`, `QuickActionsPills`,
    `StreamDeckGridView`;
  - Mac: `AppIconEncoder`, `InstalledAppScanner`, `ScreenCaptureService`;
  - the UI tests.

## iPad checks (iPad Air 11" M3, landscape first; then portrait, iPhone)

1. **OT-2:** in landscape, tap the dock's keyboard button. The keyboard
   comes up once and stays. The shell doesn't change arrangement, and the
   panel sits on the keyboard. Wait 10 s, then type. Then try:
   - rotate to portrait and back with it open;
   - Stage Manager: resize the window with it open;
   - ½ Split View;
   - the floating keyboard (pinch the keyboard);
   - a Magic Keyboard attached (keys-only panel, above the dock);
   - the lock banner's Keyboard button;
   - iPhone portrait and landscape (landscape: no header, still usable).
2. **OT-3:** Live typing, autocorrect and dictation still work, and
   hardware ⌘C/arrows go to the Mac. Then check:
   - Compose: dictate, edit, Send with and without +⏎ into a Mac text
     field, and Paste into the draft;
   - the chips' cycle: ⌘ once then C, ⌘ locked;
   - fn then F5;
   - Numpad into Numbers or a Calculator, including Enter;
   - "Typing into …" and the Return guard when the front app changes;
   - VoiceOver on the chips and the numpad;
   - light and dark.
3. **OT-1:** in the dock, in light and dark, icons have no square, the
   front app has the accent dot, and the press is subtle. Also check the
   context strip's app chip, the deck's app keys and the window picker. On
   a Mac with about 500 apps, the app list arrives in about a second.
4. **OT-4:** collapse the right column in landscape and portrait, in light
   and dark (and Increase Contrast). The handle is clearly visible and a
   tap anywhere in its 44 pt strip opens it.
5. **OT-5:** in the right column and in the iPhone sheet: ask, Run, New
   request, Save as key, Cancel, ask again. Also check Save as key with a
   name (it shows on the deck), Edit then Done, Stop, and that recent
   requests appear.

## PixelHandUITests changes

- `test18_KeyboardStaysOpenInLandscape` (new, asserts) and
  `test19_AskAgainAfterRun` (new, asserts). Both need a live Mac like the
  other walks. `test18` honours `PH_QA_FULLSCREEN=1` on iPad (VQ-092);
  without it the windowed simulator stays portrait.
- `test04` still taps `ph.dock.keyboard` or `ph.trackpad.keyboard` and
  types; the field it types into now has the identifier `ph.type.field`.

## Compile risks (most likely first)

1. `TypePanel.swift`, `TypePanelModel.swift`, `LiveTypingField.swift`,
   `AskSheet.swift` and the shell were written without an iOS SDK. They
   parse, but weren't type-checked. Watch for:
   - `@Bindable var model: TypePanelModel` with `$model.mode` and
     `$model.draft`;
   - the `ViewThatFits` / `ForEach` actions in `AskPanel.actions`;
   - `.buttonStyle(.ph(isPrimary ? .primary : .secondary, size: .small))`
     inferring the kind;
   - `LiveTypingField.sizeThatFits(_:uiView:context:)` (iOS 16+).
2. `TypePanelModel`:
   - `@ObservationIgnored nonisolated(unsafe) private var observers` and
     the `NotificationCenter` closures using `MainActor.assumeIsolated`;
   - `GCKeyboard.coalesced`, read in `init` and on the connect and
     disconnect notifications.
3. `AppIconEncoder` (Mac):
   - `nonisolated(unsafe) private static let cache: NSCache<…>`;
   - `NSImage.cgImage(forProposedRect:context:hints:)` with
     `[NSImageRep.HintKey: Any]`;
   - `UTType.heic` (macOS 11+).
4. `AskPanel`: `if case .result = model.flow.stage, let outcome = …` inside
   a `ViewBuilder` (`if case` with a `let`), and `case .plan, .editing,
   .running, .result, .naming:` matching cases with associated values
   without bindings.
5. `PixelHandShell`: `TypePanelHost` is a new `ZStack` child next to the
   `switch`. If the type checker is slow on `body`, move the host into
   `.overlay` on the `ZStack`; the identity stays stable either way.

## Behaviour notes

- While the panel is open with no keyboard up, it covers part of the
  canvas above the dock. It has its own close button, and the dock stays
  usable under it.
- The tab bar and strip no longer step aside while typing (VQ-033's
  workaround); the keyboard simply covers the shell's foot.
- `keyboardFrameChanged` measures against the key window. With two Pixel
  Hand windows side by side in Stage Manager, the non-key window may read
  the other window's overlap until it becomes key. That's rare; check it
  during the Stage Manager pass.
- Ask's result line now reads "Done on <Mac>." (one step) or "Done on
  <Mac>: N steps."; it was "Ran N steps on <Mac>.".

## Out-of-lane edits

- `Product/Design/06-Pixel-Identity.md` §5: the front app in the dock is
  now an accent dot (owner request). `04-Interaction-Model.md` §2
  "Keyboard" now describes the Type panel.
- `Integration/DECISIONS.md`: a 2026-11-26 entry for the owner's build 24
  findings. `STATUS.md`: a line under "Owner testing (build 24)".
- `Core/Tests/PixelHandCoreTests/PixelDesignTests.swift`: the dot-matrix
  font's expected set gained = × ÷.

Lane: READY TO MERGE
