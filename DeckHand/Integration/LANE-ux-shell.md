# Lane: UX shell (UX-005, UX-008 remainder, Settings redesign)

Branch `claude/pixelhand-lane-ux-shell`, merged with
`origin/claude/pixelhand-integration` at `f8eb74b` (includes the UX Pointer
lane). No protocol change, no `project.yml` or Info.plist change (new files
are picked up by folder; one file deleted).

## What changed

### UX-005 Context strip and app dock

The shell's bottom chrome is now, from the top: (keyboard panel when open) →
**context strip** → **app dock** → tab bar + Ask. That's the board's order
(`.strip`, `.adock`, `.sdock`) and Option A's; the brief said "under it"
for the strip, the board puts the strip above the dock, and the board wins.

- **Core** (`Core/Sources/PixelHandCore/Design/`):
  - `AppDockPlan`: the dock keeps the Mac Dock's rule — an app keeps its
    slot while it runs, new apps join at the end in Cmd-Tab order, quit
    apps leave (the raw Cmd-Tab order reshuffled under the thumb on every
    switch). Entries mark the front app and a dialog on it; the front app
    is always shown even before the running list catches up.
  - `ContextStripPlan`: dialog → its buttons (default first on compact,
    Mac order on medium/wide); text field focused → 3 app chips + text
    editing; otherwise up to 6 app chips; no front app → idle; free plan →
    media keys + "App chips · Pro". Spoken container label.
  - `ChordText` (`⌃⌥⇧⌘` order) and `VersionLine` (dot-matrix-safe).
  - Tests: `ContextStripAndDockTests.swift`. **588 Core tests pass** on
    Linux; `Scripts/linux-typecheck/run.sh` builds.
- **`Shell/ContextStrip.swift`**: scrolling row of `ContextChip`s with a
  trailing fade (`.fade-r`), per-chip delivery receipts (`sendConfirmed`),
  "+ Shortcuts" (dashed) opening the app's shortcuts sheet, the dialog's
  title as a 2-line label before its buttons. Bands: standard one row;
  large two rows (chip stacks its chord); huge one "Actions" button with a
  menu. On short windows (< 700 pt tall) the dock **folds** into a leading
  app chip (front app icon + chevron; menu of running apps and
  "Shortcuts for …"), as the board's iPhone SE.
- **`Shell/AppDock.swift`**: glass capsule 56 pt; 36 pt icons; 4 pt running
  dots (`ink3`, front app mint with glow and a 2 pt accent ring); warning
  pixel on the front app while it shows a dialog; hairline; keyboard button
  (36 pt circle, 44 pt target, lit accent while open). Tap = bring to
  front; touch and hold = Bring to front, Shortcuts, Hide (⌘H), Quit (⌘Q),
  also as VoiceOver actions; Large Content Viewer on icons. Hide/Quit go
  through `appShortcut`, which activates the app first on the Mac.
- **`PixelHandShell`**: hosts strip, dock, keyboard panel
  (`RemoteKeyboardPanel`), the shortcuts sheet; dock order in `@State`,
  updated `onChange(of: runningBundleIDs)`. The strip cross-fades when its
  kind changes (dialog / field / app).
- **Deck**: `StreamDeckGridView(showsQuickActions:)` (default `true`); the
  shell passes `false`, so the deck no longer shows its own Quick Actions
  bar or the numpad/keyboard FABs inside the shell. The classic layout is
  unchanged.
- `ContextChip`: empty title draws glyph-only; new `accessibilityTitle`.

### UX-008 remainder

- Mac pill **tap → My Macs** (`Shell/MyMacsPlaceholderSheet.swift`): the
  connected Mac as a card (navy 16:10 tile, live pixel, 2 pt cobalt ring),
  other paired Macs dimmed, a note that switching arrives in 1.3, and
  Disconnect. Two columns, one at AX1+.
- **Swipe placeholder**: horizontal drag on the pill follows with
  resistance (±24 pt, none under Reduce Motion), springs back, and past
  40 pt opens My Macs with a selection haptic.
- **`HostCapabilityBanner` retired**: the classic layout uses `StatusPill`
  (same copy as the shell) and `Control/HostCapabilityBanner.swift` is
  deleted.

### Settings redesign

- `SettingsView`: Geist title, accent Done, canvas behind `raised` grouped
  sections, 24 pt section spacing, 52 pt minimum rows, accent tint for
  pickers/sliders, success (mint) switches; the dot-matrix version line
  (`PIXEL HAND 1.1 - 52`, spoken "Pixel Hand version 1.1, build 52") under
  the last section.
- New **per-Mac section first** (`Settings/SettingsMacSection.swift`,
  board "STUDIO"): the connected Mac with its link badge, Play the Mac's
  sound, Follow the cursor. Hidden when no Mac is connected.
