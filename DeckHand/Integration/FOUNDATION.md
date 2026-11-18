# Pixel Hand foundation: PixelHandCore, protocol reset and hot-spot splits

Branch: `claude/pixelhand-foundation`, cut from
`origin/claude/pixelhand-integration` at `202984a`. Covers PH-003, PH-004,
PH-005 and PH-010 from `DeckHand/Product/05-Backlog.md`, and adds the lane map
for the Sill phase (`LANES.md`).

**Written in a Linux container.** `DeckHand/Core` (PixelHandCore) was built
and tested here with a real Swift 6.2 toolchain. The apps were **not**
compiled; the Mac handlers and `TrackpadSender` were type-checked on Linux
against stubs (§5). The Mac session must run §7.

## 1. Commits

| Commit | What |
| --- | --- |
| `ba0caf8` | Extract PixelHandCore as a Linux-testable package (PH-004): files move from `Shared/`, tests become Swift Testing suites, `project.yml` adds the package |
| `207b12d` | Reset the app protocol to a versioned envelope over ten domains (PH-003), with golden fixtures, and migrate every app send and receive site |
| `dc59171` | Split `ControlReceiver` into one handler per protocol domain (PH-005) |
| `80ceff2` | Add a Linux type check for app files that use only Core |
| `e8a3fde` | Split `ControlView` into a session model and toolbar views (PH-010) |
| `ebf4fbb` | Split `QuickActionsBar` into chip files (PH-010) |
| `87361cc` | Split Settings into section views (PH-010) |
| (this doc) | `LANES.md`, `FOUNDATION.md`, README layout |

`.github/workflows/`, the website and the Loom targets are untouched.

## 2. PixelHandCore (PH-004)

A Foundation-only SwiftPM package at `DeckHand/Core`, separate from the Loom
package at the root. No Loom, SwiftUI, AppKit, UIKit, CoreGraphics or
CryptoKit. Platforms: macOS 14, iOS 17.4 (same as the apps).

**Wiring.** `project.yml` declares `PixelHandCore: path: Core` and adds it
to `DeckHandMac`, `DeckHandiOS` and `DeckHandTests`.
`Shared/PixelHandCoreExports.swift` does `@_exported import PixelHandCore`,
so no app file needed a new import. It also declares two module-level
typealiases, `ScrollPhase` (SwiftUI has its own on iOS 18 / macOS 15) and
`Action`, so unqualified names stay unambiguous in files that import
SwiftUI.

### What moved where

| Before (`DeckHand/Shared/`) | Now (`DeckHand/Core/Sources/PixelHandCore/`) |
| --- | --- |
| `ControlMessage.swift` (458 lines, one enum) | `Protocol/` (see §3) |
| `LoomConnectionHandle+ControlMessage.swift`: `ControlMessageCoding` | `Protocol/ControlMessageCoding.swift`. The `LoomConnectionHandle.send(_:)` extension stays in `Shared/`. |
| `AppShortcutBinding.swift`, `CaptureMode.swift` (with `CaptureQuality`, `WindowInfo`), `DisplayInfo.swift` (with `SpaceDirection`), `InstalledAppInfo.swift`, `ScrollPhase.swift`, `UIContext.swift`, `CuratedShortcuts.swift` | `Models/` (unchanged) |
| `RemoteInputValidation.swift` | `Input/RemoteInputValidation.swift` (rewritten for the new messages, plus string/chord limits) |
| `SystemMacro.swift`, `SystemActionPlan.swift` | `System/` (`SystemMacro` is now `Codable` and travels typed) |
| `Liveness.swift` (`LivenessMonitor`, `LivenessPolicy`, `LivenessClock`, `HeartbeatResponder`) | `Session/Liveness.swift` |
| `SerialTaskQueue.swift` | `Concurrency/SerialTaskQueue.swift` |
| `PreApprovalGate.swift` | `Pairing/PreApprovalGate.swift` |
| `PeerCompatibility.swift` | Decision: `Pairing/PeerCompatibility.swift`. Loom adapter: `Shared/PeerCompatibility+Loom.swift`. |
| `ApprovalStatusCopy.swift`, `CloudRecognitionStatus.swift` | `Copy/` |
| `AppShortcut.swift` (`MacroItem.defaultDeck`) | **Removed.** Only the host's `macroButton` lookup used it, and `macroButton` is gone. |
| (new) | `Deck/Action.swift`, `Deck/DeckDocument.swift`, `Routing/ControlRouter.swift`, `Protocol/BinaryFrame.swift` |

