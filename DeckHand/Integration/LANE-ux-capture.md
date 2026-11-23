# Lane: UX capture (tile vs Pointer, UX-009)

Branch `claude/pixelhand-lane-ux-capture`, merged with
`origin/claude/pixelhand-integration` at `8e2ba59`. No protocol change
(still 12), no `project.yml` or Info.plist change. New files are picked up
by folder (`DeckHandiOS/Capture/`, Core `Capture/`).

## What changed

### 1. The floating screen tile never covers the Pointer controls

**Core `Mirror/MirrorTilePlacement.swift`** (+ `MirrorTilePlacementTests`,
11 tests): the placement maths, on Linux.

- `pointerKeepOut(pad:clickStrip:caption:keyboard:)`: the areas to avoid.
  The caption row is reserved across the whole pad, so the tile doesn't jump
  when `POINTER` grows into `DRAG LOCKED · TAP TO DROP`.
- `home(width:height:anchor:)`: the pad's top-trailing corner, 12 pt in
  (board: tile top-trailing on the pad).
- `place(_:in:avoiding:)`: the nearest frame to where the tile was dropped
  that is on the canvas (8 pt margin) and 8 pt clear of every reserved area.
  A drag sweep over the whole canvas is tested to always end clear.
- `fittingWidth(...)`: caps a pinch at the largest width that still has a
  clear spot (e.g. with the keyboard panel open the pad is short).

**iOS**

- `Mirror/MirrorTileKeepOut.swift` (new): the Pointer surface reports its
  pad, click strip, caption and keyboard button frames (window
  coordinates) with `.mirrorTileKeepOut(_:owner:)`, keyed by the session's
  `TrackpadSender` (two iPad windows don't mix). Parts remove themselves
  when they leave the screen (strip hidden in Settings or under 240 pt,
  keyboard moved to the dock, surface switched).
- `MirrorOverlay` reads its own window frame, converts the areas, and passes
  `homeAnchor`, `keepOut` and the desktop-dots height to the tile.
- `MirrorThumbnailView`: home is the pad's top-trailing corner (the
  canvas's when there's no pad, e.g. Deck and the classic layout); every
  live drag, pinch, commit and layout change goes through `place` /
  `fittingWidth`; the tile animates clear when the pad shrinks or the strip
  appears. Drag uses the global coordinate space (the tile moves under the
  finger). The desktop dots under the tile count toward its footprint.
- **Supersedes** the Screen lane's fixed 96 pt bottom band (`053f703`,
  `b36ed25`): the merge keeps this lane's `MirrorThumbnailView`.
- Saved layouts (Settings › Remember size and position) are now offsets
  from the top-trailing home; an old saved offset is simply clamped.

### 2. UX-009 Capture sheet

**Core `Capture/`** (+ `CaptureSheetChromeTests`, 8 tests):
`CaptureSheetChrome` (status strips `FULL SCREEN · 3024X1964`,
`REGION · 812X540 · MARKED`, `WINDOW · SAFARI · 1440X900`,
`ANNOTATE · 3 MARKS`, `READ TEXT · 12 LINES · 340 CHARS`; all tested
drawable in `DotMatrixFont`), the locked-Mac alert copy, pen widths and
inks; `CaptureGeometry` (aspect fit, screen → capture pixels, region
normalisation and pixel readout); `CaptureGlyphs` (Save, Copy, Annotate,
Undo, Clear, Reset, Refresh, drawn to the glyph rules and tested).

**One capture sheet, one modal level** (`ScreenshotPreviewView.swift`):
the full-screen capture presentation now holds three steps instead of
presenting a cover and a sheet on top of itself:

- **Preview**: navy stage with the resting dot grid; header = close glyph
  + status strip; the capture in a black well (radius 24, hairline) with the
  scanline sweep on arrival; pinch / double-tap zoom; at 1× a downward
  swipe closes. Dock: Save, Copy, Share, Annotate, Read text (pixel glyph +
  label; glyph only at accessibility sizes; phosphor press flash; dot wave
  while saving). Toasts are `PHToast`.
- **Annotate** (`AnnotationView.swift`): header `ANNOTATE · N MARKS` with
  Done; dock row 1 pen widths · Undo · Clear, row 2 inks (phosphor first)
  scrolling, so it fits 320 pt and AX5. **Clear asks**; Cancel with marks
  asks. Marks are stored in the capture's coordinates (rotation-safe,
  clipped to the picture) and **baked in at the capture's native size and
  scale** (the old export was screen-sized with transparent letterbox bars).
