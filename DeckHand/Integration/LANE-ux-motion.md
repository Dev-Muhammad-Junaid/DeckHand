# Lane: UX motion (UX-017 transitions, UX-018 loading, empty and focus)

Branch `claude/pixelhand-lane-ux-motion`, merged with the latest
`origin/claude/pixelhand-integration`. No protocol change (still 12).
iOS 17.4 APIs only, nothing behind `#available`.

## What changed

### UX-017 Transitions

- **Core: `Design/PixelTransitionPlan.swift`** is the single source for the
  transitions: dissolve 280 ms linear, scanline 360 ms ease-out, power-on
  600 ms (0 → 115 % at 210 ms → 100 %), 8 pt / 6 pt compact cells, the 12 %
  edge band, the seeded cell hash, and the Reduce Motion fallbacks (dissolve
  and scanline → 160 ms cross-fade, power-on → instant). `PixelHandMotion`
  (`Shared/DeckHandMotion.swift`) now reads its transition constants from it.
  Tests: `PixelTransitionPlanTests` (7 tests: timings, Reduce Motion
  fallbacks, cell size, rank spread, incoming/outgoing cells partition the
  grid, edge band, power-on jitter).
- **Pixel dissolve, promoted and rebuilt** in
  `DesignSystem/PixelTransitions.swift` + `DesignSystem/PixelTransitions.metal`.
  Two `[[ stitchable ]]` shaders (`pixelDissolveMask`, `pixelDissolveEdge`)
  draw the mask and the phosphor edge dots via `.colorEffect` on rectangles.
  They do not run a `layerEffect` over the content on purpose: the Pointer
  surface (UIKit trackpad) and the Screen surface (video layer) would
  rasterise to SwiftUI's yellow "unsupported" placeholder. The incoming view
  shows cells past the threshold, the outgoing view the rest, phosphor dots
  in the band between. At rest the shaders are off (`isEnabled: false`) and
  the mask is a plain rectangle, so views keep state and hit testing.
  API: `.pixelDissolve` (onboarding keeps using it), `.pixelDissolve(reduceMotion:isCompact:)`,
  `.pixelDissolve(cell:seed:)`, `PixelHandMotion.dissolve(reduceMotion:)`,
  `PixelHandMotion.animation(for:reduceMotion:)`.
  The old Canvas-mask dissolve in `Onboarding/Components/` is gone. Only one
  implementation exists now.
- **Shell hook** (`Shell/PixelHandShell.swift`, `canvas(centre:)`): surfaces
  swap with `.pixelDissolve(reduceMotion:isCompact:)` driven by
  `PixelHandMotion.dissolve`. Compact width uses 6 pt cells. Connecting →
  connected powers the canvas on (`.powerOn(when: session.sender != nil)`).
- **Power-on**: `.powerOn(when:)`, a `keyframeAnimator` on opacity plus a
  glow wash for the 115 % overshoot. It's an overlay, not `.brightness`, so
  UIKit content isn't rasterised. Reduce Motion: no animation.
- **Scanline**: the existing `mirrorScanline(on:)` in
  `Mirror/MirrorPixelChrome.swift` stays the only scanline. Its duration now
  comes from the plan through `PixelHandMotion.scanlineDuration`.
- **`GlyphTile` and `PageDots`** moved unchanged from
  `Onboarding/Components/OnboardingComponents.swift` to
  `DesignSystem/GlyphTile.swift`. Callers (paywall, pairing, Mac picker,
  onboarding) don't change.

### UX-018 Loading, empty and focus

- **Spinners → `DotWave`**, so the iOS app has no `ProgressView` left (and the Mac
  app had none):
  - `Settings/SettingsConnectionSection.swift`: "Test Connection" row.
  - `AppShortcutsSheet.swift`: the import spinner was the toolbar menu's
    label. The menu now always shows the ellipsis, and a separate trailing
    toolbar item shows the wave while importing.
  - `DeckHandLoadingStateView.swift`: `DotScan` → `DotWave` on a navy plate.
    This covers "Initializing…" and "Loading apps from Mac…".
  - Searching for Macs (`PeerPickerView`) keeps `DotScan`, per
    `06-Pixel-Identity.md` §6.
- **Empty lists → `PHEmptyState`**:
  - Apps (classic grid, `StreamDeckGridView.swift`): "No matches" on a
    `PixelSurface` with a Clear search action, replacing `DeckHandEmptyState`.
  - App dock (`Shell/AppDock.swift`): the capsule is never empty any more.
    It shows a small dot wave until the Mac's app list arrives, then "NO APPS
    OPEN" in dot-matrix `ink3`.
  - Macs (`Settings/SettingsPairingSection.swift`,
    `Settings/SettingsConnectionSection.swift`): "No paired Macs" glyph card
    replaces the grey text rows.
  - Windows (`WindowPickerView`) and decks (`Surfaces/DeckSurface.swift`)
    already used `PHEmptyState`, so they're unchanged.
- **Focus: `.phosphorFocusable(cornerRadius:)`** (in `DesignSystem/Feedback.swift`)
  tracks the control's own `@FocusState` and pointer hover and draws
  `.phosphorFocus`. It turns off the system focus and hover effects so only
  one ring shows. Applied to `ContextChip`, `DeckKey`, `DeckKeyRow`, `MacPill`
  (when tappable), `GlassCircleButton` and the surface tab bar's tabs.
  `PHButtonStyle` buttons keep the system focus ring, because a
  `ButtonStyle` can't disable the button's own focus effect.

