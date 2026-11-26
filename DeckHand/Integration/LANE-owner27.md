# Lane: owner testing, build 27 (owner27)

Branch `claude/pixelhand-lane-owner27`, from `claude/pixelhand-integration`
at `d8ad7bd` (after the `build27-fixes` merge). It fixes OT-14 to OT-18
from the owner's build 27 test on the iPad Air 11" (landscape, dark)
(`STATUS.md`, "Owner testing (build 27)").

No protocol change (still 16). No `project.yml`, Info.plist, Mac or Loom
change; new files are picked up by the folder sources and the package.

| ID | Sev | Status | Files |
|---|---|---|---|
| OT-14 Badges drawn behind their buttons | P2 | Fixed at the component level (needs an iPad check) | Core `Design/ControlBadgePlacement.swift` (new); iOS `DesignSystem/ControlBadge.swift` (new), `DesignSystem/PHGlass.swift`, `DesignSystem/PHButton.swift`, `DesignSystem/MacPill.swift`, `Store/RequiresPro.swift`, `Store/FreeMacBadge.swift`, `Shell/ShellHeader.swift`, `Shell/MacsSidebar.swift`, `Shell/AppDock.swift`, `Mirror/MirrorPiPViews.swift`, `Keyboard/TypePanel.swift`, `Transfer/TransferHeaderButton.swift` |
| OT-15 Inbox uneven on iPad | P2 | Fixed (needs an iPad check) | Core `Transfer/SendSheetLayout.swift`; iOS `Transfer/TransferSheet.swift`, `Transfer/TransferHeaderButton.swift`, `Transfer/InboxPanel.swift` |
| OT-16 "Send to" names truncated | P2 | Fixed (needs an iPad and iPhone check) | Core `Transfer/SendSheetLayout.swift`; iOS `Transfer/TransferSheet.swift` |
| OT-17 Paste chip looks different | P3 | Fixed as far as the paste control allows (needs an iPad check) | Core `Transfer/SendSheetLayout.swift` (`SourceChip`); iOS `Transfer/SendPasteChip.swift`, `Transfer/TransferSheet.swift` |
| OT-18 Header Ask field → ⌘K button | owner | Built (needs an iPad check) | Core `Design/HeaderAskButton.swift` (new); iOS `Shell/MacsSidebar.swift` (`AskShortcutButton` replaces `AskField`), `Shell/ShellHeader.swift`, `Shell/PixelHandShell.swift`, `Surfaces/AskSheet.swift` |

Docs: `Product/Design/07-Polish-Spec.md` §8 (Send sheet) updated, new §10
(badges) and §11 (header ⌘K button); `06-Pixel-Identity.md` §4 points to
§10. UI walks: `test23` extended, `test25_BadgesAboveGlass` and
`test26_HeaderAskButton` new.

## OT-14 · Badges drawn behind their buttons

**Cause.** Every badge was a plain `.overlay` on its control: the Send
circle's unseen dot (`TransferHeaderButton`, an 8 pt square at the
top-trailing corner), the Pro lock (`requiresPro`, bottom-trailing), the
Mac pill's live light (offset 4 pt off its tile). The header is one
`GlassEffectContainer` (`phGlassGroup`); on iOS 26 the container renders
the glass of all its controls together, and an overlay added *outside* a
control's `glassEffect` ended up under that combined glass. The dot's
inner half was under the circle's glass and its outer half outside it,
so it looked cut off; the free plan's Pro lock had the same fault. The
dock's needs-you light hung 5 pt above its icon inside a horizontal
scroll view, which clips to its own height.

**Fix (component level).**
- **`ControlBadge`** (`DeckHandiOS/DesignSystem/ControlBadge.swift`): one
  modifier, `.controlBadge(kind, style:)`, for every badge on a control.
  Kinds (`ControlBadgeKind`, Core): `dot`, `live`, `needsYou`, `offLight`,
  `proLock`, `proLockSmall`, `proLabel`, `count(n)`.
