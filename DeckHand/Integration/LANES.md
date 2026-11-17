# Pixel Hand lanes for the Sill phase

Written by the foundation session (`claude/pixelhand-foundation`). Read with
`DECISIONS.md` (what to build), `FOUNDATION.md` (what moved where) and
`DeckHand/Core/PROTOCOL.md` (how to change the protocol).

Six lanes run in parallel, one session each. A lane **owns** the files
listed for it: only that lane edits them. Everything else is either another
lane's, or a **shared hot spot** with the merge rules in §3. Where a lane
must touch a file it doesn't own, it keeps the edit to the lines named
here and says so in its handoff doc.

Paths are relative to `DeckHand/` unless they start with `Sources/` (the
Loom package at the repository root). `Core/…` means
`Core/Sources/PixelHandCore/…`.

## 1. Before you start, and before you hand off

1. Branch from the latest `origin/claude/pixelhand-integration`.
2. Install a Linux Swift toolchain if the container has none (swift.org
   6.2 tarball for Ubuntu 24.04, about 1 GB; parallel range downloads
   are much faster than one stream), then run:

   ```sh
   swift test --package-path DeckHand/Core          # 114+ tests, ~1 s
   DeckHand/Scripts/linux-typecheck/run.sh          # Mac handlers + TrackpadSender
   ```

   Put new pure logic in Core with Swift Testing tests, so it is tested
   here and not only on the Mac. Add your own app files to the type check
   (`run.sh path/to/File.swift`) when their dependencies can be stubbed.
3. Never commit to `claude/pixelhand-integration`. Push your lane branch and
   write `Integration/<LANE>.md` (what changed, Mac checks, compile risks)
   ending with the line `<Lane>: READY TO MERGE`. The primary session merges
   and the owner's Mac build loop verifies.
4. Private API: Mac app only, through `dlsym`, with a fallback when the
   symbol is missing (`DECISIONS.md`). The iOS app stays public API only.
5. Re-implement from Sill's behaviour and docs; copy no Sill code.

## 2. Lanes and what they own

### 2.1 Network: S1 AWDL off + keep-alive, S13 USB wired, S15 VPN

| Owns | |
| --- | --- |
| Core | `Protocol/SessionMessage.swift`, `Session/Liveness.swift`, new `Network/**` (link judging, wired/VPN policy) |
| Mac | `Handlers/SessionHandler.swift`, new `DeckHandMac/Network/**` (USB CDC-NCM detection, S13) |
| iOS | the heartbeat and keep-alive part of the remote's session model (see §2.7), new `DeckHandiOS/Network/**` |
| Loom | `Sources/**` changes S13/S15 need, product-agnostic only (`AGENTS.md` "Repository Isolation"; no Pixel Hand names in Loom) |

- **S1:** `enablePeerToPeer: false` in both `LoomContainerConfiguration`s
  (`MacHostApp.swift`, `DeckHandApp.swift`: those argument lines only, see
  §3) and a small, frequent keep-alive `tick` in `SessionMessage` while a
  session is in front. Keep `HeartbeatResponder` answering off the main
  actor. Pause in the background, reset the liveness clock on resume.
- **S13** may need Loom to expose the scoped remote endpoint; propose that
  in Loom terms.
- **S15** builds on S4's trust list, so it starts after Pairing merges.

### 2.2 Mirror: binary stream, S5 HEVC, S6 stats, S3 local cursor, display picker / desktop dots / cursor badge, S14 single window, S16 virtual display

| Owns | |
| --- | --- |
| Core | `Protocol/MirrorMessage.swift`, `Protocol/CaptureMessage.swift`, `Protocol/BinaryFrame.swift`, `Protocol/DiagnosticsMessage.swift` (S6 stats; activates the reserved domain), `Models/DisplayInfo.swift`, `Models/CaptureMode.swift`, new `Mirror/**` (frame pacing, stats maths, keyframe policy) |
| Mac | `MirrorStreamService.swift`, `ScreenCaptureService.swift`, `Handlers/MirrorHandler.swift`, `Handlers/CaptureHandler.swift`, new `DeckHandMac/Mirror/**` (VideoToolbox encoder, S16 virtual display) |
| iOS | `MirrorThumbnailView.swift`, the mirror part of the remote's session model (§2.7), capture views (`ScreenshotPreviewView`, `AnnotationView`, `OCRResultView`, `RegionCropView`, `WindowPickerView`) and the capture coordinator, new `DeckHandiOS/Mirror/**` |

