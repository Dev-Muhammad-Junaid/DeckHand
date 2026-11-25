# Lane: owner review, canvas, sidebar and right column (lane name: or-canvas)

Branch: `claude/pixelhand-lane-or-canvas`. Handoff: `DeckHand/Integration/LANE-or-canvas.md`.

## Scope (from OWNER-REVIEW-visual-qa-build18.md)
- **OR-04: a narrower Macs sidebar.** Take `sidebarWidth` from 232 to about 168–184 pt (Core `Design/LayoutMetrics.swift`) and use compact Mac cards. Give the space to the canvas. Update `CanvasPlan` and its Core tests.
- **OR-06: a collapsible right column with Deck | Ask.**
  - The right column (the deck and shortcuts for the front app) gets a collapse button. Collapsed, it leaves a slim edge handle.
  - Remember the collapsed state per arrangement (`ArrangementPreset`), and persist it.
  - Add a two-way switch, **Deck | Ask**, so Ask (⌘K) runs in place in the column as well as in its sheet. Reuse `AskSheet`'s view model and logic; don't fork them.
  - The Ask switch shows the typed request, the plan and the step-by-step run. That's where the dot-matrix loader belongs.
  - Selection on the switch is colour and fill only.
  - Put the state and plan logic in Core (`CanvasPlan` / `ArrangementPreset`), with tests.
  - Make it work across iPad portrait, landscape, Stage Manager narrow widths and iPhone. Where there's no right column (compact), keep today's behaviour.
- **OR-03, the remainder (Ask)**:
  - Ask's free-plan state shows no large "Try 2 weeks free" upsell card. It shows a small lock or "Pro" tag on the control (`Store/RequiresPro.swift` is already bottom-trailing).
  - The paywall opens only when the user taps a Pro feature.
  - Lane qa-surfaces already did the deck and the Screen state. Check the rest of the free-plan surfaces too.
- **The glyph, dot and loader rule** applies to everything you build. Fade panels over 150–200 ms, ease-out, and never slide them in.

## Owned files
- `DeckHandiOS/Shell/PixelHandShell.swift` and `ControlSurface.swift`
- `DeckHandiOS/Surfaces/AskSheet.swift` and `DeckSurface.swift`
- the Ask views and model
- the Macs sidebar view
- `Store/RequiresPro.swift` and `PaywallView.swift`
- Core `CanvasPlan`, `LayoutMetrics` and `ArrangementPreset`, with their tests

**Not yours:** lane or-ios-chrome, which runs at the same time, owns `ShellHeader.swift`, `SurfaceTabBar.swift`, `ContextStrip.swift`, `DesignSystem/*` and `Pairing/*`. If you need the header to pass something, add the parameter with a default and announce it. Lane or-mac-panel owns `DeckHandMac/`.

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

Write `DeckHand/Integration/LANE-or-canvas.md` with:
- a per-ID table (ID | Status Fixed/Partly/Won't fix | Note | Files);
- the Linux test results;
- re-check steps on the iPad Pro 11" simulator: portrait, landscape, and a Stage Manager window dragged down to iPhone width; and for Mac items, on the Mac;
- the `PixelHandUITests` changes, if any (keep the existing `ph.<area>.<name>` IDs working, and add IDs for new controls);
- compile risks, most likely first;
- out-of-lane edits.

The file's last line must be exactly `Lane: READY TO MERGE`. Push it.