- **A badge layer above the glass.** `phGlassGroup` now also applies
  `controlBadgeLayer()` *outside* the `GlassEffectContainer`: inside a
  group, a badge only reports its control's bounds (an anchor preference)
  and the group draws all badges in one overlay on top of the container,
  so they can't be covered or clipped by any glass in it. The layer
  clears the preference so an enclosing layer doesn't draw them twice.
  Outside a glass group the badge is the control's own last overlay
  (`zIndex` 1).
- **Presentations.** A sheet inherits the environment, so the flag that
  says "a layer is drawing badges" is cleared for presented content
  (`controlBadgeScope()`: the Send sheet/cover and the Pro paywall).
- **Placement in Core** (`ControlBadgePlacement.frame`): `rim` puts the
  badge's centre on the control's outline at 45° from the corner (circle,
  capsule, rounded-rect arc, rect corner), straddling the edge; `inset(d)`
  puts it inside the corner. The origin is rounded to the 4 pt grid and
  every kind's size is on the grid (dot 8, lights 12 with their 2 pt
  canvas ring, lock 20 / 16, PRO 40 × 20, count 20 or 28 × 20). The Pro
  lock tile grew from 18 to 20 to sit on the grid.
- `GlassCircleButton` takes `badge:`; `requiresPro` takes `badge:` (a
  `ControlBadgeStyle`; default inside the bottom-trailing corner as before).

**Every badge use, checked:**

| Where | Badge | Now |
|---|---|---|
| Header Send circle | unseen dot | `GlassCircleButton(badge: .dot)`, top-trailing rim, header layer |
| Header Screen, Capture, Send circles (free plan) | Pro lock | `requiresPro(…, badge: .circle(.bottomTrailing))`, header layer |
| Mirror toolbar Picture in Picture (free) | Pro lock | `.capsule(.bottomTrailing)`, mirror toolbar's layer |
| Type panel target chip (free) | Pro lock | `.capsule(.bottomTrailing)`, local overlay |
| Other `requiresPro` controls (deck keys, quick actions, context strip, settings rows, empty-state buttons, Type panel paste, old toolbar) | Pro lock | default inset bottom-trailing, local overlay (none are glass inside a group) |
| Mac pill tile (header) | live / off light | `.live` / `.offLight` on the tile's top-trailing rim, header layer |
| Macs sidebar tile | Pro lock (small) | `.proLockSmall` on the tile's bottom-trailing rim |
| Send card tile, My Macs `MacCard`, picker cards | PRO | `freeMacBadge` → `.proLabel` inset 4, top-trailing (stays on the tile, never over the name) |
| Dock icon | needs-you light | `.needsYou` inset 0 inside the icon's corner (was clipped by the dock's scroll view) |
| `MacCard` / sidebar tile live lights | live light | unchanged: already inside the tile with padding, no glass, nothing clips them |
| Send switch's Inbox count, Inbox rows' unseen mark | count / dot | unchanged: inline in their rows, not on a control's edge |

**UI check.** `test25_BadgesAboveGlass` (free plan, landscape and
portrait). The app is launched with `-qa.exposeBadges YES`, which makes
each badge an element `ph.badge.<kind>` (otherwise hidden from
VoiceOver). For each lock / dot on the header's circles it asserts the
badge touches its control, its origin is on the 4 pt grid relative to the
control, and the screenshot pixel at the lock tile's edge (or the dot's
centre) is the badge's own blue (b − r > 60), not washed out by glass.

**Tests (Core).** `ControlBadgePlacementTests` (6): sizes on the grid;
frames on the grid for every shape × size × corner × anchor × kind; the
header dot at (32, 4) on a 44 circle covering the rim and partly off the
glass; the lock at (28, 28) hanging past the circle; rim points for
circle / capsule / rect / off-square circle; inset badges inside the tile.

## OT-15 · Inbox uneven on iPad

**Cause.** Three things.
1. On iPad the sheet was a form sheet "fitted" to the content
   (`presentationSizing(.form.fitted(…))`) whose place is the system's; in
   the columns layout it read as off-centre over the canvas and the right
   column, and its width wasn't on the polish-spec margins.
