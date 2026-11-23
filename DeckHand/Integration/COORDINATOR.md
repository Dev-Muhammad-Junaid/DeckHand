# Coordinator state (read and update on every coordinator tick)

> **Mac builds:** build 7 was built on the Mac (2026-11-20, results in `STATUS.md`). Build 10 is queued (build 8 plus UX Pointer and UX Screen). Mac builds are now run from the primary session or the owner's Mac session.

## Needs the owner

- **App Store Connect:** done 2026-11-20 (see
  `DeckHand/AppStore/AppStoreConnectStatus.md`): app is Free; "Pixel Hand
  Pro" group with yearly ($19.99) and monthly ($2.99), 2-week trial, Family
  Sharing, 16-day grace period; URLs set; App Privacy published. Left for
  later: paywall review screenshot per subscription (needs a build with the
  paywall), App Review notes' demo video, Paid Applications agreement
  (with Apple), CloudKit schema deploy before release.

The owner approved the full program (see `DECISIONS.md`). A scheduled cloud
task starts a fresh coordinator session every 2 hours; it has no memory, so
this file is the memory. Update it, commit, and push on every tick that
changes anything. Keep at most 3 lane sessions running at once (the owner's
weekly usage limit is close).

## Active sessions

| Work | Session | Branch | Done when |
| --- | --- | --- | --- |
| Coordinator (cloud, self-waking via `send_later`) | session_01H5HwAUp6YcDNLee7GQSMJp | claude/pixelhand-integration | programme complete |
| Mac build loop (owner's Mac) — **archived since 2026-11-18; start a new Mac session** | session_01H5HwATvLJkqCFPruLyBsX8 (archived) | claude/pixelhand-integration | builds when `STATUS.md` last line is `Status: READY FOR MAC BUILD (build N)` |
| Lane: UX shell (UX-005 dock + strip, UX-008, Settings; UX-007 if time) | session_01H5HwATr5aqiTiBW55LMwiH | claude/pixelhand-lane-ux-shell | `LANE-ux-shell.md` ends `Lane: READY TO MERGE` |
| Lane: UX capture (tile vs Pointer fix, UX-009) | session_01H5HwATPUvvgLzivgTceR8t | claude/pixelhand-lane-ux-capture | `LANE-ux-capture.md` ends `Lane: READY TO MERGE` |
| Lane: UX onboarding (UX-010 onboarding + picker, UX-011 paywall) | session_01H5HwASiRB6CXssuGg7CDa1 | claude/pixelhand-lane-ux-onboarding | `LANE-ux-onboarding.md` ends `Lane: READY TO MERGE` |

## Queue (start in order, max 3 running)

**Sill phase complete; roadmap + redesign phase started 2026-11-19.**
Design: Option A "Dock & Canvas", tickets in `DeckHand/Product/Design/05-Implementation-Plan.md`.

Next, in order (max 3 running, counting fix sessions):
1. Running: UX-004, UX-005/008 + Settings, UX-006/016/009. Next: UX-007
   arrangements (if UX shell didn't finish it), UX-010 onboarding + picker,
   UX-011 paywall, UX-012 Mac panel, UX-017 transitions, UX-018
   loading/empty/focus, UX-019 icon/launch/menu-bar hand, UX-013 a11y,
   UX-014 copy + shim removal.
2. UX-020 Deck 2 UI (D2/D3); the model and shell are both merged now.
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
- 2026-11-19 ~23:50 UTC: the primary session merged build7-fixes,
  design-foundation and deck2-model and queued build 8 (`72de5cb`, protocol
  12). On its request, started the screens the owner touches: UX Pointer, UX
  shell (dock, strip, header, Settings) and UX Screen.
- 2026-11-23 18:55 UTC: the coordinator tick queued for 2026-11-20 00:55 was
  delivered almost 4 days late. All three UX lanes had failed at about
  2026-11-19 23:54 (most likely the usage limit), one commit each. I sent
  each one a message to resume from its last push. Build 8 still has no Mac
  results.
- 2026-11-23 ~19:00 UTC: UX Pointer finished; merged it clean (protocol 12,
  Core 571 tests, type check clean) and queued build 9. Its follow-ups:
  UX Screen should anchor the floating tile clear of the click strip;
  UX shell should move the keyboard button into the app dock.
  Started UX onboarding (UX-010, UX-011) in the free slot.
- 2026-11-23 ~19:00 UTC: merged UX Screen (UX-006, UX-016; protocol 12;
  Core 586 tests; type check clean) and queued build 10. UX-009 and the
  floating tile vs Pointer click strip overlap went to a new UX capture
  lane. Running: UX shell, UX onboarding, UX capture.
