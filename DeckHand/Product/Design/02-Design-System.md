# 02 · Pixel Hand design system

> **Round 2 (19 Nov 2026):** the pixel language in `06-Pixel-Identity.md` and
> the strict scales in `07-Polish-Spec.md` extend this file. Where they differ
> (spacing scale without 20 between siblings, the concentric radius table,
> 9 × 9 glyphs instead of 8 × 8, 12 pt deck gutters), round 2 wins.

Derived from the website (`website/public/styles.css`, `ui.css`,
`website/brand/concept-b2-ipad.svg`) and today's `Shared/DeckHandTheme.swift`.
It replaces `DeckHandTheme`'s ad-hoc surfaces and fixed fonts with one token
set used by the iOS app, the Mac panel and the website. The board renders
every token live: https://claude.ai/artifact/Aa8KTJubKeqahy3cmSjRTm (source
`board/board.css`, section "2. App tokens").

Rule zero, from the UX guidelines: **each colour has one job.**

## 1. Colour

### 1.1 Brand (fixed; same in both themes)

| Token (`PixelHandTheme.Brand`) | Hex | Job | Website variable |
| --- | --- | --- | --- |
| `cobalt` | `#3A4CF2` | The action colour (light) | `--accent` |
| `cobaltHigh` | `#5466FF` | The action colour on dark; gradient tops | `--accent-hover` |
| `cobaltInk` | `#2A38C9` | Cobalt as text on tints | `--accent-ink` |
| `sky` | `#86B4FF` | Tile gradient top, links on navy | `--sky` |
| `screen` | `#060A2A` | Always-dark surfaces: trackpad, mirror frame, brand screens | `--app-ink` |
| `screenRaised` | `#0E1540` | Cards on `screen` | `--app-raised` |
| `screenHigh` | `#1C2C80` | Lit centre of the glass | – |
| `navBar` | `#11152F` | Solid chrome when Reduce Transparency is on | `--nav-surface` |
| `phosphor` | `#EFFFFC` | A lit dot | `--phosphor` |
| `glow` | `#3DE0E0` | Live activity right now (touches, sending, AI thinking). **On navy only.** | `--glow` |
| `ray` | `#9FF6FF` | Tap rays, stats text on navy | `--ray` |
| `mint` | `#3DE0B0` | Connected / delivered on dark | `--mint` |
| `pixelViolet` | `#8E70FF` | The hand's fill. Dot art only, never a control. | – |
| `dotOff` | `#5064D2` @ 22 % | An unlit dot (decorative, never carries meaning) | – |

### 1.2 Semantic (adapts to light / dark)

| Token | Light | Dark | Job |
| --- | --- | --- | --- |
| `canvas` | `#F3F4F9` | `#070A1C` | Behind everything (dark is navy-biased, not `#0A0A0F`) |
| `raised` | `#FFFFFF` | `#0E1330` | Keys, chips, cards, list rows |
| `elevated` | `#FFFFFF` | `#161C40` | Sheets, popovers, menus |
| `ink` | `#121522` | `#F4F6FF` | Primary text |
| `ink2` | ink @ 64 % | ink @ 64 % | Secondary text |
| `ink3` | ink @ 40 % | ink @ 38 % | Tertiary, chords, placeholders |
| `hairline` | ink @ 8 % | white @ 8 % | Strokes and dividers |
| `fill` / `fill2` | ink @ 6 % / 10 % | white @ 7 % / 12 % | Wells, idle buttons, unlit status dots |
| `accent` | `#3A4CF2` | `#5466FF` | Primary buttons, selection, default dialog chip, edit outlines |
| `accentInk` | `#2A38C9` | `#9FB0FF` | Accent text on `accentTint` |
| `accentTint` | `#E6EAFF` | cobaltHigh @ 20 % | Selected fills, AI suggestion panels |
| `success` | `#0B7A6C` | `#3DE0B0` | Connected, delivered, toggles on |
| `successTint` | `#DCF6F1` | mint @ 14 % | Success pills |
| `warning` | `#A35F00` | `#FFB547` | Needs a fix, pending, dialog waiting |
| `warningTint` | `#FFF1DB` | warning @ 14 % | Status pill background |
| `danger` | `#D92D3F` | `#FF4D5E` | Refused, failed, destructive |
| `dangerTint` | `#FDE7EA` | danger @ 16 % | Error banners |
| `scrim` | navy @ 28 % | black @ 45 % | Behind sheets |

