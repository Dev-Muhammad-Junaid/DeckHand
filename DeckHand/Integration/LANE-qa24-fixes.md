# Lane: build 24 QA fixes (qa24-fixes)

Branch `claude/pixelhand-lane-qa24-fixes`, from `claude/pixelhand-integration`
at `8470b2f`. It fixes the 1 failed and 6 new findings in
`VISUAL-QA-build24.md`, P2 first. No protocol change, no `project.yml` or
Info.plist change, and no Loom change (`Sources/`, `Tests/` untouched).

| ID | Status | Note | Files |
|---|---|---|---|
| VQ-100 (P2) | Fixed (needs a Mac re-check) | **Cause:** opened from the picker with several Macs, the sheet's `target` fell through to `lastMacDeviceID` under the placeholder name "your Mac", which matched no picker tag, so the unlabelled menu showed (and the binding fell back to) `choices[0]`. **Fix:** Core `PairingTargetChoice.defaultTarget` picks, in order: the Mac that asked (the Mac last tapped in the picker within 10 min, kept in `PairedMacsStore.noteConnectAttempt`, or the Mac the approval overlay opened the sheet for); the only Mac in reach; the only Mac in reach that is paired or used in the last 14 days (`MacMemory.lastUsedAt`). Otherwise nothing: list order is never used. With more than one Mac, a labelled **"Pair with"** row names the Mac (or reads "Choose a Mac" in amber, with an amber ring), the heading says "Type the code showing on your Mac", Connect and pair is disabled, a full code doesn't send itself, and the footer says "Choose the Mac that shows the code." **Keypad:** on iPhone, while the number pad is up, the lock tile is dropped and the sections tighten from 24 to 16 pt (`PairingSheetLayout`), and the footer is scrolled into view above the pad when the pad comes up and whenever its line changes (not at the Huge band, where the field matters more). | Core `Pairing/PairingTargetChoice.swift` (new); iOS `Pairing/PairingCodeEntryView.swift`, `Pairing/PairedMacsStore.swift`, `PeerPickerView.swift` |
| VQ-098 (P2) | Fixed (needs a Mac re-check) | The empty page's content (glyph, "No keys yet", message, Add keys) is a new keep-out, `.deckEmptyState`, reported only for the page on screen (the pager keeps its neighbours alive off screen). The tile always keeps clear of it when it can (shrinking via `fittingWidth`). At the Huge band (AX3–AX5), where it fills the page, the tile steps aside (hidden, stream running) when not even the smallest tile has a clear spot, the same way as VQ-083's edit mode (`MirrorTilePlacement.emptyStateStepsAside`). Below the Huge band it never hides. | Core `Mirror/MirrorTilePlacement.swift` (`surfacePlan(…, deckEmptyState:, band:)`); iOS `Mirror/MirrorTileKeepOut.swift`, `Mirror/MirrorOverlay.swift`, `Surfaces/DeckSurface.swift` |
| VQ-099 (P2) | Fixed (needs a Mac re-check) | At the Huge band the compact sidebar card stacks: tile on top, then the name and the status under it across the card's whole width (148 pt instead of 96 pt beside the tile). Both use the pill's `WholeWordName` layout on up to two lines, shrinking to real smaller sizes before a word is ever cut. From AX1 the name and status use whole words too (still in the row). The card has the Large Content Viewer (name and status) and keeps its VoiceOver label. Rules in Core `SidebarCardPlan`. | Core `Design/SidebarCardPlan.swift` (new); iOS `Shell/MacsSidebar.swift` |
| VQ-066 (P1, was failing) | Fixed (needs a Mac re-check) | **Cause:** at AX3 the empty state didn't fit, so `PHEmptyState` fell back to scrolling *everything*; Show screen sat below the visible part of the card, reading as cut. **Fix:** the fallback now scrolls only the glyph, title and message (with the scroll indicator flashed on appear), and the buttons sit pinned under them, inside the card, in full. Applies to every `PHEmptyState` (Screen, the free-plan deck, empty pages). | iOS `DesignSystem/Feedback.swift` |
| VQ-101 (P3) | Fixed (needs a Mac re-check) | **Cause:** after a cold boot Loom lists the paired Mac before its start returns; the launch reconnect correctly waits for the context (VQ-058), but nothing said so. **Fix:** Core `MacReconnectPolicy.pendingLaunchTarget` names the Mac the launch reconnect will dial once the network is ready. `MacSwitcher.pendingLaunchDeviceID` holds it (for at most `launchWaitLimit`, 30 s); the existing toast shows "Connecting to <Mac>…" with Cancel (`ph.connect.toast`, `ph.connect.cancel`), and the picker's card shows its connecting state (dotted ring, wave; the other cards dim). Cancel spends the launch try, as before. | Core `Macs/MacSwitchMachine.swift`; iOS `Macs/MacSwitcher.swift`, `ContentRootView.swift`, `PeerPickerView.swift` |
| VQ-102 (P3) | Fixed (needs a Mac re-check) | Once the picker's column scrolls under Pair and Settings (more than 2 pt), the bar gets a scroll-edge backdrop: the picker's own background drawn full screen and masked to the bar (opaque to 8 pt under the buttons, then a 16 pt fade), so its gradients line up exactly. At rest it is invisible. Scroll position via `onGeometryChange` in a named coordinate space (iOS 17-safe). | Core `Design/PickerTopBarPlan.swift` (new); iOS `PeerPickerView.swift` |
| VQ-103 (P3) | Fixed (tooling) | `connect()` never taps a Mac whose row doesn't say "paired". With `PH_QA_PAIRCODE_FILE` it pairs by code from the picker's Pair sheet (choosing the Mac on the new "Pair with" row), so the code goes with the request and the Mac doesn't ask. Without it, the walk is skipped with a `skipped-unpaired` snapshot, a "SKIPPED: …" activity and a log line naming the fix. `PH_QA_ALLOW_PROMPT=1` keeps the old tap-and-wait. A request still waiting when `connect()` gives up is withdrawn (Disconnect or Cancel, `request-withdrawn` snapshot). Documented in `MAC-BUILD.md`. | `PixelHandUITests/PixelHandUITests.swift`, `Integration/MAC-BUILD.md` |
| `PixelHandUITests.swift` structure | Checked | Brace-depth scan (skipping strings and comments): final depth 0, never negative. `swiftc -parse` passes. | |

