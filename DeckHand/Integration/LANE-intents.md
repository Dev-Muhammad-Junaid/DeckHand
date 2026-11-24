# Lane: Intents (D6: App Intents, widgets, Control Center)

Branch: `claude/pixelhand-lane-intents`, cut from
`origin/claude/pixelhand-integration` at `9425586`, with the latest
integration merged in before hand-off. Written in a Linux container:
PixelHandCore built and tested here (Swift 6.2, **725 tests pass**, 23 new),
and `PixelHandAppGroup.swift` type-checked with `linux-typecheck/run.sh`.
**The iOS app and the widget extension were not compiled** (AppIntents,
WidgetKit and SwiftUI don't exist on Linux).

No protocol change: everything an intent does goes over messages the app
already sends (`deck.run`, `input.typeText`, capture, mirror start/stop).
Still protocol 12.

## 1. What changed

### How intents reach the Mac

The Loom connection lives in the app's process and iOS doesn't keep it up in
the background, so **every intent that acts on the Mac sets
`openAppWhenRun = true`**. There is no background connection. Siri, Shortcuts,
Spotlight, a widget button or a Control Center control brings Pixel Hand to
the front and then:

- **Mac connected:** the command runs on the live session straight away
  (`IntentBridge`). Keys, system actions and media keys go out as a tracked
  `deck.run`, and the receipt becomes the Siri answer ("Done." or "Your Mac
  didn't confirm it…").
- **No Mac connected:** the command waits in the App Group
  (`PendingCommandQueue`, at most 8 commands for up to 90 s) and runs once
  when the user picks a Mac. After that it's dropped, so a Mac never locks
  ten minutes late. Siri says "Pick your Mac in Pixel Hand. It runs as soon
  as it connects."

Nothing here opens or chooses connections, so it doesn't touch the
Multi-Mac lane. A command with a **Mac** parameter that doesn't match the
connected Mac fails with "Pixel Hand is connected to X. Switch Macs and try
again." Once Multi-Mac can dial a Mac by ID, `IntentBridge.handle` is the
place to call it.

### Core (`Core/Sources/PixelHandCore/Intents/`, new)

| File | What |
| --- | --- |
| `RemoteCommand.swift` | `RemoteCommand`: `runKey(keyID:)`, `system(SystemCommand)`, `media(MediaKey)`, `typeText`, `screenshot`, `mirror(MirrorIntentMode)`, `open(RemoteSurface)`. `feature` maps each command to a `ProFeature` for gating: typing, system actions, media keys and opening the trackpad are **free**; deck keys, screenshots and the mirror are **Pro**. `action` gives the existing `Action`. `validationIssue` checks the key ID (≤ 512 B) and the text (1…2 000 characters). `kindName` is the log name and never contains the typed text. `SystemCommand` covers Mission Control, App Exposé, Show Desktop, Launchpad, Find the Pointer and **Lock Screen** (`.shortcut(["ctrl","cmd","q"])`, since `SystemMacro` has no lock), each with a title, a pixel glyph and an SF Symbol. `MirrorIntentMode.shouldToggle(isRunning:)` decides whether start, stop or toggle changes anything. |
| `PendingCommandQueue.swift` | The no-Mac-yet queue: capacity 8, keeps the newest, 90 s lifetime, drops commands dated in the future. A command meant for another Mac stays queued. Damaged data reads as an empty queue. |
| `WidgetDeckSnapshot.swift` | What the app gives the extension. `widgetKeys` (up to 8): Home's first-row pins, then Home, then custom pages. It skips app pages, "Ask before running" keys and dialog presses. `allKeys` (up to 512, for the Shortcuts picker and search), `macs` (`RecentMac`, the 8 most recent, de-duplicated), `isPro`. `WidgetGlyph.resolve` uses the key's own pixel, bitmap or SF Symbol glyph, then a glyph that fits the action, then a dot-matrix monogram. App-icon keys become monograms because a widget can't draw Mac icons. A newer or damaged file reads as `.empty`. |

Tests: `Core/Tests/PixelHandCoreTests/IntentsTests.swift`, 3 suites and 23
tests. They cover gating, action mapping, every system action passing
`RemoteInputValidation`, every glyph existing, limits, the queue's order,
expiry, per-Mac waiting and capacity, snapshot order, caps, coding and
search, and recent Macs.

### iOS app (`DeckHandiOS/Intents/`, new)

| File | Target | What |
| --- | --- | --- |
| `Shared/PixelHandAppGroup.swift` | app **and** widgets | `group.com.widgetsflow.pixelhand`. Reads and writes the snapshot and the queue as atomic files in the container. Without the entitlement everything degrades to an empty snapshot and an in-memory queue. Also holds the WidgetKit kind strings. |
| `Shared/PixelHandEntities.swift` | app **and** widgets | `DeckKeyEntity` (`EntityStringQuery` over the snapshot; suggestions list the widget's keys first) and `MacEntity` (recent Macs). The enums `SystemActionOption`, `MediaKeyOption` and `MirrorModeOption`. |
| `Shared/PixelHandIntents.swift` | app **and** widgets | The intents: `RunDeckKeyIntent` (key, optional Mac; keys set to "Ask before running" ask first), `RunMacActionIntent` (action, optional Mac), `LockMacIntent`, `PressMediaKeyIntent`, `TypeTextIntent` (multiline), `TakeMacScreenshotIntent`, `SetMirrorIntent` (start, stop or toggle) and `OpenTrackpadIntent`. `IntentDispatch` hands commands to the app's handler. Where there is no handler (the extension's process), it checks Pro against the snapshot and queues the command. A refusal throws (`PixelHandIntentError`), so a Shortcuts workflow stops at that step. |
| `IntentBridge.swift` | app | Registers the handler and gates with `SubscriptionStore` (for Pro commands right after launch it waits up to 2 s for StoreKit, so a subscriber isn't refused). Runs commands on the attached session: deck keys are looked up in `DeckStore`, `sendConfirmed` maps to the outcome, typing goes through `TrackpadSender.typeText`, screenshots through `capture.beginCapture(.fullScreen)`, and the mirror through `toggleMirror` then a switch to the Screen surface. Also provides the `.intentBridge(…)` and `.intentSurfaceRequests(selection:)` view modifiers. |
| `WidgetSnapshotWriter.swift` | app | Observes `DeckStore.$document` (debounced 400 ms; **`DeckStore` itself is not edited**), the `SubscriptionStore` entitlement and Mac attaches. It writes the snapshot only when something visible changed, then reloads the widgets, the controls (iOS 18) and `PixelHandShortcuts.updateAppShortcutParameters()`. |
| `PixelHandShortcuts.swift` | app | `AppShortcutsProvider` with 8 App Shortcuts and phrases for Siri and Spotlight (listed in §3). Tile colour navy. |

### Widget extension (`DeckHandWidgets/`, new target)

| File | What |
| --- | --- |
| `DeckHandWidgetsBundle.swift` | `@main` bundle: Deck and Mac Keys widgets, plus the three controls behind `if #available(iOS 18.0, *)`. |
| `DeckWidget.swift` | **Deck** widget, small (2 × 2) and medium (4 × 2). Each key is a `Button(intent:)`. With Pro it shows the deck's keys. On the free plan, or with an empty deck, it shows the free Mac keys (Mission Control, Show Desktop, Play, Lock Screen, App Exposé, Back, Next, Launchpad), which run for free users. Navy surface with the top lift, raised navy keys, 9 × 9 dot glyphs in phosphor with the glow accent dot (or the key's tint), and a dot-matrix status strip `STUDIO · DECK` with the mint live pixel. The timeline is `.never`; the app reloads it. |
| `DeckAccessoryWidget.swift` | **Mac Keys** Lock Screen widget. Circular: the first key as one button. Rectangular: the Mac's name in dot-matrix over three key buttons. Monochrome glyphs, `widgetAccentable`. |
| `PixelHandControls.swift` | iOS 18 controls: **Deck Key** (`AppIntentControlConfiguration`, asks the user to choose a key when added), **Mission Control** and **Open Trackpad**, each a `ControlWidgetButton`. |
| `WidgetPixels.swift` | Dot-matrix text and dot glyphs drawn with `Canvas` from Core (`DotMatrixFont`, `PixelGlyphs`, `DotGeometry`, `PaletteTokens`). The app's design-system views aren't compiled into the extension. |

## 2. `project.yml`, entitlements and Info.plist (integration applies)

### 2.1 New target

Add under `targets:`. The `info:` and `entitlements:` blocks make XcodeGen
write `DeckHandWidgets/Info.plist` and `DeckHandWidgets/DeckHandWidgets.entitlements`,
so neither file is committed here.

```yaml
  # ─────────────────────────────────────────────────────────────
  # iOS widgets and Control Center controls (D6)
  # ─────────────────────────────────────────────────────────────
  DeckHandWidgets:
    type: app-extension
    platform: iOS
    deploymentTarget: "17.4"
    sources:
      - path: DeckHandWidgets
        type: group
      # The intents, entities and App Group store, shared with the app.
      - path: DeckHandiOS/Intents/Shared
        type: group
    dependencies:
      - package: PixelHandCore
      - sdk: WidgetKit.framework
      - sdk: SwiftUI.framework
      - sdk: AppIntents.framework
    info:
      path: DeckHandWidgets/Info.plist
      properties:
        CFBundleDisplayName: Pixel Hand
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    entitlements:
      path: DeckHandWidgets/DeckHandWidgets.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.widgetsflow.pixelhand
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.widgetsflow.pixelhand.widgets
        PRODUCT_NAME: PixelHandWidgets
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: 1
        TARGETED_DEVICE_FAMILY: "1,2"
        IPHONEOS_DEPLOYMENT_TARGET: "17.4"
        SWIFT_VERSION: 6.0
        APPLICATION_EXTENSION_API_ONLY: YES
        SKIP_INSTALL: YES
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: DD5AWPLT2V
    attributes:
      SystemCapabilities:
        com.apple.ApplicationGroups.iOS:
          enabled: 1
    scheme: {}
```

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` must stay equal to the
app's, or App Store validation rejects the build. Bump both together.

### 2.2 `DeckHandiOS` target

Embed the extension: add to `dependencies:`

```yaml
      - target: DeckHandWidgets
```

and to `attributes: SystemCapabilities:` (next to `com.apple.iCloud`):

```yaml
        com.apple.ApplicationGroups.iOS:
          enabled: 1
```

No source change: `DeckHandiOS/Intents/**` is already included by the
`DeckHandiOS` folder.

### 2.3 Entitlements

`DeckHandiOS/DeckHandiOS.entitlements`, add inside `<dict>`:

```xml
	<!-- App Intents lane: the widget extension reads the deck snapshot and
	     queues intents here (PixelHandAppGroup). -->
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.com.widgetsflow.pixelhand</string>
	</array>
```

The extension's entitlement is the YAML in §2.1. With automatic signing,
Xcode registers `group.com.widgetsflow.pixelhand` and the
`com.widgetsflow.pixelhand.widgets` App ID on the first build. If it
doesn't, add the App Group in the developer portal under both App IDs.

### 2.4 Info.plist

- **iOS app:** no new keys. App Intents and App Shortcuts need none.
- **Extension:** generated from §2.1.

## 3. Checks (owner's device, iOS 17.4+; Control Center needs iOS 18)

Build and run `DeckHandiOS` once so the extension installs. Connect to a Mac
once so the widgets know its name. Start with a Pro or trial account unless a
row says otherwise.

| Check | Expected |
| --- | --- |
| Shortcuts app | Pixel Hand lists **Run Deck Key, Mac Action, Lock Mac, Media Key, Type on Mac, Mac Screenshot, Mirror, Open Trackpad**. In a new shortcut, "Run Deck Key" → Key shows your deck keys (widget keys first, page title as subtitle) and search works. Mac shows the Macs you've connected to. |
| Run from Shortcuts, connected | With Pixel Hand connected, run "Run Mac Action: Mission Control": the app comes forward, Mission Control opens on the Mac, and the result says "Done." |
| Run with no Mac connected | Disconnect, run "Lock Mac": the app opens on the Mac picker and says "Pick your Mac…". Connect within 90 s and the Mac locks. Wait more than 90 s before connecting and nothing happens. |
| Type text | "Type on Mac" with "hello, world" into a TextEdit window: the text appears. An empty text fails with "There's no text to type." |
| Screenshot / mirror | "Mac Screenshot": the full-screen capture preview opens. "Mirror: Start" switches to the Screen surface with the mirror running. "Mirror: Stop" stops it. "Start" while running changes nothing. |
| Ask before running | A key with "Ask before running" asks "Run … on your Mac?" in Shortcuts. "Cancel" doesn't run it. The key never appears on the widget. |
| Siri phrase | "Hey Siri, lock my Mac with Pixel Hand", "Mission Control on my Mac with Pixel Hand", "Take a Mac screenshot with Pixel Hand", "Run Save with Pixel Hand" (a key labelled Save, after the app has written the snapshot once). |
| Spotlight | Search "Pixel Hand" or "Mission Control": the App Shortcuts appear under Pixel Hand and run. |
| Add the Deck widget | Home Screen → edit → Pixel Hand → **Deck**, small and medium: navy tile, dot-matrix `<MAC> · DECK` strip with a mint dot, 4 or 8 keys with pixel glyphs. Editing the deck in the app updates the widget within a second. |
| Interactive widget button | Tap a key on the Deck widget: Pixel Hand opens and the key runs on the connected Mac. |
| Lock Screen widget | Lock Screen → customise → **Mac Keys**, circular and rectangular: tapping a glyph opens Pixel Hand and runs it. |
| Control Center (iOS 18) | Control Center → add a control → Pixel Hand: **Deck Key** asks you to choose a key, and tapping it runs that key. **Mission Control** runs Mission Control. **Open Trackpad** opens the app on the Pointer surface (Pixel Hand shell). |
| Free-tier gating | With StoreKit Manage Transactions, expire or delete the subscription. The Deck widget switches to the free Mac keys (Mission Control, Show Desktop, Play, Lock Screen, …) and they still run. In Shortcuts, Mac Action, Lock Mac, Media Key, Type on Mac and Open Trackpad still work. Run Deck Key fails with "Running deck keys is part of Pixel Hand Pro.", Mac Screenshot with "Screenshots are part…", and Mirror with "The live mirror is part…". Start the trial again: the widget shows the deck's keys again. |
| Mac parameter | Run "Run Mac Action" with Mac set to a Mac other than the connected one: it fails with "Pixel Hand is connected to <name>. Switch Macs and try again." |

## 4. Compile risks, most likely first

1. **Swift 6 static properties on intents and enums.** `static let
   description = IntentDescription(…)`, `static let
   caseDisplayRepresentations: [X: DisplayRepresentation]` and
   `typeDisplayRepresentation` assume these SDK types are `Sendable`. If the
   compiler says "not concurrency-safe", change the declaration to
   `static var … { … }`, a computed property.
2. **`$key.requestConfirmation(for:dialog:)`** in `RunDeckKeyIntent`. If the
   signature differs in this SDK, drop the confirmation block. Widgets never
   show confirm keys anyway.
3. **`if #available(iOS 18.0, *)` in the `WidgetBundle` body.** If
   `WidgetBundleBuilder` refuses it, move the three controls into a second
   `@available(iOS 18.0, *) WidgetBundle` and return it from the first.
4. **`ShortcutTileColor.navy`.** If it's missing, use `.blue`.
5. **App Shortcuts phrases with parameters** (`\(\.$key)`, `\(\.$action)`,
   `\(\.$mode)`). The App Intents metadata processor warns or errors if a
   phrase is malformed; the build log names the phrase.
6. **`IntentDispatch.handler` is set in `DeckHandApp.init`.** If iOS runs an
   intent's `perform` before the app's `init`, the command is queued, not
   lost, and runs when a Mac attaches. Worth confirming with the
   "Run from Shortcuts, connected" check from a cold launch.
7. **Both targets compile `DeckHandiOS/Intents/Shared`.** That's intended:
   App Intents used by widgets and controls must be members of both. If
   Xcode warns about duplicate App Shortcuts metadata, check that
   `PixelHandShortcuts.swift` stays app-only (it's outside `Shared/`).

## 5. Out-of-lane edits (one line each)

| File | Owner | Edit |
| --- | --- | --- |
| `DeckHandiOS/DeckHandApp.swift` | Integration | `IntentBridge.shared.start()` at the end of `init()` |
| `DeckHandiOS/ControlView.swift` | Integration | `.intentBridge(session:settings:macID: connection.peer.deviceID, macName: peerName)` after the `.task` that runs the session |
| `DeckHandiOS/Shell/PixelHandShell.swift` | Integration (shell) | `.intentSurfaceRequests(selection: selection)` before the first `.sheet` |

No edits to `DeckStore` (observed through `$document`), `ControlSessionModel`,
connection or session management, `Assist/**`, `project.yml`, entitlements or
Info.plists.

Lane: READY TO MERGE
