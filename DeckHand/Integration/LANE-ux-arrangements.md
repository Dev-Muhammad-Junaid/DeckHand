# Lane: UX arrangements (UX-007)

Branch `claude/pixelhand-lane-ux-arrangements`, from
`origin/claude/pixelhand-integration` at `8e2ba59` (no newer integration
commits at handoff). No protocol change (still version 12), no
`project.yml` or Info.plist change; new files are picked up by folder.

## What changed

### Core (`Core/Sources/PixelHandCore/Design/`)

- **`CanvasPlan`** turns `LayoutMetrics.arrangement` into one of five
  forms, with column widths and which chrome shows:

  | Form | When | Layout |
  | --- | --- | --- |
  | `single` | compact (< 500) | unchanged: one surface, strip, dock, tab bar |
  | `rail` | short, not compact | 62 pt tab rail · pad · **deck column** (264–320 pt, 40 %) with header, status pills and the strip on top; dock folded into the strip's app chip. The column only shows while the pad keeps ≥ 300 pt; otherwise the Deck tab stays and the strip sits under the pad (iPhone SE landscape). |
  | `stacked` | medium, < 700 wide (½ Split View, Duo laptop) | header · selected surface over a **deck panel** (one row of keys by default, drag handle, never squeezes the pad under 240) · strip · dock · tab bar. Deck tab = full deck. |
  | `sideBySide` | medium, ≥ 700 wide (iPad portrait) | header with **presets** · Split: screen over (pad \| 300 pt deck column), drag handle; Screen: the screen alone; Pointer: pad (floating tile) \| deck · strip · dock + Ask circle. No tab bar. |
  | `columns` | wide and tall (iPad landscape, large Stage Manager) | **Macs sidebar** 232 · centre (Mac pill, presets, Ask field ⌘K, capture, More; the preset's panes; **floating dock** ≤ 520 pt at the foot, 88 pt reserved) · 336 pt deck column with the strip on top (a raised dialog card while a dialog is up). Sidebar collapses (header button brings it back) and is unavailable when the centre would drop under 480 pt (< 1104 wide). |

- **`PaneSplit`**: screen-over-pad heights (picture height at full width,
  capped at 62 %, or the person's drag; min 200 screen / 240 pad; `nil`
  when both can't fit, so the pad shows alone with the floating tile).
- **`DeckPanelSplit`**: the stacked deck panel's height.
- **`LayoutPreset`** (Split, Screen, Pointer) and **`LayoutPresetMemory`**
  (JSON for `@AppStorage`, keyed `"<Mac>|<form>"`, capped at 32 entries):
  presets are remembered per Mac and per size class.
- **`PixelGlyphs.layoutSplit`** and **`PixelGlyphs.sidebar`**, 9 × 9, kept
  outside `PixelGlyphs.all` (still the spec's 40).
- Tests: `CanvasPlanTests.swift` (10 tests). **613 Core tests pass**;
  `Scripts/linux-typecheck/run.sh` builds.

### iOS (`DeckHandiOS/Shell/`)

- **`PixelHandShell`** rewritten around `CanvasPlan` (one function per
  form). Scene storage for the screen/pad split, the deck panel height and
  the sidebar; app storage for presets. The floating screen tile is laid
  over **the pad alone** (`floatingScreenTile`), so `MirrorThumbnailView`'s
  120 pt band lines up with the pad's click strip and caption in every form.
- **`LayoutPresetPicker`**: glass capsule, 44 pt, three glyph segments
  (Split / Screen / Pointer), selection haptic, Large Content Viewer,
  VoiceOver "Split: screen over trackpad", "Screen focus", "Pointer focus".
- **`PaneDragHandle`**: 36 × 4 capsule in the 12 pt gap (lights accent
  while dragged), 44 pt tall hit area, VoiceOver adjustable in 10 % steps.
- **`MacsSidebar`**: "Macs" (Geist), sidebar glyph button to collapse, the
  connected Mac's card (ring, live pixel) and other paired Macs from
  `PairedMacsStore` (dimmed; tap opens My Macs, which explains 1.3).
  `MacCardPlaceholder` is now internal and shared with the My Macs sheet.
- **`AskField`** (wide header, ⌘K) and **`AskCircleButton`** (next to the
  dock on iPad portrait; in the wide header when the field doesn't fit).
- **`ShellHeader`**: optional `presets`, `onAsk`, `onShowSidebar`,
  `showsMirrorToggle`, `horizontalPadding`. The iPhone default is unchanged.
- **`ControlSurface`**: `centre(hasDeckColumn:)`, `tabs(includeDeck:)`.

## Checks on the Mac build (against the board)

Light **and** dark for each. Board: https://claude.ai/artifact/Aa8KTJubKeqahy3cmSjRTm
("Small & landscape", "iPad", "Duo & iPad").

**iPhone 17 Pro portrait (402 × 874)** and **iPhone SE (375 × 667)**:
1. Nothing changed from build 11: header, pad, strip, dock (SE: folded),
   tab bar. Pointer → Screen → Deck still switch.

**iPhone landscape (874 × 402)**, board "iPhone landscape":
1. Leading glass rail: Pointer, Screen, Ask (no Deck tab). The pad fills
   the middle at full height (≥ 300 pt, no header above it); click strip
   and caption at its foot; its own keyboard circle top-leading.
2. Trailing deck column (≈ 264 pt): Mac pill + capture + More (no screen
   button), then the strip with the app chip first (menu lists running
   apps), then the deck at 3 a row. Save dialog on the Mac → the strip
   shows its buttons in the column.
3. Screen tab: the docked screen replaces the pad; the deck column stays.
4. Show the screen from the Screen tab, go back to Pointer: the floating
   tile sits over the pad only, never over the click strip or caption.
5. Rotate the other way: the rail stays leading and clear of the Dynamic
   Island (safe area). **iPhone SE landscape**: no deck column; rail has
   Deck; strip (with app chip) under the pad.

**iPad 11″ portrait (820 × 1180)**, board "iPad portrait":
1. Header: Mac pill, then (trailing) the presets capsule, screen button,
   capture, More. No tab bar; at the foot the strip, then the dock with
   the Ask circle beside it.
2. **Split**: the screen across the top ("Show screen" empty state until
   it starts), a handle, then the pad and a 300 pt deck column side by
   side. Drag the handle: the screen grows/shrinks, the pad never drops
   under ~240 pt (click strip stays). Relaunch: the split is kept.
3. **Screen**: the screen fills the canvas. **Pointer**: pad + deck
   column; a running screen floats over the pad.
4. Pick Screen, disconnect, reconnect the same Mac: still Screen. Another
   Mac starts on Split.
5. Dock keyboard button opens the keyboard panel above the strip.

**iPad 11″ landscape (1180 × 820)**, board "iPad landscape" (round 2):
1. Macs sidebar 232 pt: "Macs", collapse button, connected Mac card
   (cobalt ring, mint pixel), other paired Macs dimmed (tap → My Macs).
2. Centre header: Mac pill, presets, "Tell <Mac>… ⌘K" field, capture,
   More. Field (or ⌘K on a hardware keyboard) opens Ask.
3. **Split**: screen ≈ 347 pt over the pad ≈ 265 pt (click strip shown),
   handle between; the dock floats centred under the pad (≤ 520 pt) with
   no tab bar. **Screen**: screen down to the dock. **Pointer**: pad down
   to the dock, tile floating over it.
4. Deck column 336 pt: chips row on top; Save dialog on the Mac → a raised
   card with the dialog's title and buttons; deck 3 a row below.
5. Collapse the sidebar: centre widens; a sidebar button appears in the
   header; tap it to bring the sidebar back. Rotation keeps the choice.
6. Dock keyboard button opens the keyboard panel above the floating dock.

**½ Split View (≈ 590 × 820)**, board "Half Split View":
1. Header, the selected surface, a handle, a deck panel one row of keys
   tall (5 a row), strip, dock, tab bar with Pointer / Screen / Deck.
2. Drag the handle up: the panel grows, the pad stops at ~240 pt. Deck tab:
   the deck fills the canvas (no panel).
3. Screen tab: the screen surface over the panel.

**⅓ Split View / Slide Over (320–499 wide)**: the iPhone portrait layout
(`single`), dock folded below 700 pt tall.

**Stage Manager**: resize a window through every size: < 500 wide →
iPhone layout; 500–699 → stacked; 700–899 → side by side with presets;
≥ 900 → columns; short windows (< 500 tall, ≥ 500 wide) → rail. The
sidebar appears from 1104 pt wide. Small windows where both panes can't fit
the Split preset show the pad with the floating tile instead of cramming.

**Dynamic Type AX1/AX3**: tab rail drops labels (as before); presets keep
glyphs with Large Content Viewer; the wide header falls back to the Ask
circle when the field doesn't fit.

## Compile risks (most likely first)

SwiftUI can't be type-checked on Linux. Every changed file passes
`swiftc -parse`; Core is tested; the Linux type check builds.

1. `PixelHandShell.screenOverPane`: generic `@ViewBuilder` method with a
   `@ViewBuilder lower: () -> Lower` parameter, `let`s and an `if let …
   else` that calls `lower()` in both branches; called with a trailing
   closure inside `GeometryReader`. If the builder complains, wrap the
   branches in `Group`.
2. `PixelHandShell.stackedCanvas`: `GeometryReader` closure with `let`s
   then `if let sender = …, let panel = DeckPanelSplit.height(…)`.
3. `ShellHeader`: `ViewThatFits(in: .horizontal)` with `AskField` and an
   `HStack`; nested `if let onAsk { if let presets {…} … } else {…}`.
   New memberwise-init parameters after `onDisconnect` (all defaulted).
4. `ScreenSurface`: `let layout = includesTrackpad ? Self.split(…) :
   (pane: proxy.size.height, showsTrackpad: false)` (tuple label match).
5. `StreamDeckGridView`: new `columnCount` / `horizontalInset` vars after
   `showsQuickActions` (memberwise order); `columns` is now computed.
6. `LayoutPresetPicker`: `ForEach(LayoutPreset.allCases, id: \.self)`;
   `.help(_:)`; `matchedGeometryEffect`. `PaneDragHandle`:
   `.accessibilityAdjustableAction` with `@unknown default`.
7. `MacsSidebar`: `.scrollBounceBehavior(.basedOnSize)` (iOS 16.4+);
   reading `PairedMacsStore.shared.macs` (Observation).

## Out-of-lane edits

- `DeckHandiOS/Surfaces/ScreenSurface.swift` (UX Screen): new
  `var includesTrackpad = true`; when false the pane takes the whole
  height. Default behaviour unchanged; the shell passes `false` for the
  iPad presets, which draw their own pad.
- `DeckHandiOS/StreamDeckGridView.swift`: new `var columnCount = 4` and
  `var horizontalInset: CGFloat = 20` (the 3 `.padding(.horizontal, 20)`
  now read it). Classic layout unchanged.

Everything else is in this lane: `Shell/**` (new `LayoutPresetPicker`,
`MacsSidebar`), Core `Design/**` (`CanvasPlan.swift`,
`PixelGlyphs+Layout.swift`) and one test file. `ControlView.swift` and
`ContentRootView.swift` needed no change. No `DesignSystem/**` file was
edited.

## Follow-ups

| Ticket | Owner | Notes |
| --- | --- | --- |
| **External display** | Design + Mirror | Spec: Screen goes to the external display, the iPad shows Pointer + Deck. Needs a scene delegate for `UIWindowSceneSessionRoleExternalDisplayNonInteractive` (app delegate adaptor in `DeckHandApp.swift` or a scene manifest in Info.plist, both outside this lane) and a shared handle to the session's mirror. `CanvasPlan` can take an `externalScreen` flag that forces the Pointer preset once that lands. Not started. |
| Deck 2 grid in columns | Deck 2 (UX-020) | The deck column/panel still hosts the app grid (`StreamDeckGridView`) at 3 (or 5–6) a row; the board's key deck with title, Edit and page dots comes with UX-020. |
| Rail keyboard in the rail | Design | Board puts the keyboard button in the rail; today the pad's own corner circle stays in landscape (dock folded). Move it when the rail gets a keyboard slot. |
| Sidebar extras | Design (UX-030/031) | Live thumbnails, link badges, alerts per Mac, "Send to" drop target, switching Macs from the sidebar. |
| Duo panes | Design (UX-040) | Book pose two-pane layout with the crease; today Duo open is `columns` (951 wide) and laptop is `stacked`. |
| Mirror toggle on wide | Design | The wide header drops the screen button (room for Ask); the screen starts from the Split/Screen preset's "Show screen". Revisit if people miss it. |

Lane: READY TO MERGE
