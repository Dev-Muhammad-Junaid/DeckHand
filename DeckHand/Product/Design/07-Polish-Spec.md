# 07 · Polish spec (round 2)

"Less sloppiness" from the owner's review (19 Nov 2026) is acceptance
criteria, not a nice-to-have. These rules have **no exceptions**; a screen
that needs one gets the spec changed first, in this file. On the board,
"Show layout grid" overlays the columns and 8 pt rows on every round-2
screen.

## 1. Layout grid per size class

Width classes come from `LayoutMetrics` (`03-Layout-Strategy.md` §0).

| Class | Columns | Margin | Gutter | Deck | Examples |
| --- | --- | --- | --- | --- | --- |
| compact (< 500 pt) | 4 | 16 | 12 | 4 keys | iPhone portrait, Duo cover, each Duo pane, Slide Over |
| medium (500–899) | 8 | 20 | 12 | 5–6 keys | iPhone landscape, iPad portrait, ½ Split View, Duo laptop |
| wide (≥ 900) | 12 | 24 | 16 | 3-key column | iPad landscape, large Stage Manager |

- **Whole points.** Key size = floor((width − 2 × margin − (n − 1) × gutter) / n).
  The remainder is split between the two margins (an odd point goes to the
  trailing one), never into gutters. 402 pt → 4 keys of 83 pt, margins 17 and
  17. 375 pt → 76 pt keys, margins 17 and 18.
- **Fixed column widths on wide.** Macs sidebar 176 with compact Mac cards
  (incl. its 16 leading margin; 232 until the build 18 owner review, OR-04),
  deck column 336 (3 × 96 + 2 × 12 + 2 × 12 inset), the rest is the
  centre column.
- **iPhone Duo.** Each pane is its own compact grid. 20 pt clear on both sides
  of the crease (the 40 pt division), measured from the system's reserved
  region, not hard-coded.
- **Rows.** A 4 pt baseline grid; every component height and vertical gap is
  a multiple of 4; the board's overlay draws 8 pt rows.

## 2. Spacing scale

`4 · 8 · 12 · 16 · 24 · 32 · 48`. Nothing else between siblings or as
padding. 20 exists only as the medium-width margin.

| Relationship | Value |
| --- | --- |
| Glyph to its label (chips, rows, buttons) | 8 (6 inside a chip) |
| Chips in a strip, keys in a deck | 8 / 12 |
| Label stack (title over subtitle) | 4 |
| Within a card | 12 |
| Card to card, section to section | 12 / 24 |
| Screen edge to content | the class margin |
| Header to first content | 4 |
| Last content to dock / tab bar | 8 |

## 3. Radius scale (concentric)

`8 · 14 · 18 · 24 · 30 · 36 · capsule`. Inner radius = outer radius − inset,
and insets are chosen so the result is on the scale:

| Outer | Inset | Inner |
| --- | --- | --- |
| Window/pane 30 | 12 | key 18 |
| Sheet 36 | 12 | card 24 |
| Card 24 | 10 | chip 14 |
| Chip 14 | 6 | kbd 8 |

Panes use `ConcentricRectangle`. Badges and the status strip use 6–8 because
they sit on pictures, not inside containers. Capsules for pills, docks and the
tab bar only.

## 4. Control sizing

| Height | Use | Glyph pitch | Text |
| --- | --- | --- | --- |
| 20 | Badges, cursor badge | 1.4 | dot-matrix 1.4 |
| 24 | Status strip, page counter, pad caption | 1.6–2 | dot-matrix |
| 36 | Secondary pill buttons, small circles | 1.8 | `.subheadline` semibold |
| 44 | Chips, header circles, list rows (min), toolbar items | 2–2.2 | `.subheadline` semibold |
| 52 | Primary button | – | `.headline` |
| 56 | App dock, header bar | 2.2 | – |
| system | Tab bar, sheets, keyboard | 2.6 | system |

Hit targets are ≥ 44 × 44 even when the visual is smaller (badges get a
`contentShape` of 44 when tappable).

Type panel keys (owner testing, build 25, OT-7): 40 pt caps on a 44 pt
grid (4 pt between caps), so every key, arrow and numpad key keeps a
44 pt target without overlapping its neighbour's. The panel's resize
handles are 44 pt and straddle the card's bottom corners, mostly outside
it, so they never take a tap meant for ⌫ or fn.

## 5. Alignment rules

1. Leading edges of every block align to the margin or a column edge.
2. Text in a row shares a baseline (`.alignmentGuide(.firstTextBaseline)`);
   glyphs centre on the cap height of the label next to them.
3. Glyphs sit on whole-point positions and pitches; nothing is placed at a
   fractional point offset (`.frame` widths are integers; use
   `.pixelLength`-aware strokes for hairlines).
