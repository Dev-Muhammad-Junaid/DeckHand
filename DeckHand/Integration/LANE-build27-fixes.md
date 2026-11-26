# Lane: build 26 and 27 fixes (build27-fixes)

Branch `claude/pixelhand-lane-build27-fixes`, from
`claude/pixelhand-integration` at `319dffb` ("Record build 27 Mac results").
It fixes the open bugs in `STATUS.md` "Mac build results (build 26)" and
"(build 27)" and `VISUAL-QA-build26.md` (VQ-104…108).

No protocol change (still 16). No `project.yml`, Info.plist or Loom change;
the new Core files are picked up by the package.

| # | Bug | Sev | Status | Files |
|---|---|---|---|---|
| 1 | Loupe swallows the Type panel's taps (OT-12, build 27 bug 1) | P2 | Fixed (needs an iPad check) | iOS `Keyboard/FocusLoupeView.swift`; audit: `ScreenshotPreviewView.swift`, `Capture/CaptureChrome.swift`, `Mirror/MirrorPane.swift` |
| 2 | Arrows don't grow with the panel (OT-11, build 27 bug 2) | P2 | Fixed (needs an iPad and iPhone check) | Core `Input/TypePanelGeometry.swift`, `Input/TypePanelLayout.swift` |
| 3 | VQ-104 Save as key under the keyboard (OT-8) | P2 | Fixed (needs an iPad portrait check) | Core `Design/KeyboardAvoidance.swift` (new); iOS `Surfaces/AskSheet.swift` |
| 4 | VQ-107 Connecting… breaks at AX3; the reconnect gave up | P2 | Fixed (needs an iPhone AX3 check) | Core `Macs/ConnectToastPlan.swift` (new), `Macs/MacSwitchMachine.swift`; iOS `ContentRootView.swift`, `DesignSystem/Feedback.swift`, `Macs/MacSwitcher.swift` |
| 5 | VQ-105 No keyboard button in iPhone landscape; no target in the headerless panel | P3 | Fixed (needs an iPhone check) | Core `Design/CanvasPlan.swift`, `Input/TypePanelLayout.swift`; iOS `Shell/SurfaceTabBar.swift`, `Shell/PixelHandShell.swift`, `Keyboard/TypePanel.swift` |
| 6 | VQ-108 Number pad over the pair sheet's title (iPad mini) | P3 | Fixed (needs an iPad mini check) | Core `Pairing/PairingTargetChoice.swift`; iOS `Pairing/PairingCodeEntryView.swift` |
| 7 | Send sheet chips 43 pt and unequal (OT-9, build 27 bug 3) | P3 | Fixed (needs an iPad check) | Core `Transfer/SendSheetLayout.swift`; iOS `Transfer/TransferSheet.swift`, `Transfer/SendPasteChip.swift` |
| 8 | Capture preview 8–9 pt off centre; oversized dock frame (OT-10, build 27 bug 4) | P3 | Fixed (needs an iPad and iPhone check) | iOS `ScreenshotPreviewView.swift`, `Capture/CaptureChrome.swift` |
| — | VQ-106 `test21` tooling (iPhone popover, leftover key name) | P3 tooling | Fixed | `PixelHandUITests/PixelHandUITests.swift` |

## 1 · The loupe swallows the Type panel's taps (P2)

**Cause.** `FocusLoupeView.picture` draws the *whole* mirror frame scaled by
1 / crop and offset so the crop lands in the loupe, then `.frame(size)` and
`.clipped()`. Clipping trims drawing only: the scaled child's layout frame
(about 4,536 pt wide on an iPad at 6×) still took part in hit-testing, and
`.accessibilityElement(children: .combine)` merged it into the loupe's
accessibility frame. So with the loupe open in portrait the target chip and
close weren't hittable, and VoiceOver landed on the loupe over the panel.

**Fix.**
- The picture: `.allowsHitTesting(false)` and `.accessibilityHidden(true)`
  before it is framed and clipped, then `.contentShape(Rectangle())` on the
  clipped frame.
