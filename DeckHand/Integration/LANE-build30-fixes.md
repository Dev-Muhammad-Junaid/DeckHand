# Lane: build 30 fixes (build30-fixes)

Branch `claude/pixelhand-lane-build30-fixes`, from
`claude/pixelhand-integration` at `5793ca2` ("Add the brief for the build
30 fixes lane"). It fixes the open bugs and walk fixes in `STATUS.md`
"Mac build results (build 30)", for build 31.

No protocol change (still 17). No `project.yml`, Info.plist or Loom change;
the new iOS file is picked up by the `DeckHandiOS` source group and the new
Core test file by the package.

| ID | Bug | Status | Note | Files |
|---|---|---|---|---|
| 1 | iPad portrait: Type panel under the keyboard when Live's field takes focus (P1) | Fixed (needs an iPad portrait check) | Second keyboard reading from UIKit's keyboard layout guide, merged with the notifications'; no edit menu on a tap at the caret in Live | Core `Input/KeyboardFrameReading.swift`; iOS `Keyboard/KeyboardGuideReader.swift` (new), `Keyboard/TypePanelModel.swift`, `Keyboard/TypePanel.swift` (host), `Keyboard/LiveTypingField.swift` |
| 2 | iPad `test20`: arrows + numpad 336 pt in a panel read as 372 (P3) | Fixed, likely cause (needs an iPad check) | Core already filled the inner width (336 = 360 − 2 × 12); the panel's `.contain` frame read 12 pt wider than the card. Header held to the inner width; new `ph.type.card`; the walk measures the card | iOS `Keyboard/TypePanel.swift`; `PixelHandUITests` |
| 3 | iPhone `test20`: panel dropped near the leading edge stays at x = 257 (P3) | Fixed (needs an iPhone check) | Docked panels narrower than the room dock to the leading edge, the centre or the trailing edge | Core `Input/TypePanelGeometry.swift`; `PixelHandUITests` |
| W1 | `openSyncedLiveField` leaves the panel in Compose (iPhone `test28`–`30`) | Fixed | Switches to Live and asserts it | `PixelHandUITests` |
| W2 | iPhone `test18` compares the panel with a portrait-space keyboard frame | Fixed | The keyboard's frame is put in the window's space; only a keyboard docked on screen is compared | `PixelHandUITests` |
| W3 | iPhone `test05`, `test16` stop early when the tab isn't hittable | Fixed | They fail with a message (`requireTap`) | `PixelHandUITests` |

## 1 · The Type panel under the keyboard in iPad portrait (P1)

**What build 30 showed.** In `test30`'s captures only the header showed
above the keyboard: the panel sat where it sits with no keyboard (bottom
centre, its bottom on the window's), so the model had no keyboard top
(`keyboardMinY == nil`) while the keyboard was up. Landscape and a
rotation to portrait with the field already focused (`test18`) were fine;
the case that failed is the field taking focus in portrait (and Live's
synced field then reloading its keyboard: predictions on, a taller
keyboard). The notifications are the one source, and a missed or
misconverted end frame leaves nothing to fall back on. Not reproducible
here (no simulator), so the fix doesn't depend on which notification went
wrong.

**Fix.**
- **A second source** (`KeyboardGuideReader`, new): an invisible,
  full-window `UIView` behind the host pins a marker to its
  `keyboardLayoutGuide` (`followsUndockedKeyboard = false`,
  `usesBottomSafeArea = false`, so hidden reads zero tall and a floating
  keyboard covers nothing) and reports the marker's frame in window space
  after each layout. UIKit lays the guide out whenever the keyboard, the
  window or the orientation changes, with no conversion between spaces.
- **Core** `KeyboardFrameReading.guideReading(_:viewMaxY:windowHeight:)`
  turns the guide into a reading (`nil` when the view doesn't reach the
  window's bottom or the values aren't numbers), and
  `merged(_:)` combines the two: covered when either says so, up to the
  higher top; clear only when every source that read something says clear.
- **`TypePanelModel`** keeps `notificationReading` and `guideReading` and
  publishes the merge (`applyReadings`): `keyboardMinY`, `keyboardOverlap`
  and `dockLift` as before. Keyboard hide clears the notification reading;
  the guide goes to zero tall by itself.
- **The first tap** (`LiveTypingField`, `textView(_:editMenuForTextIn:suggestedActions:)`):
  in Live, a tap with no selection gets an empty menu, so a tap at the
  caret only places it (iOS showed Select / Select All / AutoFill over the
  field when the focused field was tapped at its caret). A selection still
  gets the system menu; Live keeps its own Paste.

**Tests** (`Build30FixTests.swift`, `PortraitKeyboardTests`, 6): five
portrait iPads (Pro 11" M4 and earlier, Air 11", Pro 13", mini) × eight
keyboard heights (55, 69, 313, 330, 368, 380, 398, 420): every place
(3 × 3 × three heights, plus two sized ones), numpad on and off, Live and
Compose: the whole panel ends `gap` above the keyboard and its field is
above it; with the notification reading lost, read clear or turned, the
guide's reading still puts the default panel on the keyboard; the
regression itself (no reading: the panel's bottom under the keyboard);
guide readings; merging; `KeyboardAvoidance.bottomInset` for every
portrait height.

**Walk.** `openSyncedLiveField` now checks, after the field takes focus,
that the panel (its card) is above the keyboard, no edit menu opened and
the field has the keyboard; `test30` checks the menu and the panel after
each tap at the field's start. `test30` keeps its exact-content checks
(field, read back after reopening, and `PH_QA_LIVE_SYNC_OUT`).

## 2 · Arrows and numpad width (P3)

Core's numpad layout fills the panel's inner width at every width
(`NumpadOnlyTests`; new `NumpadFillTests` at test20's 360…456 pt): 336 pt
is exactly the inner width of the 360 pt minimum the walk narrows to. The
walk compared it with `ph.type.panel`'s frame, which read 372: that is a
`.contain` container whose frame is built from its children (as
`ph.capture.dock` was in build 28), so something in the panel reached
12 pt past the card. The header is the one block not cut by Core; it now
gets an explicit frame of the inner width. The card is named by a clear
element of its own shape, `ph.type.card` (value "W by H points"), and
`test20` measures the fill against it, and separately asserts the panel's
frame matches the card within 2 pt, so a remaining overhang is reported
on its own line with both frames.

## 3 · The iPhone panel snaps to the leading edge (P3)

Docked panels (a window under 500 pt either way) were always centred: in
iPhone landscape the 360 pt panel in a 734 pt room sat at
70 + (734 − 360) / 2 = 257 wherever it was dropped. Now
(`TypePanelGeometry`): a drag follows the finger sideways (`clamped`),
the drop docks to the nearest of the leading edge, the centre and the
trailing edge (`dockedSlot(of:)`, the centre on a tie and whenever the
panel spans the room) as well as the top or the bottom, `frame(for:)` and
`kept` honour it, and a resize holds the edge the panel is docked to
(centred, both edges move as before). Stored docked places have x = 0.5,
so they still read centred. iPhone portrait (full width) is unchanged.
The walk allows for the room starting inside the safe area (62 pt sensor
inset + 8 pt gap in landscape): it asserts the panel moved left and its
x is under 90 pt.

**Tests.** `DockedSlotTests` (6); `TypePanelGeometryTests.docked` and
`Build28FixTests.dockedAndNaN` updated for the new rule (sideways drags
move a narrow docked panel; `kept` moves into the room instead of
re-centring).

## Walk fixes

- **W1** `openSyncedLiveField` taps `ph.type.mode.live` when Live isn't
  selected and asserts it is (when the mode switch shows).
- **W2** `checkPanelAboveKeyboard` puts the keyboard in the window's space
  (`dockedKeyboardFrame`: the frame as reported, or turned a quarter
  either way from portrait space) and compares only a keyboard docked on
  screen (spans 90 % of the width, reaches the bottom). Build 30's iPhone
  frame (−226, 0, 162, 874) turns to a frame below or above the 874 × 402
  window, i.e. no on-screen keyboard (the iPhone walks type from the
  Mac's keyboard), which matches the captures. It compares the card when
  `ph.type.card` exists.
- **W3** `test05` (Deck tab) and `test16` (Screen tab on iPhone) use
  `requireTap`, which fails with "missing" or "there but not hittable"
  plus the frame and the window, and a snapshot.

## Linux results

- `swift test --package-path DeckHand/Core`: **1458 / 1458 pass** (267
  suites); 13 new in `Build30FixTests.swift` (3 suites), 2 updated.
- `DeckHand/Scripts/linux-typecheck/run.sh`: **Build complete**, no errors.
- `swiftc -parse` clean: `PixelHandUITests.swift`, `KeyboardGuideReader.swift`,
  `TypePanel.swift`, `TypePanelModel.swift`, `LiveTypingField.swift`.
  `PixelHandUITests.swift` braces and parentheses balance (366 / 366,
  1363 / 1363).
- No bare `TextRange` added (none in the new tests).
- Loom: not touched, not run.

## Re-checks

**iPad Pro 11" simulator (and the iPad Air), full screen:**
1. **Bug 1, portrait.** Open the Type panel, Live, tap the field: the
   whole panel sits on the keyboard (field, arrows, Accept, keys all
   above it), no Select / Select All / AutoFill menu. Type: the text
   reaches the field and the Mac. Turn predictions on and off (synced vs
   blind Live changes the keyboard's height): the panel follows.
   `test28`, `test29` (Accept found), `test30` with exact TextEdit contents
   ("Xpixel hand" + the scratch text).
2. **Landscape.** The same, and rotate with the panel open both ways:
   above the keyboard each time. `test18`.
3. **Stage Manager**, window dragged down to iPhone width: the panel
   docks (full width); with the keyboard up it sits above it.
4. **Bug 2.** `test20`: numpad on at the narrowest width: arrows and
   numpad fill the card; `ph.type.card` and `ph.type.panel` agree within
   2 pt (if not, the new assertion names both frames: tell this lane).
5. Floating keyboard (pinch the keyboard): the panel ignores it (moves
   by hand), as before.

**iPhone 17 Pro:**
1. **Bug 3.** Landscape, drag the panel by its grip to the left: it docks
   at the safe area's leading edge (x = 70), right: the trailing edge,
   middle: centred. Close and reopen: same place. `test20`.
2. **W1.** `test28`–`30` run in Live (sync badge shows) even after
   `test18` leaves Compose.
3. **W2.** `test18` passes its frame check (or reports a converted frame).
4. **W3.** `test05`, `test16`: if the tab isn't hittable they now fail
   with the frame; look at `not-hittable-ph.tab.*`.

**Mac:** the `test28`–`30` TextEdit checks above; nothing Mac-side
changed.

## PixelHandUITests changes

- New helpers: `requireTap(_:_:timeout:)`, `dockedKeyboardFrame(_:in:)`,
  `checkNoEditMenu(tag:)`.
- `checkPanelAboveKeyboard`: window-space keyboard frame, card frame.
- `openSyncedLiveField`: Live, then panel above keyboard, no edit menu,
  field focused.
- `test05`, `test16`: `requireTap`.
- `test20`: docked snap allowance; numpad fill against `ph.type.card`;
  panel vs card.
- `test30`: menu and panel checks after the taps; exact-content checks
  kept.
- Identifiers: new `ph.type.card`. All existing `ph.<area>.<name>` IDs
  unchanged (`ph.type.panel` is still the container).

## Compile risks (most likely first)

None of the UIKit or SwiftUI changes are type-checked on Linux (only
parsed).

1. **`KeyboardGuideReader.swift`** (new): `keyboardLayoutGuide.usesBottomSafeArea`
   (iOS 17; the target is 17.4) and `followsUndockedKeyboard`;
   `override var frame / center / bounds { didSet }` on a `UIView`
   subclass; `DispatchQueue.main.async { [weak self] in self?.deliver(…) }`
   from a main-actor view (Swift 6); comparing a tuple's
   `KeyboardFrameReading.Reading?` with `==`.
2. **`TypePanelHost`**: `.background { KeyboardGuideReader { reading, inset in … }
   .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true) }`
   after `.ignoresSafeArea(.keyboard, edges: .bottom)` (trailing closure
   to the memberwise `init(onChange:)`).
3. **`TypePanelModel`**: `if case let .covers(t, o)? = merged`; new
   `@ObservationIgnored private var` readings; `keyboardGuideChanged`
   called from the view.
4. **`TypePanel.body`**: the header's `.frame(width:height:alignment:)`;
   the card element in `.background { RoundedRectangle(…).fill(Color.clear)
   .accessibilityElement()… }` before `.accessibilityElement(children: .contain)`.
5. **`LiveTypingTextView`**: `textView(_:editMenuForTextIn:suggestedActions:)`
   (iOS 16 `UITextViewDelegate`), returning `UIMenu(children: [])`.
   Behaviour risk: if iOS still shows an empty menu, the walk's
   `checkNoEditMenu` reports it.
6. **UI tests**: `XCUIElement.isSelected`, `app.menuItems[…]`.

## Behaviour notes

- With the keyboard up, the panel avoids the higher of the two keyboard
  readings; in the normal case they agree.
- In Live, a tap with no selection shows no edit menu (long-press for a
  selection still does).
- On iPhone landscape (and any docked window wider than the panel) the
  panel can sit at the leading or trailing edge; it remembers which.

## Out-of-lane edits

No other lanes are running. Listed for the record:
- `Keyboard/TypePanel.swift` (host background, header width, card
  element), `Keyboard/TypePanelModel.swift`, `Keyboard/LiveTypingField.swift`
  (one delegate method; the live-sync code is untouched).
- `Core/Tests/PixelHandCoreTests/TypePanelGeometryTests.swift` and
  `Build28FixTests.swift`: one docked expectation each, for bug 3.
- `Product/Design/07-Polish-Spec.md` §4 (Type panel): the guide reading,
  the caret tap, docked edges, `ph.type.card`.

Lane: READY TO MERGE