2. The Inbox was an `.insetGrouped` `List` with its own insets (wider
   than the sheet's 24 pt margin), and "Nothing yet" sat in a list row at
   the top-leading of the panel.
3. The sheet's height came from the *open* tab: Send measured, Inbox
   estimated, so switching tabs resized it. The header's Done text was
   centred in its 44 pt target, so it sat about 6 pt inside the trailing
   margin while the switch sat on the leading one.

**Fix.**
- **iPad: a card centred on the window.** `TransferHeaderButton` presents
  a full-screen cover with a clear background (no slide; the host fades
  the scrim and card in) holding `TransferSheetHost`: a 32 % black scrim
  and the sheet as a card at `SendSheetLayout.floatingFrame` (Core):
  560 wide at most, 24 clear of every window edge, as tall as the content
  allows, centred on the window on whole points, width and height on the
  grid. The container is the whole window less the keyboard
  (`ignoresSafeArea(.container)`), so the card is centred on the window and
  rises with the keyboard. Radius 36, hairline, a soft shadow. Scrim tap,
  Done, Escape (`.cancelAction`) and the VoiceOver escape close it.
  iPhone keeps the system sheet with detents.
- **One size for both tabs.** `SendSheetLayout.sharedContentHeight`: the
  taller of Send (measured, kept while Inbox shows) and Inbox (estimated).
  Both the iPhone detent and the iPad card use it.
- **Header:** the switch on the leading margin, Done's text at the
  trailing edge of its 44 pt target (on the trailing margin), both centred
  on one 44 pt line with 8 above and below (`ph.send.header`).
- **Inbox:** a plain list with rows inset to the sheet's margin (56 pt,
  `raised`, radius 14, 8 apart; swipe to delete kept); the empty state is
  outside the list, centred both ways in the panel (`ph.inbox.empty`).

**iPad checks.** Landscape and portrait, dark: open Send from the header
(and from More when the circles fold): the card is centred on the window,
not on the canvas; Inbox with nothing: "Nothing yet" centred in the card
under the header; switch Send ↔ Inbox: the card doesn't move or resize;
the switch and Done line up with the chips' edges; tap the field: the
keyboard comes up and the card rises, still centred above it; tap the
scrim: it closes; Escape on the Magic Keyboard closes it; an incoming
transfer prompt still shows over it. VoiceOver: focus stays in the card;
the escape gesture closes it.

**Tests.** `SendSheetFloatingTests` (4): shared height; iPad Air 11"
landscape frame (560 × 340 at 310, 240); centred and clear in eight
window sizes (keyboard up included) × five content heights; overflow
stops at the window less its clearance. `test23` now asserts (iPad) the
card centred on the window within 2 pt, at most 560 wide, Send and Inbox
one height and place, "Nothing yet" centred in the panel, and (all
devices) the switch and Done on the chips' margins and on one line.

## OT-16 · "Send to" names truncated

**Cause.** The card grid used the most columns that kept a card ≥ 160 pt
(three on the iPad's 512 pt content), and the name was one line,
middle-truncated: a 162 pt card leaves about 40 pt for the name beside the
44 pt tile and the trailing readout ("Mu…Pro"). Offline Macs were a
different component, a one-line row with "Seen … ago" beside the name,
which truncated "AH's Mac mini …".

**Fix.**
- `SendSheetLayout.cardGrid(width:names:)` (Core): the most columns (up
  to the old maximum) in which **every** name, live and offline, wraps
  between words onto at most two lines in the card's text room (card width
  − 120: insets, tile, gaps and a fixed 32 pt trailing slot); one column
  when none does (then it truncates in the middle, the last resort). Cards
  are one height: 64, or 80 when any name takes two lines. The wrap is
  computed from each word's measured width (`SendCardNames`, subheadline
  semibold at the current text size), the same greedy word wrap the text
  does.
- The card shows the whole name (`lineLimit(2)`), with the status line
  under it and the readout / light in its fixed slot.
- **Offline Macs are the same card, muted:** `fill`, no hairline, the tile
  on `fill2` with the Mac glyph in ink3, the name in ink2, "Seen … ago" in
  ink3 under it, no light; same grid and height, still under the live
  cards and still queuing a send on tap (`ph.send.offlineCard` kept).
- The estimate before the first measure uses the same grid.