- The loupe: its content is framed and clipped to the size the host gives
  it; `.contentShape(Rectangle())` on the loupe so only its own rectangle
  takes touches; `.accessibilityElement(children: .contain)` (not
  `.combine`) with a label that says what it shows ("Zoom to the input: the
  text field in TextEdit, up close", "… around the pointer in …", "The
  mirror is off", "No text field in focus on the Mac"). The text line
  (`ph.type.loupe.text`) and Start the mirror stay reachable inside it.

**Audit** (scaled or offset picture carrying an identifier or taking touches):
- **Capture preview** (`ph.capture.preview`): the identifier was on the
  `Image` *after* `.scaleEffect(zoom).offset(pan)`, so when zoomed it
  reported the scaled frame. Now the image takes no touches and is hidden;
  the well-sized, clipped frame around it is the element (label, hint,
  zoom action, `ph.capture.preview`), inside `ph.capture.well`.
- **Capture dock** (`ph.capture.dock`, build 27 bug 4's "frame ends 1,169 pt
  below the window"): the identifier sat on the row inside the dock, as a
  `.contain` container whose frame is built from its children. It now names
  the dock's card (`CaptureDock(identifier:)`), which is
  `.fixedSize(vertical)` (a row of actions tall, never stretched) with its
  own `contentShape`. See bug 8.
- **Mirror pane** (`MirrorPane`): the zoomed picture (`scaleEffect` +
  `offset`) has no identifier, but the pane was clipped with `clipShape`
  only, so a zoomed JPEG picture could take touches outside the pane. The
  pane now has `.contentShape` of its rounded rectangle.
- Nothing else in `DeckHandiOS` scales or offsets a picture
  (`grep scaleEffect(zoom`).

**Tests.** `test22`: with the loupe open, `ph.type.target` and
`ph.type.close` must be hittable, the loupe's frame no taller than 201 pt,
and the target chip closes it again.

## 2 · The arrows don't grow with the panel (P2)

**Which it was.** Not the layout: `TypePanelLayout` already grew the rows
(and so the arrows) with the panel's height. The drag never got there.
`TypePanelGeometry.resized(_:edge:translation:_:heights:)` clamped the new
height to `room.maxY - start.minY`, "the room below the panel's top". The
panel rides on the keyboard (iPad, `placement.y == 1`) or docks above it
(iPhone), so its bottom *is* the room's bottom: that limit equalled the
panel's current height, and dragging the corner down changed nothing.
Both devices, both orientations: **no room to grow into with the keyboard
up**, not the panel's height failing to reach the arrow band.

**Fix.**
- **Resize from the top when the panel sits on the keyboard.** The height
  is clamped to the layout's range and to the room's *height*. A panel on
  the room's bottom (on the keyboard or the dock) keeps its bottom there
  and grows or shrinks from its top (never above the room's top).
  Anywhere else the top holds as before, and a panel that would pass the
  room's bottom rises instead. The
  resize ends with the place snapped to the bottom (`y = 1`) and the new
  height stored, so it redraws on the keyboard at its new height.
- **Arrows grow with the width too** (the owner: "the arrow keys stay one
  size whatever the panel's width and height"). `bandCell` used to make
  arrow and action cells exactly square with the row, so a wider panel only
  widened the field. Now a cell is at least square with the row and, on a
  wide panel, wider: it takes what's left once the field keeps
  `fieldShare` (half) of the band, up to 72 pt, and never so wide that the
  field drops under 144 pt. A 600 pt stacked panel at its shortest has
  68 × 44 pt arrows (was 44 × 44); 360 pt panels are unchanged (44). The
  one-block layout at its default size is unchanged (11 cells share the
  band, so the share is under the row height).

**Tests** (`Build27FixTests.swift`):
- `TypePanelGrowsOnKeyboardTests` (7): iPad Pro 11" portrait (keyboard top
  830) and landscape (440), and iPhone 17 Pro docked (538): `test22`'s
  drag (−200, +400) from the panel on the keyboard makes it taller, its
  bottom stays on the keyboard, and the arrows go from under 48 to over
  48 pt; room below keeps the top; never taller than the room or above
  it; shrinking keeps it on the keyboard; the stored place stays at the
  bottom.
- `TypePanelArrowsWidenTests` (3): at 44 pt rows the arrows widen
  monotonically with the panel, 44 → 72; the field keeps its minimum and,
  beside widened arrows, half the band; tall rows stay at least square.
- The existing `noDeadAreas`, `arrowsScale`, `fieldAndArrows` and resize
  tests still pass unchanged.

`test22` now also asserts the panel got taller, the arrows are over 48 pt,
and (with an on-screen keyboard) the panel's bottom is still above it.

## 3 · VQ-104: Save as key ends up under the keyboard (P2)

**Cause.** Save as key appends the name field, Save and Cancel at the end
of Ask's scroll view and focuses the name. Nothing scrolled them into
view: the keyboard came up and, with a three-step plan, the name field was
the last row showing and Save and Cancel were under the keyboard. In the
**right column** it is worse: the shell lays out under the keyboard on
purpose (`.ignoresSafeArea(.keyboard)`, OT-2, so the Type panel can ride
on it), so the column's scroll view never learns the keyboard is there and
can't even scroll the row above it.

**Fix** (`AskPanel`, both placements):
- A 1 pt anchor under Save and Cancel; a `ScrollViewReader` scrolls it to
  the bottom of the view when Save as key starts, when the name takes
  focus (now and again after the keyboard's 0.45 s animation), and when
  the keyboard's frame changes while naming.
- `KeyboardAvoidance.bottomInset(viewMaxY:keyboardMinY:)` (Core, new): the
  scroll view measures its bottom edge in window coordinates and adds the
  keyboard's overlap plus 8 pt as bottom content margin. The keyboard's top
  comes from the window's `TypePanelModel` (`\.typePanel`, already in the
  environment of the shell and its sheets). In the sheet the system has
  usually lifted the view already, so the overlap, and the margin, are 0.

**Tests.** `KeyboardAvoidanceTests` (overlap + gap; 0 for a lifted sheet,
no keyboard, NaN). `test21` now asserts Save and Cancel are hittable and
that Save and the name field sit above the keyboard before it taps Save.

## 4 · VQ-107: Connecting… breaks at AX3 (P2)

**Cause, layout.** The launch reconnect's toast (`ContentRootView.
switchToast`) is an `HStack` of the toast and a Cancel button. At AX3 the
fixed-size Cancel left the text a few points, so it hyphenated into a
circle ("Con- / necti…"). The toast is laid over the top of the window,
`Space.sm` down, when there is no session: exactly where the picker's Pair
and Settings bar is, so Cancel drew over Pair.

**Fix, layout.**
- `ConnectToastPlan` (Core, new): **inline** (text and Cancel in a row) at
  standard sizes, **stacked** at AX1 and up: the text on its own line(s),
  full width (at most 480), wrapping at words with no line limit, Cancel
  under it. At standard sizes the view uses `ViewThatFits`, so a row that
  doesn't fit stacks too.
- `PHToast` takes `lineLimit` (default 2, unchanged for every other toast);
  with `nil` it grows vertically and draws a rounded card instead of a
  capsule.
- On the picker (no session) the toast sits under the Pair and Settings
  bar (`ConnectToastPlan.topInset`: 8 + 44 + 8 pt), not over it; over a
  session it keeps the header clearance.
- The Mac card's "Paired · Nearby" under the "Can't find your Mac?" footer
  (also in VQ-107) is the picker's own scroll column; it already scrolls
  (VQ-102), so it wasn't changed.

**Cause, "gave up".** `LANE-qa24-fixes.md` (VQ-101) names no log files; it
says what to look for in the connection log (`DeckHandLog.connection`,
Settings › Diagnostics › Export logs). Reading that path in
`MacSwitcher`: the launch reconnect dials **once**. If that dial fails (a
busy simulator, load ~90 in build 27's run, or a Mac still waking),
`dial()`'s `catch` only redials when `reconnectingDeviceID == target`,
which is set for *dropped* connections, not the launch reconnect. So it
showed "Couldn't reach …" for 4 s and `triedLaunchReconnect` was spent:
the picker waited for a tap. Meanwhile the walk had already tapped the
card, which is disabled while the launch reconnect shows it connecting
(VQ-101), so the tap did nothing; the walk logged `waiting-for-allow` and,
90 s later, `never-allowed`. That is the most likely reading of two of
four AX3 walks giving up (no device log from those runs was kept to
confirm the failed dial; the Mac check below reproduces it).
(At AX3 the walk could also hit the toast's Cancel drawn over the bar,
which spends the launch try on purpose; the layout fix removes that.)

**Fix, reconnect.** `MacReconnectPolicy.redialsFailedDial(isEnabled:isRedial:
isLaunchReconnect:)` (Core): a failed launch reconnect now redials on the
drop schedule (1, 2, 4, 8 s, then stops), with "Reconnecting to <Mac>…"
and Cancel, when "Reconnect automatically" is on. `MacSwitcher` remembers
the launch dial's target (`launchDialDeviceID`) until it settles; Cancel
clears it. A dial the person started still reports its error and stops.
The log says "📡 Launch reconnect to <Mac> failed; redialling".

**Tests.** `ConnectToastPlanTests` (2), `LaunchRedialTests` (1). Every walk's
`connect()` now checks, when the picker shows the toast, that the toast and
its Cancel don't overlap Pair and the toast is wider than 120 pt
(`picker-connecting` snapshot).

## 5 · VQ-105: no keyboard button in iPhone landscape (P3)

**Cause.** iPhone landscape is the **rail** form: no app dock
(`foldsDockIntoStrip`), so no `ph.dock.keyboard`; the Pointer pad has its
own button (`ph.trackpad.keyboard`), but on the Screen tab the mirror
takes the whole pane and there is no pad. `CanvasPlan`'s comment already
said "the keyboard button moves to the rail", but nothing did. And with
the keyboard up the panel has no header (room under 300 pt), so its
target chip, which lives in the header, wasn't there either
(`ph.type.target` missing); the placeholder named the app instead.

**Fix.**
- `CanvasPlan.railCarriesKeyboard` (Core): the rail form. The rail
  (`SurfaceTabBar`, vertical) gets a 62 pt glass keyboard circle under Ask
  (`RailKeyboardButton`, `ph.rail.keyboard`, Show/Hide keyboard, selected
  while the panel shows). The pad then leaves its own button out
  (`dockCarriesKeyboard` is true for the rail), so there is one per window
  on every tab.
- `TypePanelLayout.targetPlace` (Core): `.header`, or `.fieldRow` with no
  header. The panel puts the target chip (app icon, and the loupe's button)
  beside the field with the grip and close. The field's placeholder is now
  always neutral ("Type here" / "Type or dictate, then Send"), so the
  target still shows exactly once.

**Tests.** `RailKeyboardButtonTests`, `TypePanelTargetPlaceTests`. The walks
open the panel through `openTypePanel()` (dock, rail, then pad) and now
**fail** with `missing-keyboard-button` instead of returning early when
there's no button (`test18`, `test20`, `test22`; `test04` keeps it
optional).

## 6 · VQ-108: number pad over the pair sheet's title (P3)

**Cause.** On iPad (the mini in particular) the code field's number pad
floats over the sheet instead of docking at the bottom, and it sat over
the heading "Type the code showing on …". Its position is the system's;
the keyboard safe area doesn't cover a floating pad.

**Fix.** While the pad is up on iPad, a line right under the code field
repeats where the code comes from: "The code showing on <Mac>" (or "Choose
the Mac that shows the code." while the person still has to pick),
`ph.pairing.fieldCaption`. Core: `PairingSheetLayout.showsFieldCaption`,
`fieldCaption(targetName:)`. iPhone is unchanged (its pad docks at the
bottom and the heading stays in view, VQ-030/100). An app-drawn keypad was
the other option; it would replace the system's one-time-code autofill, so
it wasn't taken.

**Tests.** `PairingFieldCaptionTests`.

## 7 · Send sheet chips (P3, OT-9)

**Cause.** The three chips shared an `HStack` row with `maxWidth: .infinity`
each, which split the row into fractional widths (174.5 / 175 / 173.5 pt).
The Clipboard chip is the system `UIPasteControl` inset by a hairline of
padding (the hairline drawn as a background behind it, since nothing may
cover a paste control), so the control itself measured 44 − 2 × hairline
≈ 43 pt.

**Fix.** `SendSheetLayout.chipWidth(rowWidth:)` (Core): the row less two
8 pt gaps, split in three and rounded down to whole points (at least 44).
Each chip gets that width and 44 pt outright. The paste control fills its
whole chip; its hairline is a fill drawn behind it with −hairline padding,
outside the control.

**Tests.** `SendChipWidthTests` (whole points, fits, within 3 pt of the row,
the build 27 iPad row → 174 each). `test23` already asserts equal widths
within 1 pt and ≥ 44 pt.

## 8 · Capture preview (P3, OT-10)

**Cause.** The picture is centred between the header and the dock by the
stage's `VStack` (12 pt either side of the room, the well centred in it),
but the walk measured the dock by `ph.capture.dock`, which named the row of
actions *inside* the dock's 8 pt padding. So "below" read 8 pt more than
"above" in every orientation (246 / 255, 199 / 207, 12 / 20). The same
identifier, on a `.contain` container, is where the oversized frame came
from (see 1).

**Fix.** `ph.capture.dock` names the dock's card (its visible edge), which
is a row of actions tall (`fixedSize` vertically) with its own content
shape. The picture's gaps to the header's close button and to the dock's
card are then the same `VStack` spacing plus half the free room. The
preview's identifiers now report the well's frame at every zoom (1).

**Tests.** `test24` additionally asserts the dock's frame is under 160 pt
tall and `ph.capture.preview` is as wide as the well; its existing ±4 pt
centring check now measures the card.

## VQ-106 (P3, tooling)

`test21` dismisses the deck key's confirmation by tapping outside when
there's no Cancel (the iPhone popover has only Run), and deletes 8 more
characters than the default name so none of it is left.

## Linux results

- `swift test --package-path DeckHand/Core`: **1283 / 1283 pass** (233
  suites); 1265 before, so 18 new (`Build27FixTests.swift`, 10 suites).
- `DeckHand/Scripts/linux-typecheck/run.sh`: **Build complete**, no errors;
  it covers the changed `Macs/MacSwitcher.swift`.
- `swiftc -parse` is clean on every changed iOS file and the UI tests.
- Loom: not touched, not run.

## iPad and iPhone re-checks

**iPad Pro 11" (and the real iPad Air), portrait and landscape, full
screen:**
1. **Bug 2.** Open the Type panel (on the keyboard). Drag the right corner
   down: the panel grows **upward** from the keyboard, arrows, keys and
   field grow together to 72 pt rows; release: it stays at that height on
   the keyboard; close and reopen: same height. On a wide panel the arrows
   are wider than tall at the shortest height. With room below (panel
   dragged to the top), the corner grows it downward.
2. **Bug 1.** With the mirror on, tap the target chip: the loupe opens; the
   target chip and close still work with one tap; VoiceOver over the panel
   reads the panel's controls, and over the loupe "Zoom to the input: …".
   Pinch-zoom the mirror pane: the dock and header around it still take
   taps.
3. **VQ-104.** Portrait, Ask (sheet, and the right column where the
   arrangement has one): "Open Safari and type youtube and press return" ›
   Save as key: the name field, Save and Cancel sit above the keyboard.
4. **Bug 3.** Send sheet: three chips 44 pt tall and of one width
   (Accessibility Inspector), the Clipboard chip still pastes with no
   "Allow Paste".
5. **Bug 4.** Capture: the gaps above and below the picture are equal;
   the dock's frame is the card. Pinch in: Close and the dock still work.
6. **VQ-108 (iPad mini).** Picker › Pair: with the floating pad up, "The
   code showing on <Mac>" shows under the field.

**iPhone 17 Pro:**
1. **Bug 2.** Portrait, docked panel above the keyboard: drag a corner
   down: the panel grows upward, the arrows past 48 pt.
2. **VQ-105.** Landscape, every tab (Screen especially): the rail has a
   keyboard circle under Ask; it opens and closes the Type panel. With the
   keyboard up (no header) the app's icon chip sits by the field and opens
   the loupe; the field says "Type here".
3. **VQ-107.** AX3, cold launch to the picker: "Connecting to <Mac>…" wraps
   at words across the width, Cancel under it, both under Pair and
   Settings. Make the first dial fail (Mac app quit, then reopen within a
   few seconds): "Reconnecting to <Mac>…" and it connects without a tap.
   `test01`, `test09`, `test12`, `test14` at AX3 reach the shell.

**Walks:** `test18`, `test20`, `test21`, `test22`, `test23`, `test24` on
iPad full screen and iPhone (`test18`/`test20`/`test22` now run in iPhone
landscape through the rail's button). Mac walks still need the owner's OK
and a scratch TextEdit document in front.

## PixelHandUITests changes

- New helper `openTypePanel(required:)` (dock, rail, pad); a missing button
  fails the walk with `missing-keyboard-button` (VQ-105).
- `connect()` checks the picker's connecting toast against Pair
  (`checkConnectToastClearOfPair`, `picker-connecting`).
- `test21`: Save and Cancel hittable and above the keyboard
  (`ask-typed-naming`); VQ-106 dismissal and name clearing.
- `test22`: the panel grows, arrows > 48 pt, stays above the keyboard; the
  loupe leaves the target chip and close hittable and closes again.
- `test24`: the dock is the card; the preview is the well's frame.
- New identifiers: `ph.rail.keyboard`, `ph.pairing.fieldCaption`. Changed:
  `ph.capture.dock` (now the card), `ph.capture.preview` (now the clipped
  well-sized frame). `ph.type.target` also exists without a header.

## Compile risks (most likely first)

None of the SwiftUI changes are type-checked on Linux (only parsed).

1. **`AskSheet.swift`**: `@Environment(\.typePanel) private var
   keyboardFrame` (an `Optional<TypePanelModel>`, `@Observable`) read in a
   computed property and in `.onChange(of: keyboardFrame?.keyboardMinY)`
   (`Double?`); `.contentMargins(.bottom, _, for: .scrollContent)`
   (iOS 17); `scrollingBody(_ scroller: ScrollViewProxy)` returning
   `some View` with the `.onChange` closures capturing the proxy;
   `DispatchQueue.main.asyncAfter(deadline:execute:)` with a `() -> Void`
   local closure.
2. **`ContentRootView.cancellableToast`**: a `@ViewBuilder` func with two
   `let` views and a `switch` over `ConnectToastPlan.Arrangement`, one case
   a `ViewThatFits(in: .horizontal)`; `PHToast(message:pixel:lineLimit:)`
   memberwise order (`message, isFailure, pixel, lineLimit`).
3. **`PHToast`** (`Feedback.swift`): `Group { if … { row.phGlass(in:
   RoundedRectangle) } else { row.phGlass(in: Capsule()) } }` and
   `.lineLimit(Int?)`.
4. **`FocusLoupeView`**: `crop?.mode == .pointer` (optional enum compare);
   `.contentShape(Rectangle())` after `.shadow`.
5. **`SurfaceTabBar`**: `RailKeyboardButton.Config?` as a memberwise
   parameter between `axis` and the trailing `onAsk` closure; the shell's
   call passes `RailKeyboardButton.Config(isShown:) { … }` (trailing
   closure for `toggle`).
6. **`SendPasteChip`**: `.background { RoundedRectangle(…).fill(…).padding(-…) }`
   on the `UIViewRepresentable`. If the paste control refuses pastes
   because something overlaps it, the hairline background is the suspect
   (it is behind the control, as before).
7. **`CaptureDock`**: the new `identifier:` init parameter (every call site
   still compiles without it); `.accessibilityIdentifier(identifier ?? "")`.
8. **`TransferSheet.sources`**: `let`s before `return HStack`, `PhotosPicker`
   with `.frame` before `.buttonStyle`.

## Behaviour notes

- A failed launch reconnect now retries up to four times over ~15 s (with
  Cancel) instead of showing "Couldn't reach …" and waiting. Turning off
  "Reconnect automatically" keeps the old behaviour.
- Wide Type panels show wider arrow and action keys at their shortest
  height; the field is narrower by the same amount (never under half the
  band or 144 pt).
- The Type panel's placeholder no longer names the app in iPhone landscape;
  the icon chip beside the field does.
- The pad's own keyboard button is gone in iPhone landscape (the rail has
  it on every tab).

## Out-of-lane edits

No other lanes are running. Listed for the record:
- `DesignSystem/Feedback.swift` (`PHToast.lineLimit`, shared by every toast;
  the default keeps them as they were).
- `Shell/PixelHandShell.swift` (the rail's keyboard, `dockCarriesKeyboard`),
  `Shell/SurfaceTabBar.swift`.
- `Mirror/MirrorPane.swift` (Mirror lane: one `.contentShape` line).
- `Product/Design/07-Polish-Spec.md` §4 (Type panel sizing), §8 (chips),
  §9 (capture dock and identifiers).

Lane: READY TO MERGE
