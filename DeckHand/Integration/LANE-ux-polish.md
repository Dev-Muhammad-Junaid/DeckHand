# Lane: UX polish (UX-013 accessibility, UX-014 copy and shim removal)

Branch `claude/pixelhand-lane-ux-polish`, merged with the latest
`origin/claude/pixelhand-integration`. No protocol change (still 13). No
`project.yml`, Info.plist or entitlement change. iOS 17.4 APIs only; nothing
new needs `#available`. Edits are non-structural: accessibility modifiers,
strings, theme references and Reduce Motion guards. No view was moved or
renamed.

**Nothing in this lane was compiled with Xcode** (Linux container). Core tests
and the Linux type check pass; every SwiftUI edit was checked by reading.
See compile risks below.

## What changed

### Contrast (Core, tested on Linux)

- New `Core/Sources/PixelHandCore/Design/ContrastAudit.swift`: every colour
  pair the app draws, with its WCAG 2 AA minimum (text 4.5, large text 3,
  non-text 3). Tints are composited over the canvas. Semantic pairs are
  checked in light, dark and both Increase Contrast variants. Brand pairs on
  navy are checked once. `ContrastAuditTests` (6 tests) fail if a token edit
  breaks a pair.
- **Results.**
  - Phosphor on every navy surface: 11.8–18.8:1. Passes.
  - Ray, glow, mint and sky as text on navy: ≥ 5.8:1. Pass.
  - Cobalt on navy (`screen`): 3.22:1. Passes as non-text (accent keys,
    tile, glow edges). It is never text.
  - cobaltHigh on `screen` / `screenRaised`: 4.35 / 3.93:1. Pass as
    non-text.
  - stripDim on `screen`: 4.77:1. Passes as text.
- **Two tokens failed and were adjusted (light only).**
  - `danger` `#D92D3F` → `#C8283A`: it was 4.35:1 on the canvas and 4.05:1
    on `dangerTint`, which is the destructive button. Now 5.0 and 4.66.
  - `warning` `#A35F00` → `#9E5C00`: it was 4.496:1 on `warningTint`, the
    status pills. Now 4.73.
  - `02-Design-System.md` §1.2 updated to match.
- **Documented limits** (kept out of the pass list; a test checks they're
  still below 4.5 so they get reviewed if a token moves):
  - `ink3` is 2.5:1 light and 3.3:1 dark. It's tertiary text, placeholders
    and chords, and the chord is also spoken as the key's value.
  - `accent` as body text on dark surfaces is 4.1–4.4:1. Accent text should
    use `accentInk` (about 9:1). This follows from white-on-accent buttons:
    no single dark accent passes both.
  - Plain `cobalt` on `screenRaised` / `screenHigh` is below 3:1, so it must
    not be a control's only boundary there.

### UX-014 Shim removal and decisions

- `Shared/DeckHandTheme.swift` is deleted. All ~130 references in 34 files
  now name `PixelHandTheme` directly, each mapped to the exact token the shim
  forwarded to, so nothing renders differently.
  - `subtleWellFill(s)` → `PixelHandTheme.color(PaletteTokens.fill, for: s)`
  - `Radius.md` → `.chip`; `.hero` → `.pane`; `.sm` → `.kbd + 4`
  - `TypeStyle.*` → the same text styles
  - `mint` → `success`
- `Color(hex:)`, `Color(light:dark:)` and `brandBackground()` moved into
  `Shared/PixelHandTheme.swift`. They're still used by `DeckHandMark` dot art
  and `DeliveryDots`.
- Two `project.yml` comments still say "matches DeckHandTheme.accent". This
  lane doesn't touch `project.yml`; the coordinator can reword them.
- **Classic layout: kept.** It isn't dead code: Shell › More › "Use the
  classic layout" reaches it (`ControlView.classicLayout`, `TrackpadView`,
  the QuickActions bar).
- **`desktop` / `laptop` glyphs: kept as drawn.** They're named exceptions to
  stroke rule 1. At pitch 2–2.6 the two-dot edge is what makes each shape
  read. Recorded in `06-Pixel-Identity.md` (stroke rule 1) and the
  `PixelDesignTests` comment. No other glyph may break the rule.
- **Website mockups** (`website/tools/mockups/build.py`, listed under UX-014
  in the plan): not updated here. They're out of this lane's file scope.

### UX-013 Accessibility pass

