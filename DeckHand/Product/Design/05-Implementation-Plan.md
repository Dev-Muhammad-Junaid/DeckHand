# 05 · Redesign implementation plan

**When:** after the Sill lanes merge and a green Mac build (COORDINATOR.md
queue item 8). **How:** in slices that each ship a working app.

**Lanes.** `DeckHand/Integration/LANES.md` does not exist yet on
`claude/pixelhand-integration` (checked 17 Nov 2026, `9c07a63`), so these
tickets use the lane table in `DeckHand/Product/05-Backlog.md` §1 (IOS-SHELL,
IOS-INPUT, IOS-DECK, IOS-CAP, MIRROR, MAC-CTX, REL, CORE) and the file splits
that PH-010 creates (`ControlSessionModel`, `CaptureCoordinator`,
`ControlToolbar`, chip files, `LayoutMetrics`). **When LANES.md lands,
re-map the lane column; scope and acceptance don't change.**

New folders (created by UX-001/002, owned by IOS-SHELL unless noted):
`DeckHandiOS/DesignSystem/`, `DeckHandiOS/Shell/`, `DeckHandiOS/Surfaces/`.

## Sequence

```
UX-001 tokens ─► UX-002 components ─► UX-003 shell (tabs + canvas) ─┬► UX-004 Pointer
                                                                    ├► UX-005 context strip + app dock
                                                                    ├► UX-006 Screen surface
                                                                    └► UX-007 arrangements (landscape, iPad, split)
UX-008 header / Mac pill / status pills ◄── UX-003
UX-009 capture sheet          UX-010 onboarding + picker      UX-011 paywall + free tier (with Store lane)
UX-012 Mac panel              UX-013 accessibility pass        UX-014 copy pass
── roadmap, on top of the shell ──
UX-020 Deck 2 UI (D2/D3)   UX-021 AI suggestions (D7)   UX-022 Ask (A1)
UX-030 My Macs + sidebar (M2)   UX-031 Send + Inbox (S1/S2)
UX-040 iPhone Duo panes   UX-041 PiP
```

## Tickets

Each ticket: Swift Testing for logic, the visual QA checklist (end of file) for
every screen it touches, and before/after screenshots at the QA sizes in the PR.

**UX-001 Tokens: `PixelHandTheme`** · IOS-SHELL · S
- Scope: asset-catalog colour sets (Any/Dark/High Contrast) for every
  semantic token; `PixelHandTheme.Brand`; font roles with bundled Geist (OFL
  licence file in `Assets/Fonts/`, `UIAppFonts` in iOS `Info.plist` via REL);
  space, radius and motion constants. Keep `DeckHandTheme` as a deprecated
  forwarding shim until UX-014.
- Files: `Shared/DeckHandTheme.swift` → `Shared/PixelHandTheme.swift`, asset
  catalogs, `project.yml` (fonts, via CORE).
- Accept: contrast tests pass (`02-Design-System.md` §1.2); zero
  `Color(hex:)` outside `Brand`; Geist renders in a preview at AX5.
- Tests: `ThemeContrastTests` (WCAG ratio per pair, both appearances).

**UX-002 Components** · IOS-SHELL (+ IOS-DECK for chip/key) · M
- Scope: `PHButton`, `ContextChip`, `DeckKey`, `AppDock`, `MacPill`,
  `MacCard`, `StatusPill`, `Toast`, `DotBeam`, `PixelSurface`, `EmptyState`,
  `ProBadge` with `#Preview`s for every state, light/dark, AX5. Delivery strip
  replaces `DeliveryDots` (keep its timing).
- Files: `DeckHandiOS/DesignSystem/**`, `DeliveryDots.swift`, `DeckHandEmptyState.swift`.
- Accept: previews match the board within 2 pt; every state reachable; no
  fixed font sizes.

**UX-003 Shell: tabs, canvas, `LayoutMetrics` arrangements** · IOS-SHELL · L
- Scope: replace the segmented picker with `TabView` (Pointer, Screen, Deck,
  `Tab(role: .search)` Ask placeholder); `CanvasLayout` reads `LayoutMetrics`
  and picks the arrangement; `.tabViewBottomAccessory` hosts the app dock;
  state (surface, deck page, mirror fraction) survives arrangement changes and
  scene restoration.
