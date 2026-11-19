# 06 · Pixel identity (round 2)

The owner approved the direction on 19 Nov 2026 and asked for more glyph,
pixel and dot-matrix work, so that the app feels like one instrument rather
than decoration on top of stock iOS (`DeckHand/Integration/DECISIONS.md`).
This file specifies that language and maps every element to SwiftUI. Board:
https://claude.ai/artifact/Aa8KTJubKeqahy3cmSjRTm, sections "Pixel identity",
"Key screens", "New features". Source: `board/pixel.js`, which holds the real
glyph bitmaps and font table.

## 0. The one rule

Everything is drawn with **one kind of dot**: a square at 78–80 % of the
pitch, with a corner radius of 30 % of the dot, on a whole-point pitch. That is
the app icon's dot, the website's hero grid and the trackpad's `DotField`.
Lit dots mean live (`02-Design-System.md` §6); this file adds what the dots
are allowed to draw.

## 1. Pixel glyphs

**Grid.** 9 × 9 dots. An odd grid has a true centre for targets, plus signs
and the Ask glyph.

**Stroke rule.**
1. Strokes are exactly one dot wide.
2. Corners are a single dot; no rounded corners made of extra dots.
3. Diagonals step at 45° only (one dot across, one dot down).
4. At most **one lit accent dot** per glyph, marking where the action happens:
   the cursor tip, the shutter centre, the hammer's head, the check's base.
   The accent is `glow` on navy and `accent` on light surfaces.
5. Solid fills only for media state glyphs (play, pause); every other glyph is
   an outline.
6. Glyphs keep a one-dot margin where the shape allows, so neighbouring
   glyphs never touch at small pitches.

**The set (40).** Pointer, Click, Screen, Deck, Keyboard, Capture, Mission
Control, Show Desktop, Play, Pause, Build, Run, Stop, Test, Find, Console,
Lock, Send, Share, Ask, Mac, iPhone, Space left, Space right, Displays,
Wired, VPN, Sound on, Sound off, Paste, Type, Region, Read text, Pin, Close,
Add, Picture in Picture, Wi-Fi, Settings, Wake. App icons stay the real
icons from the Mac; glyphs are for actions and states.

**Sizes (pitch → glyph size).** Only these:

| Pitch | Size | Where |
| --- | --- | --- |
| 1.4 | 12.6 pt | Inside badges and the cursor badge |
| 2 | 18 pt | Chips, toolbars, list-row tiles, header buttons (2.2 = 20 pt) |
| 2.6 | 23.4 pt | Tab bar |
| 3 | 27 pt | Deck keys, AX deck rows |
| 4 | 36 pt | Glyph sheet, small empty states |
| 6 | 54 pt | Empty states |
| 10 | 90 pt | Onboarding heroes |

Never scale a glyph with a transform. Draw it at the pitch.

**User glyphs.** The deck editor's 8 × 8 pixel editor (round 1) becomes
9 × 9 with the same rule, and lints the user's drawing for rule 1 only (a warning,
not a block).

**SwiftUI.**
```swift
// PixelHandCore (Linux-testable data)
public struct PixelBitmap: Sendable, Hashable {
    public let rows: [UInt16]        // 9 rows, low 9 bits
    public let accent: (x: Int, y: Int)?
    public let solid: Bool
}
public enum PixelGlyphs { public static let pointer = PixelBitmap(…) /* … 40 … */ }

// App
struct PixelGlyph: View {
    let bitmap: PixelBitmap
    var pitch: CGFloat = 2
    @Environment(\.pixelAccent) private var accent   // glow on navy, accent on light
    var body: some View {
        Canvas { ctx, _ in
            let d = pitch * 0.78, r = d * 0.3, o = (pitch - d) / 2
            for y in 0..<9 { for x in 0..<9 where bitmap.isOn(x, y) {
                let rect = CGRect(x: CGFloat(x) * pitch + o, y: CGFloat(y) * pitch + o, width: d, height: d)
                ctx.fill(Path(roundedRect: rect, cornerRadius: r),
                         with: bitmap.isAccent(x, y) ? .color(accent) : .foreground)
            } }
        }
        .frame(width: 9 * pitch, height: 9 * pitch)
        .accessibilityHidden(true)            // the control carries the label
    }
}
```
Tests in Core: every glyph is 9 × 9; at most one accent; no 2 × 2 filled block
unless `solid` (rule 1); names unique. A snapshot test renders all 40 at pitch
2 and 3 in both appearances.

