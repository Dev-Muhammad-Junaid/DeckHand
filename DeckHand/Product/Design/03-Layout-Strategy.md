# 03 · Layout strategy for the control surface

Mockups of the recommended option: https://claude.ai/artifact/Aa8KTJubKeqahy3cmSjRTm

## 0. The parts every option arranges

| Part | What it is | Today |
| --- | --- | --- |
| **Pointer** | The trackpad (`PixelSurface` + `MultiTouchTrackpad`), with an optional Click / Right-click strip | Trackpad tab |
| **Screen** | The mirror: floating tile, docked pane, full screen, PiP | Floating thumbnail |
| **Deck** | Pages of keys; follows the front app (Deck 2, 1.2) | Apps tab + shortcuts sheet |
| **App dock** | The Mac's running apps in Cmd-Tab order, with running dots; keyboard button | App pill + switcher menu |
| **Context strip** | Dialog buttons first, then front-app chips, then suggestions | Quick Actions bar |
| **Ask** | Command bar (1.4); app and action search before that | – |
| **Capture** | Full screen, region, window, read text | Toolbar capture menu |
| **Mac switcher** | Mac pill → My Macs; sidebar on iPad (1.3) | Disconnect + picker |
| **Settings** | Sheet | Sheet |

Size classes come from `LayoutMetrics` (`03-UX-Guidelines.md` §1, product
branch): width `compact < 500 ≤ medium < 900 ≤ wide`, height `short < 500 ≤
tall`. Device names below are examples, never conditions.

Target sizes (points):

| Space | Size | Class |
| --- | --- | --- |
| iPhone SE / 16e portrait | 375 × 667 / 390 × 844 | compact × tall |
| iPhone 17 Pro portrait | 402 × 874 | compact × tall |
| iPhone landscape | 874 × 402 | medium × short |
| iPhone Duo cover | 466 × 678 | compact × tall |
| iPhone Duo open (book) | 951 × 669, crease at x ≈ 475, 40 pt division when half-folded | wide × tall, **two-pane** |
| iPhone Duo half-folded (laptop) | 669 × 951, crease at y ≈ 475 | medium × tall, **top/bottom** |
| iPad Air 11″ portrait / landscape | 820 × 1180 / 1180 × 820 | medium × tall / wide × tall |
| iPad ½ Split View | ≈ 590 × 820 | medium × tall |
| Slide Over / ⅓ split / small Stage Manager | 320–500 wide | compact |
| PiP | system-sized floating video | – |

iPhone Duo point sizes are Sill's iOS 27.1 simulator measurements; Apple
confirms 7.6″ inner / 5.4″ cover diagonals and a shared aspect ratio. Read the
real fold from `onHingeChange` / the layout geometry's `.division` reserved
region, never from the model.

---

## Option A · Dock & Canvas (recommended)

**Idea.** One canvas shows one surface at a time on compact widths. A glass
**tab bar** switches Pointer / Screen / Deck and holds **Ask** in the search
slot. Above it, the **app dock** is the tab view's bottom accessory, and the
**context strip** sits between canvas and dock. When the space allows, the
canvas splits into panes; on iPad a **Macs sidebar** appears and the tab bar
is replaced by layout presets.

SwiftUI shape: `TabView` (`.sidebarAdaptable` on iPad) with three `Tab`s and a
`Tab(role: .search)`; `.tabViewBottomAccessory { AppDock() }`;
`.tabBarMinimizeBehavior(.onScrollDown)` for the Deck tab only (the trackpad
never scrolls, so it never minimises by accident); a `CanvasLayout` view
switches arrangement from `LayoutMetrics`.

| Space | Arrangement |
| --- | --- |
| **iPhone portrait** | Header (Mac pill · capture · more) → canvas (one surface) → context strip → app dock → tab bar + Ask. Pointer: trackpad fills the canvas, mirror floats top-trailing. Screen: mirror docked at top (follow-cursor zoom), trackpad below. Deck: page grid, 4 columns. |
| **Small iPhone (≤ 667 tall)** | Tab bar minimised to the current surface + Ask; app dock folds into a leading app chip in the strip; the click strip hides (gestures still work). |
| **iPhone landscape** | Header, tabs and Ask move into a 60 pt **leading rail**. Canvas splits: Pointer (≈ 60 %) + Deck column (≈ 40 %, 3 columns) with the context strip on top of the deck column. Mirror floats over the pad. Rail flips to the other side with the Dynamic Island. |
| **iPhone Duo, cover** | Same as iPhone portrait. |
| **iPhone Duo, open flat / book** | **Two panes, 20 pt clear each side of the crease.** Leading pane: Screen (docked, 16:10) over Pointer, app dock at its foot. Trailing pane: header, context strip (wraps), deck, tab bar + Ask. The selected tab picks which surface leads the left pane. |
| **iPhone Duo, half-folded (laptop)** | Top half: header + Screen. Crease: empty. Bottom half: strip, Pointer, tab bar. Like a tiny MacBook. |
| **iPad portrait / ½ Split View (medium)** | Screen across the top; below, Pointer and Deck side by side (portrait) or stacked with a drag handle (½ split). Strip and app dock at the bottom; Ask as a glass button. |
| **iPad landscape / large Stage Manager (wide)** | Macs sidebar (collapsible, 1.3) · centre column: toolbar (Mac pill, layout presets *Split / Screen / Pointer*, Ask field ⌘K, capture, more) → Screen → Pointer, with the app dock floating at the bottom like the Mac Dock · trailing Deck column 320–380 pt with the dialog card and chips on top. |
| **Slide Over / ⅓ / narrow window** | iPhone portrait layout. |
| **External display** | Screen goes to the external display; the iPad shows Pointer + Deck. |
| **PiP** | Leaving the app while Screen is live starts PiP automatically (§PiP below). |