- Files: `ControlView.swift` (post-PH-010 `ControlToolbar`, new `Shell/**`), `ContentRootView.swift`.
- Depends: PH-010, UX-002.
- Accept: rotating, resizing a Stage Manager window from 375 to 1180 pt, and
  entering Split View never loses the selected surface; no `userInterfaceIdiom`
  checks.
- Tests: `LayoutMetricsTests` (class boundaries, deck columns, key size).

**UX-004 Pointer surface** · IOS-INPUT · M
- Scope: `PixelSurface` hosts `MultiTouchTrackpad`; remove the gesture bar and
  sensitivity slider (slider → Settings); add the click strip (hideable);
  caption pill; first-use coach mark for drag and three-finger swipes.
- Files: `TrackpadView.swift`, `MultiTouchTrackpad.swift`, `DotField.swift`.
- Depends: UX-003, PH-033.
- Accept: in iPhone landscape the pad is ≥ 60 % of the window width and ≥ 300 pt
  tall; every gesture has a visible or VoiceOver equivalent.

**UX-005 Context strip and app dock** · IOS-DECK · M
- Scope: split `QuickActionsBar` into `ContextStrip` (dialog → chips →
  suggestions; default-first on compact; wraps at AX) and `AppDock` (running
  apps, running dots, dialog badge, long-press menu, keyboard button). Remove
  the numpad/edit rows and FABs (their keys become a "Text editing" deck page
  and the keyboard accessory).
- Files: `QuickActionsBar.swift` and its PH-010 splits, `StreamDeckGridView.swift` (FAB removal).
- Depends: UX-002, UX-003.
- Accept: a three-button dialog with long titles fits at 375 pt (scrolls, never
  clips); no unlabelled icon buttons; every chip ≥ 44 pt.

**UX-006 Screen surface** · MIRROR · M
- Scope: `MirrorPane` in three modes (floating tile on Pointer, docked on
  Screen, full screen) with the glass toolbar; follow-cursor zoom with minimap
  on compact; Direct/Trackpad toggle; tile anchored to the canvas, not to a bar;
  stats line uses the numerals role.
- Files: `MirrorThumbnailView.swift`, `Mirror/**`.
- Depends: UX-003, PH-020, PH-021.
- Accept: 44 pt close and toolbar targets; mirror errors titled "Live screen
  unavailable" (not "Screenshot Failed"); tile never overlaps the strip or dock.

**UX-007 Arrangements** · IOS-SHELL · M
- Scope: iPhone landscape rail; iPad portrait/medium split with drag handle;
  iPad wide with deck column and floating app dock; layout presets (Split /
  Screen / Pointer) remembered per Mac and size class; external display.
- Depends: UX-004–006.
- Accept: board parity at every size in the QA matrix.

**UX-008 Header, Mac pill, status pills** · IOS-SHELL · S
- Scope: Mac pill (tap, swipe placeholder until 1.3), capture and More glass
  buttons; Disconnect into More; `StatusPill` replaces `HostCapabilityBanner`;
  remove the session id from the UI.
- Depends: UX-002.

**UX-009 Capture sheet** · IOS-CAP · M
- Scope: one sheet with detents: preview → annotate (tools fit 320 pt: colour
  row scrolls or uses a picker) → read text → share/send. Swipe to dismiss;
  Clear asks; region reset always enabled.
- Files: `ScreenshotPreviewView.swift`, `AnnotationView.swift`,
  `OCRResultView.swift`, `RegionCropView.swift`, `WindowPickerView.swift`.
- Depends: UX-002, PH-039.
- Accept: max one modal level from Control; works at 320 pt and AX5.

**UX-010 Onboarding and picker** · IOS-SHELL · M
- Scope: scrollable onboarding (§5 of the interaction model), device-neutral
  copy, coach marks instead of a tour; picker header shrinks so the first Mac
  is visible in landscape; approval card max width 480 pt.
- Files: `OnboardingView.swift`, `PeerPickerView.swift`, `AuthorizationOverlay.swift`.
- Depends: UX-002, PH-030.

**UX-011 Paywall and free tier** · IOS-SHELL + Store lane · M
- Scope: paywall sheet, locked-surface cards, free-tier strip (media keys),
  Settings subscription row, trial reminder. Entitlement from the Store lane's
  StoreKit 2 model.
