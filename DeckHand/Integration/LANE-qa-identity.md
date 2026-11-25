# QA fix lane C: Settings and visual identity (build 18)

Branch `claude/pixelhand-lane-qa-identity`, merged with the latest
`origin/claude/pixelhand-integration` (2f5caec). Protocol unchanged (13).
Findings from `VISUAL-QA-build18.md`, owner review OR-14 and OR-15.

## Findings

| ID | Pri | Status | Note | Files |
| --- | --- | --- | --- | --- |
| VQ-074 | P1 | Fixed | Lock Screen rectangular: the name goes through a `ViewThatFits` of word-boundary forms (full, shorter, first word), then the Mac glyph alone; leading-aligned and clipped to the widget frame; the three key buttons share the width (`maxWidth: .infinity`). | `DeckHandWidgets/DeckAccessoryWidget.swift`, Core `Design/StatusStripText.swift` |
| VQ-009 | P2 | Fixed | Switches tint with `PixelHandTheme.accent` (cobalt), like pickers and sliders. | `Settings/SettingsBuildingBlocks.swift` (`phSettingsList`) |
| VQ-010 | P2 | Fixed | Done is `SettingsDoneButton`: semibold cobalt text, plain style, `.topBarTrailing` (not `.confirmationAction`, which iOS 26 draws as tinted glass). | `SettingsBuildingBlocks.swift`, `SettingsView.swift` |
| VQ-011 | P2 | Fixed | One header style: every section uses `SettingsSectionHeader` with a glyph (the glyph is now required; a title-only init falls back to the Settings glyph). Every switch is a new `SettingsToggle` with the 30 pt glyph tile; Remote access and Paired Macs rows use `SettingsRow` tiles instead of SF Symbols. | `SettingsBuildingBlocks.swift`, every `Settings/*Section.swift`, `Macs/SettingsMultiMacSection.swift` |
| VQ-012 | P2 | Fixed | Remote access is hidden until a Mac is paired; Paired Macs keeps the one empty state. | `Settings/SettingsConnectionSection.swift` |
| VQ-013 | P2 | Fixed | About footer ("Rows marked Not available…") removed. | `Settings/SettingsAboutSection.swift` |
| VQ-014 | P2 | Fixed | Subscription row: the `ProBadge` pill is gone; the leading slot is the standard glyph tile (lock, lit while Pro), and the dot-matrix PRO stays trailing. | `Settings/SettingsSubscriptionSection.swift` |
| VQ-053 | P2 | Fixed | "Play the Mac’s sound" and "Follow the cursor" now live only in Live mirror (they are global settings; the per-Mac section keeps the Mac and its link badge). Live mirror's footer is two sentences; each switch has a short subtitle. Pointer, Clipboard, Screenshots, Remote access, Several Macs and Privacy footers cut to one or two sentences. | `SettingsMacSection.swift`, `SettingsMirrorSection.swift`, `SettingsPointerSection.swift`, `DeckHandSettings+Input.swift`, `SettingsCaptureSection.swift`, `SettingsConnectionSection.swift`, `SettingsMultiMacSection.swift`, `SettingsPrivacySection.swift` |
| VQ-070 | P2 | Fixed | No more `prefix(6)`: the Deck widget strip shortens the name word by word and, if nothing fits, shows the live pixel alone. Pure logic in Core `StatusStripText` with tests. (No nickname setting; the first word is the short form.) | `DeckHandWidgets/DeckWidget.swift`, Core `Design/StatusStripText.swift` |
| VQ-071 | P2 | Fixed | Dot-matrix font gains `' ’ , & ( ) ? !`; accented letters fold to plain ("JOSÉ" → "JOSE"); typographic dashes and quotes (– — ‘ •) draw as their plain forms. Tests render every glyph inside its 5 × 7 box, check the app's punctuation and Mac names with apostrophes. | Core `Design/DotMatrixFont.swift`, `DotMatrixFont+Table.swift`, tests |
| VQ-076 | P2 | Fixed | The controls use Pixel Hand glyphs as custom SF Symbols (`ph.deck`, `ph.mission`, `ph.desktop`, `ph.lock`, `ph.pointer`, `ph.play`, `ph.hand`) in a new `DeckHandWidgets/Assets.xcassets`. Generated from Core (`ControlSymbolTemplate`, SF Symbols template v3.0, Ultralight/Regular/Black-S identical) by `Scripts/make-control-symbols.sh`. | `DeckHandWidgets/PixelHandControls.swift`, `DeckHandWidgets/Assets.xcassets/*`, Core `Design/ControlSymbolTemplate.swift`, `Scripts/make-control-symbols.sh` |
| VQ-077 | P2 | Fixed | `.tint(WidgetPalette.cobalt)` on each `ControlWidgetButton`. | `PixelHandControls.swift` |
| VQ-078 | P2 | Fixed | With no deck keys, Deck Key's Choose sheet offers the eight free Mac keys (Core `FreeMacKey`, IDs `mac.system.*` / `mac.media.*`); running one sends its free command, no Pro or deck needed. Unset, the control opens Pixel Hand on Deck and says how to choose a key. | `Intents/Shared/PixelHandEntities.swift`, `Intents/Shared/PixelHandIntents.swift`, Core `Intents/FreeMacKey.swift` |
| VQ-015 | P3 | Fixed | Curly apostrophes in every Settings string, the subscription status rows (Core `SubscriptionCopy.statusRow`) and the input captions; "Restore purchases"; "Free plan’s Mac". | `SettingsSubscriptionSection.swift`, `DeckHandSettings+Input.swift`, Core `Store/SubscriptionCopy.swift` |
| VQ-016 | P3 | Fixed | `presentationSizing(.page)` on iOS 18+ (large detent on 17.4), applied inside `SettingsView`, so both presenters get it. | `SettingsBuildingBlocks.swift` (`SettingsSheetSizing`), `SettingsView.swift` |
| VQ-017 | P3 | Fixed | The nav bar is painted `canvas` (explicit colour plus `.visible`; iOS 26 keeps the hard scroll edge). | `SettingsBuildingBlocks.swift` (`OpaqueSettingsBar`) |
| VQ-072 | P3 | Fixed | The strip says what the Mac is doing: front app while live, `LOCKED`, `OFFLINE`, nothing when unknown (no more "/ MAC"). The pixel is mint only while live. `RecentMac` gained optional `frontApp` and `glance` (App Group JSON only; older snapshots decode). `IntentBridge` observes `activeAppName` and `macLockState`; `WidgetSnapshotWriter.updateGlance` coalesces changes for 2 s and writes offline at once on detach. | `DeckWidget.swift`, `Intents/IntentBridge.swift`, `Intents/WidgetSnapshotWriter.swift`, Core `Intents/WidgetDeckSnapshot.swift` |
| VQ-073 | P3 | Fixed | Free keys have one-word labels (Mission, Desktop, Play, Lock, Windows, Back, Next, Apps; Core `SystemCommand.widgetLabel`), drawn at one fixed 10 pt size; no `minimumScaleFactor` (long deck-key labels end in "…"). VoiceOver keeps the full names. | `DeckWidget.swift`, Core `Intents/RemoteCommand.swift` |
| VQ-075 | P3 | Fixed | The circular widget draws `AccessoryWidgetBackground()` inside the view, with the glyph at pitch 3 (27 pt). | `DeckAccessoryWidget.swift` |
| VQ-079 | P3 | Partly | One name: "Trackpad" in the gallery and on the control. Switching the iPad to the Pointer arrangement when opened from the control is shell work (`PixelHandShell` arrangements, lane A); today the request selects the Pointer surface only. | `PixelHandControls.swift` |