## Checks for the owner (iOS build)

`xcodegen generate` first, because there's a new `.metal` file.

1. **Surface switches**: Pointer → Screen → Deck → Pointer from the tab bar,
   on iPhone and iPad. Each switch takes 280 ms. The old surface breaks into
   cells, the new one fills in behind a band of cyan dots. Nothing flashes
   yellow, and the trackpad and the mirror picture dissolve like the rest.
   Cells are visibly smaller on iPhone (6 pt) than on regular-width iPad
   (8 pt). After the switch, the trackpad responds straight away and the Deck
   keeps its page.
2. **Reduce Motion on** (Settings › Accessibility › Motion): the same
   switches are a quick cross-fade with no cells or dots. Reconnecting gives
   no fade-up or glow flash. The dot waves show a still middle frame, and
   onboarding pages cross-fade.
3. **Reduce Motion off, connect**: from "CONNECTING" to the first surface,
   the surface fades up with a brief cyan glow over about 0.6 s.
4. **Former spinners**: Settings › Remote access › a Mac › Test Connection
   shows a small dot wave in the row. Shortcuts sheet › ⋯ › Import from
   <app> shows a dot wave next to the ⋯ button while importing, and ⋯ stays
   tappable. Classic layout › Shortcuts tab before apps arrive shows the dot
   wave on a navy plate.
5. **Empty lists**: classic layout, search the apps for "zzz" to get the
   "No matches" card, then Clear search. With no apps open (or right after
   connecting), the dock shows the wave, then "NO APPS OPEN". Settings with
   no paired Macs (fresh install, or forget all) shows a "No paired Macs"
   card in both Pairing and Remote access. Check the window picker with no
   windows still shows its card.
6. **iPad focus with a hardware keyboard** (Settings › Accessibility ›
   Keyboards › Full Keyboard Access on, or just Tab): tab through the shell.
   Tabs, chips, deck keys, the Mac pill and the glass circle buttons get the
   dotted phosphor ring (cyan in dark, cobalt in light) with no second
   system ring. With a trackpad or mouse, hovering those controls shows the
   same ring. Repeat once with Switch Control scanning.
7. **Onboarding**: page scenes still dissolve between pages. The pixel
   dissolve now uses the shader, so check that pages 1 → 5 look the same as
   before or better.

## Compile risks (most likely first)

1. **`PixelTransitions.metal` / `ShaderLibrary` lookup.** These are the
   first stitchable shaders in the app. If the Metal file isn't in the iOS
   target (no `xcodegen generate`), the build succeeds but the dissolve's
   mask goes wrong at runtime. Literals are all explicit `f`/`h`; check the
   build log for MSL errors in that file first.
2. **`PixelTransitions.swift`**: `keyframeAnimator` with `MoveKeyframe` /
   `CubicKeyframe` on a `Double`, and `colorEffect(_:isEnabled:)` with
   `Shader.Argument.float(Float)`. If there's a type-checker timeout, split
   the dissolve body's `mask` / `overlay` into computed properties.
3. **`AnyTransition.pixelDissolve` overloads**: a static var plus two static
   funcs with the same base name. If `.transition(.pixelDissolve)` turns out
   ambiguous in `OnboardingView`, call `.pixelDissolve(cell: PixelHandMotion.dissolveCell)`.
4. **`Feedback.swift`**: `hoverEffectDisabled()` and `focusEffectDisabled()`
   (both iOS 17). `.focused($isFocused)` on a `Button` inside a modifier.
5. **`AppShortcutsSheet.swift`**: a conditional view inside a
   `ToolbarItem`.

The Linux type check can't see any of these SwiftUI files. Core and the
type check pass: `swift test --package-path DeckHand/Core` passes 668 tests,
and `DeckHand/Scripts/linux-typecheck/run.sh` reports Build complete.

## Out-of-lane edits

- `Shell/AppDock.swift` (shell): the empty and loading content inside the
  dock.
- `Shell/SurfaceTabBar.swift` (shell): one line,
  `.phosphorFocusable(cornerRadius: 27)` on the tab button.
- `StreamDeckGridView.swift` (classic deck): the no-match empty state swap.
- `AppShortcutsSheet.swift`: spinner → dot wave (a separate toolbar item).
- `Settings/SettingsConnectionSection.swift`: spinner → dot wave (one line)
  and the Macs empty state.
- `Settings/SettingsPairingSection.swift`: the Macs empty state.
- `DeckHandLoadingStateView.swift`: `DotScan` → `DotWave`.
- `Core/Sources/PixelHandCore/Design/PixelTransitionPlan.swift` and
  `Core/Tests/PixelHandCoreTests/PixelTransitionPlanTests.swift`: new files.
- The UX suggest lane's (`Deck/**`, Deck surface) and the Mac panel lane's
  files are untouched.

## Follow-ups

- Switching Macs should add the 12 pt slide to the dissolve once Mac
  switching exists (1.3, UX-030).
- Per-dot power-on jitter inside the hand's `Canvas`
  (`PixelTransitionPlan.powerOnDelay`) for launch and pairing success.
- Use `.powerOn(when:)` for Pro unlocked when the paywall closes (Store lane).

Lane: READY TO MERGE
