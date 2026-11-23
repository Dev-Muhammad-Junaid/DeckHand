# Lane: UX Screen (UX-006, UX-016; UX-009 deferred)

Branch `claude/pixelhand-lane-ux-screen`, merged with
`origin/claude/pixelhand-integration` at `f8eb74b` (includes UX Pointer). No protocol change, no
`project.yml` or Info.plist change. New files are picked up by folder.

## What changed

### Core: `Mirror/MirrorPaneChrome.swift` (+ `MirrorPaneChromeTests`, 15 tests)

Pure logic for every string and shape the mirror chrome draws, tested on
Linux (581 Core tests pass):

- `paneStrip` → `STUDIO · D1/2 · DESK 2/3 · 60 FPS` (drop order, so the
  Mac name always stays; `WINDOW` for a window mirror) plus a spoken label.
- `tileStrip` → `LIVE · D1 · 60`; `statsStrip` → S6 as
  `60 FPS · 7 MS · HEVC 1920 · 18 MB/S · 2 DROP · WIRED`.
- `displayCounter` → `1/2` (`WIN` for a window, nil with one display;
  an unconfirmed display counts as the main one).
- `cursorBadge` → `ON 2` + arrow toward that display from the Mac's
  arrangement (`DisplayLayout` bounds; right when unknown).
- `arrangement` → displays to scale in the Mac's arrangement, fitted in a
  box with a gap, with each display's desktop count, current desktop and
  full-screen indexes; a row when the layout is missing.
- `LinkBadgeKind.header/card(for: LinkKind)`; `dotMatrixSafe(name)` keeps
  Mac names to the 5 × 7 font's characters (12 max).

### UX-006 Screen surface (`Surfaces/ScreenSurface.swift`, `Mirror/MirrorPane.swift`)

- `ScreenSurface` no longer hosts `MirrorOverlay`. With the mirror on it
  shows the docked **`MirrorPane`** across the top and the trackpad
  (`TrackpadView`, hosted unchanged) under it. Pane height = picture at
  full width, capped at 62 % of the canvas; if that leaves < 200 pt for the
  trackpad (iPhone landscape rail, short windows) the pane takes the whole
  canvas. Mirror off: the same navy empty state with "Show screen".
- `MirrorPane`: black picture well (radius 24, hairline), status strip
  top-leading (pitch 1.6, 1.8 at ≥ 600 pt), cursor badge top-trailing,
  stats strip under it when Settings › stats is on, notices (window ended,
  pointer outside the window) above a **glass toolbar**: display button
  (Displays glyph + `1/2`, lit while Follow cursor is on), ‹ desktop dots ›,
  sound on/off (S17, writes `mirrorPlaysMacAudio`), stop. All toolbar items
  44 pt. ‹ › dim, never vanish, at the ends and with one desktop.
- Scanline (360 ms, phosphor line + cyan afterglow) on first frame, display,
  window or desktop change; none under Reduce Motion.
- Kept from the tile: JPEG/HEVC picture (`MirrorVideoLayerView`, watchdog
  untouched in the model), pointer sprite (`MirrorCursorLayer`), Follow
  cursor, window mirror, HEVC/audio settings applied live (`onChange` moved
  into the pane too), stream width from the pane width in the tile's tiers
  (`MirrorThumbnailView.streamWidth`).