- **Read text** (`OCRResultView.swift`): Vision on-device as before, shown
  on a raised navy panel, selectable; `READING` dot wave; empty and failed
  states are `PHEmptyState` (failed has Try Again). Dock: Copy all, Share,
  Picture. Re-reads if the capture was annotated since.
- **Recognize Text** from the capture menu now opens this sheet straight at
  read text (no separate OCR sheet; closing returns to Control).
- **Loading** (`ControlCaptureSheets.swift`): capture glyph at pitch 6, dot
  wave and `CAPTURING` / `READING SCREEN` in dot-matrix, Cancel button.

**Region picker** (`RegionCropView.swift`): same stage and header; strip
reads the selection's size in the capture's pixels live; selection is a
dashed phosphor rim with glow and pixel-square handles (44 pt hit areas),
outside dimmed with the navy scrim; **Reset is always enabled**; full-width
"Capture Region" primary button with the Region glyph. Normalisation now
in Core (clamped to the picture). Still a full-screen cover so its drags
never fight a sheet swipe.

**Window picker** (`WindowPickerView.swift`): navy stage, header
`CAPTURE · 7 WINDOWS` / `MIRROR · …` with Refresh, raised navy cells with a
phosphor press rim, `READING WINDOWS` dot wave, `PHEmptyState` whose copy
also covers a locked Mac (the Mac answers a locked window-list request with
an empty list). Medium and large detents. Takes `purpose:` instead of a
title string.

**Locked Mac**: the Mac's refusal (`LockPolicy.lockedErrorMessage`) now
shows the alert **"Mac Is Locked"** with "Unlock the Mac to take a
screenshot. Pixel Hand never captures the lock screen." (mirror: "…to see
its screen…"). Other errors keep "Screenshot Failed" / "Live Screen
Unavailable" and the Mac's message. The refusal itself is unchanged
(Mac-side `LockGate`).

**`CaptureCapsule`** (classic toolbar): pixel capture glyph, dot wave while
busy. `SettingsCaptureSection` unchanged (the shell lane restyled Settings).

## Checks on the Mac build

Light and dark for each (capture screens are navy in both; check the
canvas around them and system dialogs), then Larger Text at AX3/AX5.

### Floating tile on the Pointer tab (iPhone 17 Pro 402 × 874, iPad 11″ 820 × 1180 and landscape)

1. Connect, Pointer tab, turn the floating screen on: the tile appears at
   the pad's **top-trailing corner, 12 pt in**, keyboard button (if still on
   the pad) top-leading untouched.
2. Drag the tile to each corner and let go:
   - top-trailing: stays.
   - top-leading: stops 8 pt to the right of / below the keyboard button,
     never over it.
   - bottom-leading and bottom-trailing: parks **above the caption row**
     (8 pt clear), never over the caption or the Click | Right-click strip.
3. While dragging (finger still down) across the strip and caption: the
   tile slides along above them; it never sits on them.
4. Pinch the tile up as far as it goes: it stops at the canvas width (or
   the height above the caption), never growing over the strip.
5. Open the keyboard panel: the pad shrinks and the tile moves/shrinks
   with it to stay clear; close it, the tile returns. On iPhone SE with the
   panel open the strip hides (pad < 240 pt) and the tile may use that space.
6. Settings › Pointer › Click strip off: the tile can go 8 pt above the
   caption, which now sits at the pad's foot.
7. Desktop dots under the tile (Mac with 2+ desktops): the dots also stay
   clear of the caption.
8. Switch to Deck: tile top-trailing of the canvas, free to move anywhere on
   it. Screen tab: docked pane as before (unchanged).
9. Settings › Remember size and position on: move/resize, reconnect, the
   tile comes back where it was (still clear).

### Capture flows (iPhone 17 Pro, iPhone SE / 320 pt Zoomed, iPad portrait and landscape)

