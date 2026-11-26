# Lane: owner testing, build 26 (owner26)

Branch `claude/pixelhand-lane-owner26`, from `claude/pixelhand-integration`.
It builds OT-9 to OT-13 from the owner's hands-on test of build 26 on the
iPad Air 11" (M3), portrait and landscape, dark (`STATUS.md`, "Owner
testing (build 26)").

**Protocol bump 15 → 16** (OT-12). No `project.yml`, Info.plist or Loom
change; new files are picked up by the folder sources.

| ID | Status | Files |
|---|---|---|
| OT-11 Type panel uses its space (P2) | Built (needs an iPad check, portrait and landscape) | Core `Input/TypePanelLayout.swift` (new), `Input/TypePanel.swift`, `Input/TypePanelGeometry.swift`; iOS `Keyboard/TypePanel.swift`, `Keyboard/LiveTypingField.swift`, `Keyboard/TypePanelModel.swift`, `Shell/PixelHandShell.swift` |
| OT-12 Zoom to the input | Built (needs a Mac and iPad check) | Core `Models/FocusedField.swift`, `System/FocusReading.swift`, `Mirror/FocusLoupe.swift` (new), `Protocol/SystemMessage.swift`, `Protocol/PixelHandProtocol.swift`, `System/LockPolicy.swift`, `System/DisplayWakePolicy.swift`, `Input/RemoteInputValidation.swift`, `PROTOCOL.md`, fixtures; Mac `FocusTracker.swift`, `FocusReader.swift` (new), `Handlers/SystemHandler.swift`, `LockGate.swift`; iOS `Keyboard/FocusLoupeView.swift` (new), `Control/ControlSessionModel.swift`, `Control/ControlSessionModel+Mirror.swift`, `Control/ControlSessionModel+MacSystem.swift`, `TrackpadSender.swift` |
| OT-13 Inline suggestions in Live | Accept ⇥ built; native text readout built; suggestion text not readable (findings below) | Core `Input/FocusedTextReadout.swift` (new); iOS `Keyboard/TypePanel.swift`, `Keyboard/FocusLoupeView.swift`; Mac `FocusReader.swift` |
| OT-9 Send sheet in the design system (P2) | Built (needs an iPad and iPhone check) | Core `Transfer/SendTargetPlan.swift`, `Transfer/SendSheetLayout.swift`, `Transfer/TransferGlyphs.swift` (new); iOS `Transfer/TransferSheet.swift`, `InboxPanel.swift`, `TransferHeaderButton.swift` |
| OT-10 Capture preview in portrait (P2) | Built (needs an iPad and iPhone check) | Core `Capture/CapturePreviewLayout.swift` (new); iOS `ScreenshotPreviewView.swift`, `Capture/CaptureChrome.swift` |

## OT-11 · The Type panel uses its space

**Cause.** Build 25's `TypePanelLayout` sized the panel from its **width
only**. The height was whatever the content measured: a field column of
the field plus an action row holding one icon-only Paste button (the empty
strip under the field, beside the arrows); a 2-row arrow cluster at a fixed
44 pt next to a taller field column, or a 7 × 44 key block in a wider
panel (the empty block under the arrows and to the right of the keys).
Every cell was a constant 44 pt, so resizing changed nothing but the
field's width. "Typing into Claude" was in the header and again in the
field's placeholder (the placeholder named the target whenever the header
didn't show it, and on hardware keyboards always).

**Design.** The panel is resizable in **both** directions now, and Core
cuts **every block from the panel's current width and height**
(`Core/Input/TypePanelLayout.swift`, new). Nothing in the panel is sized by
its content, so nothing is left over; the tests check that every band runs
edge to edge with one 8 pt gap between blocks, for every width from 304
to 760 pt, every height in the range, Live and Compose, numpad on and off,
on-screen and hardware keyboards (`noDeadAreas`).

- **Rows** run from 44 pt (the touch target) to **72 pt**. 72 is where a
  cap is already a very big target; past it the panel would only cover
  more of the Mac picture, so the height range stops there.
- **Field and arrows** share their band's full height. Arrow and action
  cells are square with the row while the field keeps **144 pt** (about
  13 characters a line; the field shows two lines once its band is 60 pt
  tall). The field fills its frame (`LiveTypingField.fillsHeight`).
