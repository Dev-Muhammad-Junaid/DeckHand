# Pixel Hand UX and UI guidelines

These rules apply to every new screen and to the 1.0 layout pass (PH-027,
PH-028). Tokens named here live in `Shared/DeckHandTheme.swift` (renamed
`PixelHandTheme`), `Shared/DeckHandMotion.swift` and `Shared/PixelArt.swift`.

## 1. Layout: size classes and widths, never device type

Lay out from the **space the scene actually has**, not from
`userInterfaceIdiom` or the device model. iPadOS 27 ignores orientation checks
and misreports `UIScreen.main` in resizable windows (see
`AppleOS27-Support.md` §1.2), and Split View and Stage Manager give an iPad
iPhone-sized windows.

Measure once at the root of the control screen and publish a `LayoutMetrics`
value through the environment. Children read it; they do not run their own
`GeometryReader`s for layout decisions.

```
LayoutMetrics
  widthClass:  .compact (< 500 pt) | .medium (500–899 pt) | .wide (≥ 900 pt)
  heightClass: .short (< 500 pt)   | .tall
  deckColumns: Int          // derived, see §1.2
  keySize:     CGFloat      // derived, 64…96 pt
  safeInsets:  EdgeInsets
```

### 1.1 Regions

The control screen is made of five regions. Every layout is an arrangement of
them.

| Region | Content |
| --- | --- |
| **Top bar** | Mac switcher (name + chevron + online dot), front-app badge, capture button, settings |
| **Context bar** | Dialog-button chips, then front-app chips, then suggestions; one row, scrolls horizontally |
| **Deck** | Page grid with page dots |
| **Trackpad** | Multi-touch surface; always on the dark "screen" surface |
| **Mirror** | Floating tile (default) or docked pane / full screen |

### 1.2 Arrangements

| Space | Arrangement | Deck columns |
| --- | --- | --- |
| **iPhone portrait**, iPad Slide Over, narrow Split View (`compact × tall`) | Top bar → Context bar → **one main area** with a bottom segmented switch *Trackpad / Deck*. Mirror is a floating tile over the trackpad; pinch or tap to expand to full screen. | 4 |
| **iPhone landscape** (`compact/medium × short`) | Top bar collapses into a 44 pt leading rail (icons only). Trackpad left (≈ 60 %), Deck right (≈ 40 %, 3 columns, scrolls). Context bar sits above the deck column. No bottom switch. | 3 |
| **iPad ½ Split View, small Stage Manager window** (`medium × tall`) | Top bar → Context bar → Trackpad (top 55 %) and Deck (bottom 45 %) stacked; drag handle between them, position remembered per scene. | 5 |
| **iPad full screen, ⅔ Split View, large Stage Manager** (`wide`) | Top bar → Context bar across the top. Leading: Trackpad with the mirror docked above it (resizable split). Trailing: Deck column, 320–420 pt. From 1.3, an optional Macs sidebar (overview) at the far leading edge. | 4–6 by width |
| **Mirror full screen** (any) | Mirror fills the safe area; a translucent toolbar (Direct/Trackpad mode, display, keyboard, stats, close) auto-hides after 3 s; Context bar floats at the bottom edge. | – |

Rules:

- Switching arrangement must keep state: the deck page, the mirror tile
  position (as a fraction of the container, not points), the selected Mac.
- Never hard-code a frame size for a region; use the derived metrics. Fixed
  sizes are allowed for glyphs, dots and hit targets only.
- Respect safe areas on all edges. The trackpad may extend under the home
  indicator but must not put controls there.
- Stage Manager: support a minimum scene size of 375 × 500 pt and animate
  arrangement changes with `DeckHandMotion.spring`. The 27 SDK
  `UISceneClosureConfirmation` should ask before closing a scene with a live
  session.
- External display (iPadOS 27 `sceneAccessory`): the mirror goes to the
  external display, the iPad shows trackpad + deck.

### 1.3 Mac panel and windows

- Menu-bar panel: 340 pt wide, content-sized height up to 560 pt, then
  scrolls. Sections separated by 16 pt, no nested cards.
- First-run/permissions window: 560 × 460 pt, not resizable, centred.
- Incoming-request and transfer prompts are user notifications with actions,
  not floating windows, so they work in Focus modes and full-screen apps.
- Mac text uses system sizes (`.body`, `.callout`) so it follows the user's
  macOS text size setting.

## 2. Spacing, shape and type tokens

**Spacing** is a 4 pt scale: `xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32`.
Sibling groups use stacks with `spacing:` from the scale, not per-view padding.
Screen gutters are 16 pt on compact widths, 20 pt on medium, 24 pt on wide.

**Radius** uses the existing `DeckHandTheme` radii (12/14/18/20/24/28):
chips 14, keys 18, sheets and panels 24, the mirror tile 20.

**Hit targets** are at least 44 × 44 pt everywhere, including chips and the
delivery-dot row (which is not itself tappable).

**Type.** Today the theme uses fixed `Font.system(size:)` values
(`DeckHandTheme.swift:373-378`), which ignore Dynamic Type. Replace them with
text styles plus the rounded design:

| Role | Style |
| --- | --- |
| Screen title | `.title3.weight(.semibold)` rounded |
| Body, list rows | `.body` rounded |
| Chip/key label | `.subheadline.weight(.semibold)` rounded |
| Caption, receipts | `.caption` rounded |
| Numbers (stats, codes) | `.body.monospacedDigit()`, or the dot-matrix numerals for display only |

Dot-matrix lettering (`PixelArt`) is for **display only**: the wordmark,
pairing codes, the stats line, empty-state headlines. Never for body text,
labels or anything a user must read at small size.