1. **Full screen** (capture button tap): `CAPTURING` dot wave, Cancel works.
   Sheet: strip `FULL SCREEN · 3024X1964` (Mac's pixels), the scanline
   sweeps down once. Pinch/double-tap zoom, pan when zoomed. Swipe down at
   1× closes.
2. Dock: **Save** (dot wave, then "Saved to Photos"; a window capture keeps
   its transparent shadow), **Copy** (paste into Notes), **Share** (system
   sheet), with Settings › Save to Photos automatically on, one save on
   arrival.
3. **Annotate**: draw with each width and ink (ink row scrolls at 320 pt),
   Undo, Clear → "Clear all marks?" dialog. Close with marks → "Discard
   your marks?". Done → back to preview with toast "Marks applied" and
   strip `… · MARKED`; Save the result and check in Photos it is full
   resolution with no black/transparent bars and marks where drawn. Rotate
   the iPad mid-annotation: marks stay on the same spot.
4. **Read text**: `READING` then the text, selectable; strip counts lines
   and chars; Copy all, Share (text), Picture returns; annotate then Read
   text again re-reads. A blank region → "No Text Found".
5. **Recognize Text** from the capture menu: `READING SCREEN`, sheet opens
   at read text; close returns to Control.
6. **Region**: picker shows strip `REGION · DRAG TO MARK`; drag a region,
   strip shows its pixel size; move, resize from every handle, drag outside
   starts a new one; Reset always tappable; Capture Region → fresh region
   capture → sheet with `REGION · …`.
7. **Window**: picker (medium detent, drag to large) `CAPTURE · N WINDOWS`,
   Refresh, pick → `WINDOW · SAFARI · …`. From the mirror's "Window…" the
   header says `MIRROR · …` and picking mirrors the window.
8. **Locked Mac** (lock the Mac with Ctrl-Cmd-Q): full-screen and region
   capture → alert "Mac Is Locked" with the unlock sentence; window picker →
   "No Windows" empty state mentioning unlocking; Recognize Text → same
   alert. Unlock: everything works again.
9. Screen Recording off on the Mac: the existing timeout/permission message
   still shows under "Screenshot Failed".
10. AX5: header strip drops trailing items, dock shows glyphs only (labels
    spoken), annotate tools still fit, read text wraps.
11. VoiceOver: dock items read Save/Copy/Share/Annotate/Read text; the strip
    reads "Region capture, 812 by 540 pixels, annotated"; pen widths and
    inks announce selection.

## Compile risks (most likely first)

Nothing here can be type-checked on Linux; every file passes
`swiftc -parse`, Core is tested (622 tests pass), `run.sh` passes.

1. `CaptureHeader<Trailing>`: `@ViewBuilder var trailing: () -> Trailing`
   memberwise init plus the `where Trailing == EmptyView` convenience init;
   overload resolution at the three call sites without a trailing closure.
2. `CaptureCoordinator.handleScreenshotData`: switch *expression* assigning
   `capturedKind` with `case .window(let window):` and `default:`.
3. `MirrorTileKeepOut`: `@MainActor @Observable` singleton written from a
   `ViewModifier`'s `GeometryReader` callbacks; `session.sender`
   (`TrackpadSender?`, an actor) passed as `AnyObject?`.
4. `AnnotationCanvas`: `Canvas` renderer calling an instance method with
   `inout GraphicsContext`; `context.clip(to: Path(fitted))`.
5. `TextReader.read`: `Task.detached` returning `TextReadState` (implicit
   `Sendable`) and capturing a `CGImage` under Swift 6 (same as the old code).
6. `ScreenshotPreviewView`: `@State` holding an optional tuple
   `(message: String, failed: Bool)?`; `.task(id: step)` with Core's
   `CaptureStep`; `let` inside a `@ViewBuilder` switch case.
7. `MirrorThumbnailView`: `DragGesture(coordinateSpace: .global)`;
   `.animation(_:value:)` on `[CGRect]` and `CGRect?`.
8. `AnnotationRenderer`: `Path.cgPath` into `UIBezierPath(cgPath:)`.
9. `AnnotationToolbar`: `.scrollBounceBehavior(.basedOnSize, axes: .horizontal)`.

## Out-of-lane edits

- `DeckHandiOS/Surfaces/PointerSurface.swift` (merged Pointer work), four
  modifier lines, announced in the brief: `.mirrorTileKeepOut(.pad / .clickStrip
  / .caption / .keyboard, owner: sender)` on the pad, the strip, the caption
  pill and the keyboard button.

Everything else is in this lane's list: `MirrorThumbnailView.swift`,
`Mirror/MirrorOverlay.swift`, new `Mirror/MirrorTileKeepOut.swift`, Core
`Mirror/MirrorTilePlacement.swift`, the capture views and coordinator,
`CaptureCapsule.swift`, new `DeckHandiOS/Capture/CaptureChrome.swift`, new
Core `Capture/` and their tests. No edits to `Shell/**`, `DesignSystem/**`,
Settings, onboarding or the shared hot spots.

## Follow-ups for other lanes

- **Shell**: the header's capture menu could show the dot wave while
  `isCaptureBusy` (as `CaptureCapsule` now does). The tile overlay in
  `PixelHandShell` needs no change: placement is self-contained.
- **Copy pass (UX-014)**: capture strings are in Core `CaptureSheetChrome`
  and the views; "Mac Is Locked" alert copy is there too.

Lane: READY TO MERGE