- `SettingsBuildingBlocks.swift`: `.phSettingsSection()` (applied by
  `SettingsView` to every section, so **other lanes' sections are
  restyled with no edit**), `.phSettingsList()`, `SettingsSectionHeader`,
  `SettingsRowIcon` (30 pt navy glyph tile), `SettingsRow` (tile, title,
  subtitle, trailing; trailing moves under the title at AX3+, tile drops),
  `SettingsValueText` (tabular), `SettingBlock` (restyled: scale spacing,
  value under the title at AX3+), `SettingsVersionLine`.
- My sections restyled: Appearance, Apps, Privacy, About (glyph headers,
  glyph rows).

**One-liners for the owning lanes** (optional; the list colours already
apply). In each `header:` closure replace `Text("…")` with:

| Lane | File | One-liner |
| --- | --- | --- |
| Mirror | `SettingsMirrorSection` | `SettingsSectionHeader("Live mirror", glyph: PixelGlyphs.screen)` |
| Mirror | `SettingsCaptureSection` | `SettingsSectionHeader("Screenshots", glyph: PixelGlyphs.capture)` |
| Pointer | `SettingsPointerSection` | `SettingsSectionHeader("Pointer and gestures", glyph: PixelGlyphs.pointer)` and `SettingsSectionHeader("Clipboard", glyph: PixelGlyphs.paste)` |
| Network | `SettingsConnectionSection` | `SettingsSectionHeader("Connection", glyph: PixelGlyphs.wifi)` and `SettingsSectionHeader("Remote Access", glyph: PixelGlyphs.vpn)` |
| Pairing | `SettingsPairingSection` | `SettingsSectionHeader("Paired Macs", glyph: PixelGlyphs.mac)`; in `row(_:)`, `Image(systemName: mac.kind.systemImage)…frame(width: 24)` → `SettingsRowIcon(glyph: PixelGlyphs.mac)` |
| Store | `SettingsSubscriptionSection` | `SettingsSectionHeader("Subscription", glyph: PixelGlyphs.add)`; `DeckHandTheme.warning` → `PixelHandTheme.warning` |

## Checks on the Mac build (against the board)

Light and dark for each; then Larger Text at AX1 and AX3.

**iPhone 17 Pro (402 × 874), Pointer** (board "Pointer"):
1. Under the pad: the strip (chips 44 pt, 8 pt apart, 16 pt leading
   margin, trailing fade), then the dock (glass capsule, 12 pt side
   margins), then the tab bar. The pad's own keyboard circle is gone; the
   dock's keyboard button opens the keyboard panel above the strip and
   lights accent; tap again closes it.
2. Bring Xcode to the front on the Mac: its icon gets the accent ring and
   a mint dot; Xcode's chips show with chords (`⌘B`); tapping one lights
   the dots, then a check (mint) or a cross. Switch to Safari on the Mac:
   the dock **doesn't reorder**, only the ring and mint dot move.
3. Launch a new app on the Mac: it appears at the dock's end. Quit it: it
   leaves.
4. Touch and hold a dock icon: Bring to front, Shortcuts, Hide, Quit (Quit
   red). Hide and Quit act on that app.
5. Save dialog on the Mac (TextEdit ⌘S on a new doc): the strip shows the
   title label then **Save first** (cobalt with ring, `↩`), then Cancel
   (`esc`), Don't Save; the front app gets the amber dialog pixel. Press
   Save: dots, then the strip returns to chips.
6. Click into a text field on the Mac: 3 app chips, then Cut, Copy, Paste,
   Undo … Return with chords.
7. Free plan (sandbox, no subscription): strip shows ‹ ▶ › media chips and
   the dashed "App chips · Pro" chip, which opens the paywall.
8. Deck tab: no "QUICK ACTIONS" bar and no floating numpad/keyboard
   buttons inside the shell; More → classic layout still has both.
9. AX1: strip wraps to two rows, chords under labels. AX3: strip is one
   "Actions" button with a menu; dock icons show the Large Content Viewer
   on long-press.

**iPhone SE (375 × 667)** (board "iPhone SE"): no dock; the strip starts
with the app chip (icon + chevron) whose menu switches apps; the pad's own
keyboard circle is back (no dock to hold it). Dialog with three long
titles: scrolls, never clips.

**iPhone landscape (874 × 402)**: rail as before; no strip or dock yet
(UX-007). Pad keyboard circle shown.

**iPad 11″ portrait (820 × 1180)** and **½ Split View (590 × 820)**: strip
and dock above the tab bar, max width 720, dialog buttons in the Mac's
order (default last). **iPad landscape**: same chrome under the centre
column; deck column unchanged.

**Header / My Macs**: tap the Mac pill → My Macs sheet (medium/large):
connected Mac card with ring and mint pixel; other paired Macs dimmed; the
1.3 note; Disconnect (red) ends the session. Swipe the pill sideways: it
follows a little, springs back, opens My Macs. Reduce Motion: no follow.