## 2. Dot-matrix type

**Font.** 5 × 7 cells, 1-cell tracking (6-cell advance), uppercase A–Z,
0–9 and `· : / % - + < >`. Lowercase is uppercased. Same dot rule as glyphs
(80 % dot, 32 % radius).

**Use it for:** status words (LIVE, LOCKED, DIALOG), counters (01/03,
4.1/9.4 MB), stats (60 FPS · 7 MS), link badges (WIRED, VPN, WI-FI, DIRECT),
the pairing code, onboarding step counters, the PRO mark, the version line.
**Never** for sentences, buttons, prices, legal text or anything a person
must read to decide.

**Accessibility.** Every dot-matrix string has a plain-language
`accessibilityLabel` ("Page 1 of 3", "Studio, display 1 of 2, desktop 2 of 3,
60 frames per second"). Dot-matrix text does **not** follow Dynamic Type; at
AX1+ its pitch steps up one size (1.4 → 2, 2 → 2.6) and anything that would
overflow moves into the real-text row next to it.

**Pitches.** 1.3–1.4 in badges and micro strips (9–10 pt tall), 1.6 counters
(11 pt), 2 status strips (14 pt), 3 large counters (21 pt), 5 the PRO mark.

**Unlit cells.** Off by default. Shown at 14 % only where the "LED panel" look
is the point: the paywall's PRO, the dot-matrix specimen, the dim state of a
strip.

**SwiftUI.** `DotMatrixText("60 FPS", pitch: 2)` → a `Canvas` that looks up
each character's 35-bit pattern in `PixelHandCore.DotMatrixFont` (data + tests
in Core, like the glyphs). Numbers that change use
`.contentTransition(.identity)` and redraw; no per-digit animation except the
pairing code, which lights each new digit with the power-on curve.

## 3. The status strip ("now playing")

A tiny LED panel that says what a Mac is doing. Always navy
(`screen` @ 84 %), 0.5 pt light rim, live pixel at the leading end.

| Where | Height · pitch | Content |
| --- | --- | --- |
| Mirror (Screen surface, iPad, Duo) top-leading over the picture | 20–22 · 1.6–1.8 | `STUDIO · D1/2 · DESK 2/3 · 60 FPS` |
| Floating mirror tile | 18 · 1.4 | `LIVE · D1 · 60` |
| Mac cards (switcher, sidebar) bottom of the thumbnail | 16 · 1.3 | `XCODE · 60 FPS` / `PAGES · DIALOG` / `LOCKED` / `OFFLINE 2H` |
| Widgets | 24 · 2 | `STUDIO · XCODE` |
| Stats overlay (S6), when on | 24 · 2 | `60 FPS · 7 MS · 4/11 RTT · 18 MB/S · HEVC 1920 · WIRED` |

States: **live** phosphor text + mint pixel; **needs you** amber text and
pixel (dialog waiting, permission missing); **dim** `#6D7BB8` text, grey pixel
(locked, offline). The strip truncates at a separator, never mid-word; when
there is a single item it may scroll as a marquee at 24 pt/s with 2 s pauses,
which stops under Reduce Motion.

**SwiftUI.** `StatusStrip(items: [StatusItem], style: .live)`, an `HStack`
of `LivePixel` + `DotMatrixText(items.joined(" · "))` in a
`ViewThatFits` that drops trailing items first. Source data: the session
model's front app, `displayList`/`DisplayLayout` (Mac system control lane),
the mirror stats (Mirror lane), `LinkKind` (Network lane).