**iPad checks.** With "Muhammad Junaid's MacBook Pro" and "AH's Mac mini"
paired (one offline): two columns (or one), the full names on up to two
lines, all cards one height; the offline card muted with "Seen … ago";
AX1–AX3: cards grow, names still whole where a column allows. iPhone:
usually one column.

**Tests.** `SendCardGridTests` (7): short names keep three columns of
64 pt cards; the long name drops a column and gets 80 pt cards with the
name on ≤ 2 lines; cards stay in the grid (whole points, gaps, within the
row) across widths; offline names count; greedy word wrap; a name too
long for any column → one column; the estimate uses the grid. `test23`
asserts all cards (live and offline) one height (≤ 84) and one width,
inside the chips' margins.

## OT-17 · The Paste chip looks different

**Cause.** The Clipboard chip is the system paste control
(`UIPasteControl`, so there's no "Allow Paste" prompt). A paste control
draws its own icon and "Paste" label, in **one** foreground colour and in
its own font; build 26 set that colour to the accent, so Paste had accent
text while Photos and Files had an accent pixel glyph and an ink label in
`.phChip`.

**Fix (what the API allows, and the rest adapted to it).**
- The paste control's `baseForegroundColor` is now `ink` and its
  background `raised` (from `SendSheetLayout.SourceChip`), radius 14, still
  filling its 44 pt chip with the hairline drawn outside it.
- **Photos and Files follow the paste control:** system symbols
  (`photo.on.rectangle`, `folder`, next to the paste control's
  `doc.on.clipboard`) and the label in the same `ink`, and the label in the
  paste control's own font: `SendPasteTargetView.layoutSubviews` finds the
  control's `UILabel` and reports its `font` (reading only; nothing covers
  or is added to the control); until then, and if no label is found,
  subheadline semibold. Re-read when the text size changes.
- Not possible: a pixel glyph or a custom title on the paste control, so
  the three chips now use system symbols rather than pixel glyphs (owner's
  call in the brief: "adapt Photos and Files to match it").

**iPad checks.** The three chips identical: height, fill, hairline,
icon and label colour (ink, no blue text), type size and weight; tap
Paste with text, a link and an image on the clipboard: no "Allow Paste"
alert, items staged as before; AX sizes: labels shrink to 80 % before
truncating. If the label font differs from the paste control's (the
lookup found nothing), say so: it means the control draws its title
without a `UILabel` on this iPadOS.

**Tests.** `SendSourceChipStyleTests` (2): icon and label one token (not
accent), ≥ 4.5:1 on the chip in light, dark and high contrast; the chip
size and radius. `test23` samples the screenshot: the three chips' fills
match within 12 levels at both ends, and no chip has blue (accent) ink.

## OT-18 · The header's Ask field → a compact ⌘K button

**Cause.** The wide "Tell <Mac>…" field (`AskField`) took the flexible
middle of the row through `ViewThatFits`, so its width, and with it the
spacing of everything after it, changed with the window; it only ever
opened the Ask column.

**Fix.**
- **`AskShortcutButton`** (replaces `AskField`): a 44 pt glass capsule,
  at least 80 wide, the Ask glyph and "⌘K", tooltip "Ask (⌘K)" (`.help`
  and the large content viewer), `ph.ask`, ⌘K kept. Its action is the
  shell's same `openAsk(plan)`: the right column (expanded) where there is
  one, else the Ask sheet.
- **State** (`HeaderAskButton.state`, Core): idle; **open** while the
  column shows Ask (a half-strength 2 pt accent ring, VoiceOver "Open");
  **active** while Ask's field has focus (glyph and chord accent, full
  ring, "Open, typing", selected). The field's focus comes from
  `AskPanel(onFieldFocus:)`.
- **Header re-balanced:** the Mac pill (and link badge) lead, then one
  trailing cluster on the 8 pt rhythm: presets, ⌘K, the circles, More.
  The row reserves 88 for the button (`HeaderAskButton.reservedWidth`, was
  52 for the circle fallback) when deciding what folds into More; More
  still has Ask when the button folds.
