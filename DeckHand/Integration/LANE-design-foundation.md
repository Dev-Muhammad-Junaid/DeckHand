# Lane: Design foundation (UX-001, UX-015, UX-002, UX-003)

Branch `claude/pixelhand-lane-design-foundation`, merged with
`origin/claude/pixelhand-integration` at `f1af21b`. No protocol change, no
`project.yml` or Info.plist change.

## What changed

### UX-015 Glyphs, dot-matrix font, palette and layout maths (Core)

New `Core/Sources/PixelHandCore/Design/`:

- `GlyphBitmap.swift`: a 9 × 9 glyph as data (rows, accent dot, solid flag),
  the stroke-rule check, and `DotGeometry` (the one dot: 78 % of the pitch with
  a 30 % radius for glyphs, 80 % with 32 % for type).
- `PixelGlyphs.swift`: the 40 glyphs, generated cell for cell from
  `Product/Design/board/pixel.js` (`G`), with the board's labels.
- `DotMatrixFont.swift` + `DotMatrixFont+Table.swift`: the 5 × 7 font from the
  board (`F`), 46 characters, lowercase uppercased, unknown characters drawn as
  spaces, lit and unlit cell layout.
- `PixelPitch.swift`: allowed pitches, `TypeBand` (standard / large AX1–2 /
  huge AX3–5) and the one-step pitch increase at AX1+.
- `PaletteTokens.swift`: every brand and semantic colour as numbers (light,
  dark, Increase Contrast), plus WCAG luminance and contrast.
- `LayoutMetrics.swift`: width and height classes, the arrangement (single,
  rail, split, columns), grid columns, margins, gutters, deck columns and
  `DeckGrid` (whole-point keys, remainder in the margins, odd point trailing).

Tests: `PixelDesignTests.swift` and `LayoutMetricsTests.swift`; 527 Core tests
pass on Linux (`swift test --package-path DeckHand/Core`). They cover the
polish spec's key sizes (402 → 83 with 17/17 margins, 375 → 76 with 17/18),
466/820/1180, every width from 320 to 1366, the QA sizes' arrangements, and
the contrast pairs from `02-Design-System.md` §1.2.

**For the design review:** two board glyphs break stroke rule 1 (no 2 × 2
block): `desktop` (Show Desktop, two-dot side edges) and `laptop` (Mac,
screen bottom on the base). They're ported as drawn and listed as named
exceptions in the test, which fails if any other glyph breaks the rule or if
either one is redrawn. The accent dot doesn't count toward a block, so `deck`'s
lit key and `capture`'s shutter pass.

### UX-001 Tokens (`Shared/PixelHandTheme.swift`)

- `PixelHandTheme.Brand` and every semantic colour (`canvas`, `raised`,
  `elevated`, `ink`/`ink2`/`ink3`, `hairline`, `fill`/`fill2`, `accent*`,
  `success*`, `warning*`, `danger*`, `scrim`) built from Core's
  `PaletteTokens`, so the numbers live in one place and are tested on Linux.
  They follow light/dark and Increase Contrast (hairline 20 %, ink2 80 %) on
  iOS and macOS. `ShapeStyle` shortcuts: `.phCanvas`, `.phInk2`, ….
- Type roles (`TextRole`, `Font.phDisplay`, `.phChip`, `.phChord`, …): Geist
  Medium/SemiBold for display, SF Pro and SF Mono for the rest, every role
  scaling with Dynamic Type. Geist is bundled in
  `DeckHandiOS/DesignSystem/Fonts/` with its SIL OFL licence and registered at
  first use with CoreText, so **no `UIAppFonts` entry is needed**; without the
  files (Mac, tests) it falls back to the system font.
- Space (4 · 8 · 12 · 16 · 24 · 32 · 48), radius (8 · 14 · 18 · 24 · 30 ·
  36), control heights (20 · 24 · 36 · 44 · 52 · 56), strokes.
- `PixelHandMotion` in `Shared/DeckHandMotion.swift`: quick, standard, spring,
  hero, the 160 ms Reduce Motion fade, and the transition timings (dissolve,
  scanline, power-on, delivery, wave, press flash, breathe).