Behaviour notes:

- The shared `JSONEncoder` now sorts keys. Linux's Foundation otherwise
  orders keys differently between runs, and the golden fixtures compare
  bytes. The cost per message is negligible.
- Previously internal helpers that the apps or tests use are now `public`
  (`SystemActionPlan.defaultMechanisms`/`parse`, the `SymbolicHotKey`
  modifier constants, `HeartbeatResponder.maxPingBytes`,
  `PreApprovalFilter.isStatusQuery`, a public `SymbolicHotKey.Chord.init`).

Still in `Shared/` (they need Loom, Sentry, os or SwiftUI):
`DeckHandCloud`, `DeckHandDiagnostics`, `DeckHandLog`, `DeckHandMotion`,
`DeckHandTheme`, `PixelArt`, `LoomConnectionHandle+ControlMessage`,
`PeerCompatibility+Loom`, `PixelHandCoreExports`.

## 3. Protocol reset (PH-003): version 2

Rules for changing it: `DeckHand/Core/PROTOCOL.md`.

**Envelope.** Every message is one JSON object with the version and exactly
one domain key:

```json
{"input":{"mouseDelta":{"dx":1.5,"dy":-2.25}},"v":2}
{"deck":{"run":{"action":{"appShortcut":{"bundleID":"com.apple.dt.Xcode","keys":["cmd","b"]}},"requestID":"cmd-1"}},"v":2}
{"session":{"hostStatus":{"status":{"accessibility":true,"features":["commandReceipts"],"screenRecording":false}}},"v":2}
```

A message with another `v`, an unknown or missing domain, or two domains
fails to decode (`ProtocolError`). Domain payloads use Swift's synthesized
`Codable`, so a lane adds a message by adding a labelled case.

**Domains**, one file each in `Core/Sources/PixelHandCore/Protocol/`:
`InputMessage`, `SystemMessage`, `AppsMessage` (apps and context),
`DeckMessage` (chips and deck), `MirrorMessage` (mirror and displays),
`CaptureMessage` (capture; OCR stays on the remote), `PairingMessage`,
`SessionMessage` (liveness), `SharingMessage` and `DiagnosticsMessage`
(both reserved, no cases yet).

**Version.** `PixelHandProtocol.version = 2`. Version 1 is the flat enum
every earlier build sent; it never carried a version, so v1 and v2 builds
simply fail to decode each other.

**"Please update" check.** Kept, and widened: both apps now advertise
`ph-proto=2` in their Bonjour TXT record
(`LoomContainerConfiguration.advertisementMetadata`, in `MacHostApp.swift`
and `DeckHandApp.swift`), and `PeerCompatibility` compares Loom's `proto`
first, then `ph-proto`. A peer with no `ph-proto` (a v1 build, or a peer
known only through iCloud) is treated as compatible rather than blocked.

**What changed from version 1** (behaviour is the same):

| Version 1 | Version 2 |
| --- | --- |
| `macroButton(id: String)` with drifting ids | `system.run(action: SystemMacro)` |
| `mediaCommand(action: "playpause")` | `input.media(key: MediaKey)` |
| `authorizationStatus(status: String)` | `pairing.authorizationStatus(state: AuthState)`; the iOS UI still keeps strings because it adds local states |
| `hostCapabilities` + `hostFeatures` | `session.hostStatus(status: HostStatus)` with `features: [ProtocolFeature]` (unknown names are skipped) |
| `tracked(requestID, command: ControlMessage)` / `commandReceipt(requestID, delivered: Bool)` | `deck.run(requestID, action: Action)` / `deck.receipt(requestID, outcome: ActionOutcome)`. An `Action` isn't a message, so runs can't nest. |
| `screenshotError(requestID: "mirror", …)` for mirror failures | `mirror.error(message:)` |
| `startMirror` / `stopMirror` / `mirrorFrame` / `displayListUpdate` | `mirror.start` / `stop` / `frame` / `displayList` |
| optional fields with back-compat defaults | every field required (owner: no compatibility constraints) |

**Action and the deck skeleton** (`Core/Deck/`). `Action` is the one typed
command a chip, dialog chip or future deck key runs: `shortcut`,
`appShortcut`, `launchApp`, `system`, `media` and `contextAction`. Each one
maps to exactly one untracked message (`action.message`), and the Mac runs
a tracked action through that same handler. `ActionOutcome` is
`delivered | refused(reason) | failed(reason) | completed`.
`DeckDocument`, `DeckPage` and `DeckKey` plus `DeckValidation` fix the Deck 2
shape; nothing persists them yet.