**Where things live.** Trackpad: canvas (Pointer) or bottom pane. Mirror:
floating tile on Pointer, docked on Screen, pane on wide. Deck: Deck tab or
trailing column. Apps: app dock (running) + Ask (search all apps). Chips:
strip above the dock; card on top of the deck column on iPad. Capture: header
button (tap = default, menu for others) and the mirror toolbar. Settings:
"more" menu → sheet. Switching Macs: Mac pill (tap = My Macs sheet, swipe =
next Mac), three-finger swipe on the trackpad, ⌘1–⌘4, sidebar on iPad.

**Trade-offs.** + Every control is one tap from the thumb on iPhone; uses
standard iOS 26 components (less custom code, free accessibility and glass
behaviour); maps onto today's two tabs and floating mirror, so the rebuild is
incremental; panes grow naturally to Duo and iPad. − The bottom of a small
iPhone stacks three rows (strip, dock, tabs), solved by minimising; the tab
bar's look is Apple's, so brand character comes from the canvas, dots and
type rather than the chrome.

## Option B · Columns (Macs | surfaces | context)

**Idea.** A three-column `NavigationSplitView`: Macs, then that Mac's
surfaces (Pointer, Screen, Deck pages, Captures, Inbox), then the chosen
surface with its context. On iPhone it collapses to a stack: My Macs → Studio
→ Pointer.

| Space | Arrangement |
| --- | --- |
| iPhone portrait / Duo cover | Stack of three levels; a toolbar in the detail view holds chips and the dock. |
| iPhone landscape | Two columns (surfaces list hidden behind a button), detail fills. |
| Duo open | Surfaces list + detail; Macs behind the back button. |
| Duo laptop | Detail only, list as a popover. |
| iPad portrait / ½ | Two columns (surfaces + detail); Macs as overlay. |
| iPad landscape | All three columns; detail ≈ 55 % of the width. |
| Split / Stage Manager | Collapses by width like a stock split view. |
| PiP | Same as A. |

**Trade-offs.** + The most iPadOS-native; multi-Mac, Inbox and captures have
an obvious home; easy to reason about. − On iPhone, controls sit two levels
deep, which breaks "one tap beats a trip"; the columns take width from the
mirror and trackpad exactly where they need it most; switching surfaces is a
navigation, not a toggle, so you lose your place.

## Option C · Modules (user-arranged layouts)

**Idea.** The canvas is a grid of resizable modules: Pointer, Screen, Deck
page, Chips, Media, Mac card, Keyboard, Clipboard. People arrange them and
save a layout per size class; presets ship for each device.

| Space | Arrangement |
| --- | --- |
| iPhone portrait | Preset: Screen tile + Pointer + Chips; swipe between saved layouts. |
| iPhone landscape | Two modules side by side. |
| Duo open | Up to four modules, two per half. |
| Duo laptop | Screen module pinned on top. |
| iPad | Up to six modules, free resize. |
| Split / Stage Manager | Layout per window size bucket. |
| PiP | Same as A. |

**Trade-offs.** + Most flexible; closest to Stream Deck; power users love it.
− Highest design, build and test cost (modules × size classes × Dynamic
Type); discoverability suffers ("where did the trackpad go?"); easy to recreate
the wall of tiles the owner wants to get rid of; layouts don't survive moving
between devices without a reflow model anyway.

## Recommendation

**Build Option A.** Take two ideas from the others:

1. From B: the **Macs sidebar** on wide windows (1.3) and the My Macs sheet on
   compact ones. It is the only part of B that earns its width.
2. From C: **layout presets** on wide windows and on Duo (Split, Screen focus,
   Pointer focus, Deck focus), remembered per Mac and per size class. They use
   the same pane model, so free-form modules can come later without a rewrite
   if people ask for them.

Why: A keeps every frequent action one tap from the thumb on the device most
people hold (iPhone), it uses the iOS 26 components Apple is investing in, and
it degrades and grows cleanly across every size above. It also maps onto the
existing code (two tabs + floating mirror) so the redesign can land in slices.

## Mac switching (all options, specified for A)

- **Mac pill** (header): name, front app, live pixel, chevron. Tap → My Macs
  sheet (compact) or focuses the sidebar (wide). Swipe left/right on the pill
  → previous/next Mac, with a 240 ms slide of the canvas.
- **Three-finger horizontal swipe** on the trackpad: next/previous Mac when
  "Swipe between Macs" is on (default on when 2+ Macs are paired; otherwise the
  gesture stays the Mac's Spaces swipe).
- **⌘1–⌘4** with a hardware keyboard; ⌘` cycles.
- Each Mac keeps its own surface, deck page, mirror layout and preset.
- Glancing Macs show alerts in the pill as a small warning dot and a toast:
  "MacBook Air has a dialog waiting · Show".

## Picture in Picture

- Start: automatic only (`canStartPictureInPictureAutomaticallyFromInline`)
  when the user leaves the app while Screen is live, plus a PiP button in the
  mirror toolbar (user-initiated). Never started in code otherwise.
- Content: `AVSampleBufferDisplayLayer` fed by the decoded stream (1.1 HEVC
  path); the **cursor must be composited into the frames** because no app UI
  draws over PiP.
- Controls: play/pause = freeze picture, keep session; no skip
  (`requiresLinearPlayback`); live range (`timeRangeForPlayback` infinite).
- Ends: tap to return to the app on the Screen surface; 10 min paused, device
  lock, or session end closes PiP.
- Needs the "Audio, AirPlay, and Picture in Picture" background mode and the
  `.playback` audio session; review risk is moderate (see
  `04-Interaction-Model.md` §8.4).