**Contrast checks to keep in tests** (`DeckHandTests`): ink on canvas ≥ 4.5:1;
white on `accent` ≥ 4.5:1 light (6.0:1) and ≥ 4.4:1 dark; `success` text on
`canvas` ≥ 4.5:1 light; `glow` never used as text or on light surfaces.
Increase Contrast: hairline → 20 %, chips get a solid 1 pt border, `ink2` → 80 %.

### 1.3 SwiftUI mapping

```swift
enum PixelHandTheme {
    enum Brand { static let cobalt = Color(hex: "3A4CF2") /* … as §1.1 … */ }
    // Semantic colours live in the asset catalog as Color Sets with Any/Dark
    // and High Contrast variants, so Xcode previews, widgets and the Mac all
    // read the same values. Accessors:
    static let canvas    = Color("canvas")      // ShapeStyle extension too
    static let raised    = Color("raised")
    static let elevated  = Color("elevated")
    static let ink       = Color("ink")
    // …
}
extension ShapeStyle where Self == Color {
    static var phCanvas: Color { PixelHandTheme.canvas }   // .background(.phCanvas)
}
```

Move the colours from code (`Color(light:dark:)`) into the asset catalog so the
widget extension (1.2) and the Mac target share them and High Contrast variants
are possible. Keep `Brand` in code (fixed values, used in dot art).

## 2. Surfaces and materials (iOS 26+)

| Layer | Treatment | SwiftUI |
| --- | --- | --- |
| Canvas | `canvas` solid | `.background(.phCanvas)` |
| Screens (trackpad, mirror well, brand screens) | `screen` with the radial lift `#111A55 → #060A2A` and the 15 pt dot grid | `PixelSurface()` view; forced `.environment(\.colorScheme, .dark)` |
| Content (keys, chips, cards) | `raised`, 0.5 pt hairline, no shadow in dark, 1–2 pt shadow in light | `PHCard` style |
| **Chrome** (tab bar, app dock, header buttons, mirror toolbar, rail, Ask button) | **Liquid Glass** | System `TabView`, `.buttonStyle(.glass)`, `.glassEffect(.regular, in: .capsule)` inside one `GlassEffectContainer` per cluster |
| Primary chrome action | Tinted glass | `.buttonStyle(.glassProminent)` + `.tint(.accent)` |
| Sheets | System sheet (glass in 26), `elevated` content | `.presentationDetents`, `.presentationBackground(.phElevated)` only when content needs it |

Rules (from Apple's "Adopting Liquid Glass" and the product's own rules):

- Glass is for controls and navigation only. Never on the trackpad, keys, chips
  or the mirror picture.
- Group neighbouring glass controls in one `GlassEffectContainer` so they morph
  (the tab bar ↔ minimised tab, the mirror toolbar ↔ its collapsed pill).
- `.interactive()` only on glass that responds to touch.
- Panes use `ConcentricRectangle` (or `.containerShape`) so their corners follow
  the window and device corners (30 pt on iPhone, 24 pt on iPad).
- Reduce Transparency: glass → solid `navBar` / `elevated`. Test it.
- iOS 27 lets people dial glass from clear to opaque; designs must read at
  both ends, which is why chrome never carries small text over the mirror.

## 3. Typography

Pairing: **Geist** (the website's display face, SIL OFL, bundle
`Geist-Medium.otf` and `Geist-SemiBold.otf`) for display moments only, and
**SF Pro** (system) for everything people read and tap. SF Mono for chords and
numbers. Dot-matrix numerals (`PixelArt`) for codes and stats headlines only.
Drop the rounded design: the website isn't rounded, and two families plus mono
is enough.