**Binary side channel (designed, not built).** `Protocol/BinaryFrame.swift`
fixes a 28-byte big-endian frame header ("PHBF", version, kind
jpeg/hevcParameterSets/hevcKeyFrame/hevcDeltaFrame, flags, seq,
presentation time, payload length, 16 MB cap) for mirror video on its own
Loom stream, `PixelHandStream.mirror`. The host will announce it with
`ProtocolFeature.binaryMirrorStream`. Frames still travel as JSON
`mirror.frame` today.

**Limits.** The Mac decodes remote messages with
`ProtocolLimits.maxRemoteMessageBytes` (256 KB) and refuses larger ones
before parsing. `RemoteInputValidation` now also drops strings over 64 KB
and chords of more than 16 keys (or keys over 32 bytes), and checks a
`run`'s action as the message it stands for.

## 4. Hot-spot splits

### PH-005: `ControlReceiver` → `DeckHandMac/Handlers/`

| File | Lines | What |
| --- | --- | --- |
| `ControlReceiver.swift` | 603 → 177 | Connection lifecycle, liveness sweep, decode + validate loop, then `handlers.router.route(…)` |
| `Handlers/MacHandlers.swift` | 42 | The one place handlers are registered; builds the router |
| `Handlers/InputHandler.swift` | 55 | pointer, scroll, clicks, chords, media keys |
| `Handlers/SystemHandler.swift` | 155 | system actions, Space switching (with `OnceResume`) |
| `Handlers/AppsHandler.swift` | 52 | launch, app shortcut, app list, dialog press |
| `Handlers/DeckHandler.swift` | 57 | menu import, `run` → route the action's message → `receipt` |
| `Handlers/MirrorHandler.swift` | 38 | mirror start/stop |
| `Handlers/CaptureHandler.swift` | 110 | screenshots, window list, error copy |
| `Handlers/PairingHandler.swift` | 34 | approval-status resync |
| `Handlers/SessionHandler.swift` | 49 | every 5th ping → `hostStatus` |

The routing itself is `ControlRouter<Connection>` in Core, generic over the
connection so it is tested on Linux (`ControlRouterTests`: every sample
message reaches its own domain's handler once, in order, with its
connection). Handler code was moved verbatim and stays `@MainActor`
(PH-005 suggested off-main handlers; that's a behaviour change, left to the
Mac system control lane). The unused `removeConnection(id:)` is gone.

### PH-010: iOS splits (paths under `DeckHandiOS/`)

| Before | After |
| --- | --- |
| `ControlView.swift` (1028) | `ControlView.swift` 198; `Control/ControlSessionModel.swift` 439 (an `@MainActor @Observable` model: sender, the single message loop, heartbeat and liveness, approval resync poll, host status, apps and dialog context, mirror, app-list cache); `Control/CaptureCoordinator.swift` 278; `Control/ControlCaptureSheets.swift` 108; `Control/ControlToolbar.swift` 102; `Control/CaptureCapsule.swift` 61; `Control/HostCapabilityBanner.swift` 29 |
| `QuickActionsBar.swift` (997) | `QuickActionsBar.swift` 345; `QuickActions/` Pills, Chips, FABs, `TextFieldAction`, Numpad, Dialog, `AppSwitcherMenu`, IconButton (code moved unchanged) |
| `SettingsView.swift` (361) | shell plus `Settings/` sections: Mirror, Pointer, Capture, Apps, Appearance, Connection, Privacy, About; `SettingsBuildingBlocks` (`OpaqueSettingsBar`, `SettingBlock`); `CloudRecognitionRow` |
| `DeckHandSettings.swift` (357) | 189 (stored properties stay in the class); `Settings/DeckHandSettings+Mirror`, `+Input`, `+Capture`, `+Appearance` (the choice enums) |

Every fix on the branch is carried over: the heartbeat "GAVE UP" logs, the
guard that keeps a "denied" verdict from turning into "Disconnected", the
app-list re-request on first grant, the header subtitle and live pixel, the
"Live Mirror Unavailable" alert title, receipts and delivery dots,
`OpaqueSettingsBar` and the `ToolbarSpacer` gate.

Not done from PH-010's wider scope: the shared `PressableButtonStyle` (the
six `DragGesture(minimumDistance: 0)` copies stay, because an exact
equivalent couldn't be confirmed without a device), `LayoutMetrics` (part
of the coming UX redesign), and a simulator test target for
`ControlSessionModel`.

