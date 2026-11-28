# Lane: build 30 fixes (lane name: build30-fixes)

Branch: `claude/pixelhand-lane-build30-fixes`. Handoff: `DeckHand/Integration/LANE-build30-fixes.md`.

## Scope

Fix everything in "Mac build results (build 30)" in `DeckHand/Integration/STATUS.md`. Read it in full, plus `LANE-build28-fixes.md`, `LANE-live-sync.md` and `LANE-live-sync-edits.md`, which say what was tried.

1. **P1: in iPad portrait, the Type panel goes under the keyboard when Live's field takes focus.** With the keyboard up, only the panel's header shows. The first tap brings up iOS's Select / Select All / AutoFill menu, and typed text reaches neither the field nor the Mac. This is probably also why `test29` finds no Accept.
   - Landscape works (`test18`, build28-fixes); portrait doesn't.
   - The panel must sit fully above the keyboard in every orientation, including when the Live field itself takes focus.
   - The first tap must focus the field, not open the edit menu.
   - Extend the Core geometry tests (`TypePanelGeometry` / `KeyboardAvoidance`) to cover the portrait iPad keyboard heights.
   - Afterwards `test30_LiveSyncEditFromIPad` must produce the exact expected TextEdit contents. Keep its exact-content check.
2. **P3:** in iPad `test20`, the arrows plus numpad are 336 pt wide in a panel that should fill more than 344 pt. Make them fill the panel width.
3. **P3:** in iPhone `test20`, dropping the panel near the leading edge leaves it at x = 257. Snap it to the leading edge.
4. **Walk fixes in `PixelHandUITests.swift`:**
   - `openSyncedLiveField` switches the panel to Live. The panel kept Compose from `test18`, so the iPhone `test28`–`30` ran in Compose.
   - iPhone `test18` compares the panel with a keyboard frame in portrait coordinates. Convert to one coordinate space.
   - iPhone `test05` and `test16` stop early when their tab isn't hittable. They should fail with a message.

## Rules beyond the ground rules

- Core tests must compile on macOS too. Always write `PixelHandCore.TextRange`, never bare `TextRange` (it clashes with Carbon's `AERegistry.h`). Builds 29 and 30 both broke on it.
- Check the argument order of any memberwise initializer you call.
- After editing `PixelHandUITests.swift`, run `swiftc -parse` on it and check its braces balance.
- Don't change the protocol unless you must (it is 17).

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

Write `DeckHand/Integration/LANE-build30-fixes.md` with:
- a per-ID table (ID | Status Fixed/Partly/Won't fix | Note | Files);
- the Linux test results;
- re-check steps on the iPad Pro 11" simulator: portrait, landscape, and a Stage Manager window dragged down to iPhone width; and for Mac items, on the Mac;
- the `PixelHandUITests` changes, if any (keep the existing `ph.<area>.<name>` IDs working, and add IDs for new controls);
- compile risks, most likely first;
- out-of-lane edits.

The file's last line must be exactly `Lane: READY TO MERGE`. Push it.