| Role token | Font | Text style it scales with | Size at default | Tracking |
| --- | --- | --- | --- | --- |
| `display.large` | Geist Medium | `.largeTitle` | 34 | -0.9 |
| `display` | Geist Medium | `.title2` | 22 | -0.5 |
| `display.small` | Geist SemiBold | `.headline` | 17 | -0.2 |
| `title` | SF Pro Semibold | `.title3` | 20 | default |
| `headline` | SF Pro Semibold | `.headline` | 17 | default |
| `body` | SF Pro | `.body` | 17 | default |
| `chipLabel` | SF Pro Semibold | `.subheadline` | 15 | default |
| `keyLabel` | SF Pro Semibold | `.caption` | 12 | default |
| `caption` | SF Pro | `.caption` | 12 | default |
| `chord` | SF Mono Medium | `.caption2` | 11–12 | default |
| `numerals` | SF Mono, `.monospacedDigit()` | `.footnote` | 13 | default |

```swift
extension Font {
    static func phDisplay(_ style: Font.TextStyle = .title2) -> Font {
        .custom("Geist-Medium", size: style.defaultSize, relativeTo: style)
    }
    static let phChip  = Font.subheadline.weight(.semibold)
    static let phChord = Font.system(.caption2, design: .monospaced).weight(.medium)
}
```

Dynamic Type rules: no fixed sizes anywhere except glyph art. Test at default,
xxxLarge and AX5. At AX1+: chips grow and the strip wraps to two rows; deck
keys switch to a list layout (glyph + full label); the Mac pill drops the
front-app line before truncating the name; the tab bar shows icons only and
uses the Large Content Viewer on long-press.

## 4. Space, size and shape

| Token | Values |
| --- | --- |
| `space` | `xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32 · xxxl 48` |
| `gutter` | compact 16 · medium 20 · wide 24 |
| `hit` | minimum 44 × 44 everywhere (chips, key corners, close buttons) |
| `radius` | `kbd 8 · chip 14 · key 18 · card 24 · pane 30 · sheet 36 · capsule` |
| `keySize` | 64–96, derived by `LayoutMetrics` |
| `dot` | grid 2.4 on a 15 pitch · status strip 4 × 3.5 · beam 6 · live pixel 6–8 |

## 5. Motion

