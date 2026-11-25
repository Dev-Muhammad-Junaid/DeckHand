# Lane: owner review, Mac menu-bar panel (or-mac-panel)

Branch: `claude/pixelhand-lane-or-mac-panel` (merged with the latest
`origin/claude/pixelhand-integration`, `bce0e75`, before this handoff).
Brief: `BRIEF-or-mac-panel.md`. Source: `OWNER-REVIEW-visual-qa-build18.md`.

Checks run here (Linux, Swift 6.2):

- `swift test --package-path DeckHand/Core`: **940 tests in 171 suites
  pass** (the new `MacPanelOwnerReviewTests.swift` adds 24 tests in 6
  suites).
- `DeckHand/Scripts/linux-typecheck/run.sh`: passes. It covers
  `MacTransferService.swift` and `DeviceAuthorizationManager.swift`, the
  two non-SwiftUI Mac files this lane changed.
- Loom: not touched. Protocol: not bumped.

## Findings

| ID | Status | Note | Files |
| --- | --- | --- | --- |
| OR-08 | Fixed | One **Devices** list from Core `MacDeviceListPlan`. Requests come first: amber, Deny / Pair / Allow on the row. Then live sessions, newest first, with the live pixel, link badge, LOCKED and session id. Then paired devices that are away, dim, most recently seen first. A paired device that is connected shows once. Disconnect and Forget (or Pair, for a device allowed only for this session) sit in each row's menu and its right-click menu. Forget confirms in the row. One "Pair a device" button and the code status line sit under the list. The separate "Asking to connect" and "Paired" sections are gone. Kept from qa-flows: the focus sink, the turned-away note and the pending header copy (`MacPanelCopy.headerStatus`, unchanged). | Core `Design/MacDeviceListPlan.swift`, `MacMenuBarView.swift`, `Pairing/PairingMenuSection.swift` (now `MacDevicesList`), `DeviceAuthorizationManager.swift` (`pairedRef(connectionID:)`) |
| OR-09 | Fixed | The panel's dots used the shared `LivePixel`, whose `phaseAnimator` animated the whole transaction, so the dots slid along with the panel's first layout. The new `MacStatusPixel` fades in over 180 ms, ease-out (`MacPanelMotion.fadeDuration`, tested to be 150–200 ms). Its fade and breath use scoped `.animation(_:body:)` on opacity only, so position is never animated. Under Reduce Motion the dot changes at once. Only the header's dot breathes; the permission dots and device-corner dots are still. `LivePixel` (shared with iOS) is unchanged. | Core `Design/MacPanelMotion.swift`, `UI/MacPixelViews.swift`, `MacMenuBarView.swift`, `Pairing/PairingMenuSection.swift`, `Pairing/PairDeviceWindow.swift` |
| OR-10 | Fixed | The QR centre now shows the icon's hand tile (`MacHandTile`). Its side is a whole, odd number of modules (`QRCentreTile`), and it is `.position`ed on the centre module's centre. Tests check this for every QR size from 21 to 77 modules, and check that the tile covers only cleared modules. Cause of the offset: the hand's 17 × 18 canvas has an empty last column (its lit dots are 16 × 18), and the pointer glyph's dots fill only 6 of its 9 columns. Art is now centred on its lit dots (`GlyphInkCentring`): the hand moves half a pitch right, and `MacGlyphTile` (the window's placeholders) centres any glyph the same way. The hand's pitch is a whole half point and its frame is its canvas, so the glyph's height matches its frame. | Core `Design/MacPanelMotion.swift` (`GlyphInkCentring`, `QRCentreTile`), `UI/QRDotsView.swift`, `UI/MacPixelViews.swift` |
| OR-11 | Fixed (verified) | qa-flows' fix holds. The Mac plate draws both groups with the same style, with no dim check digit. The iOS entry field groups 4+4 with `PairingCode.groupSize`. Onboarding shows "4821 0934". New Core tests check that "48210934" is a valid code, that it formats as "4821 0934", and that the Mac's groups join to the entry field's grouping. No iOS edit was needed. | Core tests only |
| OR-12 (Mac) | Fixed | No Mac button or menu item ends in "…". Row actions come from `MacDeviceListPlan.Action.title`, which is tested along with "Pair a device" and the turned-away buttons. The Send menu's "File…" is now "File". A sweep of `DeckHandMac` string literals finds "…" only in status text and comments. | `Transfer/MacTransferSection.swift`, Core tests |
| OR-13 | Fixed | **Devices \| Transfers** switch (`MacPanelTabs`). Selection is shown by fill and weight only, with no dot or bar. The switch appears only while a transfer is under way, an Accept is waiting, or a transfer finished in the last hour. Its badge counts what is under way, or the last hour's finished ones when nothing is. The Devices view keeps Send (targets and prompts) plus one summary row ("3 files sending · 42 %", "4 files moving · 31 %", "4 saved · 1 cancelled · 1 failed") with the overall beam; the row opens the tab. The tab lists "Now" then "Last hour", each row with its beam, Cancel or Show in Finder, and Clear. Rows record `startedAt` and `finishedAt`; the service prunes rows that finished more than an hour ago, every minute. Core `TransferPanelPlan` holds the summary, grouping, badge and expiry, tested with 6 files (3 each way, one cancel, one failure) through to expiry. | Core `Transfer/TransferPanelPlan.swift`, `Transfer/MacTransferService.swift`, `Transfer/MacTransferSection.swift` (`MacTransfersTab`), `UI/MacPixelViews.swift`, `MacMenuBarView.swift` |
| Glyph/dot rule | Applied | Tabs show selection with colour and fill only. Only one status light breathes. No loader is used for tab switches. | as above |

## Re-check steps

The changes are Mac-only, so the iPad Pro 11" pass (portrait, landscape,
Stage Manager at iPhone width) has nothing new to see. Run it as usual
for the other lanes. On the Mac, with build 19+:

