# Lane: UX onboarding (UX-010, UX-011)

Branch `claude/pixelhand-lane-ux-onboarding`, merged with
`origin/claude/pixelhand-integration` at `ec3dfb2`. No protocol change (still
12), no `project.yml` or Info.plist change, no StoreKit or pairing logic
change. New files are picked up by folder.

## What changed

### UX-010 Onboarding (`OnboardingView.swift`, `Onboarding/`)

- **Every page has a dot-art scene** (`Onboarding/OnboardingScene.swift`) on
  the same navy plate (`PixelSurface`, radius 36, 15 pt grid, cobalt bloom):
  - 1 Welcome: `DeckHandMark` with its power-on, kept.
  - 2 Trackpad: a lit finger trail across the grid (dots brighten and grow,
    on the resting grid's exact positions), two touch rings, `2 FINGERS ·
    SCROLL` status strip.
  - 3 Mirror: a drawn Mac desktop (navy wallpaper, editor window, dialog,
    Dock) arriving top to bottom under a cyan scanline, `LIVE · 60 FPS` strip,
    PiP glyph + `PINCH TO READ` under it.
  - 4 Capture: the desktop dimmed outside a marching dotted phosphor
    selection with corner handles, then `BUILD FAILED` / `MAIN.SWIFT:42` in
    dot-matrix.
  - 5 Your Mac: Wi-Fi glyph, Mac and iPhone glyphs at pitch 10 (6 on the
    248 pt plate) with unlit cells, a `DotBeam` filling between them, the
    first 8 digits of a code.
  Each scene runs once per appearance (600–900 ms, ease-out) and holds;
  Reduce Motion shows the final frame.
- **Glyph bullets**: 30 pt navy tiles (`GlyphTile`) with the board's glyphs
  (click, Mission Control, pointer; PiP, region, screen; capture, type, read
  text; Mac, Wi-Fi, lock). Tiles grow with the stepped pitch at AX1+.
- **Dot-matrix step counter** `02/05` top-leading (spoken "Step 2 of 5"),
  Skip top-trailing (hidden on the last page), **6 pt square page dots** with
  the current one phosphor.
- **Back (secondary, 120 pt) + Continue (primary, 52 pt)**; first page "Get
  started", last page "Find my Mac". At AX sizes the buttons stack. Swipe
  left/right still pages.
- **Title** Geist Medium, 40 pt on medium/wide widths and 30 pt compact,
  scaling with `.largeTitle`; body `.body` at 72 % white.
- **Layout from `LayoutMetrics`** (never idiom): `usesTwoColumnPages` →
  scene left (400 pt wide, 248 pt iPhone landscape), 440 pt left-aligned text
  column right with dots and buttons under the text. Otherwise one column:
  scene 340 (iPad portrait / Split View) or 248 (phones), capped at 34 % of
  the height; text and bullets scroll, dots and buttons stay pinned.
- **Motion**: page change = pixel dissolve on the scene (8 pt cells,
  scattered order) and an 8 pt slide + fade on the text in the travel
  direction. Reduce Motion: cross-fades.
- **Copy** is device-neutral (board text); page 5 explains pairing with a
  code.
- `PressableButtonStyle` stays in `OnboardingView.swift` (the picker uses it).

### UX-010 Mac picker, approval card, pairing

- `PeerPickerView`: Geist title ("Choose a Mac" / "Looking for your Macs"),
  one-line subtitle, mark 112 pt; **on short heights (< 520 pt, landscape)
  the header turns into a row with a 64 pt mark** so the first Mac shows
  without scrolling. Header buttons are `GlassCircleButton`s with the region
  (pair by QR) and settings glyphs. Mac cards: 44 pt glyph tile (Mac at pitch
  3), `.headline` name, `MY MAC` dot-matrix badge, status pixel + "Paired ·
  Nearby" / "Remote", amber pixel + update message, `DotWave` and a dotted
  phosphor ring while connecting. Searching: `DotScan` + amber pixel +
  `SEARCHING`. Start failure: Wi-Fi glyph at pitch 6, `.ph` "Try again".
  Errors use `PHToast`. Footer: Wi-Fi glyph + "Same Wi-Fi, or a cable". No
  fixed font sizes left. Connection logic untouched.
- `AuthorizationOverlay`: card max width 480 pt, radius 36, Geist title,
  `.ph` buttons (tint "Enter pairing code" with the lock glyph, destructive
  Disconnect, secondary Dismiss), `DotWave` while pairing; the card scrolls
  when it doesn't fit (AX sizes, iPhone landscape).
- `PairingCodeEntryView`: from a `Form` to a navy page: lock glyph tile,
  "Code shown on <Mac>", `7 DIGITS`, the field in SF Mono `.largeTitle` on a
  navy plate (dotted phosphor ring when focused, mint ring once the check
  digit passes), hint/notice text, primary "Pair" (DotWave while waiting),
  secondary "Scan the QR code instead". Same bindings, `onChange`, submit and
  scanner sheet as before; the toolbar keeps Cancel (Pair moved into the
  page).
- `PairingQRScannerSheet`: dotted viewfinder (6 pt corner dots) with a
  sweeping phosphor scanline, "Point at the code on your Mac" + "Menu bar ›
  Pixel Hand › Pair a Device…" on a dark band, capture glyph for the camera-off
  state, `DotWave` while asking for the camera. The scanner controller is
  unchanged.

### UX-011 Paywall and free tier (UI only)

- `PaywallView`: close is a 36 pt circle with the close glyph (always
  visible, labelled "Close"); hero is `DotMatrixText("PRO", pitch: 5,
  showsUnlit: true)` glowing on a navy plate; Geist 30 headline, left
  aligned; free-plan line with a mint pixel; features as glyph tiles (the
  focus feature phosphor); plan cards with a dotted radio, the billed price
  still the most prominent line, selected card sky ring, `-44%` dot-matrix
  savings badge on Yearly (spoken "Save 44 percent"); primary `.ph` purchase
  button with `DotWave` while working. **Apple's disclosure text, Restore
  Purchases, Terms of Use and Privacy Policy are the same strings and
  actions**, now `.caption` / `.footnote` at 66–86 % white (legible at AX5),
  links stacking when they don't fit. Every StoreKit call, `onChange`,
  `finish()` and the other-Mac switch are untouched.
- `ProLockBadge`: lock glyph in dots on the sky → cobalt tile (18 pt).
- `FreeMacBadge`: a `ProBadge` on locked Mac cards (was a scaled lock).
- `SettingsSubscriptionSection`: status row with `ProBadge` (Pro) or the lock
  glyph (free), `.headline` title, and the small LED `PRO` mark on Pro.
  Buttons, links and sheets unchanged.
- `ProFeature.glyph` (in `RequiresPro.swift`) maps features to pixel glyphs.

## Checks on the Mac build (against the board, "Onboarding, every page" and "Pro paywall")

Reset onboarding (Settings → replay, or delete the app). Do each in light and
dark system appearance (onboarding, picker and paywall stay navy by design),
then at Settings → Accessibility → Larger Text AX3.

**iPhone 17 Pro (402 × 874), portrait**: compare with board `onbPhone0–4`.
1. `01/05` top-left in phosphor dots, Skip top-right. Page 1: the mark powers
   on; "Get started" only.
2. Continue: the scene dissolves cell by cell into the trackpad plate; the
   trail draws bottom-left to top-right, two rings settle, strip at the
   bottom-left. Text slides 8 pt from the right. Back appears (120 pt).
3. Page 3: scanline sweeps down over the desktop, LIVE strip top-left.
   Page 4: dotted selection grows and marches, then the two dot-matrix lines.
   Page 5: beam fills between the Mac and iPhone glyphs, code fades in; no
   Skip; button "Find my Mac".
4. Swipe left/right pages too; Back on page 2 returns with the text sliding
   from the left.
5. Bullets: three navy glyph tiles per page, the glyphs listed above.
6. AX3: title grows, buttons stack (Continue above Back), content scrolls,
   dots and buttons stay pinned, nothing clips.
7. Reduce Motion: scenes appear on their final frame, pages cross-fade.

**iPhone SE (375 × 667)**: scene about 220 pt, title and bullets scroll above the
pinned buttons.

**iPhone landscape (874 × 402)**: two columns, 248-ish scene left, text,
bullets, dots and buttons right; scrolls at AX3.

**iPad 11″ portrait (820 × 1180)**: board `onbPadP0–4`: 340 pt scene, 40 pt
title, bullets centred, buttons max 420 pt at the bottom.

**iPad landscape (1180 × 820)**: board `onbPadL1`/`onbPadL3`: 400 pt scene
left, 440 pt left-aligned column right with the dots and buttons under the
text. Resize a Stage Manager window narrow ↔ full: switches between one and
two columns without losing the page.

**Picker** (after onboarding): portrait shows the 112 pt mark, "Looking for
your Macs" and DotScan with `SEARCHING`; with Macs, "Choose a Mac", glyph
tiles, `MY MAC` badge, "Paired · Nearby". **iPhone landscape**: the header is
one row and the first Mac card is visible without scrolling. Tap a Mac: dotted
ring + dot wave on its card, the others dim. Free plan with two Macs: `PRO`
badge on the locked one. QR circle opens the scanner: dotted corners and a
moving scanline.

**Approval card**: at most 480 pt wide on iPad; "Enter pairing code" opens the
navy code page; typing 7 valid digits turns the ring mint and enables Pair.

**Paywall** (tap a locked control, or Settings → Subscription): board
`v2Paywall`: close circle top-left, `PRO` LED mark, headline, four glyph
features, Yearly selected with the `-44%` badge, purchase button, disclosure
and the three links. At AX5 the disclosure is readable and the links stack.
Buy in the StoreKit sandbox and Restore from both the paywall and Settings:
same behaviour as before.

**Settings → Subscription**: free shows the lock glyph; Pro shows the PRO
badge and the LED `PRO`.

## Compile risks (most likely first)

SwiftUI files can't be type-checked on Linux; all edited files pass
`swiftc -parse`, `swift test --package-path DeckHand/Core` (603 tests) and
`DeckHand/Scripts/linux-typecheck/run.sh` pass.

1. `Onboarding/OnboardingScene.swift`: the trackpad `Canvas` closure (the
   typed `compactMap` tuple, CGFloat/Double mixing in `trailPoint`, the
   `.shadow` filter on a copied `GraphicsContext`); `nonisolated private
   static` helpers called from `Canvas` under Swift 6.
2. `SceneClock`: `@ViewBuilder let content: (Double) -> Content` as a stored
   closure and the `if … else TimelineView` body.
3. `OnboardingComponents.swift`: `PixelDissolveModifier` as
   `ViewModifier, Animatable` used through `AnyTransition.modifier(active:
   identity:)`; `nonisolated static func rank`.
4. `OnboardingView.buttons`: `AnyLayout(VStackLayout …)` with `if` inside the
   layout closure.
5. `CaptureScene` mask (`.blendMode(.destinationOut)` + `.compositingGroup()`)
   and `StrokeStyle(lineWidth:lineCap:dash:dashPhase:)`.
6. `PeerPickerView.header(isShort:)`: `@ViewBuilder` func with a `let` and
   `AnyLayout`; `HStack(alignment: .firstTextBaseline)` around `StatusPixel`.
7. `AuthorizationOverlay.ScrollsWhenTall`: `ViewThatFits(in: .vertical)` with
   `content` used twice.
8. `PaywallView`: `ViewThatFits` over the `@ViewBuilder disclosureLinks`;
   `DotMatrixText("-\(savingsPercent)%", …)`; the toolbar close `Button`.
9. `SettingsSubscriptionSection`: `foregroundStyle(cond ? PixelHandTheme.warning
   : .secondary)` (resolves to `Color.secondary`, as before).

## Out-of-lane edits

None. Every edited file is in this lane's list (`OnboardingView.swift`,
`PeerPickerView.swift`, `AuthorizationOverlay.swift`, `Pairing/**` UI,
`Store/**` UI, `Settings/SettingsSubscriptionSection.swift`) or new under
`DeckHandiOS/Onboarding/`. `DesignSystem/**` was only used, not edited.
New app-wide names: `OnboardingScene`, `OnboardingSceneView`, `GlyphTile`,
`PageDots`, `OnboardingBulletRow`, `PageTextTransition`,
`PixelDissolveModifier`, `AnyTransition.pixelDissolve`, `ProFeature.glyph`
(checked by grep: no clashes after the merge).

## Follow-ups

| Item | Owner | Notes |
| --- | --- | --- |
| Promote `GlyphTile`, `PageDots`, `pixelDissolve` to `DesignSystem/` | UX shell | They live in `Onboarding/Components/`; UX-017 can reuse the dissolve for surface switches. |
| Onboarding pages from §5 of the interaction model (Get the Mac app with QR + send link, Local Network explainer, coach marks) | Design | This lane rebuilt the five existing pages to the board; the new pages and coach marks are a separate step. |
| Soft paywall once after onboarding | Store + Design | `04-Interaction-Model.md` §6; needs a "Not now" variant of `PaywallView` and a shown-once flag. |
| Locked-surface inline cards, free-tier media-key strip, trial reminder | Store + UX shell | UX-011 items that live on the Screen/Deck surfaces and context strip (other lanes' files). |
| Mac "Pair a device" window restyle (QR dots, dot-matrix code, countdown beam) | Pairing / UX-012 | Board `v2PairMac`; Mac files aren't in this lane. |
| Bundled still of the Mac desktop for the mirror scene | Design | The scene draws its desktop in code today; swap in an image if the owner wants a richer frame. |

Lane: READY TO MERGE