## 5. Test results (Linux)

Toolchain: Swift 6.2 (swift-6.2-RELEASE) for Ubuntu 24.04, installed from
swift.org into `/opt/swift`. Language mode Swift 6 (strict concurrency).

```sh
swift test --package-path DeckHand/Core
# ✔ Test run with 114 tests in 18 suites passed

DeckHand/Scripts/linux-typecheck/run.sh
# Build complete!  (ControlReceiver, all 9 Handlers/ files, TrackpadSender,
#                   LoomConnectionHandle+ControlMessage; no errors, no warnings)
```

Re-record the protocol fixtures (only when the protocol changes, see
`PROTOCOL.md`):

```sh
PH_RECORD_FIXTURES=1 swift test --package-path DeckHand/Core --filter ProtocolContractTests
```

**Every existing test was migrated** (89 test functions in `DeckHandTests`
at `202984a`, all XCTest) to Swift Testing:

| Before (`DeckHandTests`, XCTest) | After |
| --- | --- |
| `ApprovalStatusCopyTests` (9) | Core `ApprovalStatusCopyTests` (6) + `ConnectionHeaderStatusTests` (3) |
| `CloudRecognitionStatusTests` (5) | Core (4) + app `DeckHandCloudTests` (1: reads `DeckHandCloud`, needs Loom) |
| `ControlMessageContractTests` (14) + `UIContextSnapshotContractTests` (4) | Core `ProtocolContractTests` (16) + `UIContextSnapshotContractTests` (4). The five v1 back-compat default tests are replaced by "every field is required" and the version check, as the owner chose no compatibility. |
| `DuplicateBundleIDTests` (3) | Core (3) |
| `LivenessTests` (11) | Core `LivenessMonitorTests` (8) + `HeartbeatResponderTests` (3) |
| `PeerCompatibilityTests` (4) | Core `PeerCompatibilityTests` (7) + app `PeerCompatibilityAdvertisementTests` (4: TXT round trip through a real `LoomPeerAdvertisement`) |
| `PreApprovalGateTests` (5) | Core (5) |
| `RemoteInputValidationTests` (12) | Core (13) |
| `SerialTaskQueueTests` (3) | Core (3) |
| `SystemActionPlanTests` (13) | Core (13) |
| `SystemMacroTests` (6) | Core (7: typed wire values replace the `MacroItem` checks) |
| (new) | Core `ActionTests` (5), `DeckDocumentTests` (5), `BinaryFrameHeaderTests` (7), `ControlRouterTests` (2) |

Totals: Core 114 (run here), `DeckHandTests` 5 (Swift Testing; Mac only).

Contract coverage: 55 golden fixtures in
`Core/Tests/PixelHandCoreTests/Fixtures/protocol/` (at least one per case;
the 35 cases are pinned, and adding a case doesn't compile until it is named
in the test), a `MANIFEST` digest tied to the version, and hostile-input
tests (other versions, v1 messages, unknown/missing/multiple domains,
unknown cases, missing fields, nested runs, oversize input, oversize
strings and chords).

## 6. Compile risks for the Mac build

Most likely first:

1. **`ControlSessionModel` / `CaptureCoordinator`** (`@MainActor
   @Observable`, held in `@State` and created in `ControlView.init` with
   `State(initialValue:)`). Watch `@ObservationIgnored` on `let`/`private`
   properties, `private(set)` with the macro, and the `[weak self]` tasks.
   The mirror frame decode is still `Task.detached { UIImage(data:)?.preparingForDisplay() }`.
2. **`ControlToolbar` is a `ToolbarContent`** with
   `#if compiler(>=6.2)` / `if #available(iOS 26.0, *) { ToolbarSpacer }`
   inside its body. If `ToolbarContentBuilder` rejects the availability
   check there, move the spacer back into `ControlView`'s `.toolbar`.
3. **`ControlCaptureSheets`** is a `ViewModifier` with `@Bindable var
   capture` and `@EnvironmentObject settings`.
4. **Access levels after the splits.** Types that were `private` in
   `QuickActionsBar.swift` and `SettingsView.swift` are now internal; a
   name clash with another internal type would show here.
5. **Parameterized existentials in `ControlRouter`**
   (`any DomainHandler<InputMessage, Connection>`). Built and tested on
   Linux; they need macOS 13 / iOS 16 at run time, below our targets.