- **VoiceOver labels.** Every glyph-only and icon-only control has a spoken
  action label. Dot-matrix strings without a `label:` got sentence-case
  ones, for example:
  - mirror counters: "Desktop 2 of 3"
  - display picker: "Display 1"
  - onboarding art and the pad caption
  - the Settings Pro mark

  Decorative art (DeckHandMark, glows, dot fields, chevrons, SF Symbols next
  to text) is hidden from VoiceOver.
- **Spec §8 items.**
  - **Keys and chips:** the label is the action and the chord is the value
    (`DeckKey`, `ContextChip`). Keys in edit mode have a "Remove <key>"
    action. The value has no "on <Mac>" part, because the components don't
    know the Mac's name.
  - **Trackpad:** a direct-touch area (`.allowsDirectInteraction`) with
    Click, Double-click, Right-click, Find the pointer and Mission Control
    actions. It's on both `PointerSurface` and the classic `TrackpadView`,
    and all of them call existing sender functions. Scroll up, Scroll down
    and Drag were not added: there's no existing step or drag function, so
    they would be new behaviour.
  - **Mirror:** reads "Screen of <Mac>". On the JPEG stream it has a "Read
    text on screen" action that runs the existing `TextReader.read` and
    announces the text. The HEVC stream has no still frame to read.
  - **Context strip:** a container named "Actions for <app>".
  - **Mac pill:** reads "<Mac> focused, <app>".
  - **Receipts:** transfers announce when delivered or stopped. Deck key
    failures were already announced.
