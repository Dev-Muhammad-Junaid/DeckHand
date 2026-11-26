# Owner decisions (source of truth for all Pixel Hand sessions)

Recorded by the coordinating session ("Deckhand project status review").
Newest first. If a doc elsewhere disagrees, this file wins.

## 2026-11-26 — Owner testing, build 26 (OT-9 … OT-13)
From the owner's hands-on test of build 26 on the iPad Air 11" (M3),
portrait and landscape, dark (`STATUS.md`, "Owner testing (build 26)");
built on `claude/pixelhand-lane-owner26` (`LANE-owner26.md`):
- **The Type panel fills itself:** it resizes in both directions and every
  block is cut from its width and height (rows 44…72 pt, key rows across
  the width, field as tall as the arrows). Numpad mode shows only the
  arrows and the numpad; at its shortest the arrows go to one row. The
  app is named once, by its icon in the header. The field's minimum drops
  from 192 to 144 pt (it can show two lines now). The dock rides on the
  iPadOS keyboard bar.
- **Zoom to the input (Pro):** a loupe attached to the Type panel shows the
  Mac's focused field, cut from the mirror and following the caret
  (protocol 16: `system.watchFocus` / `system.focusState`). It needs the
  mirror: no separate crop stream (one capture and encoder per iPad).
  Electron apps get `AXManualAccessibility` only while a remote watches.
- **Inline suggestions:** an **Accept ⇥** button in Live (Tab takes the
  suggestion). Native fields' text shows in the loupe; suggestions
  themselves can't be read reliably (not in AX for native predictions,
  indistinguishable in web/Electron), so none is shown.
- **Send sheet and capture preview** redrawn in the pixel identity and
  sized to their content / the screen.

## 2026-11-26 — Owner testing, build 25 (OT-6 … OT-8)
From the owner's hands-on test of build 25 on the iPad Air 11" (M3),
landscape (`STATUS.md`, "Owner testing (build 25)"); built on
`claude/pixelhand-lane-owner25` (`LANE-owner25.md`):
- **The Type panel moves, resizes and folds:** dragged by a grip
  anywhere above the keyboard and the dock with a soft magnet to edges and
  corners, resized from 360 pt (the narrowest that keeps a 192 pt field
  beside the arrows and the whole key block) to 760 pt, folded to a pill;
  the place and size are remembered per arrangement and orientation.
  iPhone docks it top or bottom.
- **Compact typing layout:** a narrower field with an inverted-T arrow
  cluster, the keys in two rows, a 5 × 4 numpad that docks beside the keys
  in the same panel; dot-matrix legends on the key caps (an owner-asked
  exception to "dot-matrix never on buttons", `06-Pixel-Identity.md` §2).
- **Keys can type text** (`Action.typeText`, protocol 15). Any plan Ask can
  run saves as a key. A key that types always asks first, naming the app
  the text lands in; widgets leave such keys out.

## 2026-11-26 — Owner testing, build 24 (OT-1 … OT-5)
From the owner's hands-on test on the iPad Air 11" (M3), landscape
(`STATUS.md`, "Owner testing (build 24)"); fixed on
`claude/pixelhand-lane-owner24` (`LANE-owner24.md`):
- **Dock looks like the macOS Dock:** real icon shapes with no tile or
  plate behind them (the Mac sends icons with transparency), and the front
  app gets a small accent dot under its icon instead of the ring box. This
  replaces the "front app = accent ring" line in `06-Pixel-Identity.md` §5.
- **Typing is a Type panel** (the owner was open to ideas; we built the
  recommended shape): Live and Compose modes, a keys row with fn keys,
  sticky modifier chips, a dot-matrix numpad, keys-only with a hardware
  keyboard. The keyboard never changes the arrangement.
- **Ask never strands the person:** after a run, New request, Run again,
  Save as key (Name · Save · Cancel) and Edit; the field always starts over.

## 2026-11-25 — OR-16 answers: pointer control on the mirror picture
The owner chose the recommendations ("go with the recommendations"):
1. Off the first time the screen-only arrangement opens, then remember the
   last choice.
2. Keep pinch to zoom the picture while control is on (two fingers still
   scroll the Mac).
3. Trackpad style only (relative movement, same gestures and code as the
   Pointer surface UX-004). No "tap where you touch" mode for now; it can
   come later as a setting.