## Re-check steps

Run `xcodegen generate` first: the widget extension has a new asset catalog.

**Settings, iPad Pro 11" (portrait and landscape) and iPhone 17 Pro, light and dark**
1. Open Settings with no Mac paired. It fills a page sheet on iPad, not a
   480 × 650 form sheet. Done (top trailing) is cobalt text, clearly enabled.
2. Scroll slowly: no header shows through under "Settings".
3. Every section header is grey caps with a small glyph: Live mirror,
   Pointer and gestures, Clipboard, Screenshots, Appearance, Connection,
   Paired Macs, Several Macs, Subscription, Privacy, About.
4. Every switch is cobalt when on and has a 30 pt navy glyph tile.
5. Only one "No paired Macs" card (Paired Macs); no Remote access section.
   Pair a Mac: Remote access appears with the Mac as a tile row.
6. About has no footer. Subscription shows one PRO (dot-matrix, trailing)
   when Pro; "Restore purchases"; apostrophes are curly everywhere.
7. Connected to a Mac: the Mac section shows only the Mac row with its link
   badge; "Play the Mac’s sound" and "Follow the cursor…" appear once, in
   Live mirror. Footers are one or two sentences.

**Small and medium Deck widgets** (a Mac named "Muhammad's MacBook Pro")
1. Small: the strip shows `MUHAMMAD'S` (with the apostrophe), never
   `MUHAMM`. Keys read Mission, Desktop, Play, Lock at the same size.