## 4. Badges and new-feature chrome

| Element | Spec | Data |
| --- | --- | --- |
| **Link badge** | 20 pt capsule, radius 6, glyph pitch 1.4 + dot-matrix label pitch 1.4. Wired = mint, VPN = cobalt tint, Wi-Fi / Direct = muted. Shown next to the Mac pill and on Mac cards; hidden on plain Wi-Fi in the header to keep it quiet. | `session.link(LinkKind)` |
| **Desktop dots** | 6 pt dots, 5 pt gap. Current = phosphor with glow (accent on light); others `dotOff`; full-screen app desktops hollow (1.2 pt ring). Between the ‹ › Space buttons in the mirror toolbar and under each Mac card / display card. ‹ › dim when the display has one desktop. | `DisplayLayout.spaceCount`, `currentSpaceIndex`, full-screen indexes |
| **Display picker** | Toolbar button = Displays glyph + `1/2` counter. Sheet: displays drawn to scale in the Mac's arrangement, live thumbnails, desktop dots per display, the cursor glyph (phosphor) on the display that has it, toggle "Follow the cursor". | `mirror.displayList`, `DisplayLayout` |
| **Cursor badge** | 20 pt navy capsule at the mirror's top-trailing: pointer glyph + `ON 2` + arrow toward that display. Tap switches the picture there. Shown only while the cursor is on another display. | `cursorDisplayID` |
| **Sound toggle** | Sound on / Sound off glyph in the mirror toolbar (lit state = on) and a Settings row per Mac. Free tier: Pro badge. | Audio lane, `pixelhand.audio` stream |
| **Pairing code** | Mac window: QR whose modules are drawn as round dots (finder squares kept square so scanners still lock), the pointer glyph in a navy tile at the centre (within QR error correction), the 12-digit code in dot-matrix numerals, groups of 4, check digit dimmer, a dot beam counting down the 5-minute window. iPhone: dotted viewfinder with the scanline, "Found Studio · checking its key" before sending the code. | Pairing lane (`PairingCode`, `PairingInvite`) |

## 5. Phosphor highlight and focus

- **Focus ring** (keyboard focus on iPad, Switch Control, "you are here"):
  a dotted ring 3 pt outside the shape, 2 pt dots on a 4 pt rhythm, `glow` on
  dark and `accent` on light, with an 18 pt soft bloom at 50 %. SwiftUI: a
  custom `focusEffect`-style modifier drawing
  `RoundedRectangle(cornerRadius: r + 3).stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.01, 4]))`
  plus `.shadow(color: glow.opacity(0.5), radius: 9)`; disable the system
  focus effect on those views.
- **Press.** A key's or chip's glyph dots flash to phosphor for 120 ms
  (`quick` motion), then the delivery strip takes over.
- **Selection.** Selected tab, preset or Mac gets a 4 pt lit dot under the
  label (tab bar) or the 2 pt cobalt ring (cards). No filled pills for
  selection inside navy chrome.
- **Disconnected.** No phosphor, glow or mint anywhere. Glyphs stay ink.

## 6. Loading and empty states

- **Loading:** a 9 × 3 dot block where a brightness wave travels left to
  right, period 1.2 s, `cos³` falloff. Replaces every spinner. Reduce Motion:
  the middle frame, static. SwiftUI: `TimelineView(.animation)` driving a
  `Canvas`; pauses when off screen (`.onDisappear`) and in Low Power Mode drops
  to 15 fps (`TimelineView(.periodic(from:by: 1/15))`).
- **Long waits** (pairing window, transfers, AI planning): the dot beam
  (round 1) with a count in dot-matrix numerals.