- **Binary stream first:** frames move off the JSON control stream onto
  `PixelHandStream.mirror`, framed by `BinaryFrameHeader` (layout fixed and
  tested in Core). Announce it with `ProtocolFeature.binaryMirrorStream` in
  `HostStatus`, then remove `MirrorMessage.frame`. S5 (HEVC) and S6 build on
  it.
- **Display picker / desktop dots / cursor badge** (the ticket in
  `STATUS.md`): the Mac side (`SpacesMonitor`, the snapshot model and its
  message) belongs to Mac system control (§2.3). Build the picker on the
  existing `mirror.displayList` first; add dots and the badge when the
  snapshot message lands.
- **S16** stays deferred (`DECISIONS.md`) unless the owner schedules it.

### 2.3 Mac system control: S7 symbolic hot keys, S8 display wake + locked-Mac gate, S9 hardened menu reading, Spaces monitor

| Owns | |
| --- | --- |
| Core | `Protocol/SystemMessage.swift`, `Protocol/AppsMessage.swift`, `System/**` (`SystemMacro`, `SystemActionPlan`), new `Models/DisplayLayout.swift` (the Spaces/display/cursor snapshot) |
| Mac | `Handlers/SystemHandler.swift`, `Handlers/AppsHandler.swift`, `SystemActionTrigger.swift`, `CursorLocator.swift`, `AppLauncher.swift`, `ContextObserver.swift`, `MenuShortcutDiscovery.swift`, `ActiveAppMonitor.swift`, `RunningAppMonitor.swift`, `InstalledAppScanner.swift`, new `SymbolicHotKeys.swift`, `DisplayWake.swift`, `LockState.swift`, `SpacesMonitor.swift` |

- **S7** replaces `osascript` for Mission Control, App Exposé and Spaces
  with the user's real bindings (read with the CGS calls), falling back to
  defaults.
- **S8's locked-Mac gate** sits in front of the router. It may add one call
  in `ControlReceiver.consumeMessages` (shared hot spot, §3); the gate's
  logic goes in its own file, its policy in Core.
- **Spaces monitor** sends the snapshot from the ticket in `STATUS.md` as a
  new `SystemMessage` case (for example `displayState`). The Mirror lane
  consumes it on the remote.

### 2.4 Pairing: S4 persistent pairing with code / QR and "Forget device"

| Owns | |
| --- | --- |
| Core | `Protocol/PairingMessage.swift`, `Pairing/**` (`PreApprovalGate`, `PeerCompatibility`, new pairing code with Damm check digit, code window and lockout, trust-record logic), `Copy/ApprovalStatusCopy.swift` |
| Mac | `Handlers/PairingHandler.swift`, `DeviceAuthorizationManager.swift`, `DeckHandHandshakeTrustProvider.swift`, the device-list and pairing section of `MacMenuBarView.swift` |
| iOS | `AuthorizationOverlay.swift`, `PeerPickerView.swift`, new `DeckHandiOS/Pairing/**` (code entry, QR scan) |
| Shared | `Shared/PeerCompatibility+Loom.swift`, `Shared/DeckHandCloud.swift` |

- Trust is keyed on the Loom identity key (`LoomPeerIdentity.identityKeyID`),
  through Loom's trust provider hooks, not app-level ids.
- QR scanning needs `NSCameraUsageDescription` in the iOS `Info.plist`
  (shared hot spot, §3).

### 2.5 iOS interaction: text typing, click-drag, S11 gestures, S12 Pencil hover, S10 clipboard sync

| Owns | |
| --- | --- |
| Core | `Protocol/InputMessage.swift`, `Protocol/SharingMessage.swift` (S10; activates the reserved domain), `Input/**` (`RemoteInputValidation`), `Models/ScrollPhase.swift`, new `Input/**` logic (key tables, `typeText` chunking, drag state machine, gesture maps) |
| Mac | `Handlers/InputHandler.swift`, `InputInjector.swift`, new `DeckHandMac/Clipboard/**` |
| iOS | `TrackpadView.swift`, `MultiTouchTrackpad.swift`, `TrackpadSender.swift`, new `DeckHandiOS/Keyboard/**`, `DeckHandiOS/Clipboard/**` |

