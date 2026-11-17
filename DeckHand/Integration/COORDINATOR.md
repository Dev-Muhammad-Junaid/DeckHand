# Coordinator state (read and update on every coordinator tick)

The owner approved the full program (see `DECISIONS.md`). A scheduled cloud
task starts a fresh coordinator session every 2 hours; it has no memory, so
this file is the memory. Update it, commit, and push on every tick that
changes anything. Keep at most 3 lane sessions running at once (the owner's
weekly usage limit is close).

## Active sessions

| Work | Session | Branch | Done when |
| --- | --- | --- | --- |
| Foundation (PH-003/004/005/010) | session_01H5HwAUdxqkDoK2sHAUPRDx | claude/pixelhand-foundation | `FOUNDATION.md` ends `Foundation: READY TO MERGE` |
| Design strategy (no code) | session_01H5HwASjmJ3sabrVjVJ9Q1D | claude/pixelhand-design-strategy | `DeckHand/Product/Design/README.md` ends `Design strategy: READY FOR REVIEW` |
| Mac build loop (owner's Mac) | session_01H5HwATvLJkqCFPruLyBsX8 | claude/pixelhand-integration | builds when `STATUS.md` last line is `Status: READY FOR MAC BUILD (build N)` |

## Queue (start in order, max 3 running)

1. Lane: Network — S1 AWDL off + keep-alive, S13 USB wired detection.
2. Lane: Mac system control — S7 symbolic hot keys, S8 display wake + locked-Mac gate, S9 menu-read hardening, Spaces monitor.
3. Lane: Mirror — binary mirror stream, S3 local cursor, display picker / desktop dots / cursor badge (STATUS ticket), S6 stats; then S5 HEVC; then S14 single window.
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