- `Mirror/MirrorDisplayPickerSheet.swift` ("Show which display?"): displays
  drawn to scale (navy tiles, dot grid, dot-matrix number, phosphor pointer
  glyph on the cursor's display, accent ring on the mirrored one), a row per
  display with "Display 1 · 3 desktops" and its `DesktopDots`, Follow the
  cursor toggle, and "A window…" (dismisses, then opens the window picker
  after 450 ms so the two sheets don't collide). Medium/large detents.
- Mirror errors now titled **"Live Screen Unavailable"**
  (`ControlCaptureSheets.swift`).

### UX-016 Status strip, badges, dots on the floating tile (`MirrorOverlay.swift`, `MirrorThumbnailView.swift`)

- The tile's picker button is now the micro `StatusStrip` (`LIVE · D1 · 60`,
  pitch 1.4); the same menu (displays, Window…, Follow Cursor) opens from it.
- Desktop dots under the tile → `DesktopDots` on a navy 20 pt plate
  (full-screen desktops hollow, no text labels).
- Cursor badge → pixel `MirrorCursorBadgeView` (tap shows that display);
  stats → `StatusStrip` at pitch 1.3; notices → `MirrorNoticeLabel`.
- Close and ‹ › → pixel glyphs on navy circles with 44 pt targets; the
  loading spinner → `DotWave`.
- **Tile anchored clear of the Pointer foot** (UX-Pointer follow-up):
  `MirrorThumbnailView` reserves a 120 pt band across the whole width at the
  bottom (52 pt click strip + 12 + 24 pt caption + 8 clear + 24 for the
  desktop dots plate under the tile). The tile's home is
  just above it; drag can't take it lower (anywhere left or right, so it
  can't slide over the bottom-leading caption); pinch tops out at the height
  above the band. Saved layouts from older builds are clamped on render.
- Shared parts live in `Mirror/MirrorPixelChrome.swift`
  (`MirrorCursorBadgeView`, `MirrorToolButton`, `MirrorSpaceControls`,
  `MirrorNoticeLabel`, `.mirrorScanline(on:)`, `MirrorPicture`).
- Link badge in the header was already wired by the design foundation
  (`ShellHeader`); the stats strip adds the link (`WIRED`, `VPN`, `WI-FI`,
  `DIRECT`) from `RemoteLinkStatus.shared.current`.

## Checks on the Mac build (board: "Key screens", "New features")

Light and dark each; then AX3. A Mac with two displays and 3 desktops on
the main one (one a full-screen app) makes every element appear.

**iPhone 17 Pro (402 × 874), portrait**
1. Screen tab → "Show screen": the pane appears top with the scanline
   sweeping the first frame in; trackpad below it, usable (move, click,
   scroll). Compare with board "Mirror with display and desktop chrome".
2. Strip top-left reads `<MAC> · D1/2 · DESK 2/3 · 60 FPS`; VoiceOver reads
   "Studio, display 1 of 2, desktop 2 of 3, 60 frames per second".
3. Move the Mac pointer to display 2: `ON 2 →` badge top-right; tap it →
   picture switches (scanline), badge goes.
4. Toolbar: `1/2` opens the picker sheet; displays drawn as arranged on the
   Mac, pointer glyph on the right one, desktop dots per row; tap the other
   display → switches and dismisses. Follow the cursor on → display button
   lit, badge never shows. "A window…" → sheet closes, window picker opens,
   pick a window → strip says `WINDOW`, toolbar drops ‹ ›, counter `WIN`.
5. ‹ › switch desktops (dots move, scanline); at the last desktop › is dim;
   on a one-desktop display both are dim.
6. Sound button: lit with Sound on; Mac audio starts/stops at once.
7. Stop (×) ends the mirror; empty state returns.
8. Settings › Show stream stats on: a second strip under the first with fps,
   ms, codec, Mb/s, drops and the link.
9. Pointer tab with the mirror on: the floating tile as before (drag, pinch,
   tap to shrink, ‹ ›, close), now with the micro strip top-left (tap → the
   display menu), pixel close/chevrons, dots plate under it.
10. Pointer tab, tile on: drag it to the bottom-left and bottom-right
    corners and pinch it to its largest: it never covers the Click |
    Right-click strip or the `2 FINGERS · SCROLL` caption. The desktop dots
    plate under the tile stays above the caption too.

**iPhone SE (375 × 667)**: pane + trackpad both fit (trackpad ≥ 200 pt);
toolbar fits on one line; strip drops `60 FPS`, then `DESK`, never mid-word.

**iPhone landscape (874 × 402)**: rail layout; pane fills the canvas, no
trackpad; toolbar centred at the bottom.

**iPad 11″ portrait (820 × 1180)** and **landscape (1180 × 820, deck
column)**: pane across the top at full picture height (≤ 62 %), trackpad
under it; strip at pitch 1.8, stats at pitch 2.

**Regression (must not change)**
- HEVC: Settings › HEVC on → pane shows the video layer; toggle off/on while
  on the Screen tab → stream switches in place. Pull the network briefly →
  the watchdog's key-frame request recovers the picture (no frozen pane).
- Window mirror (S14): close the mirrored window on the Mac → notice "…"
  in the pane, picture returns to its display.
- Audio (S17): sound plays with the pane and with the tile, stops with
  either's stop/close, and follows the Settings toggle.
- Switching Pointer ↔ Screen with the mirror on keeps one stream (no
  restart other than a width renegotiation when the size tier changes).

## Compile risks (most likely first)

SwiftUI files can't be type-checked on Linux; all pass `swiftc -parse`, the
Linux type check (`run.sh`) passes, and the Core part is tested.

1. `MirrorOverlay.swift`: `let micro = …` inside the `Menu { } label: { }`
   builder; if it complains, move it into a computed property.
2. `MirrorPixelChrome.swift`: `MirrorScanline` generic `ViewModifier` with
   `onChange(of: trigger)` (iOS 17 zero-argument closure); `GeometryReader`
   inside `.mask`/`.overlay`.
3. `MirrorPane.swift`: `.onChange(of: proxy.size.width) { _, width in }`
   inside `GeometryReader`; `.phGlass(in: Capsule(), interactive: true)`
   followed by `.phGlassGroup()`; `.animation(…, value: cursorBadge)`
   (optional `Equatable`).
4. `MirrorDisplayPickerSheet.swift`: `ForEach(arranged)` with `let`
   bindings in the builder; `.offset(x:y:)` with `CGFloat`/`Double`
   arithmetic (`display.x` is `Double` × `CGFloat` scale — add `CGFloat(…)`
   if the compiler doesn't promote).
5. `MirrorThumbnailView.swift`: `spaceChevron`'s `symbol:` parameter is now
   unused (warning only).

## Out-of-lane edits

None. All edits are in Mirror-lane files: `Surfaces/ScreenSurface.swift`,
`Mirror/**`, `MirrorThumbnailView.swift`, `Control/ControlCaptureSheets.swift`
(one string), and new Core files `Mirror/MirrorPaneChrome.swift` +
its test. `TrackpadView`, `StatusStrip`, `DesktopDots`, `LinkBadge`,
`PHGlass`, `DotWave` and `ControlSessionModel` are used, not edited.

## Follow-ups

| Item | Owner | Notes |
| --- | --- | --- |
| **UX-009 Capture sheet** | UX Screen (next run) | Not started: one sheet with detents preview → annotate → read text → share; tools fit 320 pt; swipe to dismiss; Clear asks; region reset always enabled. Files: `ScreenshotPreviewView`, `AnnotationView`, `OCRResultView`, `RegionCropView`, `WindowPickerView`, `ControlCaptureSheets`, `CaptureCapsule` (~1,700 lines). |
| Follow-cursor zoom + minimap on compact | Mirror | Board "Screen: zoom follows the cursor"; pane is ready for it (picture is one view). |
| Direct / Trackpad toggle | Mirror + iOS interaction | Needs absolute pointer moves (protocol change). |
| PiP button in the toolbar | Mirror | No PiP yet (`03-Layout-Strategy.md` §PiP). |
| Display picker live thumbnails | Mirror | Tiles show number + pointer only; live thumbnails need per-display frames. |
| Sound toggle Pro badge on the free tier | Store + Design | Mirror is Pro already, so the toolbar only shows for Pro/trial. |
| `LinkBadge` in Mac cards | Design (UX-030) | Use `LinkBadgeKind.card(for:)`. |

Lane: READY TO MERGE