- **No command palette.** How one would plug in: `HeaderAskButton.Command`
  is the single place that says what ⌘K does (today `.ask`). A palette
  adds a case; `AskShortcutButton` (and its ⌘K) would present the
  palette, with Ask as the first command so typing without picking one
  falls through to Ask; the palette's other sources (apps from the dock
  plan, deck keys, the More menu's commands, Macs from `MacSwitcher`)
  are already Core models. The dock's `AskCircleButton` also binds ⌘K
  in the side-by-side layout and would switch with it.

**iPad checks.** Landscape: the header shows pill · presets · ⌘K ·
screen · capture · send · More, all centred on one line, nothing floating
in the middle; hover shows "Ask (⌘K)"; tap: the Ask column opens with the
field focused and the button lit; tap into the deck column or dismiss the
keyboard: the button stays ringed (open); switch the column to Deck: idle;
⌘K on the Magic Keyboard opens Ask the same way; a narrow Stage Manager
window: circles fold into More before the button squeezes.

**Tests.** `HeaderAskButtonTests` (3): states; command, key, tooltip,
chord, width; the header keeps every circle on the iPad Air 11" landscape
centre column with the button's reservation. `test26_HeaderAskButton`:
≤ 96 wide, 44 tall, on the header's line before More; tap opens Ask with
the button reading "Open…"; back to the deck, ⌘K opens Ask again.

## Linux results

- `swift test --package-path DeckHand/Core`: **1305 / 1305 pass** (238
  suites); 1283 before this lane, 22 new in `Owner27Tests.swift`.
- `DeckHand/Scripts/linux-typecheck/run.sh`: passes (no Mac file changed).
- `swiftc -parse` is clean on every changed iOS file and the UI tests.

## Compile risks (most likely first)

1. **`DesignSystem/ControlBadge.swift`** (new, parse only):
   `overlayPreferenceValue` + `GeometryReader` + `proxy[anchor]`;
   `ForEach(Array(entries.enumerated()), id: \.offset)`; a `fileprivate`
   `EnvironmentValues` property used by key path in the same file;
   `transformPreference` after the overlay; `body` with an `if/else` of
   two different modifier chains.
2. **`Transfer/TransferSheet.swift`:** `body` switches on `presentation`
   with a `let` inside a `case`; `.animation(_, value: CGRect)`;
   `UIContentSizeCategory(typeSize)` (the SwiftUI bridge initializer);
   `Font(uiFont as CTFont)` (`import CoreText` added); `TransferSheetHost`
   uses `.presentationBackground(.clear)` on the cover's root and
   `.accessibilityAction(.escape)`.
3. **`Transfer/SendPasteChip.swift`:** `SendPasteChip(onPaste:) { font in … }`
   (trailing closure for the defaulted `onLabelFont`);
   `Task { @MainActor [weak self] in self?.onLabelFont(font) }` sends a
   `UIFont` across (Sendable in the iOS 17 SDK; if Swift 6 complains,
   call `onLabelFont(font)` from `DispatchQueue.main.async`);
   `registerForTraitChanges([UITraitPreferredContentSizeCategory.self])`
   with a `(SendPasteTargetView, UITraitCollection)` handler in `init`.
4. **`Transfer/TransferHeaderButton.swift`:** `withTransaction` with
   `disablesAnimations` around the cover's binding; `.sheet` and
   `.fullScreenCover` on the same view.
5. **`Shell/MacsSidebar.swift`:** `KeyEquivalent(HeaderAskButton.key)`
   (a `Character`); `.help(_:)`.
6. **`Store/RequiresPro.swift`:** the default argument
   `ControlBadgeStyle.inset(0, corner: .bottomTrailing)` (its own default
   uses `PixelHandTheme.Radius.chip`).
7. **`Transfer/InboxPanel.swift`:** section header/footer with
   `.listRowInsets`; `.environment(\.defaultMinListRowHeight, …)`.

## Notes

- `test23`'s old assertion "an offline Mac is a smaller row" is replaced
  by "offline and live cards share one height" (OT-16 makes them the same
  card).
- Launching with `-qa.exposeBadges YES` (every walk now does) only adds
  accessibility elements for badges; nothing visible changes.

Lane: READY TO MERGE
