# Lane: iPhone Duo panes (UX-040)

Branch `claude/pixelhand-lane-duo`, merged with
`origin/claude/pixelhand-integration` at `785d970`. No protocol change (still
12), no `project.yml` or Info.plist change; the new files are picked up by
folder.

## What changed

### How the pose is detected

Both ways, best first:

1. **System API (iOS 27.1 SDK).** `DuoCrease.division(proxy:)` reads
   `GeometryProxy.reservedRegions(kind: .division, options: [.includeInactive])`
   and uses the first region's `frame` (margins included). It reads inactive
   regions too, so the layout doesn't jump between half-folded and flat.
   `DuoHingeReader` uses `onHingeChange` and maps `hinge.status` (`.closed` /
   `.partiallyOpen` / `.fullyOpen`). `.closed` forces the cover layout. Both
   sit behind `#if compiler(>=6.4)` (Xcode 27) **and**
   `if #available(iOS 27.1, *)`. The app still targets iOS 17.4.
2. **Inference, the fallback.** It is used before iOS 27.1, on an older SDK,
   or when the system reports no division. On a **phone-idiom** window that
   is neither compact (< 500 wide) nor short (< 500 tall), the window must be
   the open inner display, because an iPhone in landscape is always under
   500 tall. The crease is then the window's centre line, across its longer
   side, as a **40 pt** keep-out band (`DuoPoseMachine.minimumBandWidth`).
   The centre is the window's, not the safe area's, so the status bar and
   home indicator don't shift it. iPad never infers a crease, so a 951 × 669
   Stage Manager window keeps `columns`.

A system division narrower than 40 pt is widened to 20 pt on each side of
its centre line, and a wider one is kept as it is. If a crease would leave
either pane under 320 pt, the crease is ignored.

### Core (`Core/Sources/PixelHandCore/Design/`)

- **`DuoLayout.swift`** (new):
  - `DuoPose` (`none`, `folded`, `book`, `laptop`) and `DuoHingeStatus`.
  - `DuoPoseInput`, `DuoCreaseBand`, and `DuoRect`.
  - **`DuoPoseMachine`**, the pose state machine. `band(for:)` is a pure
    read. `update(_:)` remembers whether a crease has been seen, so the
    cover display reads as `folded` rather than `none`. It also returns a
    `Transition` (`isFold`, `isRotation`).
  - **`DuoPanes`**: the pane rectangles either side of the band (book at
    951 × 669 gives 455 | 40 | 455), plus `keepsClear(_:)`.
  - **`DuoArrangement`**: what each pane shows for the selected tab.
- **`CanvasPlan`**:
  - New forms `book` and `laptop`, chosen when `init(…, crease:)` gets a
    band. The old forms are unchanged without one.
  - New `duoPanes` and `isDuoOpen`.
  - The book's deck counts as a column, so its tab bar is Pointer and Screen.
  - The laptop folds the dock into the strip.
- Tests: `DuoLayoutTests.swift` (11 tests). **792 Core tests pass**, and
  `Scripts/linux-typecheck/run.sh` builds.

### iOS (`DeckHandiOS/Shell/`)

- **`DuoCrease.swift`** (new) builds the `DuoPoseInput` from the shell's
  `GeometryProxy` and holds the hinge reader described above.
- **`PixelHandShell`** feeds the band into `CanvasPlan` on every pass, so
  the first frame is already right. Each pane is placed at its exact frame
  (`ZStack` plus `offset`), and nothing is laid out in the band. On any pose
  transition, the pose machine drops a pane drag that is still in flight.