6. **`@_exported import PixelHandCore`** in `Shared/PixelHandCoreExports.swift`
   is relied on module-wide; if Xcode warns about it, add
   `import PixelHandCore` to the files that complain.
7. **Typealiases** `ScrollPhase` and `Action` in the same file shadow
   SwiftUI's `ScrollPhase`; a "redeclaration" error means some app file
   declares one of them at top level.
8. **`DeckHandTests` now has only Swift Testing files** (no XCTest). The
   bundle needs Xcode 16+; it has that.
9. **Swift 6.4 vs 6.2**: Core and the type-checked files were compiled with
   6.2 in Swift 6 mode. A newer region checker may flag something 6.2
   accepted.
10. **Package resolution.** Xcode resolves a new local package; as before,
    don't commit the root `Package.resolved` the app build rewrites.

## 7. What the Mac build must verify

```bash
git fetch origin claude/pixelhand-foundation
cd DeckHand
xcodegen generate                      # new Core package, Handlers/, Control/, QuickActions/, Settings/ folders
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandMac   -destination 'platform=macOS' -allowProvisioningUpdates build
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandiOS   -destination 'generic/platform=iOS' -allowProvisioningUpdates build
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandTests -destination 'platform=macOS' test   # expect 5 tests
swift test --package-path Core         # on macOS too: confirms the fixtures byte-for-byte on Apple's Foundation; expect 114
cd .. && swift test --scratch-path .build-local                                                    # Loom, unchanged: 461 + 7
```

Then install both apps (Mac with `open` only) and check, on the simulator or
the iPad. Both sides must run this build: v1 and v2 don't talk.

| Area | Check |
| --- | --- |
| Approval | First connect shows "Waiting for approval"; Allow connects; Deny shows "Access Denied"; a 45 s wait shows "Request Timed Out"; input sent while waiting is dropped ("Dropped N message(s) sent before approval"); the Apps grid loads after the first Allow. |
| Version check | Build one device with `PixelHandProtocol.version = 3` (temporarily): the picker and the Mac menu bar show "Please update Pixel Hand on your …". Revert. |
| Input | Trackpad move, click, double-click, right-click, scroll with momentum; keyboard; media keys (previous, play/pause, next) from the Quick Actions bar. |
| System actions | Mission Control and Launchpad from the Quick Actions bar and the trackpad bar; Show Desktop from both; Locate; three-finger swipes; the mirror's ‹ › Space buttons. |
| Chips and receipts | Shortcut chips follow the front app and turn mint; with Accessibility off they turn red and the banner shows. Dialog chips (TextEdit ⌘W): each works; a chip pressed after the dialog closed turns red (stale). Menu import from the Apps sheet. |
| Capture | Full screen, region, window, OCR, from the capture button and its menu; the 8 s timeout copy; the preview sheet. |
| Mirror | Start, pinch to resize (renegotiates), change sharpness and frame rate in Settings while it runs, stop. With Screen Recording off, starting it shows "Live Mirror Unavailable". |
| Liveness | Five minutes of use with the mirror on: no `GAVE UP` line on either side. Quit the Mac app: the iPad shows "Disconnected" within about 10 s. |
| Settings | Every section opens and its controls stick (Mirror, Pointer, Capture, Apps, Appearance, Connection with the iCloud row, Privacy, About); the title bar stays opaque when scrolled in dark mode. |
| Logs | `log stream --predicate 'subsystem == "com.widgetsflow.pixelhand"'` shows no "Dropped an undecodable message" lines during all of the above. |

## 8. Left for the lanes and later

- `LANES.md` maps the next phase: Network, Mirror, Mac system control,
  Pairing, iOS interaction and Store, with the merge rules for
  `project.yml`, the Info.plists and the protocol version.
- PH-006's `hello` message (app version, build, model) isn't added; the
  version check is the TXT `ph-proto` plus the envelope `v`.
- Handlers off the main actor (PH-005's suggestion): Mac system control.
- `ControlView` keeps the first connection's model if `ContentRootView`
  swaps `activeConnection` without passing through `nil`, exactly as
  before. Adding `.id(connection.handle.id)` there would fix that; it's
  left out to keep behaviour unchanged.
- `DeckHandiOSTests` (simulator tests for `ControlSessionModel`),
  `LayoutMetrics` and `PressableButtonStyle` from PH-010.
- `MacroItem`'s old default deck is gone; Deck 2 starts from
  `DeckDocument`.

Foundation: READY TO MERGE
