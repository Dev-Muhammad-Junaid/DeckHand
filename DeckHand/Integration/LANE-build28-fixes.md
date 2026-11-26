# Lane: build 28 fixes (build28-fixes)

Branch `claude/pixelhand-lane-build28-fixes`, from
`claude/pixelhand-integration` at `95dc82f` ("Queue build 29: live sync
phase 1"), so it sits on top of the caret-joystick and live-sync lanes and
keeps their work. It fixes the open bugs in `STATUS.md` "Mac build results
(build 28 with owner27)" and "Mac walks (build 28)", for build 30.

No protocol change (still 17). No `project.yml`, Info.plist or Loom change;
the new Core file is picked up by the package.

| # | Bug | Sev | Status | Files |
|---|---|---|---|---|
| 6 | Type panel under the keyboard in iPad landscape (build 25 bug 1 again) | P1 | Fixed (needs an iPad landscape check) | Core `Input/KeyboardFrameReading.swift` (new), `Input/TypePanelGeometry.swift`; iOS `Keyboard/TypePanelModel.swift`, `Keyboard/TypePanel.swift` (host) |
| 7 | Numpad mode keeps the modifier and key rows (OT-11) | P2 | Fixed (needs an iPad check) | iOS `Keyboard/TypePanel.swift` (`KeyGrid`, numpad slot) |
| 1 | iPhone Live has no Accept ⇥ (OT-13) | P2 | Fixed (needs an iPhone check) | Core `Input/TypePanelLayout.swift`; iOS `Keyboard/TypePanel.swift` (action row span) |
| 2 | iPhone landscape keyboard button not hittable (VQ-105) | P2 | Fixed, likely cause (needs an iPhone check) | Core `Design/CanvasPlan.swift`; iOS `Shell/SurfaceTabBar.swift`, `Shell/PixelHandShell.swift`; walk fallback |
| 8 | No "Ask before running" in the key editor (OT-8) | P3 | Fixed (needs an iPad check) | Core `Deck/Action.swift` (`asksFirstFootnote`); iOS `Deck/KeyInspectorSheet.swift` |
| 3 | Loupe frame overlaps the panel (`test22`) | P3 walk | Fixed in the walk | `PixelHandUITests` |
| 4 | Capture dock frame (`test24`) | P3 | Fixed (identifier moved) | iOS `Capture/CaptureChrome.swift` |
| 5 | Send sheet (`test23`): card height, Paste fill, zero window | P3 walk | Fixed in the walk; spec updated | `PixelHandUITests`, `07-Polish-Spec.md` |
| — | `test18` dock lift, `test20` panel size, `test04` toast dot | walk-only | Fixed | `PixelHandUITests`; iOS `ContentRootView.swift` (toast element) |

## 6 · The Type panel under the keyboard in iPad landscape (P1)

**Cause (most likely; not reproducible here).** The panel's free room ends
`gap` above `TypePanelModel.keyboardMinY`. With that unknown, the room runs
to the window's bottom and a panel parked at the bottom (the default
place, `y = 1`) draws under the keyboard: Compose, Numpad and Live exist
but aren't hittable, exactly `test18`'s `05-not-hittable-ph-type-mode-compose`.
A panel parked top-left (`test20`, `test22`) isn't affected, and portrait
worked, so the keyboard's top was being lost **in landscape only**.
`refreshKeyboard()` converted the notification's screen-space end frame
with one call, `window.convert(_, from: window.screen.coordinateSpace)`.
That is right in portrait (screen and interface spaces agree) and is the
one step that changes with orientation: a conversion that comes back
turned a quarter (a 1210 × 398 keyboard read as 398 × 1210) gives an
overlap of 0 (`KeyboardKind.overlap` wants the frame to reach the window's
bottom), so `keyboardMinY` was `nil` and the panel's room ignored the
keyboard. A frame from the old orientation arriving after the window
turned (build 25 bug 1's case) does the same until the Did notification.

**Fix.**
- **Read the keyboard in the window as it is now** (Core,
  `KeyboardFrameReading`, new). The model converts the end frame every way
  it can (the screen's interface space, its fixed space, the window's
  screen conversion, and as given) and Core picks the first that reads as
  a keyboard in this window: wider than tall (the full keyboard, the
  floating one and the slim bar all are), shorter than the window, not
  above it. A frame that reads as none leaves the last reading in place
  instead of wiping it. `read(_:windowWidth:windowHeight:)` returns
  `.covers(top:overlap:)`, `.clear` or `nil`.
- **Keep every frame above the keyboard** (Core,
  `TypePanelGeometry.kept(_:)`, and `fitsAbove(_:)`). The host passes the
  frame it draws, whatever it came from (the remembered place, a drag or
  resize in flight, a frame worked out before the keyboard rose or the
  window turned), through `kept`: moved into the free room, never resized;
  a panel taller than the room keeps its header in view. The remembered
  place (fractions of the room) is not rewritten, so the same corner comes
  back when the keyboard goes, and the arrangement doesn't change (OT-2).
- **On rotation** the host drops a drag or resize in flight (it belongs to
  the old window) and reads the keyboard again right away and 0.5 s later,
  after the rotation settles.

**Tests** (`Build28FixTests.swift`):
- `KeyboardFrameReadingTests` (6): a turned frame is rejected and the right
  one picked, for iPad Pro 11" and Air portrait and landscape and iPhone
  17 Pro both ways; the iPad landscape top comes out at 436; hidden and
  floating keyboards read as clear; the slim bar gives the 46 pt dock lift
  `test18` saw; nothing plausible keeps the last reading; a stale portrait
  frame in landscape isn't a software keyboard.
- `TypePanelAboveKeyboardTests` (6): every remembered place (3 × 3), numpad
  on and off, in all five windows: the header is always above the
  keyboard and a panel that fits ends `gap` above it; a tall remembered
  height shrinks to the landscape room; a frame from before the keyboard
  (or from portrait) is moved, not resized; taller than the room keeps its
  top; docked panels stay centred; NaN frames go to the room's corner; the
  place itself isn't rewritten.

**Walk.** `test18` now checks, in landscape, in portrait after rotating,
and in landscape again, that the panel ends above an on-screen keyboard
and its Compose, Live, Numpad and close are hittable
(`checkPanelAboveKeyboard`).

**`test18`'s dock check (walk-only note).** The dock rising 46 pt onto the
keyboard bar is OT-11 ("dock avoids the keyboard bar"). The walk now
checks the dock keeps its size and x and moves only straight up by less
than 120 pt (the bar's limit), instead of an equal frame.

## 7 · Numpad mode keeps the modifier and key rows (P2)

**Cause.** Core's numpad layout already had only the arrows and the
numpad (`TypePanelLayoutTests`, OT-11). The view kept the hidden key block
in the tree with a zero frame and `opacity(0)`: its caps were framed at a
zero cell (`KeyCell`), but a cap's own content doesn't shrink to zero, so
the caps overflowed the empty frame; the ⌘⌥⌃⇧ row stayed in the
accessibility tree and XCTest found `ph.type.modifier.command` hittable
(`test20`'s `05-type-numpad-docked`).

**Fix.** `KeyGrid` draws its content only when the layout gives the block a
grid: the key rows (and Live's actions, which numpad mode also drops)
leave the view tree, not just fade. The numpad slot is an `if`/`else` with
a clear view, so `PanelBodyLayout` still places five subviews in order.
Only the field must keep its identity (OT-2), and it isn't in a grid. The
arrows always have a grid; their joystick (caret-joystick lane) reads the
cell size from the grid (`typeKeyCell`), so it works on the numpad's
arrows (three columns by two rows beside the numpad, or one row across
above it).

**Tests.** `NumpadOnlyTests` (2): for every width 304…760 and every
keyboard, numpad mode shows exactly arrows + numpad, no actions in Live,
the arrows' grid matches their shape (every cell the joystick anchors to
is inside it), and together they span the panel's inner width; the 362 pt
panel puts the arrows in a row over the numpad. `test20` now checks the
modifier row, esc, ⌫, fn and the key block are gone, the arrows stay, the
arrows and numpad span the panel, and (with a scratch document in front)
a hold-and-drag on ← runs the joystick (`ph.type.joystick.last` reads
"joystick N").

## 1 · iPhone Live has no Accept ⇥ (P2, OT-13)

**Cause.** The action column was `full`-body only. On the iPhone walks the
simulator types from the Mac's keyboard (build 28 bug 2: "no system
keyboard on screen"), so `KeyboardKind` was `.hardware`, the body
`keysOnly`, and Live had no actions: no `ph.type.accept`. The iPad walk
had the on-screen keyboard, so it had Accept.

**Fix.** `TypePanelLayout.Spec.actions`: with a hardware keyboard Live keeps
**Accept ⇥** alone (Paste stays an on-screen-keyboard action; ⌘V works on
a hardware keyboard); Compose has none there, as before. A lone action
beside the inverted T spans both rows (`ActionCell.rowSpan`, new, default
1), so no cell is left empty; the view passes it to `keyCell`.

**Tests.** `LiveAcceptEverywhereTests` (2): iPhone 17 Pro portrait and
landscape, iPhone SE, iPad Pro portrait and landscape, every height in the
range, on-screen, hardware and no keyboard: Live always has Accept;
hardware Live has Accept alone spanning the column, Compose none, and the
on-screen layout is unchanged. `TypePanelLayoutTests.hardware` updated to
the new rule. `noDeadAreas` still passes for every width, height, mode,
numpad and keyboard.

## 2 · iPhone landscape keyboard button not hittable (P2, VQ-105)

**Cause (likely; not reproducible here).** The rail's keyboard circle
(`ph.rail.keyboard`) was the last control inside the rail's
`GlassEffectContainer` (`phGlassGroup`), which on iOS 26 renders the glass
of every control in the group together and, since owner27, also carries
the badge layer's overlay. The circle drew (visible in the capture) but
XCTest's hit point at its centre didn't resolve to the button. The rail's
stack also had a fixed 12 pt spacing with no check that it fits the
window's height, so on a short window the last circle could be pushed
past the edge.

**Fix.**
- The keyboard circle is its **own glass, outside** the tabs' and Ask's
  glass group, `fixedSize`, with `zIndex(1)`, an explicit 62 × 62 frame and
  a circular content shape after its glass. The rail itself has
  `zIndex(1)` in the shell's row, above the pad and the deck column.
- Core: `CanvasPlan.railStackHeight(tabs:carriesKeyboard:spacing:)`,
  `railSpacing(availableHeight:)` (12, tightening to 4 when the stack
  wouldn't fit) and `railFits(availableHeight:)`. The shell passes the
  window's height and `SurfaceTabBar` takes the spacing (new `spacing:`
  parameter, default 12, so other callers are unchanged).
- Walk: `openTypePanel()` still taps a hittable button first. If
  `ph.rail.keyboard` exists but XCTest calls it not hittable, it asserts
  the button is at least 44 × 44 with its centre inside the window, then
  taps that centre, so `test18`, `test20` and `test22` reach the panel and
  a remaining hit-test problem is reported without blocking the walk.

**Tests.** `RailStackTests` (2): the stack fits at full size in iPhone 17 Pro
Max, 17 Pro, SE and mini landscape; spacing 12 with room, tighter on short
windows, never under 4, NaN gives 12; the stack's height adds up.

## 8 · No "Ask before running" in the key editor (P3, OT-8)

**Cause.** The switch was there, but last: under the preview, Label, the
glyph grid, the colours and the action, in a `Form` whose rows below the
fold aren't built. On iPad the sheet opened without it on screen and the
walk (and the owner) found Label and Glyph only.

**Fix.** "Ask before running" is now its own section right under Label, in
view when the sheet opens, with a line under it
(`DeckKey.asksFirstFootnote`, Core, new): for a key with typed steps
(a typed step anywhere in a sequence too) it shows **on and locked** with
why ("Keys that type text always ask first…"), as already enforced by
`asksFirst`; otherwise it says what it does. Pin to first row stays in the
options below.

**Tests.** `KeyEditorAsksFirstTests` (1): typed and sequence-with-typing
keys ask first, locked, footnote = the reason; a shortcut key follows the
switch. `test21` already asserts `ph.inspector.asksFirst` exists.

## Walk fixes (bugs 3–5 and the walk-only notes)

- **`test23`.** A device card may be taller when a name wraps to two lines
  (OT-16 wins): ≤ 84 pt with one-line names, ≤ 104 pt when any name (a
  static text over 30 pt tall) wraps. The Paste chip is the system
  `PasteButton` (owner's decision): fills are compared for Photos and
  Files only (`checkChipsLookAlike(_:tag:fillChips:)`), the ink check
  still covers all three. "Sheet centred" and "sized to its content" use
  `windowFrame()`, the largest window (`app.windows.firstMatch` read as
  zero). The spec's card height line now says "taller when a name takes
  two lines".
- **`test22`.** The loupe check (`checkLoupeClearOfPanel`) compares the
  loupe with the panel's **card**, measured from its blocks (keys, arrows,
  numpad, field + 12 pt padding), so the resize handles straddling the
  card's bottom corners (26 pt outside it, reaching into a loupe placed
  8 pt below the panel) don't count; a loupe squeezed to its 96 pt
  minimum (room too short for both, `TypePanelGeometry.loupeFrame`) may
  overlap the card's top by design. The "went under the keyboard" check
  only uses an on-screen keyboard (the iPhone walk read a hidden one's
  frame, build 28 bug 2 of the first run).
- **`test24`.** `ph.capture.dock` now sits on an element of the card's own
  shape (a clear `RoundedRectangle` in the card's background, labelled
  "Capture actions"), not on the `.contain` container, whose frame was
  built from its children and ran 1,177 / 801 pt past the window. The
  walk uses `windowFrame()`.
- **`test20`.** Before the resize check the walk widens the panel by 600 pt
  (to the room), so a width remembered at the 362 pt minimum from an
  earlier walk can still get narrower.
- **`test04`.** The connecting toast is one accessibility element
  (`.accessibilityElement(children: .combine)` before
  `ph.connect.toast`), so the identifier names the whole toast and not
  its 8 pt status dot.

## Linux results

- `swift test --package-path DeckHand/Core`: **1418 / 1418 pass** (257
  suites); 19 new in `Build28FixTests.swift` (7 suites), one updated
  (`TypePanelLayoutTests.hardware`).
- `DeckHand/Scripts/linux-typecheck/run.sh`: **Build complete**, no errors.
- `swiftc -parse` is clean on every changed iOS file and the UI tests.
- Loom: not touched, not run.

## Re-checks for the Mac build

**iPad Pro 11" (and the real iPad Air), full screen:**
1. **Bug 6.** Landscape, fresh place (or after "Move to the bottom"): open
   the Type panel with the on-screen keyboard: it sits on the keyboard,
   Compose / Numpad / Live / close all work. Rotate to portrait and back
   with it open: above the keyboard each time. Drag it mid-screen, then
   bring the keyboard up: it moves up, same size, same corner when the
   keyboard goes. `test18`, `test20`, `test22`.
2. **Bug 7.** Numpad on (wide and at 362 pt): only the arrows and the
   numpad; no ⌘⌥⌃⇧ row, no key rows; hold an arrow and drag: the joystick
   runs. `test20` (`type-numpad-docked`, `type-numpad-joystick`).
3. **Bug 8.** Deck › Edit › a typed key: "Ask before running" under Label,
   on and greyed, with the reason. A shortcut key: the switch works.
   `test21`.
4. **Bug 4.** `test24`: the dock frame is the card (< 160 pt tall, inside
   the window).
5. **Bug 3 / 5.** `test22` loupe, `test23` (card height, Paste fill,
   centring) pass.

**iPhone 17 Pro:**
1. **Bug 1.** Live, portrait and landscape, with the Mac's keyboard and with
   the on-screen keyboard: ⇥ ACCEPT beside the arrows. `test22`.
2. **Bug 2.** Landscape, every tab: the rail's keyboard circle opens the
   panel with one tap; Accessibility Inspector says it is hittable.
   `test18`, `test20`, `test22` reach the panel (watch for a
   "not hittable" snapshot before the fallback tap: that means the hit
   test is still covered and needs a look by hand).
3. `test04`: the connecting toast measures its full width.

## PixelHandUITests changes

- New helpers: `windowFrame()` (the largest window), `checkPanelAboveKeyboard`,
  `checkLoupeClearOfPanel`; `checkChipsLookAlike(_:tag:fillChips:)`.
- `openTypePanel()`: rail fallback (size and in-window asserts, then a tap at
  the centre).
- `test18`: dock may rise < 120 pt for the keyboard bar; panel above the
  keyboard in landscape, portrait and landscape again.
- `test20`: widen before the narrow check; numpad leaves only the arrows and
  the numpad, they fill the width; joystick on the numpad's arrows.
- `test22`: loupe vs the card; keyboard check only with an on-screen keyboard.
- `test23`: two-line card heights; Paste chip out of the fill comparison;
  `windowFrame()`.
- `test24`: `windowFrame()`.
- Identifiers: `ph.capture.dock` moved to the card's shape element;
  `ph.connect.toast` is now the combined toast. No new identifiers.

## Compile risks (most likely first)

None of the SwiftUI or UIKit changes are type-checked on Linux (only
parsed).

1. **`TypePanelModel.refreshKeyboard`**: `window.windowScene?.screen ??
   window.screen` (`window.screen` may warn as deprecated on iOS 26; a
   warning only); `window.convert(_:from: UICoordinateSpace)` twice,
   `window.convert(_:from: nil as UIWindow?)` (the `UIWindow` overload,
   written out so `nil` isn't ambiguous with `UIView.convert(_:from:)`);
   the `switch` over `KeyboardFrameReading.Reading` with `let` bindings;
   the new `import PixelHandCore`.
2. **`SurfaceTabBar.body`**: the same `AnyLayout` value used for the outer
   and inner stacks (`layout { layout { … }.phGlassGroup(…); if … }`);
   `RailKeyboardButton(…).fixedSize().zIndex(1)` inside a layout's
   `@ViewBuilder`; the new `spacing:` memberwise parameter between
   `keyboard` and the trailing `onAsk` (the shell passes it in that order).
3. **`KeyGrid.body`**: `if grid != nil { content }` inside the `ZStack`.
   **`TypePanel.body`**: the numpad slot as `if layout.shows(.numpad) {
   NumpadGrid … } else { Color.clear }` inside `PanelBodyLayout { … }` (one
   subview either way).
4. **`TypePanelHost`**: `geometry.kept(liveFrame.map { … } ?? geometry.frame(…))`
   in the `GeometryReader` closure; `DispatchQueue.main.asyncAfter` in
   `.onChange(of: windowSize)` assigning `@State` (`liveFrame`,
   `gestureStart`).
5. **`CaptureDock`**: `.background { if let identifier { RoundedRectangle(…)
   .fill(Color.clear).accessibilityElement()… } }` (a `@ViewBuilder`
   background with an optional branch).
6. **`KeyInspectorSheet`**: the new `Section { Toggle … } footer: { Text(…) }`.
7. **`PixelHandShell.railLayout(plan:height:)`**: the new `height:` argument
   (one call site).
8. **UI tests**: `CGRect.union`/`intersection`/`isNull`, `XCUIElement.staticTexts`
   on a card, `press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)`
   (already used by `test27`).

## Behaviour notes

- With a hardware keyboard, Live now shows ⇥ ACCEPT beside the arrows (the
  field is a little narrower by one cell); Compose is unchanged.
- In numpad mode the key rows and Live's Accept/Paste are removed from the
  view (and from VoiceOver), not just hidden.
- The rail's spacing tightens on the shortest iPhone landscape windows.
- "Ask before running" moved up in the key editor; Pin to first row stays
  below.

## Out-of-lane edits

No other lanes are running. Listed for the record:
- `Shell/PixelHandShell.swift`, `Shell/SurfaceTabBar.swift` (the rail),
  `ContentRootView.swift` (one modifier on the connect toast),
  `Capture/CaptureChrome.swift` (the dock's identifier).
- `Keyboard/TypePanel.swift`: `KeyGrid`, the numpad slot, the action
  row span and the host's frame clamp; the joystick code from
  caret-joystick and the live-sync field are untouched.
- `Product/Design/07-Polish-Spec.md` §4 (Type panel), §8 (Send cards),
  §9 (capture dock).

Lane: READY TO MERGE