1. **One list (OR-08).** With nothing paired and nothing connected, the
   panel shows "No devices yet" and the Pair a device button. Pair an iPad,
   then disconnect it: one dim row reads "Paired · not connected · last
   seen now", and its row menu (the circled-ellipsis button) holds only
   Forget. Connect it: the same row becomes bright with the mint pixel,
   "Connected · paired", and its menu holds Disconnect and Forget. Connect
   an unpaired iPhone: an amber row at the top with Deny / Pair / Allow,
   and the header reads "iPhone … is asking to connect". Allow it: the row
   reads "Connected for this session", and its menu holds Pair and
   Disconnect. Forget from a menu: the row asks "Forget …? It disconnects
   now …" with Cancel and Forget. Right-click any row: the same menu.
2. **Focus (qa-flows).** Open the panel with Full Keyboard Access on: no
   focus ring, and Space does nothing. Tab reaches each row's menu button.
3. **Fade (OR-09).** Open the panel a few times: the permission dots and
   the header dot fade in where they are and never slide up. Turn on
   Reduce Motion: they appear at once and the header dot stops breathing.
4. **QR (OR-10).** Pair a device: the hand tile sits exactly in the QR's
   middle (count the modules on each side), and the hand looks centred in
   its tile. The code still scans from the iPad. The header's hand tile
   looks centred too.
5. **Code (OR-11).** The plate reads "4821 0934"-style, all eight digits
   equally bright, matching the iPad's entry field.
6. **Transfers (OR-13).** From the iPad, send 3 files to the Mac, and from
   the Mac send 3 files to the iPad (Send › File, pick three). The switch
   appears with badge 6. Devices shows one row, "6 files moving · N %".
   Click it to open Transfers: "Now" lists the six. Cancel one outgoing,
   and turn off the iPad's Wi-Fi mid-way (or decline) for a failure. When
   the rest finish, the summary reads "4 saved · 1 cancelled · 1 failed"
   and the badge shows 6. Clear removes the finished rows; with nothing
   left, the switch disappears and Devices shows again. Without Clear, the
   rows and the switch go an hour after the last one finished.

## PixelHandUITests

No changes: the UI tests drive the iOS app only, and no `ph.mac.*` ID was
referenced. The Mac IDs are kept where their controls still exist:
`ph.mac.deviceRow`, `ph.mac.pairedDeviceRow`, `ph.mac.pendingRow`,
`ph.mac.deny`, `ph.mac.pairRequest`, `ph.mac.allow`, `ph.mac.disconnect`
and `ph.mac.forget` (now menu items), `ph.mac.confirmForget`,
`ph.mac.cancelForget`, `ph.mac.pairDevice`, `ph.mac.showCode`,
`ph.mac.waitingState`, `ph.mac.clearTransfers` and `ph.mac.transferRow`.
New IDs: `ph.mac.deviceMenu`, `ph.mac.pairConnected`, `ph.mac.tabs`,
`ph.mac.tabDevices`, `ph.mac.tabTransfers`, `ph.mac.transferSummary` and
`ph.mac.transfersTab`.

## Compile risks (most likely first)

1. `MacStatusPixel`: scoped `.animation(_:body:)` (macOS 14) used twice on
   one view, with a `repeatForever` animation in the first.
2. `MacDevicesList`: `let systemImage: @MainActor (LoomConnectionSnapshot)
   -> String`, called inside `Optional.map { systemImage($0) }`; explicit
   closure types in the three `map`s; `let` declarations inside `body`
   and inside `ForEach`.
3. `MacDeviceRowView`: `Button(action.title, role: … ? .destructive : nil)`
   inside a `Menu` and a `.contextMenu` with an `if`; `.menuIndicator(.hidden)`;
   `detailText(row.detail) { $0.formatted(.relative(presentation: .named)) }`
   (a trailing closure for the `relative:` label).
4. `MacTransfersTab`: `ForEach(groups.map { $0.group }, id: \.self)` over
   the plan's `(group:, items:)` tuples, with a `let` inside.
5. `MacPanelTabs`: `.accessibilityAddTraits(isOn ? .isSelected : [])` and
   `AnyShapeStyle` fills in a ternary.
6. `MacMenuBarView`: `let showsTransfers` inside the `VStack` builder;
   `devicesView(authorizedConnections:)` is a `@ViewBuilder` func using the
   private `PanelSection` and `PanelDivider`.
7. `QRDotsView`: `if let tile = …` with a `let` and `.position` inside the
   `ZStack`.
8. `MacHandTile`: `private static let handBox` (a Core `Sendable` struct)
   on a SwiftUI view.

## Out-of-lane edits

None. Every edit is in `DeckHandMac/**` or in new Core design and
transfer files with their tests. `DeckHandiOS` is untouched: OR-11 needed
no shared-string change, and lane or-ios-chrome owns the iOS "Pair a
device" hint (OR-12, iOS side).

Lane: READY TO MERGE