- `DeckHandTheme` is now a forwarding shim (removed in UX-014). **Visible
  effect app-wide:** the dark canvas is navy (`#070A1C`), the light canvas
  `#F3F4F9`, cards are `raised` with hairlines, unlit dots use the new
  `dotOff`, `DeckHandTheme.TypeStyle` fonts follow Dynamic Type at the same
  default sizes, and old radii map onto the scale (20 → 18, 28 → 30).

Deviation from the plan: colours live in code (from the Core table), not in
asset-catalog colour sets. That keeps one source that the Linux tests read and
still gives Increase Contrast variants; a widget target can compile
`PixelHandTheme.swift` the same way the Mac does.

### UX-002 Components (`DeckHandiOS/DesignSystem/`)

`PHGlyph` and `DotMatrixText` (`Canvas`, drawn at the pitch, never scaled;
`PageCounter`), `PixelSurface` (navy, radial lift, 15 pt resting grid),
`phGlass` / `phGlassGroup` (Liquid Glass on iOS 26 behind `#available`,
material before, solid under Reduce Transparency), `PHButtonStyle` (`.ph()`:
primary, secondary, tint, destructive; 52/44/36) and `GlassCircleButton`,
`ContextChip`, `DeckKey` and `DeckKeyRow` (AX3+), `DeliveryStrip` (3/4 dots
with a check or cross so receipts read without colour; `DeliveryDots`'
timing), `StatusStrip` (drops trailing items to fit), `StatusPixel`,
`LinkBadge`, `DesktopDots`, `StatusPill`, `PHToast`, `DotBeam`, `DotWave`,
`ProBadge`, `PHEmptyState`, `MacPill`, `.phCard()`, `.phosphorFocus()`. Every
file has `#Preview`s. Nothing here replaces an existing view yet;
`DeliveryDots`, `DeckHandEmptyState` and `HostCapabilityBanner` are untouched
and get swapped by the lanes that restyle their screens.

### UX-003 Shell (`DeckHandiOS/Shell/`, `DeckHandiOS/Surfaces/`)

- `PixelHandShell`: header, status pills, canvas, tab bar. The canvas reads
  `LayoutMetrics` from its own size (no idiom checks): **single** (compact),
  **rail** (short and not compact: the tabs become a vertical glass rail on
  the leading edge), **split** (medium and tall: one surface for now; panes are
  UX-007), **columns** (wide and tall: centre surface plus the 336 pt deck
  column, so the Deck tab goes and its selection is kept).
- `SurfaceTabBar`: Pointer / Screen / Deck with glyphs at pitch 2.6, a 4 pt lit
  dot under the selection, and the Ask circle. Labels drop at AX1+ with the
  Large Content Viewer on long-press. **Deviation:** drawn by hand instead of
  `TabView` + `Tab(role: .search)`, so tabs carry pixel glyphs and it runs on
  iOS 17.4 (`Tab` is iOS 18). It's still glass on iOS 26.
- The selected surface is `@SceneStorage`, so it survives rotation, Split
  View, Stage Manager resizing and scene restoration.
- `ShellHeader`: Mac pill (live pixel, name, front app or approval state;
  lock glyph when the Mac is locked), link badge (cable and VPN only), glass
  circles for the floating screen, capture (tap = default capture, hold =
  menu) and More (Settings, Use the classic layout, Disconnect). The session
  id isn't shown.
- Status pills replace the old banners in the shell (Accessibility, locked
  Mac, Screen Recording).
- Surfaces are hosted as they are: Pointer = `TrackpadView`, Deck =
  `StreamDeckGridView`, Screen = `ScreenSurface` (a navy pane holding
  `MirrorOverlay`, or an empty state with "Show screen"). On Pointer and Deck
  the floating mirror tile behaves as before.
- Ask opens `AskPlaceholderSheet` until UX-022.
- **Flag:** `ControlView` shows the shell by default
  (`@AppStorage("pixelhand.usesPixelHandShell")`). More → "Use the classic
  layout" switches back; the classic toolbar has a leading "Use the new
  layout" button. Both share one session, so switching doesn't reconnect.

### UX-008 (partly)

Done inside the shell: Mac pill, link badge, glass header buttons, Disconnect
in More, session id removed, `StatusPill`s. Left: pill tap → My Macs and the
swipe placeholder, retiring `HostCapabilityBanner` (still used by the classic
layout).

