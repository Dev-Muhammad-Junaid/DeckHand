# Lane: UX Pointer (UX-004)

Branch `claude/pixelhand-lane-ux-pointer`, merged with
`origin/claude/pixelhand-integration` (`COORDINATOR.md` update). No protocol
change (still 12), no `project.yml` or Info.plist change.

## What changed

### The Pointer surface (`DeckHandiOS/Surfaces/PointerSurface.swift`, new)

The shell's Pointer tab now shows `PointerSurface` instead of the classic
`TrackpadView`. It follows the board's "Control surface · Pointer":

- **Pad**: a navy `PixelSurface` (radius 30, hairline) with the `DotField`
  running under the whole pad, strip included, so the grid reads as one
  screen. Same canvas margin as the other surfaces (`LayoutMetrics.margin`).
- **Caption** (board `pad__cap2`): bottom-leading, 12 pt above the strip, a
  24 pt plate (radius 8) with a pixel glyph and dot-matrix text. At rest
  `2 FINGERS · SCROLL` (or `1 FINGER · SCROLL` in one-finger scroll mode);
  while a finger works it lights phosphor and names it: `POINTER`,
  `SCROLLING`, `MOVE TO DRAG`, `DRAGGING`, `DRAG LOCKED · TAP TO DROP`,
  `PENCIL`, and after a three-finger gesture `MISSION CONTROL`,
  `APP EXPOSE`, `NEXT SPACE`/`PREVIOUS SPACE`, `APPS`, `DESKTOP` (held
  1.2 s). Replaces the SF Symbol gesture indicator and the 9 pt hint line.
