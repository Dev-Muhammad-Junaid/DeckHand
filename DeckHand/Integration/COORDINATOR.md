# Coordinator state (read and update on every coordinator tick)

> **Mac loop needed:** run `/loop 1h Follow the "Build loop" section in DeckHand/Integration/MAC-BUILD.md on claude/pixelhand-integration` in a Mac session. (Build 3 waited about 14 h with no Mac build; build 4 is now queued and replaces it.)

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
| Lane: Mirror 2 (desktop dots, S5 HEVC; S14 if time) | session_01H5HwARaG2DQsSAmTij3Pjo | claude/pixelhand-lane-mirror-2 | `LANE-mirror-2.md` ends `Lane: READY TO MERGE` |
| Lane: iOS interaction (typing, drag, S11, S12, S10) | session_01H5HwAUQUjPJwVFTCm2GHwq | claude/pixelhand-lane-ios-interaction | `LANE-ios-interaction.md` ends `Lane: READY TO MERGE` |
| Lane: Pairing (S4) | session_01H5HwATY2su8kZcgNm19S2Q | claude/pixelhand-lane-pairing | `LANE-pairing.md` ends `Lane: READY TO MERGE` |

## Queue (start in order, max 3 running)

Merged: Network, Mac system control, Mirror. Running: Mirror 2, iOS
interaction, Pairing (see Active sessions).

1. Lane: mirror-window (S14), unless Mirror 2 finishes it.
2. Lane: Store (StoreKit 2 subscription + free tier). Merges last.
3. Lane: Network S15 VPN remote (after Pairing merges).
4. Lane: S17 audio.
5. Roadmap + redesign (after all Sill lanes merged and a green Mac build):
   design-strategy recommendation (merge `claude/pixelhand-design-strategy`
   docs first), Deck 2, App Intents/widgets/Control Center, multi-Mac,
   sharing, AI (on-device first), iPhone Fold two-pane, PiP live screen.
   S16 virtual display stays deferred.

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