## Checks on the Mac build (against the board, sections "Key screens" and "Components")

Light and dark for each; then Settings → Accessibility → Larger Text at AX3.

**iPhone 17 Pro (402 × 874), portrait**
1. Connect to a Mac. The shell appears: header 56 pt with the Mac pill
   (navy tile, breathing mint pixel, name, front app), then the trackpad, then
   the glass tab bar with Ask on the right. Compare with board "Pointer".
2. Tap Screen: the navy pane with the dot grid and "See <Mac>'s screen";
   "Show screen" starts the mirror inside the pane. Tap Deck: today's deck.
3. With the mirror on, go back to Pointer: the floating tile is where it was.
4. Header: floating-screen circle lights cobalt while on; capture tap takes
   the default capture, touch-and-hold shows Full screen / Region / Window /
   Read text; More → Settings, Use the classic layout, Disconnect.
5. More → Use the classic layout: the old screen, same session, no
   reconnect. Its leading grid button returns to the shell.
6. Dark: canvas navy `#070A1C`, selected tab's dot glows cyan; light: canvas
   `#F3F4F9`, dot cobalt.
7. AX3: tab labels drop, long-press a tab shows the Large Content Viewer; the
   pill drops its second line; nothing clips in the header.
8. Lock the Mac: the pill's tile shows the lock glyph and a "locked" status
   pill appears. Revoke Accessibility on the Mac: the Accessibility pill shows.

**iPhone SE (375 × 667)**: header fits (pill truncates in the middle), tab bar
fits with labels.

**iPhone landscape (874 × 402)**: tabs move to a vertical rail on the leading
edge; Ask under them; the trackpad takes the rest. Rotate back: the selected
tab is kept.

**iPad 11″ portrait (820 × 1180)** and **½ Split View (590 × 820)**: one
surface, bottom tab bar, 20 pt margins.

**iPad landscape (1180 × 820)**: tabs are Pointer and Screen; the deck sits in
a 336 pt column on the trailing side. Choose Deck in portrait, rotate to
landscape: the centre shows Pointer and the deck column is there; rotate back:
Deck is selected again. Resize a Stage Manager window from narrow to full and
back: no lost selection.

**Everywhere:** Reduce Transparency → solid header and tab bar; Increase
Contrast → stronger hairlines; Reduce Motion → cross-fades only. Settings,
onboarding and the picker should look as before except for the new canvas and
card colours (from the shim).

**Previews** (Xcode canvas): every file in `DesignSystem/` and
`SurfaceTabBar.swift`; check light, dark and AX5.

## Compile risks (most likely first)

The SwiftUI files can't be type-checked on Linux; all of them pass
`swiftc -parse`, and the Core part is tested.

1. `DesignSystem/PHGlass.swift`: the iOS 26 names under
   `#if compiler(>=6.2)` + `#available(iOS 26.0, *)` (`Glass`,
   `.tint(_:)`, `.interactive()`, `glassEffect(_:in:)`,
   `GlassEffectContainer(spacing:)`).
2. `DesignSystem/StatusStrip.swift`: `ViewThatFits` over a `ForEach`; the
   `switch pitch { case ..<1.35: … }` range patterns on `CGFloat`.
3. Double → CGFloat in ternaries passed to `pitch:` (`GlassCircleButton`,
   `PHGlyph(…, pitch: PixelPitch.badge)`); add `CGFloat(…)` if the compiler
   complains.
4. Switch and ternary expressions with implicit members returning `Color`
   (`DeliveryStrip.color(for:)`, `StatusPixel`, `LinkBadge`).
5. `SurfaceTabBar`: `.accessibilityShowsLargeContentViewer { Label … }`;
   `.accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)`.
6. `Shared/PixelHandTheme.swift` (both apps): `Color(token:)`'s
   `UIColor`/`NSColor` dynamic providers under Swift 6 concurrency (captures
   only a `Sendable` `ColorToken`); the AppKit appearance names
   `.accessibilityHighContrastAqua` / `…DarkAqua`; `CTFontManagerRegisterFontsForURL`.
7. `ControlToolbar`: `if let onNewLayout { ToolbarItem … }` inside the
   `ToolbarContent` builder.
