# Coordinator state (read and update on every coordinator tick)

> **Owner: the next Mac pass needs your Mac.** Builds 27 and 28 still owe the walks that type and click on the Mac, the protocol 16 checks and the final QA pass. When you can spare the Mac, unlock it, keep a scratch TextEdit document in front, keep the iPad unlocked on Wi-Fi, and let the Mac build loop run them.

> **Build 29 is building on the Mac** (protocol 17). The primary merged **build28-fixes** into integration already, but left STATUS alone. **Once "Mac build results (build 29)" lands:** append "Build 30 queued" (build 29 plus `LANE-build28-fixes.md`) and set `Status: READY FOR MAC BUILD (build 30)`. Then the Mac walks and the live-sync checklist (they need the owner's Mac), then the review page if there's no P1 or P2. After that: live-sync phase 2 (web and Electron opt-in), once build 30 is green.

> **Mac builds:** 15, 16, 18 and 19 built (19 with 5 bugs, fixed in build 21). The primary session or the owner's Mac session runs Mac builds.

## Needs the owner

- **Developer portal:** nothing needed. Automatic signing registered the App Group and the widget and share App IDs (builds 15 and 16).

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
| Primary (cloud, owner-facing: the owner sends changes here) | "★ Pixel Hand · PRIMARY" | claude/pixelhand-integration | programme complete |
| Mac build loop (owner's Mac, Claude Desktop session "DeckHand MAC build loop", `/loop` every 30 min; the only Mac build loop since 2026-11-25) | local_d0e9b529 | claude/pixelhand-integration (worktree `pixelhand-build`) | builds when `STATUS.md` last line is `Status: READY FOR MAC BUILD (build N)` |

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
- 2026-11-23 ~19:05 UTC: merged the UX Screen tile fix (`23f9cbe`) and UX
  shell (UX-005, UX-008, Settings; Core 603 tests; type check clean; lock
  banner kept). Queued build 11. UX-007 arrangements are next.
  Started UX arrangements (UX-007). Next in line: UX-020 Deck 2 UI, then UX-012 Mac panel, UX-017/018/019, UX-013, UX-014.
- 2026-11-23 ~19:25 UTC: merged UX capture (UX-009 and a keep-out based
  tile placement, which replaces Screen's fixed band because it also covers
  the keyboard button and pad resizes). Core 622 tests; type check clean.
  Queued build 12.
  Started UX Deck 2 UI (UX-020). Running: UX onboarding, UX arrangements, UX Deck 2.
- 2026-11-24 ~00:00 UTC: the 19:55 tick reached the coordinator only at
  23:52. All three lanes had finished by about 19:45. Merged UX onboarding,
  UX arrangements and Deck 2 UI. Fixed the conflict in the shell's deck slot:
  it now shows DeckSurface with the inset applied. Core 661 tests pass; the
  type check is clean. Queued build 13. Next: UX-017 transitions with
  UX-018 loading/empty/focus, UX-012 Mac panel with UX-019 icon/menu-bar
  hand, UX-021 suggest a deck (on-device AI), then UX-013 a11y, UX-014 copy
  and shim removal, App Intents/widgets, multi-Mac, sharing, Duo, PiP.
  Started UX motion, UX Mac and UX suggest.
- 2026-11-24 ~01:00 UTC: merged UX motion, UX Mac and UX suggest, all
  clean. Applied UX Mac's `UILaunchScreen` plist keys. Core 702 tests and
  the type check are green. Queued build 14. Next: UX-013 accessibility
  pass and UX-014 copy + shim removal, App Intents/widgets/Control Center,
  UX-022 Ask, then multi-Mac (UX-030), sharing (UX-031), Duo (UX-040) and
  PiP (UX-041).
  Started Intents, Multi-Mac and Ask. Still queued: UX-013 a11y, UX-014 copy + shim removal, sharing (UX-031), Duo (UX-040), PiP (UX-041).
- 2026-11-24 ~10:20 UTC: the 02:30 tick ran late. Merged Ask, Multi-Mac
  and Intents, all clean. Applied the widget extension target, the App
  Group capability and the entitlement. Core 781 tests pass; type check
  clean. Queued build 15. Remaining: UX-013 accessibility, UX-014 copy and
  shim removal, sharing between paired devices (UX-031), iPhone Duo panes
  (UX-040), PiP live screen (UX-041).
  Started Sharing, Duo and PiP. Last up after these: UX-013 a11y and UX-014 copy + shim removal (one lane), then the final review page.
- 2026-11-24 ~11:25 UTC: build 15 was **green on the Mac** after 6 compile
  fixes. It's installed on the owner's Mac and iPad. No owner findings yet.
  Merged Duo, PiP and Sharing, all clean. Applied the Share extension
  target and the iOS/Mac plist keys. Core 851 tests pass; type check clean.
  Queued build 16. Lanes stay paused until the owner's build-15 findings
  are in and routed to a fix session. Then the last lane (UX-013 + UX-014)
  and the review page.
- 2026-11-24 16:10 UTC: builds 15 and 16 are green on the Mac. No owner
  findings yet. The primary queued build 17 (Unlock Pro for testing). I
  lifted the pause and started the last lane, UX polish. Couldn't message
  the primary (it needs a trusted device), so this file is the update. After
  UX polish merges and a Mac build is green: the review page, then
  PROGRAMME COMPLETE.
- 2026-11-24 ~16:35 UTC: primary session merged UX polish (last queued lane)
  and queued build 18 (build 17 + UX polish). Every planned lane is merged.
  Remaining: green build 18, owner testing and fixes, release prep.
- 2026-11-24 17:15 UTC: the primary merged UX polish (`7175fb7`) and queued
  build 18 (`f8eae4d`: Unlock Pro for testing + UX polish). **Every lane is
  merged.** No lanes are running. Linux Core tests and the type check are
  green on the merged state. Waiting for "Mac build results (build 18)" and
  owner findings. If build 18 is green with no open findings, publish the
  review page and mark PROGRAMME COMPLETE.
- 2026-11-24 ~19:00 UTC: build 18 green and installed (primary session).
  The owner found many rough edges. The primary queued a visual QA run;
  waiting for `VISUAL-QA-build18.md` before starting up to three fix lanes.
- 2026-11-24 23:45 UTC: the build 18 visual QA landed: 82 findings (P1 13,
  P2 43, P3 26). Split them by area into QA fix lanes A (surfaces, 33),
  B (flows, 29, starting with VQ-001, which blocks simulator QA) and
  C (identity, 20). Each does P1 → P2 → P3 and reports per-ID status. No
  owner findings yet beyond the QA run.
- 2026-11-25 00:50 UTC: QA lanes A, B and C were ready, and I merged them:
  - A merged cleanly.
  - B conflicted in `ShellHeader`: kept A's folding More menu and B's default-capture menu.
  - C conflicted in a `MirrorPaneChromeTests` expectation: word-boundary cut plus curly apostrophe gives "JUNAID’S".

  Added `SettingsDiagnosticsSection` to Settings with a glyph header. Core has 916 tests, all passing; the type check passes. **Build 19 queued** (`6e8f18e`), with protocol 14 (8-digit codes, `pairing.refused`).
- 2026-11-25 01:10 UTC: `OWNER-REVIEW-visual-qa-build18.md` (OR-01 to OR-16) had arrived just before the QA lanes started, and they covered only part of it. Started three owner-review lanes for the rest: or-ios-chrome, or-canvas and or-mac-panel. OR-16 is parked under Needs the owner. After these merge: build 20, then the visual QA re-run, then the review page.
- 2026-11-25 ~02:05 UTC: primary session merged or-ios-chrome, or-canvas
  (resolved MacsSidebar/PixelHandShell conflicts; kept 24 pt padding) and
  or-mac-panel; queued build 20. Started the build 19 fix session
  (branch `claude/pixelhand-lane-build19-fixes`); merge it as build 21.
- 2026-11-25: owner answered OR-16 (recommendations; see DECISIONS.md).
  Primary session started lane `claude/pixelhand-lane-or16-picture-pointer`.
- 2026-11-25 02:20 UTC: the primary reported three things, all confirmed in
  the repo: it merged the three owner-review lanes (build 20, `8b1c250`),
  recorded the OR-16 answers, and started the build19-fixes and OR-16 lanes.
  I merged build19-fixes. Core has 992 tests, all passing, and the type check
  passes. **Build 21 queued** (`c993044`), replacing build 20, which was not
  built. Next: the OR-16 lane, then build 22, the visual QA re-run and the
  review page.
- 2026-11-25 02:35 UTC: OR-16 ready. Merged it (`bca7639`): the UI test
  conflicted only on numbering, so OR-16's walk is now test16. Core has 1018
  tests, all passing, and the type check passes. **Build 22 queued**,
  replacing build 21. No lanes are running. Waiting on the Mac build, then
  the visual QA re-run.
- 2026-11-25 12:00 UTC: build 22 built first time on the Mac.
  - The Mac session also fixed my OR-16 merge, which had dropped the closing
    brace of `test15` in the UI tests. That's a lesson: check brace balance
    after resolving Swift conflicts.
  - Core 1018/1018, Loom 477, DeckHandTests 8/8.
  - Passed: VQ-001, capture errors, iPad-as-Mac.
  - 3 P2 bugs: Try again during a slow first start, the AX3 pill cutting
    the name mid-word, and the AX3 lock banner overlapping the header.
  - Not checked yet, because the Mac locked partway through: OR-16 and the
    deck tile. The iPad is still on build 20.

  Started the build22-fixes lane (`BRIEF-build22-fixes.md`).
- 2026-11-25 13:05 UTC: build22-fixes ready.
  - It touched Loom: `LoomStore.start()` is single-flight, CloudKit runs
    after advertising, with DocC and tests. I checked that the Loom diff
    doesn't mention the product.
  - Merged at `0f92060`. Core has 1031 tests, all passing; the type check
    passes; the UI tests' braces balance.
  - **Build 23 queued**, with the full VQ and OR visual QA re-run. Loom
    tests must run on the Mac.
- 2026-11-25 17:10 UTC: build 23 built first time.
  - Core 1031, Loom 480 (the new start suite passes), DeckHandTests 8.
  - Visual QA re-run in two passes:
    - VQ-001…082: 51 pass, 4 fail, 27 not checked.
    - OR: 10 pass, 6 not checked.
    - 15 new findings: VQ-083…097.
  - Build 22's three bugs pass, and OR-16 passes by hand.
  - Started the qa23-fixes lane (`BRIEF-qa23-fixes.md`) for the 19 failed
    and new IDs.
- 2026-11-25 21:10 UTC: qa23-fixes ready.
  - 19 IDs: 17 fixed and 2 partly fixed (the fades).
  - No protocol or Loom change.
  - Merged at `d1aaa06`. Core has 1058 tests, all passing; the type check
    passes; the braces balance.
  - **Build 24 queued**, with the final QA pass, including the areas never
    checked: landscape and the sidebar, widgets, transfers, dark mode.
- 2026-11-26 03:15 UTC: build 24 is in progress on the Mac (compile fix `7b205ca`). Its results and the final QA haven't arrived yet. Noted under Needs the owner that the walks need the Mac.
- 2026-11-26 12:40 UTC: build 24 is green after one compile fix (memberwise
  argument order).
  - Core 1058, Loom 480, DeckHandTests 8.
  - Final QA: all 20 qa23 IDs pass; VQ 74 pass, 1 fail, 22 not checked;
    OR 12 pass, 4 not checked.
  - Newly checked: landscape, the sidebar, widgets and dark mode.
  - Open: VQ-100, 098, 099, 066 (P2) and VQ-101…103 (P3).
  - The real iPad isn't reachable (CoreDevice 4016), so transfers (OR-13)
    are still unchecked. Started the last fix lane, qa24-fixes.
- 2026-11-26 12:55 UTC: the primary reported that the owner tested build 24
  on the iPad and found OT-1…5 (now in STATUS.md). The primary started lane
  owner24 for them. I told qa24-fixes to stay out of the dock, keyboard,
  Type, Ask and handle files. Both lanes merge into one build 25.
- 2026-11-26 13:00 UTC: qa24-fixes merged (`00bc3c0`). It stayed out of the
  owner24 files. Core has 1083 tests, all passing; the type check passes;
  the braces balance. Build 25 waits for owner24, then gets queued as one
  build.
- 2026-11-26 13:45 UTC: the primary merged owner24 (`eec7022`) and queued build 25 (`c9b87da`). Confirmed in the repo. Waiting on the Mac.
- 2026-11-26 14:50 UTC: build 25 built first time.
  - Core 1133, Loom 480, DeckHandTests 8.
  - The iPad got it this time.
  - OT-1…5 pass, and VQ-066/098/099 pass.
  - Bugs: 1, the Type panel hidden behind the keyboard in portrait (P1);
    2, Ask keeping the old text (P3).
  - The owner added OT-6…8. The primary started owner25 for them.
  - I couldn't message the primary (untrusted device), so I sent both bugs
    to the owner25 session directly, because they're in its files.
  - I added the walk guard myself (`58d9204`): it checks the Mac's front
    app before typing.
- 2026-11-26 15:20 UTC: owner25 is ready (OT-6…8 plus both build 25 bugs;
  protocol 15). Merged it (`45e9e7d`). Core has 1180 tests, all passing; the
  type check passes; the UI tests parse and balance. **Build 26 queued**,
  with the final QA pass.
- 2026-11-26 16:20 UTC: the primary reported that the owner tested build 26 on the iPad (OT-9…13; confirmed in STATUS.md) and started lane owner26. The Mac's build 26 results haven't arrived; it pushed one walk fix, `a2f4adf`.
- 2026-11-26 16:55 UTC: the primary merged owner26 (`62ca293`) and queued build 27 (`e017feb`, protocol 16). Confirmed in the repo. Started the paste-control lane for the follow-up the primary asked for (`DECISIONS.md`: the Clipboard chip uses PasteButton).
- 2026-11-26 17:55 UTC: the primary merged paste-control into build 27 (`20be05f`, `66c9a53`). Waiting on the Mac.
- 2026-11-26 19:10 UTC: build 27 built and installed; only the walks that send nothing to the Mac ran (the owner was using it). 5 bugs, plus 4 open VQ items from build 26. The primary started lane build27-fixes. Added the owner note at the top.
- 2026-11-26 19:50 UTC: the primary merged build27-fixes (`b56c73c`) and queued build 28 (`d8ad7bd`). Confirmed in the repo. The owner's build 27 findings OT-14…18 are with the primary's lane owner27. Live-text-sync R&D is design only: not to merge.
- 2026-11-26 21:00 UTC: the primary folded owner27 into build 28 (`7fc7d2f`). The Mac is rebuilding (compile fix `5348ee6`). Nothing to merge here.
- 2026-11-26 21:05 UTC: the owner approved live-sync R&D. The primary merged the docs (`fb0fa77`) and recorded the decisions (`1fbd090`), and started lanes caret-joystick and live-sync. Neither branch is pushed yet. Merge order: joystick, then live-sync, then build 29.
- 2026-11-26 22:05 UTC: the primary merged caret-joystick and live-sync and queued build 29 (protocol 17). Build 28 had 8 bugs; the primary started lane build28-fixes for them. Next: merge it, then build 30.
- 2026-11-26 22:30 UTC: the primary merged build28-fixes. Build 30 gets queued after build 29's Mac results, which are in progress (live-sync compile fixes at 22:12).