**Classic layout**: revoke Accessibility on the Mac → amber `StatusPill`
"<Mac> needs Accessibility." under the toolbar instead of the old banner;
lock the Mac → locked pill.

**Settings** (board "Settings", 402 × 874): Geist "Settings" title, Done;
first section is the connected Mac (name header with Mac glyph, row with
lit Mac tile and link badge, two switches); sections on `raised` with
hairlines over the canvas; switches mint; segmented pickers cobalt;
Appearance/Apps/Privacy/About headers with glyphs; dot-matrix version line
centred at the foot (VoiceOver reads "Pixel Hand version …"). AX3: row
values move under titles, glyph tiles drop, nothing truncates mid-word.
No Mac connected: the Mac section is absent.

## Compile risks (most likely first)

SwiftUI can't be type-checked on Linux; every changed file passes
`swiftc -parse`, Core is tested, the Linux type check builds.

1. `Shell/ContextStrip.swift`: `StripItem.title`'s `switch self` with
   nested patterns (`case .media(.previous):`) as an expression; the
   `@ViewBuilder` `leading` with `if case .dialog(let title, let message, _)
   = mode, …, let text = …` (multi-clause `if case`); `StripChip.body`
   switch returning different view types (relies on `body`'s implicit
   `@ViewBuilder`). If needed, wrap branches in `Group` / `AnyView`.
2. `PixelHandShell.bottomChrome`: `let` bindings inside an `if let` in a
   `@ViewBuilder`; `.sheet(item: $shortcutsApp)` content with `if let`;
   `onChange(of:initial:)` (iOS 17).
3. `SettingsBuildingBlocks`: `AnyLayout` with `let layout = cond ? … : …`
   inside a `VStack` builder; `SwitchToggleStyle(tint:)` (deprecated, a
   warning); `.listSectionSpacing` (iOS 17); `environment(\.defaultMinListRowHeight, …)`.
4. `SettingsView`: `.phSettingsSection()` on a `Group` of sections inside
   `Form` (list-row modifiers should reach every row; if a section's rows
   stay default, move the modifier onto each section call).
5. `AppDock`: `.accessibilityAddTraits` twice; `.contextMenu` on a `Button`
   with `ChipPressStyle`; `ScrollViewReader.scrollTo` inside `onChange`.
6. `SettingsMacSection.linkBadge`: switch over `LinkKind?` with
   `case .some:` after specific cases.
7. `ShellHeader`: `.simultaneousGesture(DragGesture)` on the pill button;
   `MacPill(…, action:)`.

## Out-of-lane edits

- `DeckHandiOS/Surfaces/PointerSurface.swift` (UX Pointer): new
  `var keyboardInDock = false`; when true, `chromeLayer` (the corner
  keyboard circle) isn't drawn. The shell passes `true` whenever the dock
  shows (not on short windows or the rail). This is the follow-up the
  Pointer lane asked for; its internal keyboard panel and VoiceOver action
  are untouched.

Everything else is in this lane's list: `Shell/**`, `DesignSystem/ContextChip.swift`,
`ControlView.swift`, `Control/HostCapabilityBanner.swift` (deleted),
`StreamDeckGridView.swift`, `SettingsView.swift`,
`Settings/SettingsBuildingBlocks|Appearance|Apps|Privacy|About.swift`, the
new `Settings/SettingsMacSection.swift`, Core `Design/**` + one new test
file. `ControlSessionModel` is read only. No other lane's Settings section
was edited.

## Follow-ups

| Ticket | Owner | Notes |
| --- | --- | --- |
| **UX-007 Arrangements** | Design | Not started. Rail: strip on top of a deck column, dock folded (pad ≥ 300 pt on 874 × 402); `.split`: Screen over Pointer + Deck with a drag handle; `.columns`: dialog card + chips on top of the deck column, dock floating at the centre column's foot; presets per Mac; external display. `LayoutMetrics.arrangement` is the switch; the strip/dock are self-contained views that can move. |
| Settings one-liners | Mirror, Pointer, Network, Pairing, Store | Table above. |
| Strip long-press | Design (UX-020) | Pin to deck, Run on…, Edit on chips. "+ Suggest" when UX-021 lands; today "+ Shortcuts". |
| Dock "Send to" | Design (UX-031) | Long-press item, 1.3. |
| Numpad / text editing page | Deck 2 (UX-020) | The shell drops the FABs; the strip covers text editing. A "Text editing" deck page and the keyboard accessory are still to come. |
| My Macs | Design (UX-030) | Replace the placeholder; real swipe to the next Mac. |
| Volume chips in free strip | Mac system | Board shows volume ±; `MediaKey` has no volume keys. |
| `StatusPixel.needsYou` | Design (UX-014) | Literal amber colour; move to `PixelHandTheme.warning`. |
| Settings per-Mac depth | Design + Network | Mirror quality and VPN per Mac as on the board need per-Mac settings storage. |

Lane: READY TO MERGE
