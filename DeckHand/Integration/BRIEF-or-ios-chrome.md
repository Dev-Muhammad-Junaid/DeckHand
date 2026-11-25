# Lane: owner review, iOS chrome and the glyph rule (lane name: or-ios-chrome)

Branch: `claude/pixelhand-lane-or-ios-chrome`. Handoff: `DeckHand/Integration/LANE-or-ios-chrome.md`.

## Scope (from OWNER-REVIEW-visual-qa-build18.md)
- **OR-01**: remove the tab bar selection dot (`Shell/SurfaceTabBar.swift` `TabDot`).
- **OR-02**: remove the three-dot row under shortcut chips and quick-action chips (`DesignSystem/ContextChip.swift`, `Shell/ContextStrip.swift`, `QuickActions/QuickActionsChips.swift`). Running a chip gives a press state and a haptic only.
- **OR-05**: the sidebar show/hide button stays in the same leading spot in both states (`Shell/ShellHeader.swift`, `onShowSidebar`).
- **OR-12, iOS**: drop the trailing "…" from every iOS button label. Update the hint that says "choose “Pair a Device…”" in `Pairing/PairingQRScannerView.swift` and `PairingCodeEntryView.swift` to the Mac's new label, "Pair a device".
  - Status text such as "Connecting…" may keep its ellipsis. Buttons may not.
- **The glyph, dot and loader rule, across the iOS app**:
  - Selection is shown by colour and fill only.
  - The dot-matrix loader appears only for real waiting.
  - Panels and status rows fade over 150–200 ms, ease-out, and never slide in from the bottom.
  - Reduce Motion changes instantly.
  - Audit every use of the loader, plus any `.transition(.move(edge: .bottom))` or similar, and fix them.
  - Don't touch the widgets. OR-15 keeps their glyphs.
- **VQ-079, the remainder**: opening the Trackpad control should switch the iPad to the Pointer arrangement. See `LANE-qa-identity.md`, which says what's left.
- **VQ-069, the remainder**: the picker's fallback (`PeerPickerView.swift`). See `LANE-qa-flows.md`, which says what wasn't done.

## Owned files
- `DeckHandiOS/Shell/SurfaceTabBar.swift`, `ShellHeader.swift` and `ContextStrip.swift`
- `DeckHandiOS/DesignSystem/*`
- `DeckHandiOS/QuickActions/*`
- `DeckHandiOS/Pairing/*`
- `DeckHandiOS/PeerPickerView.swift`
- `DeckHandiOS/Surfaces/PointerSurface.swift`
- the intents only as needed for VQ-079
- Core tests for any plan you add

**Not yours:** `PixelHandShell.swift`, `ControlSurface.swift`, `AskSheet.swift`, `CanvasPlan`/`LayoutMetrics` and the Macs sidebar belong to lane or-canvas, which runs at the same time. Lane or-mac-panel owns `DeckHandMac/`.

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

Write `DeckHand/Integration/LANE-or-ios-chrome.md` with:
- a per-ID table (ID | Status Fixed/Partly/Won't fix | Note | Files);
- the Linux test results;
- re-check steps on the iPad Pro 11" simulator: portrait, landscape, and a Stage Manager window dragged down to iPhone width; and for Mac items, on the Mac;
- the `PixelHandUITests` changes, if any (keep the existing `ph.<area>.<name>` IDs working, and add IDs for new controls);
- compile risks, most likely first;
- out-of-lane edits.

The file's last line must be exactly `Lane: READY TO MERGE`. Push it.