4. Numbers that update use tabular figures, so they never jitter.
5. One primary (cobalt) action per screen; destructive actions never sit next
   to the primary.
6. Icons only where the meaning is clear; otherwise a label. No unlabelled
   icon rows.
7. No stray default controls: every control is a design-system component;
   `Toggle`, `Slider` and `Picker` appear only inside Settings lists, styled
   by tokens.
8. Centred text only for one-line headlines and empty states; body copy is
   leading-aligned.
9. The same thing has the same size everywhere (a Mac card in the switcher, the
   sidebar and the share sheet uses one component with one size per class).

## 6. Dynamic Type that still looks designed

Three bands, switched by `dynamicTypeSize`:

| Band | Sizes | Layout |
| --- | --- | --- |
| Standard | xSmall – xxxLarge | As designed |
| Large | AX1 – AX2 | Strip wraps to two rows and the chord moves under the label; deck keeps a grid with 3 columns and 2-line labels; tab bar drops labels (Large Content Viewer on long-press); Mac pill drops the front-app line |
| Huge | AX3 – AX5 | Deck becomes rows (glyph pitch 3, label, chord trailing) at 64 pt minimum; the strip collapses into an "Actions" button that opens a list; header keeps the Mac pill and one menu |

Rules: text never truncates mid-word before the band switch; glyphs and
dot-matrix text step pitch, never scale continuously; spacing stays on the
scale (bands may move up one step); `ViewThatFits` picks between the band
layouts so there is no in-between state. Board: "Deck at AX3".

## 7. Per-screen visual QA checklist

Sizes (light **and** dark for each): iPhone 17 Pro 402 × 874 · iPhone SE
375 × 667 · iPhone landscape 874 × 402 · iPhone Duo folded (cover) 466 × 678 ·
iPhone Duo unfolded 951 × 669 (book) and 669 × 951 (laptop) · iPad 11″
820 × 1180 and 1180 × 820 · ½ Split View 590 × 820.

Every screen, every size:

- [ ] Grid overlay matches: margins, columns, gutters per §1; whole-point keys.
- [ ] Spacing values only from §2; radii from §3 and concentric.
- [ ] Control heights from §4; every target ≥ 44 pt.
- [ ] Baselines aligned in every row; leading edges on the grid.
- [ ] Glyphs from the set, at an allowed pitch, accent colour correct for the surface.
- [ ] Dot-matrix only for status, counters and codes; each has a spoken label.
- [ ] Lit dots only while live; none when disconnected.
- [ ] One primary action; no stray default controls.
- [ ] Nothing on the Duo crease; nothing under the Dynamic Island or home indicator.
- [ ] Standard, Large and Huge type bands each look intentional (§6).
- [ ] Reduce Motion, Reduce Transparency, Increase Contrast checked.
- [ ] Matches the board within 1 pt (round 2 screens) or the PR says why.

Screen-specific checks:

| Screen | Also check |
| --- | --- |
| Control surface (Pointer) | Pad ≥ 60 % of the window height in portrait and ≥ 300 pt in landscape; mirror tile never covers the click strip or the caption; dialog chips default-first on compact |
| Screen (mirror) | Status strip truncates at a separator; cursor badge only when the cursor is elsewhere; ‹ › dimmed with one desktop; toolbar fits 375 pt with sound and PiP |
| Display picker | Displays to scale and in the Mac's arrangement; cursor glyph on the right display; full-screen desktops hollow |
| Deck | 4 / 5–6 / 3 columns by class; page counter right-aligned to the grid; ghost keys use the dashed outline only |
| Mac switcher | Cards equal size; strip, badge and desktop dots in the same position on every card; amber only for "needs you" |
| Paywall | Prices and disclosures in real text at AX5; PRO mark at pitch 5; close button 44 pt target; Restore reachable |
| Settings | Per-Mac section first; glyph tiles 30 pt; trailing values aligned; version line dot-matrix with a spoken label |
| Onboarding | Step counter matches page; works in landscape (scrolls); one primary per page |
| Pairing (Mac window and iPhone) | QR scannable (test with the Camera app) at 1× and 2×; code groups of 4 with a dim check digit; countdown beam matches the 5-minute window |
| Mac panel | Follows the Mac's text size; no hover-only controls |

## 8. Send sheet (owner testing, build 26, OT-9)

The Send / Inbox sheet follows the grid, not stock controls. Sizes and
copy live in Core (`SendSheetLayout`, `SendTargetPlan`, `SendTargetCopy`,
`TransferGlyphs`); the view is `DeckHandiOS/Transfer/TransferSheet.swift`.

