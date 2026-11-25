# Lane: build 22 fixes (lane name: build22-fixes)

Branch: `claude/pixelhand-lane-build22-fixes`. Handoff: `DeckHand/Integration/LANE-build22-fixes.md`.

## Scope

Fix the 3 bugs in "Mac build results (build 22)" in `DeckHand/Integration/STATUS.md`. Read that section in full.

1. **Try again during a slow first start breaks discovery (P2).** With no iCloud account, the first `LoomContext` start waits about 45 s on the CloudKit account check. Meanwhile the picker shows "Can't find your Mac?". Tapping **Try again** starts a second attempt while the first is still pending. Both then fail ("Already advertising service", then `CancellationError`), and the picker sticks on SEARCHING.
   - Make Try again wait for, or cleanly cancel, the start in flight, so starts are single-flight.
   - Don't block advertising and browsing on the CloudKit account check.
   - Fix this in the app's use of Loom, on the DeckHand side (`DeckHandiOS` / `DeckHandMac` / Core), if at all possible.
   - If Loom itself (`Sources/`) must change, keep it product-agnostic. Never mention Pixel Hand or DeckHand in Loom code, comments or tests, and add Loom tests (Swift Testing).
   - Pin the start state machine with Core tests.
2. **The AX3 Mac pill still cuts the name mid-word (P2, VQ-065).** On iPhone 17 Pro at AX3 the pill reads "Muhamma…" on one line. Expected: "Muhammad’s" / "MacBook Pro" on two lines, or a tail "…" on line 2, breaking only at words.
   - See `DesignSystem/MacPill.swift` and `ShellHeaderPlan.pillNameLines`.
   - Add a Core word-wrap plan with tests if needed.
3. **The AX3 lock banner overflows into the header (P2).** On iPhone 17 Pro at AX3 with the Mac locked, the banner text wraps "Muham-" mid-word, and its first line draws over the Mac pill.
   - The banner must sit below the header, grow downward and break at words.
   - The screenshot is `iphone-ax3/test04_ConnectAndPointer/01-pointer`.

Also check `PixelHandUITests.swift` compiles structurally: every `func` is closed, and the class brace is balanced. A merge broke it once.

## Owned files

The picker and connection start path (`PeerPickerView.swift`, `ControlSessionModel+Network.swift` and its Core start or discovery state), `DesignSystem/MacPill.swift`, the lock banner view, Core plans and tests for these, and `PixelHandUITests.swift` (only to add or adjust walks for these bugs). No other lanes are running.

## Ground rules (read before starting)

You are one lane in the Pixel Hand build programme, run by a coordinator session. Repository `Dev-Muhammad-Junaid/DeckHand`, starting from `claude/pixelhand-integration` (build 19 queued: the build 18 QA lanes A/B/C are merged). Work and push only on your lane branch (named below). Never push to `claude/pixelhand-integration` or `main`, and never open a PR. Push often; the coordinator merges.

Read first:
- `DeckHand/Integration/OWNER-REVIEW-visual-qa-build18.md`: the owner's review, including the **rule for glyphs, dots and loaders**, which applies to everything you touch.
- `DeckHand/Integration/VISUAL-QA-build18.md`: the findings.
- The three QA lane handoffs, which say what is already done: `DeckHand/Integration/LANE-qa-surfaces.md`, `LANE-qa-flows.md` and `LANE-qa-identity.md`.
- `DeckHand/Product/Design/`: the design system.
- `DeckHand/Integration/DECISIONS.md` and `LANES.md`.

How to work:
- Put pure logic (layout plans, state machines, copy) in Core, `DeckHand/Core`, with Swift Testing tests.
- Run `swift test --package-path DeckHand/Core` and `DeckHand/Scripts/linux-typecheck/run.sh` on Linux. Swift 6.2 is at `/opt/swift-dl/swift-6.2-RELEASE-ubuntu24.04/usr/bin`; if it is missing, install the swift.org 6.2 Ubuntu 24.04 tarball there.
- The app files (SwiftUI, AppKit, UIKit) are first compiled on the Mac build, so keep the APIs conservative and list your compile risks.
- iOS uses public APIs only. Mac private APIs go through dlsym.
- Never copy code from other projects; re-implement.
- Don't touch the Loom package (`Sources/`, `Tests/`).
- Don't bump the protocol unless you must. If you do, bump `PixelHandProtocol.version`, re-record with `PH_RECORD_FIXTURES=1 swift test --package-path DeckHand/Core --filter ProtocolContractTests`, and update `expectedCaseCount` and the `PROTOCOL.md` history.
- Keep to your owned files. If you must edit another lane's file, keep the edit minimal and announce it in the handoff.
- Commit trailers:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

## Handoff

Write `DeckHand/Integration/LANE-build22-fixes.md` with:
- a per-ID table (ID | Status Fixed/Partly/Won't fix | Note | Files);
- the Linux test results;
- re-check steps on the iPad Pro 11" simulator: portrait, landscape, and a Stage Manager window dragged down to iPhone width; and for Mac items, on the Mac;
- the `PixelHandUITests` changes, if any (keep the existing `ph.<area>.<name>` IDs working, and add IDs for new controls);
- compile risks, most likely first;
- out-of-lane edits.

The file's last line must be exactly `Lane: READY TO MERGE`. Push it.