- **Click strip** (board `pad__clicks`): Click | Right-click across the
  pad's foot, 52 pt, hairline top and divider, press flash (phosphor wash +
  lit text). Touch and hold the strip for Double-click, Find the pointer and
  One-finger scrolling (the old bar's extra buttons). Hidden by Settings ›
  Pointer and gestures › **Click strip**, and automatically when the pad is
  under 240 pt tall (small iPhone with the keyboard open).
- **Keyboard**: a 44 pt glass circle with the keyboard glyph at the pad's
  top-leading corner (the floating screen tile keeps the trailing side);
  opens the same `RemoteKeyboardPanel` under the pad. Moves to the app dock
  when UX-005 lands.
- **Coach mark** (first use only): drag ("Rest a finger until it buzzes,
  then move to drag") and three fingers (Mission Control, Spaces), on a
  `screenRaised` card; dismissed by "Got it", the first drag or the first
  three-finger gesture (`@AppStorage("pixelhand.pointer.coachMarkSeen")`).
- **Removed** from the shell's Pointer: the 7-button gesture bar and the
  sensitivity slider (sensitivity is already in Settings). Mission Control
  and Show Desktop are three-finger gestures and deck keys.
- **VoiceOver**: the pad is one direct-touch element ("Trackpad", value =
  the caption's spoken text) with actions for Click, Double-click,
  Right-click, Mission Control, App Exposé, Show Desktop, Next/Previous
  Space, Find the pointer, one-finger scrolling and the keyboard. So every
  gesture has a visible or VoiceOver equivalent.

### Shared input wiring (`TrackpadView.swift`)

`TrackpadInputLayer` (new, in `TrackpadView.swift`) is the dot field +
`MultiTouchTrackpad` + every callback to `TrackpadSender`, lifted out of
`TrackpadView` unchanged. Both the classic `TrackpadView` and
`PointerSurface` use it, so typing, drag (press-hold-move, drag lock), S11
gestures with toggle-back and S12 Pencil hover behave identically. The
classic layout keeps its gesture bar and slider.

### Core (`Input/PointerCaption.swift`, new)

`PointerActivity`, `PointerCaption.caption(for:)` (text, spoken label,
glyph, lit) and `PointerSurfaceLayout` (strip height, the 240 pt rule).
Tests in `PointerCaptionTests.swift`: every caption is uppercase, ≤ 26
characters and drawable in `DotMatrixFont`; Space captions match
`GestureMap`'s natural direction; the strip rule. 571 Core tests pass;
`linux-typecheck/run.sh` passes.

### Settings

`SettingsPointerSection`: **Click strip** toggle (same `@AppStorage` key the
surface reads: `pixelhand.pointer.showsClickStrip`, default on), caption in
`TrackpadInputCopy.clickStripCaption`. `DotField` reads `PixelHandTheme`'s
`dotOff` instead of the shim.

## Checks on the Mac build (against the board)

Light and dark for each (the pad stays navy in both; only the canvas around
it changes), then Settings › Accessibility › Larger Text at AX3.

**iPhone 17 Pro portrait (402 × 874)**, board "Control surface · Pointer"
1. Connect. Pointer tab: a navy pad 16 pt from both edges, radius 30, dot
   grid edge to edge including behind the strip; no gesture bar, no slider
   under it.
2. Caption bottom-leading, 12 pt above the strip: click glyph +
   `2 FINGERS · SCROLL` in dim white dots. Move a finger: `POINTER` lights
   phosphor with a glow; two fingers: `SCROLLING`; rest a finger until it
   buzzes: `MOVE TO DRAG`, move: `DRAGGING`; second finger down: lock glyph
   + `DRAG LOCKED · TAP TO DROP`. Three fingers up: Mission Control opens on
   the Mac and the caption says `MISSION CONTROL` for about a second.
3. Strip: Click | Right-click, 52 pt, hairline divider; each press flashes
   and clicks on the Mac. Touch and hold the strip: Double-click, Find the
   pointer, One-finger scrolling (turn on: caption says
   `1 FINGER · SCROLL`, one finger scrolls).
4. Keyboard circle top-leading: opens the keyboard panel under the pad;
   typing, special keys, latching modifiers and Paste to Mac work; the pad
   shrinks and keeps working.
5. First launch only: the coach card in the pad; "Got it" dismisses it for
   good (also dismissed by the first drag or three-finger gesture). To see
   it again: delete the app or reset `pixelhand.pointer.coachMarkSeen`.
6. Floating screen on: the tile sits over the pad as before (see risks).
7. Settings › Pointer and gestures › Click strip off: the strip goes, the
   caption drops to 12 pt above the pad's bottom edge.
8. AX3: caption steps up one pitch (glyph 1.6 → 1.8, dots 1.3 → 1.4) and
   still fits; strip labels grow, the strip grows taller instead of
   clipping; coach text wraps inside its card.

**iPhone SE (375 × 667)**: strip shows; with the keyboard panel open the
strip hides (pad under 240 pt), gestures still work.

**iPhone landscape (874 × 402)**: rail on the leading edge, pad takes the
rest with the strip; pad should be ≥ 300 pt tall (polish spec) — measure,
see risks.

**iPad 11″ portrait (820 × 1180)**, ½ Split View and **landscape
(1180 × 820)** with the deck column: pad with 20 pt margins; Apple Pencil
hover moves the pointer (caption `PENCIL`), tap clicks; four-finger gestures
where iPadOS allows.

**VoiceOver**: the pad reads "Trackpad, Two fingers to scroll"; rotor →
Actions lists Click … Show keyboard; each works. Direct touch still moves
the pointer.

**Classic layout** (More › Use the classic layout): unchanged, gesture bar
and slider still there and still work.

## Compile risks (most likely first)

None of the SwiftUI can be type-checked on Linux; every file passes
`swiftc -parse`, Core is tested, `run.sh` passes.

1. `PointerSurface.touchSurface`: the chain of
   `.accessibilityAction(named:)` with a ternary `String` name, and
   `.accessibilityElement()` on a `UIViewRepresentable`-backed view.
2. `TrackpadInputLayer.callbacks`: closures capture a `Binding<GestureMap>`
   and call the mutating `resolve`/`forget` through `wrappedValue`; and
   call the main-actor `DotFieldModel` from `TrackpadCallbacks` closures
   (same isolation as the old inline code in `body`).
3. `PHGlyph(glyph:pitch:stepsWithType:)` with literal pitches (1.6, 2) —
   `CGFloat` literals, memberwise order glyph → pitch → stepsWithType.
4. `pad(height:)`: `let` bindings inside a `@ViewBuilder` func;
   `.animation(_:value: caption)` needs `PointerCaption: Equatable` (it is,
   `GlyphBitmap` is `Hashable`).
5. `onGestureChanged`'s `switch gesture { case .none, .system: … case .some: … }`
   over `TrackpadGestureKind?`.
6. `ClickStrip.contextMenu` with a `Toggle` inside.
7. `PixelHandShell`: `colorScheme` may now be unused there (warning only).

## Out-of-lane edits

- `DeckHandiOS/Shell/PixelHandShell.swift` (Design lane), one line in
  `surfaceView`: `.pointer` → `PointerSurface(sender:clipboard:margin:)`
  instead of `TrackpadView(...)`.

Everything else is in this lane's list: `TrackpadView.swift`,
`DotField.swift` (UX-004's file list), `Settings/SettingsPointerSection.swift`,
`Settings/DeckHandSettings+Input.swift`, the new
`Surfaces/PointerSurface.swift`, Core `Input/PointerCaption.swift` + test.

## Follow-ups for other lanes

- **Mirror (UX-006)**: the floating tile is still placed by
  `MirrorThumbnailView`'s remembered layout and can cover the click strip or
  the caption; the polish spec says it must not. Anchor it to the pad's
  top-trailing corner (board: 12 pt inset, 176 × 110 on 402 wide).
- **Design (UX-005)**: move the keyboard button into the app dock (the board
  puts it there) and remove `PointerSurface.chromeLayer`; the dock can toggle
  it through a binding if needed.
- **Design (UX-007)**: landscape pad height depends on the header/rail; if
  it measures under 300 pt on 874 × 402, trim the header in the rail
  arrangement.

Lane: READY TO MERGE
