# Coordinator state (read and update on every coordinator tick)

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
| Lane: Network (S1, S13) | session_01H5HwATY1dvE2kGpF8EJ5Cw | claude/pixelhand-lane-network | `LANE-network.md` ends `Lane: READY TO MERGE` |
| Lane: Mac system control (S7, S8, S9, Spaces) | session_01H5HwAVpEkSemaj3uPn1AaK | claude/pixelhand-lane-mac-system | `LANE-mac-system.md` ends `Lane: READY TO MERGE` |
| Lane: Mirror (binary stream, S3, picker, S6; may split S5/S14) | session_01H5HwASAnQxuNTmWj7uVoBs | claude/pixelhand-lane-mirror | `LANE-mirror.md` ends `Lane: READY TO MERGE` |

## Queue (start in order, max 3 running)

Started 2026-11-18: Network, Mac system control, Mirror (see Active sessions).

1. (Mirror follow-ups, if the Mirror lane splits: mirror-hevc S5, mirror-window S14.)
4. Lane: iOS interaction — text typing, click-drag, S11 gestures, S12 Pencil hover, S10 clipboard sync.
5. Lane: Pairing — S4 persistent pairing (code/QR, Forget device).
6. Lane: Store — StoreKit 2 subscription + free tier (DECISIONS.md).
7. Later Sill: S15 VPN remote, S16 virtual display, S17 audio.
8. Roadmap + redesign (after all Sill lanes merged and a green Mac build):
   design-strategy recommendation, Deck 2, App Intents/widgets, multi-Mac,
   sharing, AI, iPhone Fold two-pane, PiP live screen.

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