## 2026-11-24 — "Unlock Pro for testing" switch
The owner asked for a Settings switch that enables Pro without a
subscription while the subscriptions aren't live. It sits in
Settings › Subscription and is offered only in Debug, development-signed
and TestFlight builds (`AppTransaction.environment != .production`); App
Store downloads never show it and ignore a stored "on". Implementation:
`DeckHand/DeckHandiOS/Store/DeveloperUnlock.swift`, `SubscriptionStore`
(`entitlement` = override or StoreKit's `storeEntitlement`; only the
StoreKit answer is cached).

## 2026-11-19 — Design direction approved, with more pixel identity
The owner reviewed the design board
(https://claude.ai/artifact/Aa8KTJubKeqahy3cmSjRTm, branch
`claude/pixelhand-design-strategy`) and approved the direction: "I really
liked the direction". For the redesign phase:
- Lean further into the **glyph, pixel and dot-matrix** language: dot-matrix
  type and numerals for status and counters, pixel glyphs for actions and
  app keys, dot grids for empty and loading states, phosphor-style
  highlights, pixel-dissolve transitions. It should feel like one
  instrument, not decoration on top of stock iOS.
- **Less sloppiness:** every screen gets a strict grid, consistent spacing
  and alignment, no stray default controls or mismatched sizes, no cluttered
  button walls. Polish (pixel-perfect alignment, consistent radii and
  insets, Dynamic Type that still looks designed) is acceptance criteria,
  not nice-to-have. Add a visual QA pass per screen at iPhone, iPhone Fold
  and iPad sizes, light and dark.
- Before implementation, the design session extends the board with these
  pixel/glyph ideas (component sheet + key screens) so the build follows a
  concrete reference.