8. Name clashes checked by grep (one found and fixed: `DotGrid` exists in
   `DotField.swift`, mine is `RestingDotGrid`). New Core public names:
   `RGBColor`, `Swatch`, `ColorToken`, `PaletteTokens`, `GlyphPoint`,
   `GlyphBitmap`, `PixelGlyphs`, `DotGeometry`, `DotMatrixFont`, `PixelPitch`,
   `TypeBand`, `LayoutMetrics`, `DeckGrid`.

`DeckHand/Scripts/linux-typecheck/run.sh` fails on integration as well as here,
only in the Store lane's `SubscriptionStore.swift` (`cannot find type
'StoreKit'` in `StoreKitStubs.swift`). Not touched by this lane.

## Out-of-lane edits

None. Every edited or new file is in the Design lane's list (`ControlView.swift`,
`Control/ControlToolbar.swift`, `Shared/DeckHandTheme.swift`,
`Shared/DeckHandMotion.swift`, `DeckHandiOS/DesignSystem/**`, `Shell/**`,
`Surfaces/**`, Core `Design/**`) or new (`Shared/PixelHandTheme.swift`, two new
Core test files). Other lanes' views are only hosted, not edited:
`TrackpadView`, `StreamDeckGridView`, `MirrorOverlay`, `RemoteLinkStatus`,
`requiresPro`, `LivePixel`. `ControlSessionModel` is read only.

The build 7 fix lane is running in parallel; if it touched `ControlView.swift`
or `ControlToolbar.swift`, expect a small conflict around `body` (this lane
moved the sheets and `.task` from the `NavigationStack` to an outer `Group`).

## project.yml / Info.plist

Nothing to apply. New files are picked up by folder, including the two Geist
`.ttf` files and `Geist-OFL.txt` as iOS resources; fonts are registered at
runtime, so `UIAppFonts` isn't needed.

## Follow-up lanes (owner per `05-Implementation-Plan.md`)

| Ticket | Owner lane | Notes |
| --- | --- | --- |
| UX-004 Pointer surface | iOS interaction | Host `MultiTouchTrackpad` in `PixelSurface`; remove the gesture bar; click strip; caption via `DotMatrixText`. |
| UX-005 Context strip + app dock | Design | `ContextChip`, `DeliveryStrip` ready; dock goes above `SurfaceTabBar` in `PixelHandShell`. |
| UX-006 Screen surface | Mirror | Replace `ScreenSurface`'s hosted `MirrorOverlay` with a docked `MirrorPane`; `StatusStrip`, `DesktopDots`, `LinkBadge` ready. |
| UX-007 Arrangements | Design | Split panes for `.split`, the rail's strip/dock, presets, external display. `LayoutMetrics.arrangement` is the switch. |
| UX-008 remainder | Design | Pill → My Macs, swipe placeholder, retire `HostCapabilityBanner`. |
| UX-009 Capture sheet | Mirror | |
| UX-010 Onboarding + picker | Design | `LayoutMetrics.usesTwoColumnPages`, `PHGlyph` pitch 10, `DotMatrixText` step counter. |
| UX-011 Paywall + free tier | Design + Store | `ProBadge`, `DotMatrixText("PRO", pitch: 5, showsUnlit: true)`. |
| UX-012 Mac panel | Design + Pairing | `PixelHandTheme` already compiles for the Mac. |
| UX-013 Accessibility pass | all iOS lanes | |
| UX-014 Copy pass + shim removal | Design | Remove `DeckHandTheme`; also decide the `desktop`/`laptop` glyph exceptions. |
| UX-016 Status strip wiring, display picker | Design + Mirror | Components exist; wire `LinkKind`, `DisplayLayout`, mirror stats. |
| UX-017 Transitions | Design | Timings already in `PixelHandMotion`; the shell switches surfaces with `.id(centre)` + `.transition(.opacity)`, the place for `pixelDissolve`. |
| UX-018 Loading/empty/focus | Design | `DotWave`, `PHEmptyState`, `.phosphorFocus` exist; replace spinners. |
| UX-019 Icon, launch, menu-bar hand | Design + Pairing | |
| UX-020 Deck 2 UI | Design | `DeckKey`, `DeckKeyRow`, `LayoutMetrics.deckGrid`, `PageCounter`. |

Lane: READY TO MERGE
