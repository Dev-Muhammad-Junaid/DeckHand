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
- **Fixed column widths on wide.** Macs sidebar 232 (incl. its 24 leading
  margin), deck column 336 (3 × 96 + 2 × 12 + 2 × 12 inset), the rest is the
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