- **Empty states:** on navy, the relevant glyph at pitch 6 over its unlit
  9 × 9 grid; the accent dot breathes (opacity 0.4 → 1, 2.4 s, ease-in-out);
  headline in `display.small`, one sentence, one or two actions. Searching for
  Macs keeps `DotScan`.

## 7. Transitions, with timing

| Transition | Use | Timing | Spec | Reduce Motion |
| --- | --- | --- | --- | --- |
| **Pixel dissolve** | Switching surface (Pointer ↔ Screen ↔ Deck), switching Mac, paywall → unlocked surface | 280 ms total, linear threshold | The outgoing view is cut into 8 pt cells (6 pt on compact). Each cell has a seeded random threshold; when progress passes it, the cell shows the new view. The band of cells within 12 % behind the edge draws as phosphor dots with a 2 pt glow. Switching Mac adds a 12 pt slide in the swipe's direction. | 160 ms cross-fade |
| **Scanline** | Mirror connects, display or desktop changes, returning from PiP, capture taken | 360 ms ease-out | A 1.5 pt phosphor line sweeps top to bottom revealing the new picture, with a 14 pt cyan afterglow (40 %) behind it. Capture: one sweep plus the shutter glyph's accent flash. | 160 ms fade |
| **Power-on** | Launch, pairing success, Pro unlocked | 600 ms | Dots light with 0–180 ms per-dot jitter; brightness overshoots to 115 % at 210 ms and settles by 600 ms (the website hero's `powerOn` curve). | Instant, no flash |
| **Delivery** | Chips, keys | 45 ms stagger per dot, hold 900 ms (1.4 s refused) | Existing `DeliveryDots` timing, on the new tokens | Final state only |
| **Dot wave** | Loading | 1.2 s loop | §6 | Static |

**SwiftUI.**
- Dissolve: a `Transition` whose body applies `.layerEffect` with a
  `[[ stitchable ]]` Metal function `pixelDissolve(position, layer, progress,
  cell, seed, edgeColor)`: computes the cell, hashes it to a threshold,
  returns transparent / the layer sample / a rounded-square phosphor dot.
  `maxSampleOffset: .zero`. Provide `.pixelDissolve(seed:)` as
  `AnyTransition`. Gate on `accessibilityReduceMotion`.
- Scanline: `.visualEffect { content, proxy in content.mask { LinearGradient(...) } }`
  driven by a `phase` animated with `.easeOut(duration: 0.36)`; the line and
  afterglow are an overlay `Rectangle` at `proxy.size.height * phase`.
- Power-on: `PhaseAnimator([0, 1.15, 1.0])` on brightness, per-dot delay from
  a seeded table, inside the hand's `Canvas` (`PixelArt.swift`).
- All timings live in `DeckHandMotion` (renamed `PixelHandMotion`) as
  constants with the numbers above; tests assert the Reduce Motion fallbacks.

## 8. The menu-bar hand and the app icon

**Menu bar (Mac).** One 18 pt template image of the dot hand
(`StatusItemIcon.swift`), five states drawn from the same dots:

| State | Look |
| --- | --- |
| Not ready (starting, failed) | Whole hand at 50 % |
| Ready | Outline dots |
| A device is asking | Fingertip dot blinks at 1 Hz (template, so it follows the menu bar) |
| Being controlled | Fill dots on, tap rays lit |
| Receiving a file | A 3-dot beam under the hand |

Reduce Motion: blinking becomes a steady filled fingertip.

**App icon → app.** The icon is a cobalt tile with a navy screen and the hand.
The **launch screen** is that screen full-bleed: navy, the hand at the icon's
position, the mint pixel top-trailing. The first frame of the app then
zooms (hero motion) into the trackpad's dot grid, so the icon, the launch and
the control surface are one continuous object. Widgets, Control Center
controls and Live Activities (later) use navy, glyphs and the status strip.
The Mac panel's header uses the same hand on the cobalt tile.

## 9. Onboarding: every page at the first page's level

**Owner feedback (19 Nov 2026):** on iPad the welcome page looks good, but the
other pages don't have the same craft or icons. **Why:** in
`DeckHandiOS/OnboardingView.swift` only page 1 draws real artwork
(`DeckHandMark(size: 172)`). Pages 2–5 use `OnboardingPage.symbol`, a stock SF
Symbol (`hand.point.up.left`, `rectangle.on.rectangle`, `camera.viewfinder`,
`wifi`) at 54 pt light weight in a blurred 136 pt navy square, with green
SF `checkmark` circles as bullets and fixed 36 pt rounded titles. The result
reads as a generic iOS template next to a bespoke first page.

**Fix (board section "Onboarding, every page").**

| Part | Now | New |
| --- | --- | --- |
| Artwork | Page 1: mark. Pages 2–5: SF Symbol in a blurred square | Page 1: the icon tile with the dot hand (kept). Pages 2–5: an `OnboardingScene` on the same navy plate (radius 36, 15 pt dot grid, cobalt bloom): **Trackpad** a lit finger trail across the grid with two touch rings and a `2 FINGERS · SCROLL` strip; **Mirror** the Mac's screen arriving under a scanline with a `LIVE · 60 FPS` strip; **Capture** a dotted phosphor region selection with the lifted text in dot-matrix; **Your Mac** Mac and iPad glyphs (pitch 10) joined by a beam, Wi-Fi glyph above, the first 8 digits of a pairing code below |
| Bullets | SF `checkmark` in mint circles | 30 pt navy glyph tiles with the page's own glyphs (scroll → Click, desktops → Mission Control, drag → Pointer; Picture in Picture, Region, Screen; Capture, Type, Read text; Mac, Wi-Fi, Lock) |
| Title | SF Rounded 36 fixed | Geist Medium `display.large` (40 on iPad, 30 on iPhone at default size, scales with `.largeTitle`) |
| Progress | Capsule dots | Dot-matrix `02/05` top-leading + 6 pt square page dots, current one phosphor |
| Buttons | Continue only; swipe to go back | Back (secondary, 120 pt) + Continue (primary, 52 pt); last page "Find my Mac" |
| iPad landscape | One centred column | Two columns: scene 400 pt left, text column 440 pt right, left-aligned, buttons under the text |
| Motion | Fade + 10 pt rise | Page 1 power-on (600 ms); scenes animate in place (trail draws, scanline sweeps, selection marches, beam fills; 600–900 ms, once); page change = pixel dissolve on the scene, 8 pt slide + fade on text. Reduce Motion: final frames, cross-fade |
| Copy | iPad-only ("Your iPad becomes…", "Approve the iPad once") | Device-neutral; page 5 explains pairing with a code (Pairing lane) |
| Small screens | Not scrollable; clips in landscape | Content in a `ScrollView` with the buttons pinned; iPhone landscape uses the two-column layout at 248 pt scene size |

**SwiftUI.**
- `OnboardingPage` drops `symbol: String?` for `scene: OnboardingScene`
  (`.mark`, `.trackpad`, `.mirror`, `.capture`, `.pairing`) and
  `bullets: [(glyph: PixelBitmap, text: String)]`.
- `OnboardingSceneView(scene:size:)`: a `PixelSurface` plate; the trackpad
  trail reuses `DotField`'s lighting maths fed by a scripted path; the mirror
  uses a still frame (bundled image of the Mac desktop drawn in the app's
  palette) with the scanline `visualEffect`; capture uses the phosphor focus
  stroke for the dotted selection and `DotMatrixText`; pairing uses
  `PixelGlyph` and `DotBeam`. Each scene is a `TimelineView(.animation)` that
  runs once per appearance, then holds.
- Layout from `LayoutMetrics`: `wide || (medium && short)` → two columns.
  Scene size: 400 / 340 / 248 by class.
- Owner of the file: Integration today (`LANES.md` §2.7), the Design lane in
  the redesign phase; ticket **UX-010** below includes this.
