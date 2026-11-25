# Lane: build 23 QA fixes (qa23-fixes)

Branch `claude/pixelhand-lane-qa23-fixes`, from `claude/pixelhand-integration`
at `8983b84`. It fixes the 4 failed and 15 new findings in
`VISUAL-QA-build23.md`, P1 first. No protocol change, no `project.yml` or
Info.plist change, and no Loom change.

| ID | Status | Note | Files |
|---|---|---|---|
| VQ-083 (P1) | Fixed (needs a Mac re-check) | **Cause:** the deck header reports its keep-out from a `Group { if editing … else … }`. Tapping Edit, the edit header reported its frame (appear) *before* the normal header withdrew its own (disappear, after the transition), and that late withdrawal wiped the header just reported. The tile then homed to the canvas's top-trailing corner, over Done. **Fix:** every report carries its reporter's token, and a withdrawal only clears its own report (Core `MirrorTileKeepOutRegistry`). The edit grid is a new keep-out while editing (`.deckEditGrid`). Where no spot clear of the header and the grid is left even for the smallest tile (iPhone), the tile steps aside (hidden, not hit-testable, stream still running) until Done (`MirrorTilePlacement.surfacePlan` / `isShown`). On iPad the pad stays the anchor and the tile is moved clear of the deck column. | Core `Mirror/MirrorTileKeepOutRegistry.swift` (new), `Mirror/MirrorTilePlacement.swift`; iOS `Mirror/MirrorTileKeepOut.swift`, `Mirror/MirrorOverlay.swift`, `MirrorThumbnailView.swift`, `Surfaces/DeckSurface.swift` |
| VQ-058 (P2) | Fixed (needs a Mac re-check) | **Cause:** since build 22, Loom advertises and browses before its start returns (the CloudKit step). The paired Mac was listed before `MacSwitcher.start(context:)` ran, so the launch reconnect dialled with no context. `dial` failed silently, but the one try per launch was already spent, so the picker waited for a tap. **Fix:** `MacReconnectPolicy.launchTarget` takes `isNetworkReady`, and returns nothing (without spending the try) until the switcher has its context. `start(context:)` runs the launch check again. The existing "Connecting to <Mac>…" toast with Cancel (`ph.connect.cancel`) shows during the dial. | Core `Macs/MacSwitchMachine.swift`; iOS `Macs/MacSwitcher.swift` |
| VQ-095 (P2) | Fixed (needs a Mac re-check) | **Cause:** the Mac's curve (`d × (1 + (|d| − 3) × 0.12)` per message) is unbounded, so a flick's large coalesced deltas were multiplied up to ~12×. **Fix, on iOS:** `mouseDelta` names no display, so clamping on the Mac would need a protocol change. The remote knows the mirrored display and the pointer, so it clamps. While pointer control is on, `TrackpadSender` passes each coalesced delta through Core `PicturePointerGuard`, which: (1) caps the Mac's gain at 2× (a slow drag, under the knee, is untouched); (2) shortens the delta so the pointer stops 1 pt inside the mirrored display's edge, predicted with the Mac's own curve (Core `MacPointerAcceleration`, which the Mac's `InputInjector` now uses too). Cursor updates that lag the deltas in flight are ignored until the pointer rests 150 ms. With a mirrored window, or the pointer off the display, only the cap applies. The Pointer surface is unchanged. | Core `Input/MacPointerAcceleration.swift`, `Mirror/PicturePointerGuard.swift` (new); iOS `TrackpadSender.swift`, `Mirror/MirrorPicturePointer.swift` (`MirrorPicturePointerGuardFeed`), `Mirror/MirrorPane.swift`, `Control/ControlSessionModel+Mirror.swift`; Mac `InputInjector.swift` |
| VQ-060 (P2) | Fixed (needs a Mac re-check) | **Cause (most likely):** the button was dropped wherever `AVPictureInPictureController.isPictureInPictureSupported()` is false. iPhone simulators report false; iPad simulators and iPhones (iOS 14+) report true. **Fix:** phones always show the button (`MirrorToolbarPlan.pipButton`). Where the system can't start PiP, a tap explains in an alert ("Picture in Picture isn’t available") instead of doing nothing. iPads without PiP still hide it. | Core `Mirror/MirrorToolbarPlan.swift` (new); iOS `Mirror/MirrorPiPViews.swift` |
| VQ-084 (P2) | Fixed (needs a Mac re-check) | The picker's subtitle and status line wrap (`fixedSize` vertical). The Mac's name uses the pill's whole-word layout: one tail-truncated line at Standard and Large, and two whole-word lines at accessibility sizes. It is never cut in the middle. The layout is shared as `WholeWordName`. | iOS `PeerPickerView.swift`, `DesignSystem/WholeWordName.swift` (new) |
| VQ-085 (P2) | Fixed (needs a Mac re-check) | **Cause:** `ViewThatFits` measures ideal sizes, so build 22's shrinking fallback (`minimumScaleFactor`) never won by size. At AX5 both lines simply truncated. **Fix:** after the full-size candidates, the whole-word splits are offered at real smaller font sizes (85 %, 70 %, 55 %), which `ViewThatFits` can measure. The last resort is the first word alone at 50 %. No "…" in any shrunk layout. | Core `Design/ShellChromePlan.swift` (`shrinkCandidates`, `lastResort`, `pillNameShrinkScales`); iOS `DesignSystem/MacPill.swift`, `DesignSystem/WholeWordName.swift` |
| VQ-086 (P2) | Fixed (needs a Mac re-check) | The keyboard-bar copy of Pair / Connect and pair is gone; it floated over the footer. One button stays under the field, above the keypad (VQ-030), and a full code still sends itself. The title is now "Pair"; the heading names the Mac. | iOS `Pairing/PairingCodeEntryView.swift` |
| VQ-034 (P3) | Partly | The keyboard row already had a fade, but only 16 pt, which read as no fade at a cut key. It is now one key wide (48 pt, `TrailingFade.overflowWidth`), with the same trailing padding, so a row that fits shows no fade. `frame(maxWidth: .infinity)` keeps the scroll view inside the panel. Partly, because I couldn't confirm on Linux why QA saw no fade at all. Re-check on the iPhone. | iOS `Keyboard/RemoteKeyboardPanel.swift`, `Shell/AppDock.swift` (`TrailingFade`) |
| VQ-061 (P3) | Fixed (needs a Mac re-check) | **Cause:** the 3 s timer was keyed only on touches. When the pane appeared before the first frame, it fired, saw no frame, gave up, and never ran again. **Fix:** the timer is keyed on `MirrorToolbarPlan.HideKey` (touches, picture, picker sheet, VoiceOver), so it restarts when the first frame lands. It also restarts when a sheet closes or VoiceOver turns off. | Core `Mirror/MirrorToolbarPlan.swift`; iOS `Mirror/MirrorPane.swift` |
| VQ-087 (P3) | Fixed (needs a Mac re-check) | At the Huge band the Deck \| Ask segments show glyphs only, with the Large Content Viewer and VoiceOver giving the word. The Ask placeholder is "Ask your Mac" there. | Core `Design/RightColumn.swift` (`switchShowsTitles`, `AskFieldCopy`); iOS `Shell/RightColumnChrome.swift`, `Surfaces/AskSheet.swift` |
| VQ-088 (P3) | Partly | Same as VQ-034: the chip row's fade (24 pt) is now 48 pt with matching padding. | iOS `Shell/ContextStrip.swift` |
| VQ-089 (P3) | Fixed (needs a Mac re-check) | Settings' segmented pickers (frame rate, haptics, send rate, quality, theme) become menu pickers at the Huge band (`SettingsPickerPlan`, `.settingsChoicePickerStyle()`). | Core `Design/SettingsPickerPlan.swift` (new); iOS `Settings/SettingsChoicePicker.swift` (new) and four Settings sections |
| VQ-090 (P3) | Fixed | "Restore purchases" in the paywall footer and the error copy. | iOS `Store/PaywallView.swift`, `Store/SubscriptionStore.swift` |
| VQ-091 (P3) | Fixed | The hint is now "Bring an app to the front", short enough for the landscape rail. VoiceOver still hears "…on the Mac". | iOS `Shell/ContextStrip.swift` |
| VQ-092 (P3) | Fixed (tooling) | `test02` and `test11` call `useFullScreenAppsIfAsked()`. With `TEST_RUNNER_PH_QA_FULLSCREEN=1` on an iPad, it sets Settings › Multitasking & Gestures › Full Screen Apps through the Settings app before rotating. The manual step and the env vars are documented in `MAC-BUILD.md`. | `PixelHandUITests/PixelHandUITests.swift`, `Integration/MAC-BUILD.md` |
| VQ-093 (P3) | Fixed (needs a Mac re-check) | **Cause (most likely):** with `drawsDotField: false`, the picture's `TrackpadInputLayer` held only the UIKit view. Its `.accessibilityElement()` and `ph.mirror.pointerSurface` had no SwiftUI node to land on; the Pointer pad has its `DotField`. **Fix:** a `Color.clear` takes the dot field's place (it isn't hit-testable, so touches still reach the pad). `test16` already uses this ID. | iOS `TrackpadView.swift`; UI tests (comment) |
| VQ-094 (P3) | Fixed (needs a Mac re-check) | The pair window has the panel's invisible focus sink, so New code no longer opens with the pink ring. Tab still reaches every button. | Mac `Pairing/PairDeviceWindow.swift` |
| VQ-096 (P3) | Fixed (tooling) | `connect()` taps the row whose label starts with `PH_QA_MAC_NAME` (set `TEST_RUNNER_PH_QA_MAC_NAME`). Unset, it taps the first Mac. | `PixelHandUITests/PixelHandUITests.swift`, `Integration/MAC-BUILD.md` |
| VQ-097 (P3) | Fixed | "Last seen" is minute-grained ("just now", "N min ago", then the system's relative date), and the row redraws every 30 s, so it never freezes on seconds. | Core `Design/MacDeviceListPlan.swift` (`recentSeen`); Mac `Pairing/PairingMenuSection.swift` |
| `PixelHandUITests.swift` structure | Checked | Brace-depth scan (skipping strings and comments): final depth 0, never negative. | |

## Linux results

- `swift test --package-path DeckHand/Core`: **1058 / 1058 pass** (190 suites). There were 1031 before this lane, so 27 tests are new:
  - `MirrorTileDeckEditTests` and `MirrorTileKeepOutRegistryTests`: the build 23 appear-before-disappear sequence; iPhone edit mode steps aside; iPad moves clear; a sweep of grid sizes never covers the header.
  - `MacReconnectTests.waitsForNetwork`.
  - `PicturePointerGuardTests` and `MacPointerAccelerationTests`: the build 23 flick stops at the edge; every direction lands on the display; a slow drag is unchanged; the gain cap; lagging cursor updates; bad input.
  - `MirrorToolbarPlanTests`.
  - `ShellChromePlanTests.pillNameShrinks`.
  - `MacPanelLastSeenTests`.
  - `Build23AccessibilityPlanTests`.
- `DeckHand/Scripts/linux-typecheck/run.sh`: **Build complete**, no errors. `TrackpadSender.swift` (changed) is in its list. No files were added to the list.
- Every changed iOS, Mac and UI-test file passes `swiftc -parse`.
- Loom: not touched, not run.

## Re-check steps

**iPad Pro 11" simulator (portrait, landscape, and a Stage Manager window dragged down to iPhone width):**
1. **VQ-083.** Mirror on, show the deck, tap Edit.
   - The tile moves clear of the deck column's header and grid, and Done is hittable.
   - In the narrow Stage Manager window (tabbed, like iPhone): the tile disappears while editing and comes back on Done.
   - Drag the tile onto the header outside edit mode: it springs back below.
2. **VQ-095.** Layout › Screen focus, pointer control on.
   - A slow 50 pt drag still moves the pointer about 180 pt.
   - A quick flick in any direction stops the Mac pointer at the mirrored display's edge. It never reaches another display.
   - With two displays, pick the other one in the display picker and repeat.
   - The Pointer tab still crosses displays freely.
3. **VQ-093.** Run `test16`: no `missing-ph.mirror.pointerSurface`; `pointer-control-moved` and `pointer-control-zoomed` are captured.
4. **VQ-061 / VQ-060 on iPad.** The toolbar hides 3 s after the first frame, also after closing the display picker. The PiP button is unchanged.
5. **VQ-087 / VQ-089 at AX3.**
   - The column switch shows two glyphs. Long-press one: the Large Content Viewer says Deck or Ask.
   - The Ask placeholder reads "Ask your Mac".
   - Settings' frame rate, send rate, quality, theme and haptics are menus.
6. **VQ-088.** iPad portrait, keyboard up: the chip row's last chip fades over about one chip width.
7. **VQ-092.** Run `test11` with `TEST_RUNNER_PH_QA_FULLSCREEN=1`: `fullscreen-set`, then real landscape captures and the Macs sidebar.

**iPhone 17 Pro simulator:**
1. **VQ-083.** `test14`: `deck-edit-with-tile` shows edit mode with no tile, and Done is tapped. There is no `not-hittable-ph.deck.done`.
2. **VQ-058.** Fresh install, pair during onboarding, finish: "Connecting to <Mac>…" with Cancel, then the shell. Quit and relaunch: it reconnects by itself. Cancel during the dial leaves the picker.
3. **VQ-060 / VQ-061.** `test06`:
   - `ph.mirror.pictureInPicture` exists. On the simulator, the tap shows `pip-unavailable`.
   - At `screen-4s` the toolbar is hidden.
   - A tap on the picture brings it back.
4. **VQ-084.** AX3 picker: the subtitle wraps, and the name reads "Muhammad’s / MacBook Pro" with no middle cut. The status reads "Paired · Nearby", wrapped if needed.
5. **VQ-085.** AX5: the pill shows two whole-word lines in a smaller size, or "Muhammad’s" alone. It never shows "Muhamma…".
6. **VQ-086.** Picker › Pair: one Connect and pair button under the field. The footer is readable above the keypad. The title is "Pair".
7. **VQ-034.** Keyboard up: the modifier row's last key fades.
8. **VQ-091.** Landscape: the rail hint reads "Bring an app to the front" in full.

**Mac:**
1. **VQ-094.** Open Pair a device: no focus ring on New code. Tab moves focus to New code and then Cancel.
2. **VQ-097.** With the panel open, a device's "last seen just now" becomes "1 min ago" and then "2 min ago" without closing the panel.
3. **VQ-090.** Free plan (`PH_QA_FREE=1`): the paywall footer reads "Restore purchases".
4. **VQ-096.** With "AH’s Mac mini" on the network, run `test04` with `TEST_RUNNER_PH_QA_MAC_NAME="Muhammad’s MacBook"`: only the MacBook gets a request.

## PixelHandUITests changes

- `connect()` taps `macRow()`: by `PH_QA_MAC_NAME` (label prefix, case-insensitive), or the first Mac when it isn't set.
- `test02_OnboardingLandscape` and `test11_Landscape` call `useFullScreenAppsIfAsked()`. It does nothing unless `PH_QA_FULLSCREEN=1` on an iPad, and on failure it captures `fullscreen-missing-multitasking` or `fullscreen-missing-option`.
- `test06`: after the PiP tap, it dismisses the "Picture in Picture isn’t available" alert if shown (captures `pip-unavailable`).
- `test16`: unchanged logic. `ph.mirror.pointerSurface` now exists (VQ-093).
- No IDs were renamed. The PiP button keeps `ph.mirror.pictureInPicture` in both states.

## Compile risks (most likely first)

None of the SwiftUI, UIKit or AppKit changes are type-checked on Linux.

1. **`WholeWordName.body`**: `ViewThatFits` with two `ForEach`es plus one more child. One `ForEach` is over the `Hashable` struct `ShrinkStep`. If the type checker struggles, build one array of `(lines, size)` and use a single `ForEach`.
2. **`MirrorPicturePointerGuardFeed`**:
   - `.onChange(of: size?.width)` on an `Optional<Double>`.
   - `.onChange(of: session.mirrorCursor, initial: true)`.
   - It calls the actor methods `startPicturePointer(displayWidth:height:)`, `stopPicturePointer()` and `syncPicturePointer(...)` from `Task {}`.
   - `mirroredDisplayPointSize` returns a labelled tuple.
3. **`MirrorThumbnailView.isShown`**: builds `MirrorTileSurfacePlan` (PixelHandCore, through the module's re-export, as `MirrorTilePlacement` already is) and adds `.opacity`, `.allowsHitTesting`, `.accessibilityHidden` and `.animation(value: isShown)` after the existing chain.
4. **`MirrorTileKeepOutReporter`**: now holds `@State private var reporter = UUID()` and an `.onChange(of: isActive)`. `MirrorTileKeepOut` stores a Core generic struct in an `@Observable` class. `layout(for:in:)` is now `plan(for:in:)`; `MirrorOverlay` is its only caller.
5. **`MirrorPiPToolButton.body`**: an `if / else if` with two `MirrorToolButton` branches, each with its own `.alert`. It now imports UIKit (`UIDevice`).
6. **`SettingsChoicePickerStyle`**: `content.pickerStyle(.menu)` and `.segmented` on `ViewModifier` content, inside `if/else`.
7. **`RightColumnSwitch`**: `.accessibilityShowsLargeContentViewer { Text(...) }` (iOS 15+, as in `AppDock`) and `PHGlyph(..., stepsWithType: true)`.
8. **`PairDeviceWindow`**: the focus sink sits in `.background(alignment: .topLeading) { … }` (macOS 14 `focusEffectDisabled`, as in the panel).
9. **`useFullScreenAppsIfAsked()`**: `UIDevice.current` in the UI-test runner (XCTest on iOS re-exports UIKit; the file already uses `UIDeviceOrientation`).

## Behaviour notes

- VQ-083: on iPhone the tile now hides while the deck is edited. That is the brief's "hide it while editing" option, used only where nothing clear is left; iPad keeps it visible.
- VQ-095: the cap makes a fast flick on the *picture* travel less than before (2× gain at most), which is the point. The Pointer surface and the classic trackpad are untouched.
- VQ-060: on a device whose system says no PiP, phones now show a button that explains. If the owner prefers it hidden there, return `.hidden` for `isPhone` in `MirrorToolbarPlan.pipButton`.
- VQ-034 / VQ-088 are "Partly": the fades existed and are now three times wider. If the iPhone still shows no fade, the mask isn't the problem: look at the row's frame.

## Out-of-lane edits

No other lanes are running. The brief owns whatever these need, so these are listed only for the record:
- `DeckHandMac/InputInjector.swift`: the acceleration curve now calls Core `MacPointerAcceleration.apply`. The maths are identical.
- `DeckHandiOS/TrackpadView.swift`: a `Color.clear` takes the dot field's place when it isn't drawn.
- `DeckHandiOS/Shell/AppDock.swift`: `TrailingFade` gained `overflowWidth`. The dock itself is unchanged.

Lane: READY TO MERGE
