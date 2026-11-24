# Owner review of the build 18 visual QA (2026-11-25)

The owner reviewed the gallery (https://claude.ai/artifact/EWnkLTGtb5bpXMHrGFJnzB)
and `VISUAL-QA-build18.md`. They agree with the findings and the direction.
Fix all 82 VQ items, and fold in the points below. OR-01 to OR-15 are
understood; build them now. OR-16 is a new feature. Its open questions are
at the end; don't start it until the owner answers them.

Work P1 → P2 → P3. Mark VQ and OR IDs done in each lane's handoff. Re-check on
the iPad Pro 11" simulator: portrait, landscape, and a Stage Manager window
dragged down to iPhone width. That replaces separate iPhone simulators until
the iPad version is finished.

## Rule for glyphs, dots and loaders (applies everywhere)

The owner sees "too many glyphs" and dot effects. From now on:

- **Selection is shown by colour and fill only.** No extra dot or indicator
  under a selected tab, chip or row.
- **The dot-matrix loader is only for real waiting.** Use it for an Ask plan
  running several steps, waiting on the Mac, a stuck or slow step, or a
  connection. Never use it for running a shortcut or chip, switching tabs, or
  opening an app. Those get the press highlight and a haptic, nothing else.
- **Buttons say what they do with no trailing "…" or dots.** Write "Forget",
  "Pair a device" and "Pair", not "Forget…".
- **Motion stays simple.** Panels and status rows fade in and out (150–200 ms,
  ease-out). Nothing flows in from the bottom. Reduce Motion gets an instant
  change.

## iOS / iPadOS

- **OR-01, tab bar dot.** Remove the 4 pt selection dot under the active tab
  in the compact tab bar. The tint and glass fill already show the active
  tab. File: `DeckHandiOS/Shell/SurfaceTabBar.swift` (`TabDot`, line ~84).
- **OR-02, chip dots.** Remove the three-dot row under every shortcut chip
  in the context strip and the quick-action chips. Files:
  `DeckHandiOS/DesignSystem/ContextChip.swift`, `Shell/ContextStrip.swift`,
  `QuickActions/QuickActionsChips.swift`. Running a chip gets the press
  state and a haptic only.
- **OR-03, Pro upsells.** Stop showing the large "Try 2 weeks free" upsell
  cards in the free plan's surfaces (deck, screen, Ask; see VQ-025 and
  VQ-026). A Pro feature shows a small lock glyph or "Pro" tag on the control
  itself. The paywall opens only when the user taps a Pro feature or goes to
  Settings › Subscription. Make sure the paywall does open from there
  (VQ-055). Files: `Store/RequiresPro.swift`, `Surfaces/DeckSurface.swift`,
  `Surfaces/AskSheet.swift`, `Settings/SettingsSubscriptionSection.swift`.
- **OR-04, Macs sidebar too wide.** The sidebar is 232 pt
  (`Core/.../Design/LayoutMetrics.swift` `sidebarWidth`). It only switches
  Macs, so make it narrower (about 168–184 pt) with compact Mac cards, and
  give the canvas the space. Update `CanvasPlan` and its Core tests.
- **OR-05, sidebar button jumps.** Hiding the sidebar moves its button from
  the leading edge to the trailing group, next to Settings
  (`Shell/ShellHeader.swift` `onShowSidebar`, line ~96). The show and hide
  button must stay in the same leading spot in both states.
- **OR-06, right column: collapsible, with Ask.** The right column (the
  deck/shortcuts for the front app) can't be hidden. Add a collapse button;
  collapsed, it leaves a slim edge handle. Remember the state per
  arrangement. Give the column a two-way switch, **Deck | Ask**, so Ask
  (⌘K) can run in place there as well as in its sheet. The Ask switch shows
  the typed request, the plan, and the step-by-step run, which is where the
  dot-matrix loader belongs. Files: `Shell/PixelHandShell.swift`,
  `Shell/ControlSurface.swift`, `Surfaces/AskSheet.swift`, Core
  `CanvasPlan` and `ArrangementPreset`.
- **OR-07, Stage Manager.** Inset the header so the window controls never
  cover the Mac pill (VQ-080). At compact width, fold the four header
  buttons into one More button and truncate the Mac name at the end, not
  "M…ro" (VQ-081).

## Mac menu-bar panel

- **OR-08, Devices / Paired / Pair a device is confusing.** Today the panel
  has three parts: "Devices" (connected now), "Paired" (trusted, may be
  offline) and "Pair a device…". Make it one list, **Devices**. Each row is
  an iPad or iPhone with its state: *Connected* (live pixel), *Paired · not
  connected* (dim), or *Asking to connect* (amber, with Allow / Pair /
  Deny). One "Pair a device" button sits under the list. "Forget" lives
  in each row's menu (or appears on hover), not as a row of buttons. Remove
  the separate Paired section. Files: `DeckHandMac/MacMenuBarView.swift`,
  `Pairing/PairingMenuSection.swift`.
