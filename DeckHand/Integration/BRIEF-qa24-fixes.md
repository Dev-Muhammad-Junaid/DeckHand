# Lane: build 24 QA fixes (lane name: qa24-fixes)

Branch: `claude/pixelhand-lane-qa24-fixes`. Handoff: `DeckHand/Integration/LANE-qa24-fixes.md`.

## Scope

This is the last fix round before the owner's review. Fix the open items in `DeckHand/Integration/VISUAL-QA-build24.md`. Also read "Mac build results (build 24)" in `STATUS.md` and the gallery linked there. Work P2 first, then P3.

**P2**
- **VQ-100, pairing.** The code sheet has an unlabelled Mac chooser (a lone ⌃⌄) that defaults to the first Mac in the list, which can be another person's Mac.
  - Default to the Mac that asked, or to the only paired or recently seen Mac.
  - If there are several, show a labelled "Pair with" row naming the Mac, and require a choice.
  - On iPhone the footer also runs under the keypad; fix that too.
  - Put the chooser default logic in Core, with tests.
- **VQ-098.** Outside edit mode, the floating mirror tile covers the empty deck's "No keys yet" at AX3, and most of the card at AX5.
  - Extend the VQ-083 keep-out (`LANE-qa23-fixes.md`) to the empty state.
  - Or shrink or hide the tile at accessibility sizes.
- **VQ-099.** In iPad AX3 landscape, the Macs sidebar cards cut names mid-word. Use the pill's whole-word layout, or glyph-only cards with the Large Content Viewer at the Huge band.
- **VQ-066 (still failing).** In the iPhone AX3 free plan, Show screen is cut by its card's bottom edge. The card must grow or scroll.

**P3**
- **VQ-101.** During a slow auto-reconnect, show "Connecting to <Mac>…" with Cancel instead of a bare "Paired · Nearby".
- **VQ-102.** At AX5 the picker's subtitle slides under the Pair and Settings buttons. Give the top bar a scroll-edge background.
- **VQ-103, tooling.** Let the walks pair an unpaired simulator by code with `PH_QA_PAIRCODE_FILE`, or skip the connect walks with a clear message. Never leave an Allow prompt waiting on the Mac. Document this in `MAC-BUILD.md`.

Owned files: whatever these need. No other lanes are running. Read `LANE-qa23-fixes.md` first: it has the keep-out and pill layout this round builds on.

## Ground rules (read before starting)

You are one lane in the Pixel Hand build programme, run by a coordinator session. Repository `Dev-Muhammad-Junaid/DeckHand`, starting from `claude/pixelhand-integration` (build 19 queued: the build 18 QA lanes A/B/C are merged). Work and push only on your lane branch (named below). Never push to `claude/pixelhand-integration` or `main`, and never open a PR. Push often; the coordinator merges.

Read first:
- `DeckHand/Integration/OWNER-REVIEW-visual-qa-build18.md`: the owner's review, including the **rule for glyphs, dots and loaders**, which applies to everything you touch.
- `DeckHand/Integration/VISUAL-QA-build18.md`: the findings.
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

Write `DeckHand/Integration/LANE-qa24-fixes.md` with:
- a per-ID table (ID | Status Fixed/Partly/Won't fix | Note | Files);
- the Linux test results;
- re-check steps on the iPad Pro 11" simulator: portrait, landscape, and a Stage Manager window dragged down to iPhone width; and for Mac items, on the Mac;
- the `PixelHandUITests` changes, if any (keep the existing `ph.<area>.<name>` IDs working, and add IDs for new controls);
- compile risks, most likely first;
- out-of-lane edits.

The file's last line must be exactly `Lane: READY TO MERGE`. Push it.