- Every new remote → Mac number or string gets a rule in
  `RemoteInputValidation.sanitize(_:)` and a test.
- S11's Mission Control gestures call S7's system actions; ask Mac system
  control for any new `SystemMacro` case rather than adding one.
- S10 uses `UIPasteControl` on iOS (no paste prompts).

### 2.6 Store: StoreKit 2 subscription and free-tier gating

As decided in `DECISIONS.md` (2026-11-17): $2.99/month and $19.99/year,
2-week trial, group "Pixel Hand Pro", IDs
`com.widgetsflow.pixelhand.pro.monthly` / `.yearly`, Family Sharing on. Free:
trackpad, keyboard and media keys with one Mac. Pro: decks and chips,
mirror, capture/OCR, multiple Macs, sharing, AI. Everything unlocked during
the trial. iOS only; no server.

| Owns | |
| --- | --- |
| Core | new `Store/**`: the entitlement model and the gating policy (feature → free/Pro, trial), tested on Linux |
| iOS | new `DeckHandiOS/Store/**` (StoreKit 2 manager, `Transaction.currentEntitlements`, paywall, Restore Purchases, the subscription disclosures), a new Settings section file for the subscription row (§2.7), `PixelHand.storekit` |
| Docs | `AppStore/**` subscription copy |

- Gating reaches other lanes' views through one environment value (for
  example `\.entitlements`) and a single modifier; other lanes don't import
  StoreKit. Adding the modifier to another lane's view is a one-line edit,
  listed in the handoff doc.
- Wiring the `.storekit` file into the scheme touches `project.yml`
  (shared hot spot, §3).
- Merge last: it gates UI the other lanes are still changing.

### 2.7 The remote's session model and shared iOS views

PH-010 split `ControlView`, `QuickActionsBar` and `SettingsView`; see
`FOUNDATION.md` §4 for the new files. Ownership:

| File (under `DeckHandiOS/`) | Owner |
| --- | --- |
| `Control/ControlSessionModel.swift` | **Shared hot spot.** One connection's state and its single message loop. See the rule below. |
| `Control/CaptureCoordinator.swift`, `Control/ControlCaptureSheets.swift`, `Control/CaptureCapsule.swift` | Mirror |
| `ControlView.swift`, `Control/ControlToolbar.swift`, `Control/HostCapabilityBanner.swift`, `ContentRootView.swift` | Integration. A lane adds a toolbar item or banner with a small, announced edit. |
| `QuickActions/TextFieldAction.swift`, `QuickActions/QuickActionsNumpad.swift` | iOS interaction (text-field chips and numpad belong with typing) |
| `QuickActionsBar.swift`, the rest of `QuickActions/**`, `StreamDeckGridView.swift`, `AppShortcutsSheet.swift`, `ShortcutStore.swift`, `DeliveryDots.swift` | Integration (chips and deck, §2.8) |
| `Settings/SettingsMirrorSection.swift`, `Settings/SettingsCaptureSection.swift`, `Settings/DeckHandSettings+Mirror.swift`, `Settings/DeckHandSettings+Capture.swift` | Mirror |
| `Settings/SettingsPointerSection.swift`, `Settings/DeckHandSettings+Input.swift` | iOS interaction |
| `Settings/SettingsConnectionSection.swift` | Network (Pairing adds its rows, for example "Paired devices", in its own `Settings/SettingsPairingSection.swift`) |
| `Settings/CloudRecognitionRow.swift` | Pairing |
| new `Settings/SettingsSubscriptionSection.swift` | Store |
| `SettingsView.swift` (the section list), `Settings/SettingsBuildingBlocks.swift`, `Settings/SettingsAppearanceSection.swift`, `Settings/SettingsAppsSection.swift`, `Settings/SettingsPrivacySection.swift`, `Settings/SettingsAboutSection.swift`, `Settings/DeckHandSettings+Appearance.swift` | Integration. Adding your section to the list in `SettingsView.swift` is a one-line edit. |

**`ControlSessionModel` rule.** `@Observable` needs stored properties in the
class body, so:

- add stored properties under your lane's `// MARK:` in the class (create
  one: `// MARK: Network`, `// MARK: Mirror`, …);