- **OR-09, panel animation.** When the panel opens, the green permission and
  connection dots flow in from the bottom. Replace that with a plain fade
  (see the rule above). Files: `MacMenuBarView.swift`, `UI/MacPixelViews.swift`.
- **OR-10, Pair window: QR icon off-centre.** The hand tile in the middle of
  the QR code isn't centred, probably because the glyph's height doesn't
  match its frame. Centre it exactly on the QR's centre module. File:
  `Pairing/PairDeviceWindow.swift` (`MacGlyphTile` overlay, line ~116).
- **OR-11, last digit faded.** The faded last digit is on purpose: it's the
  check digit, drawn at 45 % opacity (`PairDeviceWindow.swift` ~228–240).
  The owner read it as a bug, and the user has to type it anyway. Draw
  every digit at full brightness. Use one code format everywhere: the Mac,
  onboarding and the entry field (VQ-029, VQ-030).
- **OR-12, ellipses.** Drop "…" from Forget…, Pair…, Pair a device…, Revoke…
  and every other button on the Mac and iOS. Update the iOS hint that says
  "choose “Pair a Device…”" (`DeckHandiOS/Pairing/PairingQRScannerView.swift`,
  `PairingCodeEntryView.swift`) to match the new label.
- **OR-13, Transfers tab.** With 5–6 files moving, the transfer rows push
  everything else off the panel. Add a **Transfers** tab or segment next to
  Devices. It appears only while transfers exist or finished in the last
  hour, with a count badge. The Devices view shows one summary row ("3 files
  sending · 42 %") that opens the tab. Test it for real with 6 files in both
  directions, including a cancel and a failure. File:
  `DeckHandMac/Transfer/MacTransferService.swift` and the panel views.

## Widgets and Control Center

- **OR-14:** VQ-070 to VQ-079 (strip names, the apostrophe in the dot font,
  the Lock Screen overflow, glyph-based Control Center symbols with cobalt
  tint, and Deck Key with an empty deck).
- **OR-15:** Under the glyph rule, the widgets keep their dot glyphs because
  they are the product's identity there. Just don't add more dots.

## OR-16 (new feature): drive the Mac from the screen picture

In the screen-only arrangement (the mirror full size, no trackpad below it),
the user can watch but not move the pointer. Add **pointer control on the
picture**:

- A toggle in the mirror's floating toolbar, beside PiP, sound and Spaces.
  It shows the pointer glyph and is lit when on.
- When it's on, the picture works like a trackpad, not a touchscreen. A
  finger anywhere on the picture moves the Mac pointer *relative* to where
  it already is, using the trackpad's acceleration. The finger can start
  anywhere, even far from the pointer, so it never covers what it's aiming
  at. A tap clicks, a two-finger tap right-clicks, two fingers scroll, and
  resting until it buzzes then moving drags. These are the same gestures
  and code as the Pointer surface (`UX-004`), reused.
- Show the Mac cursor in the picture (the stream already carries the
  position, `mirror.moveCursor`), plus a faint ring where the finger is.
- When it's off, the picture behaves as it does today (pinch to zoom, pan).
- iPad first; the iPhone's Screen tab next.

### Questions for the owner before OR-16 starts

1. **On or off by default** when the screen-only arrangement opens?
   Recommended: off the first time, then remember the last choice.
2. **Pinch to zoom while control is on:** keep pinch for zooming the
   picture (two fingers still scroll the Mac), or turn zoom off while
   controlling? Recommended: keep pinch for zoom.
3. **A "tap where you touch" mode** (the pointer jumps to the finger, like a
   touchscreen) as a second option, or only the trackpad style?
   Recommended: trackpad style only for now.

## Suggested lanes (max 3 running, per COORDINATOR.md)

1. **iOS layout, wording, polish:** VQ Layout and Wording items, OR-01,
   OR-02, OR-04, OR-05, OR-07, OR-12 (iOS strings), and the widget text
   (VQ-070 to VQ-075).
2. **Behaviour and flows:** VQ Behaviour and Responsiveness items
   (VQ-001, VQ-003 and VQ-037 first), OR-03, OR-06, VQ-078.
3. **Mac panel, motion, identity:** OR-08 to OR-13, VQ Loading and
   animation and Visual identity items, VQ-076 and VQ-077.
4. **Later (after the owner's answers):** OR-16.

Then build 19 for the Mac and the iPad, and run the PixelHandUITests walk
plus the manual iPad pass again.