| Token | Value | SwiftUI | Use |
| --- | --- | --- | --- |
| `quick` | 160 ms ease-out | `.easeOut(duration: 0.16)` | Press states, dot changes |
| `standard` | 240 ms | `.smooth(duration: 0.24)` | Show/hide chips, strip changes |
| `spring` | 0.4 s, bounce 0.15 | `.spring(duration: 0.4, bounce: 0.15)` | Arrangement changes, docks, sheets (the site's `--ease-spring`) |
| `hero` | 0.8 s, no bounce | `.spring(duration: 0.8, bounce: 0)` | Onboarding, pairing success (the site's `--ease-hero`) |

Every animation reads `@Environment(\.accessibilityReduceMotion)`; when on,
replace movement with a 160 ms cross-fade and freeze dot effects (as
`DeckHandMotion.swift` already does). Haptics follow the Off / Light / Full
setting and never carry information alone.

## 6. The dot-matrix language

The dots are a **status language**, not decoration. Lit dots only while a Mac
is talking.

| Motif | Where | Spec |
| --- | --- | --- |
| Resting grid | Every navy surface | 2.4 pt dots, 15 pt pitch, `dotOff` |
| Lit trail | Under fingers on the trackpad | Existing `DotField`: 64 pt reach, 0.3 s afterglow |
| Live pixel | Mac pill, Mac cards, app dock front app | 6–8 pt mint square with glow; grey when offline |
| Running dots | App dock, under each running app | 4 pt square, `ink3`; front app mint |
| Delivery strip | Chips (3 dots) and keys (4 dots) | Idle `fill2` → sending glow (sequential) → delivered mint, then a check → refused danger, then a cross |
| Dot beam | Pairing waits, transfers, AI thinking | Row of 6 pt dots filling left to right; turns mint and collapses on success |
| DotScan | Searching for Macs | Existing component |
| 8 × 8 pixel glyphs | Deck keys, empty states | Same dots as the icon; editable in the deck editor |
| Dot-matrix numerals | Pairing codes, stats headline | 3 × 5 digits, groups of 4, check digit dimmer |
| Ask glyph | Ask button, AI panels | 3 × 3 dots with a lit cyan centre. **No sparkles anywhere.** |
| Ghost keys | AI proposals | Dashed cobalt outline, 75 % content until kept |

## 7. Components

Each is one SwiftUI view or style in `DeckHandiOS/DesignSystem/` (new
folder, IOS-SHELL lane). Board section "Components" shows all states.

| Component | Anatomy | States | Notes |
| --- | --- | --- | --- |
| `PHButton` | Capsule, 44–52 pt | primary (cobalt gradient), secondary (fill), glass, destructive | Wraps system `.glass` / `.glassProminent` on chrome |
| `ContextChip` | Label + chord in mono + 3-dot strip; min 44 pt | idle, sending, delivered, refused, dialog, default (cobalt + 2 pt ring), AI proposal (dashed) | Long-press: "Run on…", "Pin to deck", "Edit" |
| `ContextStrip` | One row of chips; leading app chip on compact heights | dialog mode (default button first on compact), app mode, free-tier media mode | Two rows at AX sizes; `accessibilityElement(children: .contain)` labelled "Actions for <app>" |
| `DeckKey` | Square `keySize`, glyph 26–30, label 2 lines, chord, 4-dot strip | idle, sending, done, refused, ask-first (`?` corner), system (navy), ghost, editing (dotted outline + remove badge) | List layout at AX1+ |
| `DeckPage` | Header (app icon, title, follow/pin, Edit), reflowing grid, page dots | following, pinned, editing | Stores order, not coordinates |
| `AppDock` | Glass capsule; running apps with running dots; trailing keyboard button | front app ring + mint dot; dialog badge on an app; long-press menu (Quit, Hide, Shortcuts, Send to) | Becomes the leading app chip on short screens |
| `SurfaceTabs` | System `TabView` with three tabs + `Tab(role: .search)` for Ask | full, minimised (`tabBarMinimizeBehavior`) | On wide: layout preset picker instead |
| `MacPill` | Glass capsule: Mac glyph with live pixel, name, front app, chevron | online, offline (grey pixel), locked (lock glyph), alert badge | Tap: My Macs; swipe sideways: next Mac |
| `MacCard` | 16:10 glance thumbnail, live pixel, name, front app, badge | focused (2 pt cobalt ring), offline (dimmed last frame), dialog, locked, needs update | iPad sidebar and My Macs sheet; drop target |
| `MirrorPane` | Picture, LIVE tag, stats line, glass toolbar | floating tile, docked, full screen, PiP | Cursor drawn on device (S3) |
| `PixelSurface` | Navy pane with dot grid and optional click strip | idle, touching (lit), scroll mode (caption) | Hosts `MultiTouchTrackpad` |
| `StatusPill` | Icon + one sentence + Fix button | warning, info, locked | Replaces `HostCapabilityBanner` |
| `Toast` | Glass capsule, live pixel, one line | delivered, refused | Announced to VoiceOver |
| `DotBeam` | Row of dots | progress, success, failure | Replaces every spinner on brand surfaces |
| `EmptyState` | Dot art, headline (display.small), one sentence, one action | – | Existing `DeckHandEmptyState`, restyled |
| `ProBadge` | Sky → cobalt gradient capsule "PRO" | – | Only on locked features and the paywall |

## 8. Mac panel tokens

The Mac panel uses the same colour tokens through the shared asset catalog, but
**system text styles** (`.body`, `.callout`, `.caption`) so it follows the
Mac's text size, and the system's popover material rather than Liquid Glass
from iOS. 340 pt wide (03-UX-Guidelines §1.3).

## 9. Migration from `DeckHandTheme`

| Today | Becomes |
| --- | --- |
| `DeckHandTheme.accent`, `mint`, `warning`, `danger` | Same names on `PixelHandTheme`, asset-catalog backed |
| `canvasBackground(_:)`, `cardFill`, `cardBorder`, `navDivider`, `tabContainer*`, `searchFieldFill`, `subtleWellFill` | `canvas`, `raised`, `hairline`, `fill`, `fill2` (no `ColorScheme` parameter) |
| `trackpadSurface` | `PixelSurface` |
| `Radius.sm…hero` (12…28) | `radius.kbd…sheet` by role |
| `TypeStyle.*` fixed fonts | Font roles in §3 |
| `FAB` tints | Removed with the FABs |
| `DeliveryDots` hard-coded hex | `glow`, `success`, `danger` tokens |