## 3. Components

| Component | Spec |
| --- | --- |
| **Chip** | 44 pt min height, label + optional chord glyphs (⌘⇧S in a lighter weight), delivery-dot row 3 dots × 4 pt under the label. States: idle, sending (dots light in sequence, cyan glow), delivered (mint, 600 ms then fade), refused (danger, stays 2 s with a VoiceOver announcement). Dialog chips use the cobalt fill; the default button gets a 2 pt cobalt ring. |
| **Deck key** | Square, `keySize`. Glyph centred (SF Symbol, app icon, or 8×8 pixel glyph), label below (2 lines max, truncates middle). A 4-dot status strip on the bottom edge shows the same states as chips. "Ask before running" keys show a small dot-matrix "?" in the corner. |
| **Mac card** | 16:10 thumbnail (glance stream, or last frame dimmed when offline), name, front-app icon, online dot (mint lit / dot-off), alert badge (dialog waiting, locked, update needed). |
| **Status pill** | One line, icon + text, colour by meaning (§4). Used for "Mac locked", "Accessibility missing", "Update needed". Tapping explains and offers the fix. |
| **Sheet** | Medium + large detents on compact widths; form sheet on wide. Always a clear title and one primary action on the trailing side. |
| **Empty state** | `DeckHandEmptyState`: dot art, one-line headline, one sentence, one action. |
| **Progress** | Dot "beam": a row of dots filling left to right, used for transfers, pairing waits and AI thinking. No spinners on brand surfaces. |

## 4. The dot-matrix identity in new screens

The identity is a status language. Keep each colour to its one job (README
"Design"):

| Signal | Meaning | Where it appears in new screens |
| --- | --- | --- |
| **Cobalt** | The action colour | Primary buttons, selection, the default dialog chip, edit-mode outlines |
| **Screen navy** | Always-dark surfaces | Trackpad, mirror frame, picker, onboarding, Mac cards |
| **Cyan glow** | Live activity right now | Touches, sending dots, transfer beam, AI thinking scan |
| **Mint** | Connected / confirmed | Online dots, delivered receipts, paired state |
| **Danger red** | Refused / failed | Refused receipts, failed transfers |
| **Pixel violet** | Inside dot art only | The hand, pixel glyphs on keys |

Rules for new screens:

- **Mac switcher / overview**: each Mac card is a small "screen" (navy, dot
  border). The focused Mac's card border is lit cobalt; online dots are mint.
- **Sharing**: transfers show a dot beam between two device glyphs; on
  completion the beam turns mint and collapses into a check (PixelMorph).
- **Pairing code**: shown in dot-matrix numerals in groups of 4, with the
  check digit dimmer.
- **AI**: "thinking" is a cyan DotScan sweep across the proposal area, not
  sparkles; proposals are drawn as ghosted (dot-outline) keys until kept.
- **Deck editor**: edit mode outlines keys in dotted cobalt; the pixel-glyph
  editor is an 8×8 grid of the same dots used by the icon.
- Lit dots only when talking to a Mac. A disconnected state never shows
  cyan or mint.
- Every effect holds still under Reduce Motion (already a rule in
  `DeckHandMotion.swift`); replace motion with a cross-fade.

## 5. Accessibility

**Dynamic Type.** All text uses text styles (§2). Test at default, xxxLarge
and AX5:
- chips grow in height and the context bar becomes two rows at AX sizes;
- deck keys keep their square size, but labels move to a list-style layout
  (glyph + full label in a row) at AX1+, with `deckColumns` reduced;
- the top bar drops the front-app label before truncating the Mac name.

**VoiceOver.**
- Every chip and key: label = action name; value = chord or target
  ("Save, Command S, in Pages"); hint for destructive keys.
- Receipts are announced (`AccessibilityNotification.Announcement`):
  "Save sent", "Save refused: Accessibility is off on the Mac".
- The trackpad is a direct-touch area (`.allowsDirectInteraction`) and offers
  custom actions: Click, Right-click, Double-click, Scroll up/down.
- Mirror image: label "Screen of <Mac>", with a custom rotor action "Read
  text on screen" (OCR) when available.
- Mac switcher announces "<Mac> focused, <front app>".
- Group the context bar as a container labelled "Actions for <front app>".

**Contrast.** Body text ≥ 4.5:1, large text and icons ≥ 3:1, in both themes.
Known risks to check: `dotOff` (`2B3C99` at 50 %) on navy is decorative only
and must never carry meaning alone; light-mode cobalt `3A4CF2` on white passes
for text, cyan glow on white does not (use it on navy only). Support
**Increase Contrast** with a stronger tile stroke and solid chip borders.

**Colour independence.** Receipt states also differ by shape: delivered dots
become a small check, refused dots a cross, so they read without colour
(Differentiate Without Color).

**Motion.** Respect Reduce Motion (cross-fades), and Reduce Transparency
(solid backgrounds behind the floating tile and toolbars).

**Haptics** follow the existing Off/Light/Full setting and never carry
information that has no visual or spoken equivalent.

## 6. Copy

- Name things as people see them: "Your Mac", "Pair a device", "Allow
  Pixel Hand to control this Mac".
- Buttons say what happens: "Allow", "Deny", "Forget This Mac", "Send to
  Studio Mac".
- Errors say what went wrong and the fix: "Your Mac needs Accessibility
  turned on for Pixel Hand. Open System Settings on the Mac."
- The product is "Pixel Hand" in all UI strings. Keep the name in one
  constant (`AppBrand.name`) so the rename never has to touch copy again.