- **Book** (from the board's `v2DuoBook`):
  - Leading pane: a 16 pt outer margin and none toward the crease.
  - Selected Screen: the docked screen over the Pointer, with a drag handle
    (the same `PaneSplit` as iPad Split).
  - Selected Pointer or Deck: the Pointer alone, with the floating tile laid
    over the pad only.
  - At the leading pane's foot: the keyboard panel, then the app dock.
  - Trailing pane: header, status pills, the strip (compact, so dialog
    chips wrap), the deck, and the tab bar (Pointer, Screen) with Ask.
- **Laptop** (from the board's `duoLaptop`):
  - Top pane: the header, status pills, and the docked screen (or its
    "Show screen" state).
  - Bottom pane: the keyboard panel, the strip (running apps folded into
    its app chip), Pointer or Deck, and the tab bar (Pointer, Deck) with
    Ask. The pad keeps its own keyboard circle.
- **Cover display**: unchanged. It is the `single` iPhone layout, and the
  selected surface is kept across folds because it is scene storage.

**Keep-outs.** The Pointer's click strip, caption and keyboard sit at the
pad's own foot, and the floating tile (`MirrorTileKeepOut`) is still laid
over the pointer pane alone. Every keep-out therefore works inside a Duo
pane exactly as it does elsewhere.

## Checks on the Mac build

Board: https://claude.ai/artifact/Aa8KTJubKeqahy3cmSjRTm ("Duo & iPad",
"iPhone Duo"). Light **and** dark. Use the iPhone Duo simulator on iOS 27.1,
or the device.

**Cover (466 × 678)**
1. The iPhone portrait layout: header, pad, strip with the folded app chip,
   and the tab bar. It should look as it did in the build before this one.

**Book (951 × 669, open flat and half-folded)**
1. Two panes with a clear gap of about 40 pt down the middle. Nothing
   (glass, text, the handle, the dock or the tile) touches the crease, in
   both the flat and half-folded positions.
2. Pick Screen: the screen is docked on the left, above the pad, with the
   handle between them. Drag the handle and check that the pad keeps its
   click strip.
3. Pick Pointer: the pad fills the left pane. Start the mirror: the tile
   floats over the pad only and never covers the click strip or the
   caption.
4. Right pane: Mac pill, capture and More, then the strip. Raise a Save
   dialog on the Mac: the chips wrap and are not truncated. Below them,
   the deck at 4 a row, then the tab bar with Ask.
5. Press the dock's keyboard button: the keyboard panel opens above the
   dock in the left pane.

**Laptop (669 × 951, half-folded with the hinge horizontal)**
1. Top: the header, then the screen. A clear band of about 40 pt sits at
   the fold. Bottom: the strip, the pad, and the tab bar (Pointer, Deck).
2. Pick Deck: the deck replaces the pad. The screen stays on top.
3. Hold the device upright and flat (the same size): the layout is the
   same, and still nothing sits on the crease.

**Transitions with the mirror on.** Start the mirror in book with Pointer
selected, then do each of the following:
1. Fold to the cover: the floating tile keeps streaming and the selection
   is kept.
2. Open again: it goes back to book.
3. Rotate to laptop: the screen docks on top.
4. Rotate back.

Check that the stream never stops or restarts, that no layout from the
previous pose stays on screen, and that no pane flashes `columns` or
`stacked` for a frame. Do the same while dragging the split handle in the
middle of a transition: the drag is dropped, with no crash and no jump.

**Is the system path in use?** With iOS 27.1 the band should follow the
system's division. Temporarily log `crease?.fromSystem` in
`PixelHandShell.body`, and expect `true` on iOS 27.1 and `false` before it.

**Regressions**
1. iPhone 17 Pro portrait and landscape, and iPhone SE: unchanged (`single`
   and `rail`).
2. iPad 11″ portrait and landscape, ½ Split View, and a Stage Manager
   window resized to about 951 × 669: unchanged (`sideBySide`, `columns`,
   `stacked`). No crease on iPad.

## Compile risks (most likely first)

SwiftUI can't be type-checked on Linux. Every changed file passes
`swiftc -parse`, Core is tested, and the Linux type check builds.

1. **The iOS 27.1 API spelling** (`DuoCrease.swift`). I wrote it from
   third-party write-ups and couldn't check it against the SDK:
   - `reservedRegions(kind: .division, options: [.includeInactive])`;
   - `region.frame`;
   - `onHingeChange { old, new in }`;
   - `new.hinge?.status` with `.closed`, `.partiallyOpen` and `.fullyOpen`.

   If something is spelled differently, fix the call. If it fights back,
   delete the inside of the `#if compiler(>=6.4)` blocks: inference alone
   still gives the right panes.
2. **`#if compiler(>=6.4)` with Xcode 27.0.** If Xcode 27.0's Swift is also
   6.4, its iOS 27.0 SDK won't have these symbols. The owner builds with
   27.1. On 27.0, take the same fix as in risk 1.
3. **`PixelHandShell.body`**:
   - `.onChange(of: crease, initial: true)` sits inside the `GeometryReader`
     and captures `proxy`;
   - `DuoCrease.input` is `@MainActor`;
   - `duoPose.update` mutates `@State`.
4. **`duoLayout`**: a `ZStack` of `Group { if … else … }` with
   `.frame(…).offset(…)`. The `switch plan.form` has a new
   `case .book, .laptop: if let panes`.
5. **`bookLeadingPane`**:
   - `switch` on a Core enum inside `Group`;
   - `dock.padding(.horizontal, -PixelHandTheme.Space.md)` (negative
     padding cancels the dock's own inset).
6. **`SurfaceTabBar(tabs: DuoArrangement.bookTabs.compactMap(ControlSurface.init(rawValue:)))`**:
   the initialiser is used as a function reference.

## Known gaps

- If the cover display had Screen selected, the laptop tab bar (Pointer,
  Deck) highlights nothing. The same happens in book when Deck was selected,
  because book offers Pointer and Screen. The selection is kept on purpose,
  so the cover layout reopens on the same surface.
- Presets (Split, Screen, Pointer) aren't offered on Duo. The tab bar picks
  the book's lead instead, as `03-Layout-Strategy.md` describes. The board's
  "Deck focus" preset for Duo is left for later.

## Out-of-lane edits

None. The changes are in `DeckHandiOS/Shell/**` (`PixelHandShell.swift`
and the new `DuoCrease.swift`), Core `Design/**` (`CanvasPlan.swift` and
the new `DuoLayout.swift`), one new test file, and this handoff. No surface,
`Mirror/**`, `Transfer/**` or Share extension file was touched.

Lane: READY TO MERGE