- **Keys mode, stacked:** field │ actions │ inverted T on top; the two key
  rows **span the panel's width** (cells = inner width ÷ 7, as tall as a
  row), so there's no block to their right.
- **Keys mode, one block** (wide and short, from **676 pt**): field │
  actions │ T │ key rows in one band two rows tall. Taller than 140 pt of
  body it becomes stacked (that's where three 44 pt rows plus a gap fit),
  so the height range is continuous.
- **Shortest:** under four rows of 44 (184 pt of body) the arrows go to
  **one row** (← ↑ ↓ →) and the two actions sit side by side: one row
  saved (44 pt + its gap). Only from **448 pt** wide: narrower, the field
  would drop under 144 pt beside six cells, so the T stays.
- **Numpad mode:** only the arrows and the 5 × 4 numpad (the modifier and
  special-key rows go). Side by side from **384 pt** wide (eight columns
  of at least 44 pt: 3 arrows + 5 numpad), with the arrows as tall as the
  numpad; narrower, the arrows in one row across with the numpad under
  them. In Compose a one-line draft with +⏎ and Send sits on top (the
  numpad writes into it, so it has to be visible). The field stays in the
  view tree with no size (OT-2: the keyboard never moves to a new view).
- **Actions** (replaces the action row under the field): Live has
  **Accept ⇥** (OT-13) and **Paste**; Compose has **+⏎** and **Send**.
  Compose's Paste button went: its field is local, so the system's Paste
  (edit menu, ⌘V, the keyboard bar's Paste) already works in it. Live keeps
  Paste because Live's field doesn't hold the text.
- **Header:** one row from **456 pt** (grip 44, Live│Compose 144, target
  chip 44, numpad 44, collapse 44, close 44, gaps, padding); narrower, a
  second row holds the mode switch and the app's name, so neither row is
  half empty. The clipboard status line under the body is gone (it changed
  the panel's height); the paste status now shows in the header's name
  slot for its few seconds. "Copied on the Mac: …" no longer shows in the
  panel.
- **Target once:** the header's chip shows the Mac app's **icon** (from
  the installed-apps list), its name from 560 pt wide (or on the second
  header row), and a magnifier: it is also the **Zoom to the input**
  button (OT-12). The placeholder is neutral: "Type here" / "Type or
  dictate, then Send". Only when there's no header (iPhone landscape with
  the keyboard up) does the placeholder name the app.
- **Resize:** the bottom corners now drag in both directions (sideways the
  other edge holds; down and up the top holds), clamped to the layout's
  height range for the new width and to the room below the panel's top.
  The height is stored with the place (`TypePanelPlacement.height`,
  optional, so build 25's stored places still read). A panel taller than
  the free room (the keyboard came up) shrinks to it, never under its
  shortest. VoiceOver's adjustable action steps width by 40 and height by
  20.
- **Keyboard bar:** with a hardware or minimised keyboard, iPadOS keeps
  its slim bar (EN US · Paste · mic) at the bottom; its frame comes through
  the keyboard notifications with an overlap under 120 pt. The panel
  already ended above it (its free room stops at the keyboard's top); the
  **dock** didn't, because the shell ignores the keyboard's safe area
  (OT-2). `KeyboardKind.barLift(overlap:bottomInset:)` gives the bar's
  height above the home-indicator inset, `TypePanelModel.dockLift` follows
  it, and the shell pads the dock up by it. A full on-screen keyboard
  lifts nothing (it covers the dock by design).

**What changed.**
- Core: `Input/TypePanelLayout.swift` (new: `Arrangement` oneBlock /
  stacked / numpad, `Block`, `Grid`, `Action`, `ActionCell`, `heightRange`,
  `headerRows`, `showsAppName`, `fieldLines`); `Input/TypePanel.swift`
  (the old width-only layout removed; `ArrowCluster.Shape` and
  `cells(for:)`; neutral placeholders; `KeyboardKind.barLift`);
  `Input/TypePanelGeometry.swift` (placement height, 2-D resize,
  `placement(resizedTo:keeping:keepsHeight:)`, `height(for:)`, the
  loupe's frame).
- iOS: `Keyboard/TypePanel.swift` (body placed at Core's frames by
  `PanelBodyLayout`; `KeyGrid`/`KeyCap` take the cell size from the block;
  legends scale up to 1.5×; header with the target chip; action block;
  host passes height, the app icon and the zoom switch);
  `Keyboard/LiveTypingField.swift` (`fillsHeight`);
  `Keyboard/TypePanelModel.swift` (`dockLift`); `Shell/PixelHandShell.swift`
  (the dock's bottom padding, two lines).

**Tests.** `TypePanelLayoutTests` (new, 15): keys-only body; **no dead
areas** across every width × height × mode × numpad × keyboard; compact
default; field and arrows share the band; arrows grow 44 → 72 and stop;
key rows span the width; numpad shows only arrows and numpad (side by side
or row-over-pad; Compose's draft row); one-row arrows and the 448 / 676
thresholds; actions per mode; shrinking to the room; target once and the
header rows; short room; Slide Over; every test window. Plus
`KeyboardBarLiftTests`, `TypePanelHeightResizeTests` (taller, clamped,
stored, build 25 places still read) and `TypePanelLoupePlacementTests`.
The build 25 width-only `TypePanelLayoutTests` were replaced.

## OT-12 · Zoom to the input

**Design.** The header's target chip (the Mac app's icon, its name, a
magnifier) is the button. It opens a **loupe attached to the panel**: as
wide as the panel, 30 % of its width tall (96…200 pt), above it when
there's room (the panel usually rides on the keyboard or dock), else below
it, else squeezed to the bigger side (`TypePanelGeometry.loupeFrame`). It
shows the Mac's focused text field up close, live, following the caret.
Closing the panel closes the loupe. Pro: the chip has
`.requiresPro(.mirror)` (a tap opens the paywall) and the host also checks
the entitlement.

- **Mac** (`FocusTracker` on the system-control path, `FocusReader` on a
  dedicated serial queue with a 0.1 s Accessibility timeout per call, never
  on the main actor): the system-wide `kAXFocusedUIElementAttribute` (else
  the front app's), its role, subrole, position and size, the caret from
  `kAXSelectedTextRangeAttribute` + `kAXBoundsForRangeParameterizedAttribute`
  (an empty rect for a bare caret retries the character before or after;
  web content falls back to the `AXSelectedTextMarkerRange` attributes, by
  name, no private API). The rects are converted to the containing
  display's top-left points. It **polls** 8×/s while things change and
  4×/s after 2 s of quiet, and sends only when something moved by more
  than 0.75 pt. A poll rather than `AXObserver`: nothing notifies when a
  field moves because its window was dragged, resized or scrolled;
  Chromium/Electron notifications are unreliable; observers need
  re-registering on every app switch; and the pointer fallback has to be
  sampled anyway. It runs only while at least one remote watches and stops
  on disconnect.
- **Electron:** Chromium builds its accessibility tree only for assistive
  apps. While a remote watches, the reader sets `AXManualAccessibility` on
  apps that bundle the Electron framework (only if not already on) and
  turns it back off when the last remote stops. `AXEnhancedUserInterface`
  is never set (it slows window animations in ordinary apps). The user
  default `PHFocusElectronAccessibility = NO` turns this off. Known side
  effect: VS Code may offer its screen-reader mode.
- **Fallback:** no frame from Accessibility (some web and Electron fields)
  → `source = .pointer`, a square around the pointer; the loupe zooms 3×
  around it and says in small print "Around the pointer: <App> doesn't say
  where its text field is."
- **Protocol 16:** `system.watchFocus(on:)` (remote → Mac) and
  `system.focusState(focus: FocusedFieldSnapshot)` (Mac → remote).
  `PROTOCOL.md` history; new fixtures `system.watchFocus`,
  `system.focusState`, `system.focusState.pointer`,
  `system.focusState.none`; every fixture and `MANIFEST` re-recorded.
  A 15 and a 16 can't talk; `PeerCompatibility` says "Please update".
- **Lock:** `watchFocus` is always admitted (it's a subscription). While
  the Mac is locked it reads no Accessibility, sends one `.none`, and
  nothing more until unlocked (`LockPolicy.withholdsFocus`). A
  `focusState` sent *to* the Mac is dropped by `RemoteInputValidation`.
- **Core maths** (`FocusLoupe`): display points → normalized; zoom to fit
  the field's width (1.5×…6×, 8 pt padding), never past the display's
  edges; on each axis the crop centres the field if it fits, else follows
  the caret and recentres only when the caret comes within 20 % of an edge
  (hysteresis, so it doesn't swim); a snapshot for another display than
  the mirrored one gives no crop; `videoRect` maps it into the video's
  pixels.
- **iPad** (`FocusLoupeView`): a display layer can only be in one place, so
  the session feeds a **second `AVSampleBufferDisplayLayer`**
  (`mirrorLoupeRenderer`) the same HEVC samples while the loupe shows, and
  asks for a key frame when it opens (a decoder can't start mid-GOP). The
  view draws the whole frame scaled by 1 / crop and offset, clipped to the
  loupe, with an accent bar at the caret. JPEG mirrors are cropped the same
  way from `mirrorImage`. Opening the loupe sends `watchFocus(true)`;
  closing sends `false`.
- **Mirror off:** the loupe says "The loupe cuts from the Mac's picture"
  and offers **Start the mirror**. It does **not** start a separate crop
  stream: the Mac has one capture and one encoder per connection ("latest
  request wins", one subscriber and one `pixelhand.mirror` stream per
  connection), so a `sourceRect` on `mirror.start` would replace the
  iPad's own mirror (and other remotes'); a real second stream needs a
  second capture and encoder per subscriber and a new stream kind:
  Mirror-lane sized. A window mirror (S14) isn't mapped either ("Mirror a
  display, not a window").
- **Limit:** the loupe magnifies the mirror's pixels. A 1512 pt display
  mirrored at 1920 px is about 1.27 px per point, so text reads fine to
  about 1.5× and gets soft beyond on an @2x iPad.
  `FocusLoupe.recommendedMirrorWidth` exists for raising the mirror's
  `maxWidth` while the loupe is open; not wired yet (it would renegotiate
  the stream).

**Tests.** `FocusLoupeTests` (19: mapping, other display, zoom fit and
clamp, pan hysteresis, caret following, pointer fallback, video pixels),
`FocusReadingTests` (13: roles, secure fields, text window, displays,
change tolerance, pacing), `TypePanelLoupePlacementTests` (2),
`ProtocolContractTests` (samples and case names, 59).

## OT-13 · Inline suggestions in Live mode

**Built:**
- **Accept ⇥** in the Type panel's action column whenever Live is on
  (`ph.type.accept`): it presses Tab on the Mac (with any latched
  modifiers), which is how Claude, Xcode, Mail and most editors take their
  grey inline suggestion. The loupe makes the ghost text visible, so you
  see it and take it with one tap.
- **The field's text** in the loupe, for native fields: one line around
  the caret (`FocusedTextReadout`: the selection highlighted, the caret
  marked, "…" where cut, a suggestion dimmed after the caret if one ever
  arrives). VoiceOver reads it.

**Findings** (from the frameworks' documented behaviour; not yet measured
on a Mac, see Mac check 8):
- **Native `AXTextField` / `AXTextArea`** (NSTextField, NSTextView):
  `AXValue`, the selected range, the character count, string-for-range and
  bounds-for-range are reliable. Read, at most 1 000 UTF-16 units around
  the caret (`AXStringForRange` for long documents), never for
  `AXSecureTextField` or anything whose role/subrole says secure or
  password, never inside an `AXWebArea`, never while locked.
- **macOS 14+ inline predictions** in native fields are drawn by the text
  system as a temporary completion outside the text storage: they are not
  in `AXValue` and no documented attribute exposes them.
- **WebKit / Chromium / Electron** (including the Claude desktop app): the
  caret works through text markers, but ghost text is whatever the page
  draws (a styled span or overlay). It shows up, if at all, as ordinary
  static text or inside the value, with nothing that tells it apart from
  typed text across apps. Web text is deliberately not read (privacy, and
  it would mix in the ghost text as if typed).
- **So `suggestion` stays `nil`.** Surfacing Claude's ghost text as text
  would need an app-specific heuristic on its AX tree, verified on a Mac;
  not built. The loupe shows it as pixels, which is reliable everywhere.

## OT-9 · The Send sheet follows the design system

**Cause.** A `NavigationStack` with a stock segmented `Picker`, a
`.roundedBorder` field and the system `PasteButton` (the lone blue
circle). "Send to" reused the 150 pt My Macs `MacCard` (16:10 tile), the
offline Mac at 55 % opacity, and the sheet was a fixed `[.medium, .large]`
detent, hence the empty space.

**Design.**
- A 60 pt header: a **Send | Inbox** switch like the Type panel's
  Live│Compose (unseen Inbox items as a dot-matrix count) and Done.
- **Sources:** Photos, Files and Clipboard as three equal 44 pt chips
  (a third of the row each, pixel glyph + label; new glyphs for photos,
  files and links).
- **One field** shaped like Ask's (52 pt, radius 24, hairline) with a round
  Add button inside it.
- **Send to:** a grid of compact 64 pt cards (1–3 columns; 2 on iPhone): a
  44 pt navy tile, the name over one status line, a dot-matrix "42%" or a
  status light. States: Ready, Sending N items, Waiting to accept, Locked
  (amber), Busy, Connecting, N waiting, Nearby / Remote. **Offline Macs**
  are small muted 44 pt rows, "Seen 2 h ago", most recent first; a tap
  still queues a send for that Mac.
- **Sized to its content:** the sheet measures its content (≥ 240 pt,
  ≤ the window less 48); Large is offered only when it overflows; on
  iPad (iOS 18) a form sheet fitted to that height.
- Inbox rows use the raised background, pixel glyphs and Core's
  relative-time words.
- **Behaviour unchanged:** same `TransferCenter` calls, drops and beam;
  existing identifiers kept (`ph.transfer.send`, `ph.transfer.tab`,
  `ph.transfer.macCard`, `ph.inbox`, `ph.inbox.row`); new `ph.send.*`
  ones are listed in `07-Polish-Spec.md` §8.
- **One behaviour to confirm:** the Clipboard chip reads the pasteboard
  itself, so iOS may show its "Allow Paste" prompt on tap. That's the
  price of dropping the system paste circle; the alternative is a styled
  `PasteButton` (no prompt, but the system draws it).

**Tests.** `SendSheetTests` (18): card states and order, offline rows and
"seen … ago" copy, columns per width, sheet height from content.

## OT-10 · Capture preview in portrait

**Cause.** The VQ-051 fix hugged the picture to the width
(`.aspectRatio(fit)`, `maxHeight: nil`), which put the dock right under
the picture with a `Spacer` below it: in portrait the bottom half was empty.

**Design.** Every step takes the room between the header and the dock;
the dock is anchored at the bottom (at most 560 pt wide, centred, for the
preview and Read text; Annotate's toolbar keeps its width). The picture is
aspect-fit into that room, centred, on whole points, the black well
hugging it (`CapturePreviewLayout.pictureFrame`). **Pinch** 1×–6×, pan
when zoomed (clamped to the picture's edges), **double-tap** zooms 2.5× on
the tapped point and again returns to 1×; a downward swipe at 1× still
closes.

**Tests.** `CapturePreviewLayoutTests` (9): fit in portrait, landscape and
iPhone; zoom clamping; pan clamping; double-tap anchor.

## Linux results

- `swift test --package-path DeckHand/Core`: **1253 / 1253 pass** (223
  suites); 1180 before, so 73 new.
- `DeckHand/Scripts/linux-typecheck/run.sh`: passes; it now also checks
  the Mac `FocusTracker.swift` (a `FocusReader` stub was added).
- `swiftc -parse` is clean on every changed file that can't be type-checked
  here: iOS `Keyboard/TypePanel`, `FocusLoupeView`, `LiveTypingField`,
  `TypePanelModel`, `Shell/PixelHandShell`, `Control/ControlSessionModel`
  (+`Mirror`, +`MacSystem`), `Transfer/*`, `ScreenshotPreviewView`,
  `Capture/CaptureChrome`; Mac `FocusReader`; the UI tests.

## iPad checks (iPad Air 11" M3; portrait and landscape, dark; then iPhone)

1. **OT-11 fill:** open the Type panel. Default: one compact block (720
   wide) or stacked. Drag a bottom corner **down**: arrows, keys and field
   grow together up to 72 pt rows; no strip under the field, no block
   under the arrows, no gap right of the keys. Drag up to the shortest:
   on a panel ≥ 448 pt the arrows go to one row ← ↑ ↓ →. Close and reopen:
   same size. Rotate: each orientation keeps its own.
2. **Numpad:** only the arrows and the numpad, filling the panel (side by
   side ≥ 384 pt, else arrows in a row on top). Compose: a one-line draft
   with +⏎ and Send on top. The numpad button brings the keys back.
3. **Target once:** the header shows the Mac app's icon (and name when
   wide), the field says "Type here". iPhone landscape with the keyboard
   up (no header): the placeholder names the app.
4. **Accept ⇥:** in Claude on the Mac, type until a grey suggestion shows;
   Accept takes it. Paste still works in Live (Pro).
5. **Keyboard bar:** with the Magic Keyboard attached (or the on-screen
   keyboard minimised), the EN US · Paste · mic bar sits at the bottom and
   the **dock rides above it**; the panel stays above both. Detach: the
   dock drops back.
6. **OT-12 loupe:** mirror on, tap the target chip: the loupe opens above
   the panel (below it when the panel is parked at the top), as wide as
   it. Click into TextEdit, Notes, a Safari field, Claude, Slack: it
   zooms to the field and follows the caret as you type; the caret bar
   sits on the caret; a native field's text shows in one line at the
   bottom. Where the app gives no frame, "Around the pointer: …" shows.
   Mirror off: "Start the mirror" works. A window mirror: it says it needs
   a display. Not Pro: the chip opens the paywall.
7. **OT-9:** Send sheet: the switch, three equal chips, the field with
   Add, compact cards, an offline Mac as a small "Seen … ago" row; the
   sheet hugs its content in both orientations and on iPhone, after
   staging items and during a send; the Clipboard chip (and its prompt);
   drop on a card; the Inbox count; the Store lane's PRO badge on the
   44 pt tile.
8. **OT-10:** a capture in portrait fills the width, centred, the actions
   at the bottom; landscape and a tall window capture fill the height;
   pinch, pan to the edges, double-tap in and out; swipe down closes at
   1×; Annotate and Read text unchanged; nothing under the home indicator.

## Mac checks (protocol 16)

1. A 16 iPad and a 16 Mac connect; a 15 Mac shows "Please update".
2. Open the loupe and click into TextEdit, a Safari search field, Notes,
   Mail: field and caret right on both displays (including one left of or
   above the main one).
3. Type in a long TextEdit document: the loupe follows; the Mac's CPU stays
   low (Activity Monitor).
4. A password field (Safari, System Settings): no text in the loupe.
5. Claude desktop or Slack: the log shows "AXManualAccessibility on for …";
   the caret appears within about a second, else the pointer fallback;
   close the loupe: "… off".
6. Lock the Mac: the loupe shows "No text field"; unlock: it resumes.
7. Disconnect the iPad: "Focus tracking stopped" in the log.
8. **OT-13 measurement:** with Accessibility Inspector, check whether
   Claude's ghost text appears in the AX tree (a separate static text, or
   in `AXValue`); report it, so a follow-up can decide on an app-specific
   reader.

## PixelHandUITests changes

- **`test22_TypePanelFillsItsSpace`** (new, portrait and landscape): the
  target named at most once; Accept present in Live; a corner drag down
  grows the arrows; the field spans the arrows' band; the key rows reach
  both edges; the shortest puts the arrows in one row (≥ 448 pt); the
  target chip opens the loupe as wide as the panel and not over it (or
  the paywall).
- **`test20`:** the numpad step now asserts the modifier row is gone and
  the numpad fills the panel (it used to assert the field stayed and the
  numpad was ≤ 222 pt).
- **`test23_SendSheetLayout`** and **`test24_CapturePreviewFillsPortrait`**
  (new, assert layout).
- New identifiers: `ph.type.accept`, `ph.type.loupe`,
  `ph.type.loupe.text`, `ph.type.loupe.startMirror`; `ph.type.target` is
  now a button when the loupe is available; `ph.send.*` (polish spec §8).
  Gone: the Compose `ph.type.paste` (Live keeps it).

## Compile risks (most likely first)

1. **`Keyboard/TypePanel.swift`** (parse only):
   - `PanelBodyLayout` with five children, one of them a
     `NumpadGrid` wrapped in `.opacity/.allowsHitTesting/.accessibilityHidden`;
     `subview.place(…, proposal: .zero)` for hidden blocks;
   - `targetChip(showsName:)`: a `let label = HStack {…}` inside a
     `@ViewBuilder` func, used in both branches of `if let zoom`;
   - `KeyGrid(grid:)`'s `@ViewBuilder let content` memberwise init and the
     `.environment(\.typeKeyCell, …)` it sets;
   - `KeyCap.Legend.stacked` and the `legendScale` free function;
   - in the host, `DeckAppIcons.image(for:in:)` with
     `Dictionary(…, uniquingKeysWith:)`, and `geometry.resized(…,
     translation:_:heights:)` passing the `heights` method.
2. **`FocusLoupeView`**: `Text + Text` with `.foregroundColor` (deprecated
   on iOS 17, a warning), `onChange(of: session.focusedField)` (needs
   `Equatable`: it's `Hashable`), the `(String, () -> Void)?` tuple
   parameter, `PHButtonStyle(kind:size:)`.
3. **`FocusReader.swift`** (Mac, parse only): `as! AXValue` /
   `as! AXUIElement` after the type-ID checks, `AXValueCreate(.cfRange,
   &range)`, `CFEqual` on `AXUIElement`, the parameterized attribute names
   as `String`, `kCFBooleanTrue` as `CFTypeRef`, `FocusReader.frontmost()`
   being `@MainActor static`.
4. **`TransferSheet.swift`**:
   `.presentationSizing(.form.fitted(horizontal: false, vertical: true))`
   (iOS 18, under an availability check), `onGeometryChange(for:of:action:)`,
   `presentationDetents(_:selection:)` with a `@State` selection set in a
   custom `init`, `PhotosPicker` with `ChipPressStyle`.
5. **`ScreenshotPreviewView.swift`**: `onTapGesture(count: 2,
   coordinateSpace: .local) { location in }` (iOS 17), the `GeometryReader`
   with `let`s and `.position`, `CaptureDock(maxWidth:)`'s
   `@escaping @ViewBuilder` init.
6. **`LiveTypingField.sizeThatFits`** with `fillsHeight`: if the field
   jumps while typing, the `isScrollEnabled` toggle there is the suspect.

## Behaviour notes

- The loupe adds a second hardware HEVC decode while it's open (the same
  stream decoded twice). Fine on an M-series iPad; it stops when the loupe
  closes.
- "Copied on the Mac: …" no longer shows in the Type panel (it was a line
  that changed the panel's height); the paste status shows in the
  header's name slot.
- Compose has no Paste button now: the system's Paste works in its local
  field.
- A Type panel place stored by build 25 (no height) opens at the compact
  default height.

## Out-of-lane edits

- Mirror lane: `Control/ControlSessionModel.swift` (the loupe renderer
  and flag), `Control/ControlSessionModel+Mirror.swift` (feeding it,
  `setMirrorLoupe(active:)`, flush on clear).
- Mac system lane: `Handlers/SystemHandler.swift`, `LockGate.swift` (one
  line each in `connectionRemoved` and `lockStateChanged`), new
  `FocusTracker.swift` / `FocusReader.swift`, Core `System/*`.
- Shell: `Shell/PixelHandShell.swift` (the dock's lift over the keyboard
  bar).
- `Product/Design/04-Interaction-Model.md` §2 Keyboard (fill, numpad,
  loupe), `07-Polish-Spec.md` §4 (Type panel sizing), §8 Send sheet, §9
  Capture preview.
- `Integration/DECISIONS.md` (a build 26 entry), `STATUS.md` (a line
  under "Owner testing (build 26)").
- `Core/PROTOCOL.md` (version 16) and the re-recorded fixtures;
  `Scripts/linux-typecheck/Stubs.swift` and `run.sh`.

Lane: READY TO MERGE
