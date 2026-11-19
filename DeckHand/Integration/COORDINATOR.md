# Coordinator state (read and update on every coordinator tick)

> **Mac loop needed:** run `/loop 1h Follow the "Build loop" section in DeckHand/Integration/MAC-BUILD.md on claude/pixelhand-integration` in a Mac session. (Build 3 waited about 14 h with no Mac build. Builds 4–7 have been queued since; build 7, the complete Sill phase, replaces all of them.)

## Needs the owner

- **App Store Connect:** done 2026-11-20 (see
  `DeckHand/AppStore/AppStoreConnectStatus.md`): app is Free; "Pixel Hand
  Pro" group with yearly ($19.99) and monthly ($2.99), 2-week trial, Family
  Sharing, 16-day grace period; URLs set; App Privacy published. Left for
  later: paywall review screenshot per subscription (needs a build with the
  paywall), App Review notes' demo video, Paid Applications agreement
  (with Apple), CloudKit schema deploy before release.
- **Mac build loop:** see the note above. No Mac has built anything since
  build 2, and the roadmap phase waits for a green Mac build.

The owner approved the full program (see `DECISIONS.md`). A scheduled cloud
task starts a fresh coordinator session every 2 hours; it has no memory, so
this file is the memory. Update it, commit, and push on every tick that
changes anything. Keep at most 3 lane sessions running at once (the owner's
weekly usage limit is close).

## Active sessions

| Work | Session | Branch | Done when |
| --- | --- | --- | --- |
| Fixes from Mac build 7 (started by the primary session) | (see primary) | claude/pixelhand-lane-build7-fixes | marker `Lane: READY TO MERGE`; then queue build 8 |
| Lane: Design foundation (UX-001, UX-015, UX-002, UX-003; UX-008 if time) | session_01H5HwAV3VhDHk1ihCzNeneg | claude/pixelhand-lane-design-foundation | `LANE-design-foundation.md` ends `Lane: READY TO MERGE` |
| Lane: Deck 2 model (D1 + Mac execution + DeckStore) | session_01H5HwAV6p8GVQAcj8VAQXfB | claude/pixelhand-lane-deck2-model | `LANE-deck2-model.md` ends `Lane: READY TO MERGE` |
| Coordinator (cloud, self-waking via `send_later`) | session_01H5HwAUp6YcDNLee7GQSMJp | claude/pixelhand-integration | programme complete |
| Mac build loop (owner's Mac) — **archived since 2026-11-18; start a new Mac session** | session_01H5HwATvLJkqCFPruLyBsX8 (archived) | claude/pixelhand-integration | builds when `STATUS.md` last line is `Status: READY FOR MAC BUILD (build N)` |

## Queue (start in order, max 3 running)

**Sill phase complete; roadmap + redesign phase started 2026-11-19.**
Design: Option A "Dock & Canvas", tickets in `DeckHand/Product/Design/05-Implementation-Plan.md`.

Next, in order (max 3 running, counting fix sessions):
1. After Design foundation merges: UX-004 Pointer surface (iOS interaction),
   UX-005 context strip + app dock, UX-006 Screen surface (Mirror), UX-007
   arrangements, UX-008 header, then UX-009…UX-019 (pixel identity).
2. After Deck 2 model merges and the shell exists: UX-020 Deck 2 UI (D2/D3).
3. App Intents / widgets / Control Center.
4. Multi-Mac (UX-030), sharing between paired devices (UX-031).
5. AI on-device first (UX-021, UX-022).
6. iPhone Duo two-pane (UX-040), PiP live screen (UX-041).

Lanes start only after Foundation is merged. Each lane: own branch from
`claude/pixelhand-integration`, follows `LANES.md` file ownership,
re-implements from Sill's behaviour (no copied code), runs PixelHandCore
tests on Linux, writes `DeckHand/Integration/LANE-<name>.md` ending
`Lane: READY TO MERGE`, no PR.

## Merge log

- 2026-11-17: build1 fixes merged (`dd7479b`); build 2 queued (`202984a`).
- 2026-11-18: build 2 green on the Mac (89 app tests). Foundation merged
  (`3789fab`); build 3 queued. Design strategy done
  (`claude/pixelhand-design-strategy`, board https://claude.ai/artifact/Aa8KTJubKeqahy3cmSjRTm).
  The scheduled fresh-session coordinator couldn't push (no repo source) and
  was deleted; coordination moved to a cloud coordinator session.
- 2026-11-18 23:32 UTC: coordinator tick 1. No lane ready; build 3 awaiting the
  Mac. Started lanes Network, Mac system control, Mirror (3/3 slots).
- 2026-11-19 ~11:50 UTC: tick 2. Merged Network (`9328dfe`, protocol 3), Mac
  system control (`9149e2a`, renumbered to 4) and Mirror (`10a79e3`,
  renumbered to 5; lock gate updated for `mirror.moveCursor` and
  `diagnostics`). Core 222 tests and the Linux type check are green. Build 4
  queued (`2464a70`); it replaces build 3, which was never built. Started
  Mirror 2, iOS interaction and Pairing. Swift 6.2 is installed at
  `/opt/swift-dl` in this container.
- 2026-11-19 ~13:30 UTC: tick 3. Merged Mirror 2 (`5347488`, protocol 6),
  iOS interaction (`affbde8`, renumbered to 7) and Pairing (`6341278`,
  renumbered to 8). Added `NSCameraUsageDescription` (iOS, for QR), and
  `ControlReceiver` now withholds typed text, clipboard text and pairing codes
  from the log. Core 368 tests and the Linux type check are green. Build 5
  queued (`cfa4b0f`), replacing 4. No Mac results yet. Started Mirror window,
  Network VPN and Store.
- 2026-11-19 ~17:10 UTC: tick 4 (delayed: the account hit its usage limit
  ~14:05; it reset by ~17:00). Merged Mirror window (`f3689c7`, protocol 9,
  clean). Core 389 tests and the type check are green. Build 6 queued
  (`a05e0a7`), replacing 5. Network VPN and Store had failed at the limit
  with nothing pushed; told both to resume. Started Audio (S17). No Mac
  results yet.
- 2026-11-19 ~18:50 UTC: tick 5. Merged Network VPN (protocol 10, clean;
  Loom changes stay product-agnostic), Audio (renumbered to 11) and Store
  (`project.yml` StoreKit config applied). Core 497 tests and the type check
  are green. Build 7 queued: the whole Sill phase. Roadmap waits for a green
  Mac build; ticks are now every 180 min.
- 2026-11-19 21:47 UTC: tick 6. Nothing new. Build 7 is still waiting. The
  recorded Mac loop session is archived, so no Mac will build until the owner
  starts a new Mac session with the `/loop` line at the top.
- 2026-11-19 ~22:55 UTC: the primary session reported build 7 green on the
  Mac (`2d14aff`, 5 compile fixes; 2 bugs that are Simulator-only or a flaky
  test) and passed the redesign gate. It started the build 7 fix session and
  recorded App Store Connect done (`7404f08`). The owner is testing by hand;
  ticks are every 60 min while work runs. Merged the design-strategy docs
  (`d38f34e`). Started Design foundation and Deck 2 model (3 running,
  counting the fix session).
- 2026-11-19 ~23:30 UTC: primary session merged build7-fixes, design-foundation
  and deck2-model (all marked READY TO MERGE) and queued build 8. No lane
  sessions running now; start the next redesign/roadmap lanes.

