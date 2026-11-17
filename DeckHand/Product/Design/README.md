# Pixel Hand design strategy

UX and visual redesign for the rebuild that follows the Sill lanes (see
`DeckHand/Integration/DECISIONS.md`, 2026-11-17 "Full go-ahead", and
`COORDINATOR.md` queue item 8). Design and planning only: no app code changed.

**Mockup board (private Artifact, opens on a phone; tap any screen to zoom):**
https://claude.ai/artifact/Aa8KTJubKeqahy3cmSjRTm
Source: `board/` (`index.html`, `board.css` with the real tokens, `board.js`
with one function per screen). Open `board/index.html` in a browser to view it
locally.

## Recommendation in one paragraph

Build **Option A, Dock & Canvas**. One canvas shows the **Pointer**, **Screen**
or **Deck** surface; an iOS 26 glass tab bar switches them and holds **Ask**;
above it, the **app dock** shows the Mac's running apps with the Mac Dock's
running dots, and the **context strip** shows dialog buttons first, then the
front app's chips. When there's room the canvas splits into panes: a leading
rail in iPhone landscape, two panes on iPhone Duo (nothing on the crease), and
on iPad the screen over the trackpad with a deck column and a **Macs sidebar**.
Layout presets (Split, Screen, Pointer) replace free-form modules. The look is
the website's: Geist display type, cobalt-biased neutrals, navy screens with
the dot grid, cobalt as the only action colour, and dots that light only while
a Mac is talking.

## Contents

| # | File | Deliverable |
| --- | --- | --- |
| 1 | [01-UX-Audit.md](01-UX-Audit.md) | Every screen of today's app: what's confusing or cramped, what breaks in landscape, Split View, small iPhones and at large text, and what the website does better |
| 2 | [02-Design-System.md](02-Design-System.md) | Tokens (colour, type with Dynamic Type, space, radii, motion, Liquid Glass), the dot-matrix language, components, SwiftUI mapping, migration from `DeckHandTheme` |
| 3 | [03-Layout-Strategy.md](03-Layout-Strategy.md) | Options A (Dock & Canvas), B (Columns), C (Modules), each across iPhone portrait/landscape, iPhone Duo folded/open/laptop, iPad portrait/landscape, Split View/Stage Manager and PiP; trade-offs; recommendation; Mac switching; PiP rules |
| 4 | [04-Interaction-Model.md](04-Interaction-Model.md) | Navigation, gestures per surface, Apple Intelligence (suggested decks, Ask, ask about the screen), multi-Mac and sharing, onboarding and permissions, paywall and free tier, empty and error states, accessibility, review risks, copy |
| 5 | [board/](board/) + the Artifact | High-fidelity mockups at real point sizes, light and dark: iPhone (Pointer, Deck, Screen, Ask, My Macs), iPhone SE, iPhone landscape, iPhone Duo (cover, book, laptop), iPad (landscape, portrait, ½ Split View), PiP (iPhone, iPad), pairing, paywall, free tier, send, deck editor, error state, Mac panel, components |
| 6 | [05-Implementation-Plan.md](05-Implementation-Plan.md) | Sequenced tickets UX-001…UX-041 mapped to lanes and PH-010's file splits, with acceptance criteria and the visual QA checklist |

## Decisions for the owner

1. **Option A** as the control-surface layout (recommended), or B / C.
2. **Type:** Geist for display text (bundled, SIL OFL) with SF Pro for
   everything else, dropping SF Rounded. Recommended: yes, it matches the site.
3. **Dark canvas:** navy-biased `#070A1C` instead of neutral `#0A0A0F`.
   Recommended: yes.
4. **Gesture bar removal:** replace the 7 trackpad buttons with gestures, a
   two-part click strip and deck keys. Recommended: yes.
5. **Follow-cursor zoom** as the default Screen view on iPhone. Recommended: yes.
6. **PiP** ships off by default with a one-time "Keep watching your Mac" switch,
   given the App Review risk around the background audio mode. Recommended: yes.

## Facts this work relies on

- iPhone Duo (Apple's folding iPhone, shipped 23 Oct 2026 with iOS 27.1):
  inner 951 × 669 pt, cover 466 × 678 pt, 40 pt crease division when
  half-folded (Sill's simulator measurements; Apple confirms the 7.6″ / 5.4″
  diagonals). Layout reads the hinge from the system, not the model name.
- PiP may start only from user action or automatically on leaving the app
  (Apple's custom-player guide).
- Liquid Glass is for controls and navigation, not content (Apple, "Adopting
  Liquid Glass").
- `DeckHand/Integration/LANES.md` did not exist at `9c07a63`; the plan uses the
  lane table in `DeckHand/Product/05-Backlog.md` and must be re-mapped when it
  lands.
- Sill was read for interaction patterns only; nothing was copied.

Board: https://claude.ai/artifact/Aa8KTJubKeqahy3cmSjRTm
Design strategy: READY FOR REVIEW
