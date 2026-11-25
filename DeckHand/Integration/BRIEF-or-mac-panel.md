# Lane: owner review, Mac menu-bar panel (lane name: or-mac-panel)

Branch: `claude/pixelhand-lane-or-mac-panel`. Handoff: `DeckHand/Integration/LANE-or-mac-panel.md`.

## Scope (from OWNER-REVIEW-visual-qa-build18.md, Mac panel section)
- **OR-08: one Devices list.** Each row is an iPad or iPhone with its state:
  - *Connected*: live pixel.
  - *Paired · not connected*: dim.
  - *Asking to connect*: amber, with Allow / Pair / Deny.

  One "Pair a device" button sits under the list. "Forget" goes in each row's menu, or appears on hover. Remove the separate Paired section. Keep lane qa-flows' work: the focus sink (no focus ring; Space does nothing), the "tried to connect from another network" note, and the pending header copy (see `LANE-qa-flows.md`). Put the row and state model in Core (`MacPanelCopy` or a new plan), with tests.
- **OR-09**: the panel's permission and connection dots no longer flow in from the bottom. Use a plain fade over 150–200 ms, ease-out. Reduce Motion changes instantly. Files: `MacMenuBarView.swift` and `UI/MacPixelViews.swift`.
- **OR-10**: centre the hand tile exactly on the QR's centre module (`Pairing/PairDeviceWindow.swift`, the `MacGlyphTile` overlay). The glyph's height must match its frame.
- **OR-11**: draw every digit at full brightness, using one code format everywhere. Lane qa-flows reports this done; verify it, and check the onboarding and entry-field formats match the Mac's (eight digits, "4821 0934").
- **OR-12, Mac**: no trailing "…" on any Mac button or menu item: Forget, Pair, Pair a device, Revoke, and the rest. Status text may keep its ellipsis.
- **OR-13: a Transfers tab.**
  - Add a Transfers segment next to Devices. It shows only while transfers exist or finished in the last hour, with a count badge.
  - The Devices view shows one summary row ("3 files sending · 42 %") that opens the tab.
  - Put the summary, grouping and expiry logic in Core, with tests. Include 6 files in both directions, with a cancel and a failure, as a Core test scenario.
  - Files: `DeckHandMac/Transfer/MacTransferService.swift` and the panel views.
- **The glyph, dot and loader rule** applies to the panel. Selection is colour and fill only.

## Owned files
- `DeckHand/DeckHandMac/**`
- the Core design and copy for the Mac panel and pairing-code display, with their tests

Don't edit `DeckHandiOS`, except the one shared code-format string if OR-11 needs it, and announce that. Lanes or-ios-chrome and or-canvas run at the same time and own the iOS side.

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

Write `DeckHand/Integration/LANE-or-mac-panel.md` with:
- a per-ID table (ID | Status Fixed/Partly/Won't fix | Note | Files);
- the Linux test results;
- re-check steps on the iPad Pro 11" simulator: portrait, landscape, and a Stage Manager window dragged down to iPhone width; and for Mac items, on the Mac;
- the `PixelHandUITests` changes, if any (keep the existing `ph.<area>.<name>` IDs working, and add IDs for new controls);
- compile risks, most likely first;
- out-of-lane edits.

The file's last line must be exactly `Lane: READY TO MERGE`. Push it.
