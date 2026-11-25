# Lane: build 23 QA fixes (lane name: qa23-fixes)

Branch: `claude/pixelhand-lane-qa23-fixes`. Handoff: `DeckHand/Integration/LANE-qa23-fixes.md`.

## Scope

Fix everything that failed or is new in `DeckHand/Integration/VISUAL-QA-build23.md`. Also read "Visual QA and re-checks (build 23)" in `STATUS.md`, including its second pass. The gallery link is in that section. Work through P1, then P2, then P3.

**P1**
- **VQ-083.** On iPhone in deck edit mode, the floating mirror tile covers the header's Done and three key slots. This was build 19 bug 2, and `LANE-build19-fixes.md` only partly fixed it.
  - The tile must keep clear of the deck header and the edit grid in every mode: move it, shrink it, or hide it while editing.
  - Use a Core keep-out plan with tests.

**P2**
- **VQ-058.** After onboarding, and after a relaunch, the picker shows the paired Mac as "Paired · Nearby" and waits for a tap. It should reconnect to the paired, nearby Mac by itself, with Cancel, as in `LANE-qa-flows.md` VQ-058.
- **VQ-060.** The iPhone mirror toolbar has no PiP button; the iPad's has one.
- **VQ-084.** At AX3 the picker truncates the subtitle, cuts the Mac name in the middle and cuts the status. Wrap at words; never cut in the middle.
- **VQ-085.** At AX5 the Mac pill cuts both lines mid-word. Apply the shrink to the first word, then break at words.
- **VQ-086.** A second floating "Connect and pair" capsule covers the code sheet's footer on iPhone. Show one button only.
- **VQ-095.** With pointer control on, a quick flick throws the Mac pointer about 3,250 pt, off the mirrored display.
  - Cap the acceleration for picture control and clamp the pointer to the mirrored display's bounds.
  - Clamp on the Mac side if the protocol allows; otherwise on iOS.
  - Pin it with Core tests.

**P3**
- **VQ-034.** The iPhone modifier row runs off the edge with no fade. Fade it, or make it scroll with a cue.
- **VQ-061.** The iPhone mirror toolbar never hides. Match the iPad: hide after 3 s, and a tap brings it back.
- **VQ-087.** At AX3 the right column's Deck | Ask switch and the Ask placeholder are truncated.
- **VQ-088.** The chip row ends mid-label with no fade.
- **VQ-089.** Segmented controls in Settings stay small at AX3.
- **VQ-090.** "Restore purchases" should be sentence case in the paywall too.
- **VQ-091.** The rail's empty-state hint is cut mid-word in iPhone landscape.
- **VQ-092.** Test tooling: let the walks get real iPad landscape. Turn windowing off in the walk setup if possible, and document the step in `MAC-BUILD.md`.
- **VQ-093.** `ph.mirror.pointerSurface` is missing when pointer control is on. Add the identifier, and keep `test16` in step with it.
- **VQ-094.** The Mac pair window opens with a pink system focus ring on New code. Give no button initial focus, or use a cobalt ring.
- **VQ-096.** `connect()` in `PixelHandUITests` taps the first Mac. Let it pick by name from an environment variable (`PH_QA_MAC_NAME`), falling back to the first Mac.
- **VQ-097.** "Last seen 38 seconds ago" doesn't tick on the Mac panel. Use `TimelineView` or show a time.

Owned files: whatever these need, across iOS, Mac, Core and the UI tests. No other lanes are running. If you change the protocol, follow the bump rules below.

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

Write `DeckHand/Integration/LANE-qa23-fixes.md` with:
- a per-ID table (ID | Status Fixed/Partly/Won't fix | Note | Files);
- the Linux test results;
- re-check steps on the iPad Pro 11" simulator: portrait, landscape, and a Stage Manager window dragged down to iPhone width; and for Mac items, on the Mac;
- the `PixelHandUITests` changes, if any (keep the existing `ph.<area>.<name>` IDs working, and add IDs for new controls);
- compile risks, most likely first;
- out-of-lane edits.

The file's last line must be exactly `Lane: READY TO MERGE`. Push it.