- **Grouping.** Mac rows on the connect screen ("Studio, my Mac, paired,
  nearby"), Mac cards, inbox rows, onboarding art, the approval overlay
  (modal container), Mac panel rows, the pairing code (read digit by digit)
  and status lines each read as one element. Rows that hold separate buttons
  use `.contain`, so the buttons stay reachable (for example the Mac
  transfer row).
- **Reduce Motion.** Guards added where they were missing:
  - press-scale on QuickActions, the app grid and window cells
  - the floating screen tile and the switch toast (fade instead of
    move/scale)
  - mirror desktop dots
  - Mac panel dot beam
  - AppShortcuts and screenshot transitions, screenshot zoom
  - scroll toggle spring

  Already honoured: DotScan, DotWave, PixelMorph, the transitions, power-on,
  the scanline, LivePixel and the status-item ticker.
- **Dynamic Type.** About 20 fixed `.system(size:)` fonts on readable text
  became text styles (AppShortcutsSheet, PasteToMacControl,
  DeckHandEmptyState, StreamDeckGridView section titles, HostLinkBadge).
  Hint text in RegionCropView now wraps. The bands were already in place:
  - **Deck:** rows at AX3+ (`DeckKeyRow`), via `DeckSurface` and
    `typeSize.typeBand`.
  - **Settings:** `SettingsRow` and `SettingBlock` stack at huge.
  - **Strip:** an "Actions" menu at huge.
  - **Tab bar:** drops labels at AX1+ and uses the Large Content Viewer.
  - **Mac pill:** drops the front app at AX1+.
- **iPad focus.** `.phosphorFocusable` was added to custom tappable controls
  that didn't have it: the capture and More menus, the Ask circle, dock
  apps, sidebar Mac cards, layout preset segments, mirror toolbar and tile
  buttons, display picker shapes, Mac cards, inspector glyph and colour
  buttons, glyph editor tools, capture chrome buttons, keyboard keys and
  shortcut cards.
- **UI-test identifiers** use the scheme `ph.<area>.<name>`, one per element
  type:
  - **Tabs:** `ph.tab.pointer`, `.screen`, `.deck`, `.ask`
  - **Header:** `ph.header.macPill`, `.screen`, `.capture`, `.more`,
    `.layout`
  - **Trackpad:** `ph.trackpad`, `.click`, `.rightClick`, `.keyboard`
  - **Deck:** `ph.deck.key`, `.pin`, `.edit`, `.pageMenu`, `.pageDot`,
    `.keyInspector`, `.actionLibrary`, `.suggestions`
  - **Strip and dock:** `ph.strip`, `.chip`, `.actions`; `ph.dock`, `.app`,
    `.keyboard`
  - **Mirror:** `ph.mirror`, `.close`, `.sound`, `.displayPicker`,
    `.displayRow`, `.pictureInPicture`
  - **Ask and sidebar:** `ph.ask`, `.submit`, `.example`; `ph.sidebar.mac`
  - **Keyboard:** `ph.keyboard.modifier`, `.key`
  - **Macs and transfer:** `ph.macs.card`; `ph.transfer.send`, `.tab`,
    `.macCard`; `ph.inbox`, `.row`
  - **Apps and capture:** `ph.apps.app`, `.shortcut`; `ph.capture.window`,
    `.preview`, `.confirmRegion`
  - **Connect screen:** `ph.connect.macRow`, `.scanQR`, `.settings`,
    `.searching`, `.retry`
  - **Approval overlay:** `ph.authorization`, `.enterCode`, `.dismiss`,
    `.disconnect`
  - **Onboarding:** `ph.onboarding.continue`, `.back`, `.skip`, `.title`
  - **Settings:** `ph.settings`, `.done`, `.version`, `.remoteAddressField`,
    `.addAddress`, `.testConnection`, `.pairedMac`, `.subscribe`, `.restore`,
    `.manageSubscription`
  - **Paywall:** `ph.paywall.close`, `.subscribe`, `.restore`, `.plan`,
    `.done`, `.switchMac`
  - **Pairing:** `ph.pairing.codeField`, `.pair`, `.scanQR`, `.scanner`,
    `.openSettings`
  - **Mac panel:** `ph.mac.*` (about 40 ids: header, deviceRow, allow,
    deny, quit, permission rows and buttons, pairing, QR, code, forget,
    transfers). The pairing window's id changed from `pair-device-window` to
    `ph.mac.pairDeviceWindow`; nothing referenced the old one.

### Copy

- **Sentence case** on buttons, menus and titles, for example:
  - "Clear marks", "Hide app", "Add key", "Delete page", "Follow cursor"
  - "Capture region", "Scan pairing code", "Remote access", "Test connection"
  - "Copy code", "Turn on…", "Show in Finder", "Full screen", "Read text"
  - "My shortcuts"
- **Device-neutral and named:** "your iPhone or iPad", "Mac picker".
  Allow, Deny, Forget and Cancel on the Mac name the device. The connect
  error names the Mac and keeps the underlying reason: "Couldn’t connect
  to Studio. <reason>".
- **Clearer errors:**
  - remote identity mismatch: "Check the address in Settings, or pair with
    your Mac again"
  - unreadable screenshot data: "The Mac sent an image that couldn’t be
    read"
- **"Initializing…" → "Connecting…".** Arrow keys say "Left arrow" and so
  on.
- **Unchanged on purpose:**
  - All Store and subscription disclosure text, including both "Restore
    Purchases".
  - App Shortcut phrases (Siri registration).
  - "Pair a Device…" (matches the Mac menu item).
  - Core copy tables (`MacPanelCopy`, `TransferCopy`, `CaptureSheetChrome`
    titles such as "Screenshot Failed" and "Mac Is Locked"). This lane may
    not touch Core logic. See follow-ups.
  - The `session xxxxxxxx` debug lines in the Mac panel and the classic
    iOS toolbar. Spec §9 says to move them to Diagnostics, but the owner is
    testing with them now (they spot silent session swaps). They're hidden
    from VoiceOver.

### Other

- `Scripts/linux-typecheck/run.sh` now also compiles
  `DeckHandiOS/Store/DeveloperUnlock.swift`. The type check was failing on
  integration `7d14ebf` because `SubscriptionStore` uses it.

## Checks on the Mac

1. **Build** both apps. The compile risks are listed below.
2. **VoiceOver walk-through on iPhone** (Settings › Accessibility ›
   VoiceOver):
   - **Connect:** each Mac row reads "<name>, …, nearby" as one element, with
     "Connecting" as its value while connecting. Searching reads "Searching
     for Macs". The QR button reads "Scan pairing code". The approval overlay
     is modal and reads its title. "Enter pairing code" has a hint. The code
     field reads digits one by one.
   - **Trackpad:** one element. A three-finger tap or the rotor reaches
     Click, Double-click, Right-click, Find the pointer and Mission Control.
     Direct touch passes gestures through. The caption reads in sentence
     case.
   - **Deck:** each key reads "<label>", value "<chord>". Edit mode offers
     "Remove <key>". Page dots and the page menu are labelled. At AX3 keys
     become rows.
   - **Mirror:** "Screen of <Mac>". On the JPEG stream the rotor action
     "Read text on screen" speaks the text. Toolbar buttons and the display
     picker read "Display N".
   - **Settings:** every row reads as one element. The version line reads
     "Pixel Hand version X, build Y". Subscription rows are unchanged
     except for the Pro mark.
   - **Header and strip:** the Mac pill reads "<Mac> focused, <app>". The
     strip is "Actions for <app>". Chips give their chord as the value.
3. **Mac panel with VoiceOver** (⌘F5): the status item reads "Pixel Hand,
   <state>". Allow and Deny name the device. Transfer rows keep Cancel and
   Show in Finder as separate buttons. "Check for updates" and "Quit Pixel
   Hand" are spoken.
4. **AX3 on iPhone and iPad** (Settings › Accessibility › Display & Text
   Size › Larger Text, AX3), on the deck, strip, header, Settings, connect,
   paywall and onboarding. No clipped text. Known gaps that may squeeze
   (they need structural row changes, out of scope):
   - the subscription status row
   - `CloudRecognitionRow`
   - the Paired Macs row with its inline Forget button
   - `RemoteAccessMacRow`
   - `SettingsMacSection` toggles
5. **Reduce Motion:** the floating screen tile and the switch toast fade.
   Press-scales are off. Mirror desktop dots, the Mac dot beam and the
   scanning dots are frozen. Surface changes cross-fade.
6. **Contrast:** light-mode error text and destructive buttons are a shade
   darker red, and warning pills a shade darker amber. Check they still
   look right next to the board.
7. **iPad hardware keyboard and pointer:** Tab and the arrow keys move a
   phosphor ring through:
   - tabs, header circles, strip chips, dock apps
   - deck keys, sidebar Mac cards, the Ask circle
   - mirror toolbar buttons, Mac cards
   - keyboard keys and shortcut cards

   Pointer hover shows the same ring. There's never a double ring.

## Compile risks (most likely first)

1. `DesignSystem/DeckKey.swift` ~107 and `Mirror/MirrorPane.swift` ~40:
   `.accessibilityActions { if …, let x { Button(…) { … } } }`. This uses
   `if let` inside the actions view builder. MirrorPane's action also does
   `Task { await TextReader.read(image) }` and
   `AccessibilityNotification.Announcement(…).post()`.
2. Ternary transitions such as
   `reduceMotion ? .opacity : .opacity.combined(with: .scale(…))` in:
   - `Shell/PixelHandShell.swift` (FloatingScreenTile)
   - `ControlView.swift`
   - `TrackpadView.swift`
   - `ContentRootView.swift`
   - `AppShortcutsSheet.swift`
   - `ScreenshotPreviewView.swift`

   Any one can fail type inference. The fix is `AnyTransition.opacity`.
3. `TrackpadView.swift` (ScrollToggleButton): the inference of
   `withAnimation(reduceMotion ? nil : .spring(…))`. Similarly,
   `.animation(reduceMotion ? nil : …, value:)` in `MacPixelViews.swift`
   ~116 and others.
4. `ScreenshotPreviewView.swift` ~186:
   `accessibilityAction(named: zoom > 1.01 ? "Zoom out" : "Zoom in")`. The
   overload is picked through a ternary. If ambiguous, wrap it in `Text(…)`.
5. `Transfer/TransferSheet.swift`: the new
   `.onChange(of: phase) { _, newPhase in … }` (iOS 17 two-argument form).
   It needs `phase` to be Equatable, which it is.
6. `PairingCodeEntryView.swift`: `.accessibilityValue(text.map { … }.joined(separator: " "))`.
   `PairingQRScannerView.swift`: `.accessibilityElement()` on a
   `UIViewControllerRepresentable`.
7. New `@Environment(\.accessibilityReduceMotion) private var reduceMotion`
   in about 10 structs, one of them a `ButtonStyle`
   (`WindowCellButtonStyle`). A scripted check found no duplicate
   declarations and no use without one.
8. `Shared/PixelHandTheme.swift` now holds the `Color(hex:)` /
   `Color(light:dark:)` extension. If an open fix branch still adds or edits
   `Shared/DeckHandTheme.swift` or uses `DeckHandTheme.*`, the merge brings
   the type back or breaks. The fix is the same mapping as above.

## Follow-ups (not in this lane)

- Core copy:
  - `CaptureSheetChrome` titles in sentence case ("Screenshot failed",
    "Mac is locked")
  - `MacPanelCopy`: "1 device connected · ready" and lowercase "locked".
    "Ready for a device" would be plainer as "Waiting for an iPhone or
    iPad".
  - `TransferCopy`: "Always from this device" → "Always accept from this
    device"
- Move the `session` debug lines to Diagnostics once testing is done.
- Deck key value "…, on <Mac>": pass the Mac name into `DeckKey` and
  `ContextChip`.
- Trackpad Scroll up and Scroll down actions need a step size and a
  natural-scrolling decision.
- Settings AX3 rows listed in check 4.
- Update the website mockups (UX-014 in the plan).

## Files touched

- **Core:**
  - `Core/Sources/PixelHandCore/Design/ContrastAudit.swift` (new)
  - `Core/Sources/PixelHandCore/Design/PaletteTokens.swift` (two light
    hex values)
  - `Core/Tests/PixelHandCoreTests/ContrastAuditTests.swift` (new)
  - `Core/Tests/PixelHandCoreTests/PixelDesignTests.swift` (comment)
- **Shared:**
  - `Shared/DeckHandTheme.swift` (deleted)
  - `Shared/PixelHandTheme.swift`
  - `Shared/PixelArt.swift`
- **Mac:**
  - `DeckHandMac/MacMenuBarView.swift`
  - `DeckHandMac/CursorLocator.swift` (comment)
  - `DeckHandMac/Network/HostLinkBadge.swift`
  - `DeckHandMac/Pairing/PairDeviceWindow.swift`
  - `DeckHandMac/Pairing/PairingMenuSection.swift`
  - `DeckHandMac/Transfer/MacTransferSection.swift`
  - `DeckHandMac/UI/MacPixelViews.swift`
  - `DeckHandMac/UI/QRDotsView.swift`
- **iOS, root files:**
  - `AnnotationView.swift`, `AppShortcutsSheet.swift`,
    `AuthorizationOverlay.swift`
  - `ContentRootView.swift`, `ControlView.swift`
  - `DeckHandEmptyState.swift`, `DeckHandLoadingStateView.swift`,
    `DeckHandMark.swift`
  - `DeliveryDots.swift`, `DotField.swift`, `DotScan.swift`,
    `PixelMorph.swift`
  - `MirrorThumbnailView.swift`, `OCRResultView.swift`,
    `OnboardingView.swift`, `PeerPickerView.swift`
  - `QuickActionsBar.swift`, `RegionCropView.swift`,
    `ScreenshotPreviewView.swift`
  - `SettingsView.swift`, `StreamDeckGridView.swift`, `TrackpadView.swift`,
    `WindowPickerView.swift`
- **iOS, by folder:**
  - **Capture/:** `CaptureChrome.swift`
  - **Clipboard/:** `PasteToMacControl.swift`
  - **Control/:** `CaptureCapsule`, `CaptureCoordinator`,
    `ControlCaptureSheets`, `ControlToolbar`
  - **Deck/:** `ActionLibrarySheet`, `DeckSuggestionsPanel`,
    `KeyInspectorSheet`, `PixelGlyphEditor`
  - **DesignSystem/:** `ContextChip`, `DeckKey`, `MacPill`
  - **Keyboard/:** `RemoteKeyboardPanel`
  - **Macs/:** `MyMacsSheet`
  - **Mirror/:** `MirrorDisplayPickerSheet`, `MirrorOverlay`,
    `MirrorPane`, `MirrorPiPViews`, `MirrorPixelChrome`
  - **Network/:** `RemoteConnect`, `RemoteLinkStatus`
  - **Onboarding/:** `OnboardingScene`, `Components/OnboardingComponents`
  - **Pairing/:** `PairingCodeEntryView`, `PairingQRScannerView`
  - **QuickActions/:** `AppSwitcherMenu`, `QuickActionsChips`,
    `QuickActionsDialog`, `QuickActionsFABs`, `QuickActionsIconButton`,
    `QuickActionsNumpad`, `QuickActionsPills`, `TextFieldAction`
  - **Settings/:** `CloudRecognitionRow`, `SettingsAppearanceSection`,
    `SettingsBuildingBlocks`, `SettingsConnectionSection`,
    `SettingsMirrorSection`, `SettingsPairingSection`,
    `SettingsPointerSection`, `SettingsSubscriptionSection`
  - **Shell/:** `AppDock`, `ContextStrip`, `LayoutPresetPicker`,
    `MacsSidebar`, `PixelHandShell`, `ShellHeader`, `SurfaceTabBar`
  - **Store/:** `PaywallView` (identifiers and grouping only)
  - **Surfaces/:** `AskSheet`, `DeckSurface`, `PointerSurface`
  - **Transfer/:** `InboxPanel`, `TransferHeaderButton`, `TransferSheet`
- **Docs and scripts:**
  - `Product/Design/02-Design-System.md`
  - `Product/Design/06-Pixel-Identity.md`
  - `Scripts/linux-typecheck/run.sh`
  - `Integration/LANE-ux-polish.md`

Tests: `swift test --package-path DeckHand/Core`: **857 / 857 pass** (154
suites). `DeckHand/Scripts/linux-typecheck/run.sh`: **build complete**.

Lane: READY TO MERGE
