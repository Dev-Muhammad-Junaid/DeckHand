# Coordinator state (read and update on every coordinator tick)

> **Mac loop needed:** run `/loop 1h Follow the "Build loop" section in DeckHand/Integration/MAC-BUILD.md on claude/pixelhand-integration` in a Mac session. (Build 3 waited about 14 h with no Mac build. Builds 4, 5 and 6 have been queued since; build 6 replaces all of them.)

The owner approved the full program (see `DECISIONS.md`). A scheduled cloud
task starts a fresh coordinator session every 2 hours; it has no memory, so
this file is the memory. Update it, commit, and push on every tick that
changes anything. Keep at most 3 lane sessions running at once (the owner's
weekly usage limit is close).

## Active sessions

| Work | Session | Branch | Done when |
| --- | --- | --- | --- |
| Coordinator (cloud, self-waking via `send_later`) | session_01H5HwAUp6YcDNLee7GQSMJp | claude/pixelhand-integration | programme complete |
| Mac build loop (owner's Mac) | session_01H5HwATvLJkqCFPruLyBsX8 | claude/pixelhand-integration | builds when `STATUS.md` last line is `Status: READY FOR MAC BUILD (build N)` |
| Lane: Network VPN (S15) | session_01H5HwAV9xeAp8DZb7gWseyK | claude/pixelhand-lane-network-vpn | `LANE-network-vpn.md` ends `Lane: READY TO MERGE` |
| Lane: Store (StoreKit 2 + free tier; merge last) | session_01H5HwAVs7ec2swJGq7DGiQh | claude/pixelhand-lane-store | `LANE-store.md` ends `Lane: READY TO MERGE` |
| Lane: Audio (S17) | session_01H5HwAVjmsSY4Xhpcuuecy2 | claude/pixelhand-lane-audio | `LANE-audio.md` ends `Lane: READY TO MERGE` |

## Queue (start in order, max 3 running)

Merged: Network, Mac system control, Mirror, Mirror 2 (dots + S5),
iOS interaction, Pairing, Mirror window (S14). Running: Network VPN (S15),
Store, Audio (S17) — every Sill lane is now started. Store merges last; if it finishes first, it
waits and re-merges integration before its merge.

1. Roadmap + redesign (after all Sill lanes are merged and a Mac build is
   green): merge the `claude/pixelhand-design-strategy` docs first, take its
   recommended option; then design system + new layout, Deck 2, App
   Intents/widgets/Control Center, multi-Mac, sharing between paired devices,
   AI (on-device first), iPhone Fold two-pane, PiP live screen (backlog on
   `claude/pixelhand-product-spec`). S16 virtual display stays deferred.

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