2. Medium while connected with Chrome in front: `MUHAMMAD'S MACBOOK PRO ·
   GOOGLE CHROME` or a word-shortened name with the app; mint pixel. Lock
   the Mac: `… · LOCKED`. Disconnect: `… · OFFLINE`, grey pixel, dim text.
3. Free plan or empty deck: eight free keys, one label size.

**Lock Screen (iPad)**
1. Rectangular Mac Keys: the name stays inside the widget, leading-aligned,
   shortened at a word; three buttons fill the width.
2. Circular: the glyph sits on the system's grey disc like its neighbours.

**Control Center (iPadOS 18+)**
1. Add the three controls: the gallery says Deck Key, Mission Control and
   Trackpad; the labels match.
2. Icons are the dot glyphs (deck grid, Mission Control, the dot hand), not
   SF Symbols; tinted cobalt, not gold or magenta.
3. Empty deck: Deck Key's Choose sheet lists the Mac keys under "Mac keys";
   pick Mission Control and tap it: Mission Control runs on the Mac.
4. Add Deck Key without choosing: tapping it opens Pixel Hand on Deck.

## Compile risks (most likely first)

1. **Custom symbol assets.** The `.symbolset` SVGs are generated, not
   exported from the SF Symbols app. If Xcode rejects a template ("missing
   guides" or similar), the controls show no icon. Fix: open one in the SF
   Symbols app and re-export, or adjust `ControlSymbolTemplate` and rerun
   `Scripts/make-control-symbols.sh`.
2. **`.tint(_:)` on `ControlWidgetButton`** (`PixelHandControls.swift`). If
   the template type has no `tint`, move it onto the `Label`.
3. **`ViewThatFits` with a `ForEach` of candidates** in the widgets
   (`DeckWidget.swift`, `DeckAccessoryWidget.swift`). Should be fine; if a
   widget renders only the last candidate, replace the `ForEach` with a
   `GeometryReader` and `StatusStripText.fit(name:details:maxCells:)`.
4. **`withObservationTracking` returning a tuple** in
   `IntentBridge.observeGlance` (Swift 6 sendability of the captured
   `session` in the `@Sendable` onChange). `ControlSessionModel` is
   `@MainActor`, so it should be Sendable.
5. **`SettingsSectionHeader` init** now takes a non-optional glyph (plus a
   title-only init). A call passing `glyph: nil` would fail; none exist on
   this branch.
6. **`presentationSizing(.page)`** behind `#available(iOS 18.0, *)`.

Not type-checked on Linux: SwiftUI, WidgetKit and AppIntents files can't
be stubbed. Core: `swift test --package-path DeckHand/Core` **876 / 876
pass** (159 suites). `DeckHand/Scripts/linux-typecheck/run.sh`: **build
complete**.

## Out-of-lane edits

- **Lane A (mirror pane):** Core test expectations in
  `MirrorPaneChromeTests.swift` (`dotMatrixSafe` now keeps `’` and `( )`,
  e.g. "JUNAID’S MAC"). No source change in their files.
- **Lane B (paywall flow, PiP entry, Diagnostics):**
  `Settings/SettingsSubscriptionSection.swift` (row layout, "Restore
  purchases", header) and the PiP switch in `SettingsMirrorSection.swift`
  now use `SettingsToggle`; expect small merge conflicts if lane B edits
  the same lines. A new Diagnostics section can call
  `SettingsSectionHeader("Diagnostics", glyph: …)`; the title-only init
  still compiles. Core `SubscriptionCopy.statusRow` strings use curly
  apostrophes (paywall copy untouched).
- Core `ContextStripAndDockTests` (version line now keeps `( )`).

Lane: READY TO MERGE
