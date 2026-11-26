# Lane: owner testing, build 26 (owner26)

Branch `claude/pixelhand-lane-owner26`, from `claude/pixelhand-integration`.
It builds OT-9 to OT-13 from the owner's hands-on test of build 26 on the
iPad Air 11" (M3), portrait and landscape, dark (`STATUS.md`, "Owner
testing (build 26)").

<!-- TABLE -->

## OT-11 · The Type panel uses its space

**Cause.** Build 25's `TypePanelLayout` sized the panel from its **width
only**. The height was whatever the content measured: a field column of
the field plus an action row holding one icon-only Paste button (the empty
strip under the field, beside the arrows); a 2-row arrow cluster at a fixed
44 pt next to a taller field column, or a 7 × 44 key block in a wider
panel (the empty block under the arrows and to the right of the keys).
Every cell was a constant 44 pt, so resizing changed nothing but the
field's width. "Typing into Claude" was in the header and again in the
field's placeholder (the placeholder named the target whenever the header
didn't show it, and on hardware keyboards always).

**Design.** The panel is resizable in **both** directions now, and Core
cuts **every block from the panel's current width and height**
(`Core/Input/TypePanelLayout.swift`, new). Nothing in the panel is sized by
its content, so nothing is left over; the tests check that every band runs
edge to edge with one 8 pt gap between blocks, for every width from 304
to 760 pt, every height in the range, Live and Compose, numpad on and off,
on-screen and hardware keyboards (`noDeadAreas`).

- **Rows** run from 44 pt (the touch target) to **72 pt**. 72 is where a
  cap is already a very big target; past it the panel would only cover
  more of the Mac picture, so the height range stops there.
- **Field and arrows** share their band's full height. Arrow and action
  cells are square with the row while the field keeps **144 pt** (about
  13 characters a line; the field shows two lines once its band is 60 pt
  tall). The field fills its frame (`LiveTypingField.fillsHeight`).
- **Keys mode, stacked:** field │ actions │ inverted T on top; the two key
  rows **span the panel's width** (cells = inner width ÷ 7, as tall as a
  row), so there's no block to their right.
- **Keys mode, one block** (wide and short, from **676 pt**): field │
  actions │ T │ key rows in one band two rows tall. Taller than 140 pt of
  body it becomes stacked (that's where three 44 pt rows plus a gap fit),
  so the height range is continuous.
- **Shortest:** under four rows of 44 (184 pt of body) the arrows go to
  **one row** (← ↑ ↓ →) and the two actions sit side by side: one row
  saved (44 pt + its gap). Only from **448 pt** wide: narrower, the field
  would drop under 144 pt beside six cells, so the T stays.
- **Numpad mode:** only the arrows and the 5 × 4 numpad (the modifier and
  special-key rows go). Side by side from **384 pt** wide (eight columns
  of at least 44 pt: 3 arrows + 5 numpad), with the arrows as tall as the
  numpad; narrower, the arrows in one row across with the numpad under
  them. In Compose a one-line draft with +⏎ and Send sits on top (the
  numpad writes into it, so it has to be visible). The field stays in the
  view tree with no size (OT-2: the keyboard never moves to a new view).
- **Actions** (replaces the action row under the field): Live has
  **Accept ⇥** (OT-13) and **Paste**; Compose has **+⏎** and **Send**.
  Compose's Paste button went: its field is local, so the system's Paste
  (edit menu, ⌘V, the keyboard bar's Paste) already works in it. Live keeps
  Paste because Live's field doesn't hold the text.
- **Header:** one row from **456 pt** (grip 44, Live│Compose 144, target
  chip 44, numpad 44, collapse 44, close 44, gaps, padding); narrower, a
  second row holds the mode switch and the app's name, so neither row is
  half empty. The clipboard status line under the body is gone (it changed
  the panel's height); the paste status now shows in the header's name
  slot for its few seconds. "Copied on the Mac: …" no longer shows in the
  panel.
- **Target once:** the header's chip shows the Mac app's **icon** (from
  the installed-apps list), its name from 560 pt wide (or on the second
  header row), and a magnifier: it is also the **Zoom to the input**
  button (OT-12). The placeholder is neutral: "Type here" / "Type or
  dictate, then Send". Only when there's no header (iPhone landscape with
  the keyboard up) does the placeholder name the app.
- **Resize:** the bottom corners now drag in both directions (sideways the
  other edge holds; down and up the top holds), clamped to the layout's
  height range for the new width and to the room below the panel's top.
  The height is stored with the place (`TypePanelPlacement.height`,
  optional, so build 25's stored places still read). A panel taller than
  the free room (the keyboard came up) shrinks to it, never under its
  shortest. VoiceOver's adjustable action steps width by 40 and height by
  20.
- **Keyboard bar:** with a hardware or minimised keyboard, iPadOS keeps
  its slim bar (EN US · Paste · mic) at the bottom; its frame comes through
  the keyboard notifications with an overlap under 120 pt. The panel
  already ended above it (its free room stops at the keyboard's top); the
  **dock** didn't, because the shell ignores the keyboard's safe area
  (OT-2). `KeyboardKind.barLift(overlap:bottomInset:)` gives the bar's
  height above the home-indicator inset, `TypePanelModel.dockLift` follows
  it, and the shell pads the dock up by it. A full on-screen keyboard
  lifts nothing (it covers the dock by design).

**What changed.**
- Core: `Input/TypePanelLayout.swift` (new: `Arrangement` oneBlock /
  stacked / numpad, `Block`, `Grid`, `Action`, `ActionCell`, `heightRange`,
  `headerRows`, `showsAppName`, `fieldLines`); `Input/TypePanel.swift`
  (the old width-only layout removed; `ArrowCluster.Shape` and
  `cells(for:)`; neutral placeholders; `KeyboardKind.barLift`);
  `Input/TypePanelGeometry.swift` (placement height, 2-D resize,
  `placement(resizedTo:keeping:keepsHeight:)`, `height(for:)`, the
  loupe's frame).
- iOS: `Keyboard/TypePanel.swift` (body placed at Core's frames by
  `PanelBodyLayout`; `KeyGrid`/`KeyCap` take the cell size from the block;
  legends scale up to 1.5×; header with the target chip; action block;
  host passes height, the app icon and the zoom switch);
  `Keyboard/LiveTypingField.swift` (`fillsHeight`);
  `Keyboard/TypePanelModel.swift` (`dockLift`); `Shell/PixelHandShell.swift`
  (the dock's bottom padding, two lines).

**Tests.** `TypePanelLayoutTests` (new, 15): keys-only body; **no dead
areas** across every width × height × mode × numpad × keyboard; compact
default; field and arrows share the band; arrows grow 44 → 72 and stop;
key rows span the width; numpad shows only arrows and numpad (side by side
or row-over-pad; Compose's draft row); one-row arrows and the 448 / 676
thresholds; actions per mode; shrinking to the room; target once and the
header rows; short room; Slide Over; every test window. Plus
`KeyboardBarLiftTests`, `TypePanelHeightResizeTests` (taller, clamped,
stored, build 25 places still read) and `TypePanelLoupePlacementTests`.
The build 25 width-only `TypePanelLayoutTests` were replaced.

<!-- REST -->