- Depends: Store lane, UX-003, UX-005.
- Accept: Apple's disclosures present and legible at AX5; Pointer never
  blocked; Restore works from the paywall and Settings.

**UX-012 Mac menu-bar panel** · IOS-SHELL (Mac panel UI) + REL · M
- Scope: 340 pt panel, system text styles, devices with capability chips and a
  visible Disconnect, Pair a device, permissions with live pixels, footer.
  Shared tokens via the asset catalog.
- Files: `DeckHandMac/MacMenuBarView.swift`.
- Accept: follows the Mac's text size; every control keyboard-reachable; no
  hover-only actions.

**UX-013 Accessibility pass** · all iOS lanes · M (extends PH-028)
- Scope: the eight items in `04-Interaction-Model.md` §8; UI tests at AX5.

**UX-014 Copy pass and shim removal** · IOS-SHELL + DOCS · S
- Scope: copy rules (§9); remove `DeckHandTheme` shim; update website mockups
  (`website/tools/mockups/build.py`) to the new UI.

### Roadmap tickets (build on the shell)

| Ticket | Lane | Scope | Depends |
| --- | --- | --- | --- |
| **UX-020** Deck 2 UI | IOS-DECK | Pages, follow/pin, reflowing grid, editor with action library, key inspector, 8 × 8 pixel glyph editor, undo (D2/D3) | D1, UX-005 |
| **UX-021** Suggest a deck | ASSIST | Ghost keys panel, Keep all / tap to keep, deterministic fallback (D7) | UX-020 |
| **UX-022** Ask | ASSIST + IOS-SHELL | Ask tab/⌘K, plan view, Run/Save as key, confirmations (A1–A3) | UX-020, Action model |
| **UX-030** My Macs + sidebar | IOS-SHELL | Mac cards with glance tier, pill swipe, ⌘1–4, three-finger switch, per-Mac state (M1/M2) | PH-112, PH-104 |
| **UX-031** Send + Inbox | IOS-SHELL + REL | Send sheet with dot beam, drop on Mac card, Inbox, incoming prompts (S1/S2) | S1 transfers |
| **UX-040** iPhone Duo | IOS-SHELL | Book (two panes, crease clear) and laptop (top/bottom) arrangements from hinge state; cover = compact | UX-007, iOS 27.1 SDK |
| **UX-041** PiP | MIRROR | `AVPictureInPictureController` with sample-buffer source, automatic start, cursor composited into frames, pause = freeze | PH-103 (HEVC → `AVSampleBufferDisplayLayer`) |

## Visual QA checklist

Run for every PR that changes UI. Screenshots at deviceScaleFactor 2 in light
and dark, attached to the PR.

**Sizes:** iPhone SE 375 × 667 · iPhone 17 Pro 402 × 874 (portrait and
landscape) · iPhone Duo cover 466 × 678, open 951 × 669, laptop 669 × 951 · iPad
11″ portrait and landscape · ½ Split View · Slide Over 320 pt · Stage Manager
window resized live from 375 to full.

**Checks**
- [ ] Colours come only from tokens; no literal hex outside `Brand`.
- [ ] Glow/cyan appears only on navy surfaces and only while live.
- [ ] Nothing lit (cyan or mint) while disconnected.
- [ ] One cobalt primary action per screen.
- [ ] Glass only on chrome; never on the trackpad, keys or mirror picture.
- [ ] Text uses font roles; screen checked at default, xxxLarge, AX5.
- [ ] Every target ≥ 44 pt; no hover-only or long-press-only actions without an alternative.
- [ ] Radii by role (14 chip · 18 key · 24 card · 30 pane · 36 sheet); panes concentric with the window.
- [ ] Spacing from the 4 pt scale; gutters 16/20/24 by width class.
- [ ] Nothing on the iPhone Duo crease (40 pt division clear).
- [ ] Arrangement change keeps surface, deck page, mirror position and selected Mac.
- [ ] Reduce Motion: cross-fades only. Reduce Transparency: solid chrome. Increase Contrast: solid strokes.
- [ ] VoiceOver: labels, values, receipt announcements, container names.
- [ ] Receipts readable without colour (check / cross shapes).
- [ ] Copy is device-neutral and names the Mac; no debug ids.
- [ ] Matches the board (https://claude.ai/artifact/Aa8KTJubKeqahy3cmSjRTm) within 2 pt, or the difference is noted in the PR.