## Linux results

- `swift test --package-path DeckHand/Core`: **1083 / 1083 pass** (194 suites). There were 1058 before this lane, so 25 tests are new:
  - `PairingTargetChoiceTests` (13): build 24's two unknown Macs with the other person's first give no default; the Mac that asked wins; the asking window; the only Mac, paired or recent Mac; duplicates; choices; copy; the keypad layout.
  - `MirrorTileDeckEmptyTests` (5): AX5 steps aside; the Huge band with room keeps the tile clear; smaller bands never hide; the band rule.
  - `SidebarCardPlanTests` (4), `PickerTopBarPlanTests` (2).
  - `MultiMacTests.pendingWhileNetworkStarts` (1).
- `DeckHand/Scripts/linux-typecheck/run.sh`: **Build complete**, no errors or warnings. `PairedMacsStore.swift` and `MacSwitcher.swift` (both changed) are in its list. No files were added to the list.
- Every changed iOS and UI-test file passes `swiftc -parse` (Swift 6.2).
- Loom: not touched, not run.

## Re-check steps

**iPad Pro 11" simulator (portrait, landscape, and a Stage Manager window dragged down to iPhone width):**
1. **VQ-100.** With two Macs listed (the MacBook and AH’s Mac mini), neither paired, tap Pair.
   - A "Pair with" row reads "Choose a Mac" in amber; the heading reads "Type the code showing on your Mac"; Connect and pair is disabled; typing a full code doesn't send it; the footer says "Choose the Mac that shows the code."
   - Choose the MacBook: the row and heading name it, and the code sends.
   - Tap the MacBook's row first (its Allow prompt shows), Disconnect, then Pair: the row already names the MacBook.
   - With the MacBook paired (or connected to in the last two weeks) and the mini not: the row names the MacBook.
   - With one Mac listed: no row; the heading names it.