| Part | Spec |
| --- | --- |
| Sheet | As tall as its content: header + content, at least 240, at most the window less 48, on the 4 pt grid; the Large detent is offered only when the content is taller. iPad (iOS 18): a form sheet fitted to that height. Radius 36, `canvas` background, class margin (16 · 20 · 24) |
| Header | 60: Send \| Inbox switch leading, Done trailing (semibold accent text, 44 target). No navigation title: the switch names the tab |
| Switch | The Type panel's mode switch: `fill` capsule with a 2 pt inset, 32 pt segments, the selected one accent with white text; selection by colour and fill only. Unseen Inbox items: a dot-matrix count (pitch 1.4) with a spoken label |
| Sources | Photos · Files · Clipboard: three chips of one size (44 tall, a third of the row each, 8 apart), glyph (pitch 2, accent) + label, `raised` with a hairline, radius 14. Clipboard is a chip like the others, not the system paste circle |
| Field | One field for text or a link: the Ask field's shape (52, `raised`, radius 24, hairline), the Add button inside it (36 accent circle, add glyph, 44 target; ink3 while empty) |
| Tray | Staged items as 52 rows (glyph, name, size; remove glyph with a 44 target), radius 14, 8 apart, under a footnote label |
| Send to | Device cards in equal columns: `floor((w + 12) / (160 + 12))`, 1–3 (two on iPhone). A card is 64: a 44 navy tile (radius 14; Mac glyph lit while the Mac talks, lock glyph when locked, dot wave while connecting), the name over one status line, and at the trailing edge the dot-matrix readout (`42%` sending, a waiting count) or the status pixel. Card radius 24 (10 inset → 14). The focused Mac gets the 2 pt cobalt ring; a drop target the dashed accent ring |
| States | Ready · Sending N items (+ readout) · Waiting to accept · Locked · unlock to receive (amber) · Busy · sending you N items · Connecting… · N waiting · switch to send · Nearby / Remote · switch to send |
| Offline | Not a card: a 44 row, `fill`, radius 14, unlit Mac glyph (pitch 1.6), name, "Seen 2 h ago" in ink3 (`MacGlanceCopy.age`, the same words as My Macs), most recently seen first, under the cards in the same columns. Tapping still queues a send for that Mac |
| Beam, Waiting | The dot beam on a navy plate (radius 24, device and Mac glyphs at pitch 2.6); waiting rows 44 with a small destructive Cancel |
| Inbox | Rows on `raised`, pixel glyphs for link / text / photo / file, the unseen mark a 6 pt rounded square, ages in Core's words |

Checks (every size in §7, light and dark): chips equal size and on one
line; no stock segmented control, `.roundedBorder` field or paste circle;
cards equal width per row with their names on one leading edge; an
offline Mac is a row, never a full card; no empty band under the last
section, portrait and landscape, iPad and iPhone; at AX1+ the chip labels
shrink to 80 % before they would truncate.

Identifiers: `ph.transfer.send` (header), `ph.transfer.tab` (switch),
`ph.send.tab.send`, `ph.send.tab.inbox`, `ph.send.done`,
`ph.send.source.photos`, `ph.send.source.files`,
`ph.send.source.clipboard`, `ph.send.field`, `ph.send.add`,
`ph.send.trayItem`, `ph.transfer.macCard` (live card),
`ph.send.offlineCard`, `ph.send.beam`, `ph.send.waiting.cancel`,
`ph.inbox`, `ph.inbox.row`.

## 9. Capture preview (owner testing, build 26, OT-10)

The full-screen capture (`ScreenshotPreviewView`, preview step) uses the
whole stage. Maths in Core (`CapturePreviewLayout`).

| Part | Spec |
| --- | --- |
| Layout | Header (close · status strip), the picture's room, the dock, 12 apart. Every step takes the room between header and dock; the dock is anchored at the bottom, 8 above the home indicator, in both orientations and on iPhone |
| Picture | Aspect-fit into the room less 16 each side, centred, on whole points; the black well (radius 24, hairline) hugs the picture. A wide capture fills the width in portrait; a tall one fills the height in landscape. Replaces VQ-051's "dock right under the picture", which left half the screen empty in portrait |
| Zoom | Pinch 1×–6× (the pan scales with it); double-tap zooms to 2.5× on the tapped point, again back to 1×; a drag pans while zoomed and never shows past the picture's edges; at 1× a downward swipe closes. VoiceOver: a "Zoom in / Zoom out" action |
| Dock | Raised navy, radius 24, at most 560 wide and centred (iPad keeps the five actions together); annotate's toolbar keeps the full width |

Checks: iPad 11″ portrait and landscape, iPhone portrait and landscape;
the picture's gaps to the header and to the dock are equal within 1 pt;
nothing under the home indicator; a double-tap on a corner keeps that
corner in view.

Identifiers: `ph.capture.well`, `ph.capture.preview`, `ph.capture.dock`.