- put the logic in your own extension file,
  `Control/ControlSessionModel+<Lane>.swift` (move the existing mirror or
  heartbeat code there the first time you change it);
- in `handleOnMain(_:)` and the pre-UI switch in `listenForHostMessages`,
  each message has one `case`; add yours, keep the `default`, and don't
  reorder others' cases;
- there is still exactly **one** reader of `connection.messages`. Don't add
  a second loop; a binary mirror stream is a separate Loom stream, read in
  the Mirror lane's own code.

Network owns the heartbeat in `run(settings:)`; Mirror owns the mirror
frame path and `toggleMirror`/`renegotiateMirror`; Pairing owns the
`pairing.authorizationStatus` case and the resync poll.

### 2.8 Not in a lane this phase

Owned by the integration (primary) session; lanes ask before editing:

- `Core/Deck/**` (`Action`, `ActionOutcome`, `DeckDocument`),
  `Protocol/DeckMessage.swift`, `Handlers/DeckHandler.swift`, the chips and
  deck views. A lane that needs a new `Action` case adds it in its own
  small commit and says so.
- `Copy/CloudRecognitionStatus.swift`, `Concurrency/SerialTaskQueue.swift`,
  `Models/` files not listed above, `Shared/DeckHandTheme.swift`,
  `PixelArt.swift`, `DeckHandMotion.swift`, `DeckHandDiagnostics.swift`
  (Sentry), `AppUpdater.swift` (Sparkle), the website, `.github/workflows/`.

## 3. Shared hot spots and merge rules

| Hot spot | Rule |
| --- | --- |
| **Protocol version and envelope**: `Core/Protocol/PixelHandProtocol.swift` (`version`), `Core/Tests/PixelHandCoreTests/Fixtures/protocol/MANIFEST`, the history table in `Core/PROTOCOL.md`, `Protocol/ControlMessage.swift` | Every message change bumps `PixelHandProtocol.version` by one, re-records fixtures and adds a history line (`PROTOCOL.md`). **Protocol changes merge one at a time:** rebase on integration, take the next free number, re-record, `swift test`, then hand off. Two lanes that both took the same number conflict on these three files; the later one rebases and takes the next. `ControlMessage.swift` changes only to activate a reserved domain (`sharing`: iOS interaction; `diagnostics`: Mirror): one decode line, plus its handler in the router (next row). |
| **Router and receiver**: `Core/Routing/ControlRouter.swift`, `DeckHandMac/Handlers/MacHandlers.swift`, `DeckHandMac/ControlReceiver.swift` | Integration-owned. Allowed edits: the lane activating a reserved domain adds its handler (one property, one init argument, one `route` line, one `MacHandlers` line); Mac system control adds the S8 gate call in `consumeMessages`. Nothing else. |
| **`project.yml`** | Sources are included by folder, so new files and subfolders need no edit. Only new targets, packages, schemes or build settings touch it, and only through the integration session: put the exact YAML in your handoff doc. Expected this phase: the Store lane's StoreKit configuration. Never commit an app-generated `Package.resolved` at the repo root. |
| **Info.plists and entitlements** (both apps) | Same: list the exact keys in the handoff doc; the integration session applies them. Expected: `NSCameraUsageDescription` (Pairing, QR); nothing else is known yet. Merge conflicts here are resolved by keeping both sides' keys. |
| **`LoomContainerConfiguration`** in `MacHostApp.swift` and `DeckHandApp.swift` | Network owns the transport arguments (`enablePeerToPeer`, transports, retry). Others don't edit these calls. |
| **`DeckHandSettings.swift`** (iOS settings store) | Stored `@Published` settings must live in the class. Add yours under your area's `// MARK:` (create one if needed), with its key in the same place. Conflicts are resolved by keeping both. |
| **`Shared/PixelHandCoreExports.swift`, `Core/Package.swift`** | Integration-owned. |
| **Loom (`Sources/`, `Tests/`, `Package.swift`)** | Network only, product-agnostic, with Loom tests (`swift test --scratch-path .build-local` on the Mac). |

### Merge order

Protocol-bumping branches go one at a time; within that, the suggested
order is: Network (S1), Pairing (S4), Mac system control (S7/S8/S9, Spaces),
iOS interaction, Mirror (binary stream, then S5/S6), Store last. A lane that
doesn't bump the protocol can merge in between.