2. **VQ-099.** AX3, landscape, Macs sidebar shown: each card has its tile on top and the name and status in whole words under it ("Muhammad’s / MacBook Pro", "AH’s Mac / mini", or the same at a smaller size). No "Muh / am…", "Text…", "Near…". Long-press a card: the Large Content Viewer shows the name and status. At AX1 the cards stay in a row without mid-word cuts.
3. **VQ-098 in the narrow Stage Manager window.** AX3, mirror on, an empty deck page, not editing: the tile sits clear of "No keys yet" or, with no room, is hidden; it is back when the page has keys or Dynamic Type is below AX3.
4. **VQ-102.** AX5 picker: scroll the list; the subtitle passes under a solid backdrop behind Pair and Settings, fading at its bottom edge. At rest no band is visible.
5. **VQ-066 on iPad.** Free plan (`PH_QA_FREE=1`), AX3, Screen focus with the mirror off: Show screen is whole inside the card.

**iPhone 17 Pro simulator:**
1. **VQ-100.** Picker › Pair: with the keypad up, the lock tile is gone and the field, Connect and pair, and the whole footer sit above the keypad. Type a wrong code: the error line scrolls into view above the keypad.
2. **VQ-098.** AX3 and AX5, mirror on, empty deck page, outside edit mode: the tile doesn't cover "No keys yet" or the card; at AX5 it is hidden (Edit and Add keys hittable). `test14` still shows the header clear.
3. **VQ-066.** `test12` with AX3 (`PH_QA_TAG=ax3`): `free-screen` shows Show screen whole inside the card, with the message scrolling above it if needed.
4. **VQ-101.** Shut down and boot the simulator, then launch: while Loom starts, "Connecting to <Mac>…" with Cancel shows, and the Mac's card has the dotted ring; then the shell. Cancel during the wait leaves the picker and doesn't dial.
5. **VQ-102.** AX5 picker, as on iPad.

**Mac (with the simulators):**
1. **VQ-103.** iPad mini (unpaired), no `PH_QA_PAIRCODE_FILE`: `test04` records `skipped-unpaired` and the result bundle has a "SKIPPED: …" activity; **no** Allow prompt appears on the Mac.
2. **VQ-103.** Open Pair a device on the Mac, put the code in a file, run `test15` on the iPad mini with `TEST_RUNNER_PH_QA_PAIRCODE_FILE` and `TEST_RUNNER_PH_QA_MAC_NAME`: `pair-sheet-from-picker`, `pairing-code-typed`, `pairing-sent`, then `paired-and-connected`, and no Allow prompt left on the Mac. Then `test04` connects without a code.
3. **VQ-103.** With a wrong code in the file: the walk ends with `never-allowed` then `request-withdrawn`, and the Mac's request card is gone.

## PixelHandUITests changes

- `connect()`: an unpaired row (its label lacks ", paired") is no longer tapped. It pairs by code from the picker (`pairFromPicker`), or skips (`skipConnect`), or, with `PH_QA_ALLOW_PROMPT=1`, taps and waits as before. On give-up it calls `withdrawRequest()`.
- New helpers: `isPairedRow`, `rowName`, `pairFromPicker`, `withdrawRequest`, `skipConnect`.
- New env var: `PH_QA_ALLOW_PROMPT`. Header comment lists `PH_QA_MAC_NAME` and `PH_QA_ALLOW_PROMPT`.
- New snapshots: `skipped-unpaired`, `pair-sheet-from-picker`, `pairing-sent`, `pair-sheet-stuck`, `pair-chooser-missing-mac`, `request-withdrawn`.
- No IDs renamed. `ph.pairing.macChooser` now names the labelled "Pair with" row (its label reads "Pair with, <Mac>" or "Pair with, Choose a Mac"). `ph.pairing.codeField`, `ph.pairing.pair`, `ph.pairing.reconnect`, `ph.pairing.scanQR`, `ph.connect.pair`, `ph.connect.toast`, `ph.connect.cancel` are unchanged. No new controls needed new IDs.

