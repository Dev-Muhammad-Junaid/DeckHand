# Lane or-ios-chrome: owner review, iOS chrome and the glyph rule

Branch: `claude/pixelhand-lane-or-ios-chrome` (from `claude/pixelhand-integration` at
`16425e9`). Brief: `BRIEF-or-ios-chrome.md`. Run `xcodegen generate` first:
there are new iOS files (`DesignSystem/PanelFade.swift`,
`Network/LastLANStore.swift`).

## Per-ID table

| ID | Status | Note | Files |
|---|---|---|---|
| OR-01 | Fixed | The 4 pt `TabDot` is gone. The selected tab is accent on a `fill2` capsule. The capsule fades in place over 180 ms instead of sliding (`matchedGeometryEffect` removed). With Reduce Motion it changes at once. | `Shell/SurfaceTabBar.swift` |
| OR-02 | Fixed | No dot row under strip chips, quick-action chips, dialog chips or deck keys. `DeliveryStrip` and `.deliveryDots` are replaced by `.deliveryReceipt`. Running a chip or key gives only the press state and the existing haptic. A refusal tints the outline danger for 1.4 s, plays a heavy haptic and is announced. Rule in Core: `ChromeRule.pressFeedback`. | `DesignSystem/ContextChip.swift`, `DesignSystem/DeckKey.swift`, `DesignSystem/DeliveryStrip.swift`, `QuickActions/QuickActionsChips.swift`, `QuickActions/QuickActionsDialog.swift`, `DeliveryDots.swift` |
| OR-05 | Fixed | One `SidebarToggleButton` (44 pt, lit while the sidebar shows). When the sidebar is hidden, it leads the header row, before the Mac pill. When the sidebar shows, it leads the sidebar's title row. Both rows are 56 pt tall, start at the 24 pt wide margin and sit after Stage Manager's window controls, so the button doesn't move. It no longer folds into More. Core: `SidebarTogglePlacement`. | `Shell/ShellHeader.swift`, `Shell/MacsSidebar.swift` (out of lane) |
| OR-12 (iOS) | Fixed | Removed the trailing "…" from the remaining iOS buttons and menu items: Region, Window (capture menu and the mirror's menu), A window (display picker), Share (inbox). Both pairing hints name "Pair a device"; the code-entry hint now quotes it. Status text ("Connecting…", "Pairing…") keeps its ellipsis. A Core lint test keeps new ellipses out. | `Control/CaptureCapsule.swift`, `Mirror/MirrorOverlay.swift`, `Mirror/MirrorDisplayPickerSheet.swift`, `Transfer/InboxPanel.swift`, `Pairing/PairingCodeEntryView.swift` |
| Glyph rule: selection | Fixed | Tab bar (OR-01), chips (OR-02). The dock's running dot under app icons is also removed: the front app keeps only its accent ring. Pagers (deck page dots, desktop dots, onboarding page dots) are position indicators, not selection markers under an item, so they stay. | `Shell/AppDock.swift` (out of lane) |
| Glyph rule: loader | Fixed (audit) | Every loader use was audited (`DotWave`, `DotScan`, `DotBeam`, `DeckHandLoadingStateView`, one `ProgressView`). Each one is real waiting: connecting, pairing, the camera, the Mac's screen/windows/apps/menus, capture, OCR, prices, logs, a host test, transfers, Ask planning. No chip, shortcut, tab switch or app opening shows one, so nothing needed changing. Core: `ChromeRule.showsLoader(for:)`. | (audit only) |
| Glyph rule: motion | Fixed | Every `.move(edge: .bottom)` in the iOS app now fades: the Pointer keyboard panel, the shell keyboard panel, the picker's Mac cards, the screenshot toast and the classic trackpad's keyboard. The top and trailing slides also fade: the shortcuts import banner and grid, the classic bar's chip rows, and the sidebar's leading slide. New `phPanelFade(value:)` / `PixelHandMotion.panelFade` give 180 ms ease-out, and `nil` (instant) under Reduce Motion. Used on the Pointer surface (keyboard, click strip, caption), the picker (cards, checks, error toast) and the tab bar. A Core lint test fails on any new bottom slide. | `DesignSystem/PanelFade.swift`, `Surfaces/PointerSurface.swift`, `PeerPickerView.swift`, `Shell/PixelHandShell.swift`, `ScreenshotPreviewView.swift`, `TrackpadView.swift`, `AppShortcutsSheet.swift`, `QuickActionsBar.swift` |
| Widgets (OR-15) | Not touched | As the brief says. | — |
| VQ-079 (rest) | Fixed | Requests now carry the `RemoteSurface`. On preset windows (iPad side-by-side and columns), Trackpad switches the arrangement to Pointer. Screen switches Pointer to Split, because in Pointer the screen is only a tile. Deck leaves the arrangement alone. Tabbed windows only switch the tab, as before. A request is applied once per shell. Core: `RemoteSurface.arrangement(from:)`. | `Intents/IntentBridge.swift`, `Shell/PixelHandShell.swift` (out of lane, one call moved) |
| VQ-069 (rest) | Fixed | Fallback to the paired Mac's last LAN address while Bonjour is quiet. Each session on Wi-Fi or Ethernet to a paired Mac records the private address it runs over. Cable (link-local), VPN, cellular, loopback and public addresses are not kept. Addresses expire after 30 days, and a forgotten Mac's address is dropped. The overlay directory probes these addresses next to the saved VPN hosts. A Mac that answers is listed and dialled as a remote peer: paired only, pinned to its stored key (`RemoteConnect`, S15). While no Mac is listed, the picker calls `loomContext.refreshPeers()` at 2, 5, 9, 15, 25 and 40 s. That also restarts the Bonjour browse. The three checks still show at 10 s. Core: `LastLANBook`, `LANFallbackPlan`. No protocol change. | `PeerPickerView.swift`, `Network/LastLANStore.swift` (new), `Network/RemoteHostsStore.swift`, `Control/ControlSessionModel+Network.swift` (out of lane) |

Core additions, all with Swift Testing tests:
- `Design/ChromeRule.swift`: panel fade, loader occasions, press feedback and button titles.
- `Design/SidebarTogglePlacement.swift`.
- `Network/LastLANBook.swift`: `LastLANBook` and `LANFallbackPlan`.
- `Intents/SurfaceArrangement.swift`.
- Tests: `ChromeRuleTests.swift` (rule, OR-05, VQ-079, and a lint over `DeckHandiOS/` for bottom slides, selection and delivery dots, button ellipses and the pairing hints) and `LastLANBookTests.swift`.

The design docs were updated to match: `06-Pixel-Identity.md` §5 (press, selection, panels), `02-Design-System.md` (delivery receipt) and `04-Interaction-Model.md` (chips).

## Linux results

- `swift test --package-path DeckHand/Core` (Swift 6.2): **939 tests in 169 suites passed.**
- `DeckHand/Scripts/linux-typecheck/run.sh`: **Build complete.** `Network/LastLANStore.swift` was added to the list, because `RemoteHostsStore.swift` now uses it.

## Re-check steps (iPad Pro 11" simulator)

Check portrait, landscape, and a Stage Manager window dragged down to iPhone width.

1. **OR-01:** at iPhone width (tab bar), switch Pointer, Screen and Deck. There is no dot under the selected tab. Only the accent tint and the fill change, and the fill fades in place without sliding. Turn on Reduce Motion: the change is instant.
2. **OR-02:** run a strip chip, a deck key and (in the classic layout, DEBUG) a quick-action chip. You get the press dim and a haptic, and no dots appear. Quit the Mac app, then run a chip. After the timeout the outline turns red for about 1.4 s, a stronger haptic plays, and VoiceOver says "The Mac didn't confirm that command".
3. **OR-05:** in landscape (columns), hide the Macs sidebar with the button at the left of "Macs". The show button appears in the same place, at the left of the header before the Mac pill. Tap it: the hide button is back in the same place. Repeat in a Stage Manager window that is still wide enough for columns. The button sits just after the window controls in both states.
4. **OR-12:** long-press the capture button: Full screen / Region / Window / Read text, none ending in "…". The mirror's menu shows "Window". The display picker shows "A window". The inbox shows "Share". On the pairing code screen with no Mac code: Choose “Pair a device”…
5. **Motion:** on the Pointer surface, open and close the keyboard. It fades in place and doesn't rise from the bottom. With no Mac running, launch: the picker's cards fade in when the Mac appears.
6. **VQ-079:** in landscape, choose the Split arrangement. Add the Trackpad control in Control Center and tap it. Pixel Hand opens in the Pointer arrangement. In portrait at iPhone width it opens the Pointer tab, as before.
7. **VQ-069:** connect once over Wi-Fi to a paired Mac. The console (`category:connection`) shows "Saved the paired Mac's LAN address…". Quit Pixel Hand. On the Mac, stop Bonjour from answering: for example, block mDNS with the firewall or put the iPad on a network that drops multicast. Then relaunch. Within a few seconds the Mac is listed (as Remote) and connects without asking. Console: "No Mac listed yet; refreshing discovery…". An unpaired Mac is never probed this way.

## PixelHandUITests

No changes. Existing IDs are kept: `ph.tab.*`, `ph.strip.chip`, `ph.deck.key`, `ph.connect.*`, `ph.header.*`. The new sidebar button has the ID `ph.header.sidebar`, in both the header and the sidebar. No test referred to the labels that changed.

## Compile risks (most likely first)

1. **`IntentSurfaceModifier` moved inside the `GeometryReader`** in `PixelHandShell.body`. It gets a fresh `presetBinding(plan)` on every pass and has `@State appliedID`. If or-canvas restructured `body`, re-attach the call to the ZStack where `plan` is in scope.
2. **`MacsSidebar` title row** uses `SidebarToggleButton` (declared in `ShellHeader.swift`) and `WindowControlsInset`. If or-canvas rewrote that row for OR-04, keep `SidebarToggleButton(sidebarShown: true, action: onCollapse)` leading, the row height at `SidebarTogglePlacement.rowHeight`, and the leading padding at `sidebarLeadingPadding`.
3. **`DeliveryReceiptModifier`** uses `.onChange(of:) { _, new in }` (iOS 17) and `GestureHaptic.heavy`.
4. **`PeerPickerView`** has a second `.task(id: peers.isEmpty)` that reads `peers` (`@LoomQuery`) and calls `loomContext.refreshPeers()` after awaits.
5. `withAnimation(PixelHandMotion.panelFade(...))` passes an `Animation?`. The SwiftUI API accepts an optional.
6. `DeliveryDots` is now a caseless enum with a `@MainActor static func announceFailure()`. The view and the `.deliveryDots` modifier are gone, and nothing else used them.
7. `PointerSurface` still declares `reduceMotion`, but nothing uses it now (no warning for property wrappers).

## Out-of-lane edits (all minimal)

- `Shell/PixelHandShell.swift` (or-canvas): the sidebar and keyboard-panel transitions are now `.opacity`, and `.intentSurfaceRequests` moved inside the GeometryReader with `preset:`. **Left for or-canvas:** the keyboard panel's `.animation(spring, value: isKeyboardShown)` (several places) still times its fade with the 0.4 s spring, because it also animates layout. The sidebar show/hide also still uses the spring for the layout change.
- `Shell/MacsSidebar.swift` (or-canvas): the title row only (OR-05). Also note: the Ask field's "Tell <Mac>…" in that file reads as a field placeholder, not a button title, so it keeps its ellipsis. Change it if the owner reads it as a button.
- `Shell/AppDock.swift`: removed the running dot.
- `DeliveryDots.swift`: the dot view is removed; `DeliveryState` and `DeliveryTracker` are kept.
- `Control/ControlSessionModel+Network.swift`: records the LAN address in `linkTask`.
- `Network/RemoteHostsStore.swift`: `currentSeeds()` appends the LAN seeds.
- One-line transition or label changes in `ScreenshotPreviewView.swift`, `TrackpadView.swift`, `AppShortcutsSheet.swift`, `QuickActionsBar.swift`, `Control/CaptureCapsule.swift`, `Mirror/MirrorOverlay.swift`, `Mirror/MirrorDisplayPickerSheet.swift` and `Transfer/InboxPanel.swift`.
- `Scripts/linux-typecheck/run.sh`: added `LastLANStore.swift`.
- `Product/Design/02-…`, `04-…` and `06-…`: the rule text.

Lane: READY TO MERGE