## 2026-11-17 — Full go-ahead: Loom first, then all of Sill, then the roadmap
The owner approved the whole plan without further check-ins ("You have full
approval from my end, so you don't have to wait for anything") and asked
for one update when everything is done, tested and ready to review.
- Order: (1) Loom up to date (done: 2.2.16 merged) plus the foundation
  refactor (protocol reset, PixelHandCore, hot-spot file splits); (2) every
  worthwhile Sill item S1–S15 and S17, by lane; (3) the Pixel Hand roadmap
  (Deck 2, App Intents, multi-Mac, sharing, AI) together with a major UX and
  visual redesign. No time limit.
- Method: re-implement from Sill's behaviour and docs (no copied code).
- AWDL off by default: approved.
- Mac private APIs: approved generally for the Mac app (Developer ID, not
  the Mac App Store), always via `dlsym` with graceful fallback. Includes
  the build-1 Show Desktop/Apps mechanisms (`CGSSetSymbolicHotKeyEnabled`,
  `CGSSetSymbolicHotKeyValue` with restore, `CoreDockSendNotification`) and
  S16 virtual display when it is scheduled. The iOS app stays public-API
  only.
- Later, after the Sill work: iPhone Fold ("iPhone Duo") two-pane layouts,
  and a Picture-in-Picture live Mac screen on iPhone and iPad that keeps
  running on the Home Screen.
- UX: the app should match the website's quality and visual language;
  redesign layouts for landscape and small screens, fewer button walls,
  a dock / column / multi-layout system, and Apple Intelligence where it
  helps. A design-strategy session proposes options first; implementation
  follows the Sill work.

## 2026-11-17 — What we take from upstream Loom and Sill
Sources: comparison report `docs/review/upstream-comparison-2026-11.md` on
`claude/upstream-comparison-2026-11` (§4 ranks Sill items S1–S17) and the
backlog `DeckHand/Product/05-Backlog.md` on `claude/pixelhand-product-spec`.

**Upstream Loom:** merged (2.2.16) on the integration branch, with
`DeckHandHandshakeTrustProvider` keeping the Mac's Allow/Deny prompt. Builds;
all 461 Loom tests and 51 app tests pass on the owner's Mac (2026-11-17).

**Sill:** re-implemented from its behaviour and docs, no code copied, so no
license obligations. By release:
- Done: S2 Sparkle + notarized DMG pipeline.
- 1.0: S1 AWDL off + Wi-Fi keep-alive; S3 cursor drawn on the device;
  mirror on its own binary stream; S7 real Mission Control shortcuts
  (Mac private API, approved); S8 display wake + locked-Mac check; S9
  hardened menu reading; S6-lite stats overlay. Plus Pixel Hand's own:
  text typing, click-drag, crash fixes, display picker / desktop dots.
- 1.1: S5 HEVC mirror (with S6 stats HUD); S4 persistent pairing with
  code/QR and "Forget device"; S10 clipboard sync.
- Later (1.2–1.3): S11 more gestures, S12 Pencil hover, S13 USB "wired"
  mode, S14 single-window streaming, S15 remote access over VPN (with
  multi-Mac in 1.3), S17 audio (only if users ask).
- Not doing: S16 virtual display (deferred: most likely to break on macOS
  updates); Sill's iPhone layout (Pixel Hand has its own grid UI).
- Kept as Pixel Hand's identity: shortcut chips from real menus,
  dialog-button chips, OCR + annotation, media keys, delivery receipts,
  dot-matrix cobalt look, and the coming Deck 2 / multi-Mac / sharing / AI.

## 2026-11-17 — Business status
- Free app with paid options confirmed by the owner. Paid Applications
  agreement: bank and tax details submitted, under Apple review.
- Sentry: the owner is creating the projects.

## 2026-11-17 — Private API approved: reading Spaces on the Mac
- The owner approved `CGSCopyManagedDisplaySpaces` (with `CGSMainConnectionID`), loaded with `dlsym`, in the **Mac app only**. It is used to read each display's desktops, which one is current, and which are full-screen apps.
- This is acceptable because the Mac app ships as a Developer ID download, not through the Mac App Store. The iOS app only receives plain data and calls no private API.
- If the symbol is missing on a future macOS, the Mac app must fall back gracefully: no desktop dots, and everything else keeps working.
- This was recorded by the Mac build session at the owner's request. The design is the "Mirror: Spaces, displays and cursor awareness" ticket in `STATUS.md`.

## 2026-11-17 — Business model: subscription with a 2-week free trial
- iPhone/iPad app is **free to download**; access is an **auto-renewable
  subscription** with **monthly** and **yearly** plans, each with a
  **2-week free trial** (introductory offer).
- **Confirmed by the owner 2026-11-17:** $2.99/month and $19.99/year
  (USD tier; other storefronts follow Apple's equalisation); one
  subscription group "Pixel Hand Pro"; product IDs
  `com.widgetsflow.pixelhand.pro.monthly` and
  `com.widgetsflow.pixelhand.pro.yearly`; Family Sharing on.
- **Decided 2026-11-17 (owner delegated the call):** free tier = trackpad, keyboard and
  media keys with one Mac; Pro = decks and chips, mirror, capture/OCR,
  multiple Macs, sharing, AI. During the trial everything is unlocked.
- The Mac app stays a free Developer ID download; entitlement lives on the
  iOS side (StoreKit 2, `Transaction.currentEntitlements`), no server.
- Needed in the app: StoreKit 2 paywall and "Restore Purchases", a
  subscription status row in Settings, a local `.storekit` configuration for
  testing, and Apple's required subscription disclosures (price, period,
  auto-renewal, links to Terms of Use / standard EULA and the privacy
  policy) on the paywall and in the App Store description.
- This is a new M1 ticket. It touches iOS settings/onboarding, so it goes in
  after the hot-spot file splits (PH-003/005/010).

## 2026-11-16/17 — Earlier decisions
- Name **Pixel Hand**; store name "Pixel Hand: Remote for Mac"; IDs
  `com.widgetsflow.pixelhand` (iOS), `com.widgetsflow.pixelhand.mac`,
  container `iCloud.com.widgetsflow.pixelhand` (all registered; app record
  Apple ID 6835622962).
- Site **pixelhand.app**, support **support@pixelhand.app**; Sparkle feed
  `https://pixelhand.app/mac/appcast.xml`.
- Mac app: free notarized Developer ID download with Sparkle, not on the Mac
  App Store. Mac and iOS apps release together.
- Plan "Option C": ~3 weeks to 1.0 (M0 merge/refactor, M1 Sill quick wins +
  typing and drag, M2 beta and release), then 1.1 HEVC / persistent pairing /
  clipboard, 1.2 Deck 2 + App Intents, 1.3 multi-Mac + sharing between any
  paired devices, 1.4 AI commands.
- AI runs on-device (Foundation Models), else on the paired Mac, else a
  deterministic fallback; no third-party cloud. Private Cloud Compute: not
  used unless the owner asks.
- Clean break from old versions (no users yet). Re-implement Sill features
  from its behaviour; don't copy its code. Mac private APIs: Mission Control
  shortcut reading and locked-Mac check approved; virtual display on hold.
- Crash reporting: Sentry with a user toggle. CI: GitHub Free, PR-only.