## Compile risks (most likely first)

None of the SwiftUI changes are type-checked on Linux.

1. **`PairingCodeEntryView.macChooser`**: a `Menu { Picker(selection: Binding<UUID?>) { ForEach … .tag(Optional(id)) } } label: { AnyLayout … }` with `.buttonStyle(.plain)` on the `Menu`. If the plain style doesn't apply to `Menu`, use `.menuStyle(.button)` with it, or drop it.
2. **`PairingCodeEntryView.sheetScroll(_:)`**: a `ScrollViewProxy` parameter used only in synchronous `.onChange` closures (the delayed scroll bumps `footerScrollTick` from a `Task`, so the proxy isn't captured by it). `footerLine` returns a `(text: String, color: Color)` tuple with `.white.opacity(0.7)` as an implicit member chain.
3. **`PeerPickerView`**: `.onGeometryChange(for:of:action:)` reading `geometry.frame(in: .named(Self.scrollSpace))`, `.coordinateSpace(.named(Self.scrollSpace))` (iOS 17), and `topBarBackdrop`'s `.mask(alignment: .top) { VStack … }`. In `peerList`, a `let busy = …` inside the `ForEach` builder closure.
4. **`PHEmptyState.pinnedActionsLayout`**: `ScrollView(showsIndicators:)` with `.scrollIndicatorsFlash(onAppear: true)` (iOS 17) inside `ViewThatFits(in: .vertical)`.
5. **`CompactMacCard`**: `AnyLayout(VStackLayout / HStackLayout)`, two `@ScaledMetric private var`s, `.accessibilityShowsLargeContentViewer { Text(…) }`, `WholeWordName(name:lines:size:weight:color:)` (memberwise order checked), and `import PixelHandCore` added.
6. **`MirrorOverlay`**: a new `@Environment(\.dynamicTypeSize)`; `MirrorTileKeepOut.plan(for:in:band:)` passes `deckEmptyState:` then `band:` after `deckEditGrid:`, in declaration order.
7. **`DeckSurface.emptyPage`**: `.mirrorTileKeepOut(.deckEmptyState, owner: sender, isActive: page.id == shownPage?.id)` on the `PHEmptyState` inside `PixelSurface`'s builder.
8. **`PixelHandUITests`**: `XCTContext.runActivity(named:) { _ in }` from the `@MainActor` test class; `XCUIElement.label` string handling.

## Behaviour notes

- VQ-100: with several Macs and none known, the person must now choose before a code goes out. That is the brief's "require a choice".
- VQ-098: below AX3 the tile never hides over an empty page; it only moves and shrinks to cover as little as it can. If the owner wants it hidden at AX1–AX2 too, return true for `.large` in `MirrorTilePlacement.emptyStateStepsAside`.
- VQ-101: while the launch reconnect waits, the picker's cards are dimmed and disabled, as during any dial; Cancel frees them.
- VQ-066: the pinned buttons apply to every `PHEmptyState` that doesn't fit, not only the free plan's.

## Out-of-lane edits

No other lanes are running. The brief owns whatever these need; listed for the record:
- `DeckHandiOS/DesignSystem/Feedback.swift` (`PHEmptyState`): shared by every empty state.
- `DeckHandiOS/ContentRootView.swift`: the switch toast's waiting case.
- `DeckHand/Integration/MAC-BUILD.md`: the VQ-103 section.

Lane: READY TO MERGE
