# Pixel Hand implementation backlog

Plan: **Option C**. 1.0 in about 3 weeks, then 1.1 (weeks 4–6), then 1.2–1.4.
Every ticket is sized for one session (≤ 2 days). Paths use today's names;
read them through the rename (`DeckHand` → `PixelHand`).

**Start condition:** no ticket starts until the rename and branch-merge work
now in progress has landed on `main`. Rebase on it first.

## How to read a ticket

```
PH-nnn  Title                                      lane · size · Mac?
Scope       what changes
Files       main files touched (★ = shared hot spot, see §2)
Depends     tickets that must merge first
Accept      acceptance criteria
Tests       automated tests to add (Swift Testing) + manual checks
```

**Mac?** — `Linux` means it can be built and tested in a cloud container
(PixelHandCore only). `Mac-build` means it needs Xcode to compile but can be
written in the cloud and verified in the next Mac session. `Mac-verify`
means it needs a Mac (and often devices) to verify behaviour; do it on the
owner's Mac or batch it into a Mac session.

## 1. Lanes

Each lane owns a set of files. Two sessions never work in the same lane at
the same time, and a session only edits files outside its lane through a
ticket that names them.

| Lane | Owns |
| --- | --- |
| **CORE** | `DeckHand/Core/**` (new package), `Shared/Protocol/**`, `Shared/ControlMessage.swift` ★, `project.yml` ★, `Package.swift` ★, `DeckHandTests/**` |
| **REL** (release, connection, trust) | `MacHostApp.swift`, `DeviceAuthorizationManager.swift`, `DeckHandAppDelegate.swift`, both `Info.plist` ★ and entitlements ★, `Scripts/**`, Loom merge, Sparkle, `Shared/DeckHandCloud.swift` |
| **MAC-IN** (Mac input and system) | `InputInjector.swift`, `CursorLocator.swift`, `AppLauncher.swift`, new `SymbolicHotKeys.swift`, `DisplayWake.swift`, `LockState.swift`, `Handlers/InputHandler.swift`, `Handlers/SystemHandler.swift` |
| **MAC-CTX** (Mac context and apps) | `MenuShortcutDiscovery.swift`, `ContextObserver.swift`, `ActiveAppMonitor.swift`, `RunningAppMonitor.swift`, `InstalledAppScanner.swift`, `Handlers/ContextHandler.swift`, `Handlers/AppsHandler.swift` |
| **MIRROR** (capture and mirror, both apps) | `ScreenCaptureService.swift`, `MirrorStreamService.swift`, `Handlers/CaptureHandler.swift`, iOS `MirrorThumbnailView.swift`, new iOS `Mirror/**` |
| **IOS-SHELL** | `ContentRootView.swift`, `ControlView.swift` ★, `PeerPickerView.swift`, `AuthorizationOverlay.swift`, `OnboardingView.swift`, `SettingsView.swift`, `DeckHandSettings.swift` ★, `Shared/DeckHandTheme.swift`, `MacMenuBarView.swift` (Mac panel UI) |
| **IOS-INPUT** | `TrackpadView.swift`, `MultiTouchTrackpad.swift`, `TrackpadSender.swift`, new `Keyboard/**` |
| **IOS-DECK** | `QuickActionsBar.swift` ★, `StreamDeckGridView.swift`, `AppShortcutsSheet.swift`, `ShortcutStore.swift`, `DeliveryDots.swift`, `Shared/CuratedShortcuts.swift`, `Shared/AppShortcut*.swift` |
| **IOS-CAP** | `ScreenshotPreviewView.swift`, `AnnotationView.swift`, `OCRResultView.swift`, `RegionCropView.swift`, `WindowPickerView.swift` |
| **DOCS** | `README.md`, `DeckHand/Product/**`, `AppStore/**`, DocC |

## 2. Shared hot spots and how to serialise them

| Hot spot | Why it is hot | Rule |
| --- | --- | --- |
| `Shared/ControlMessage.swift` | Every feature adds a message; one 458-line switch | **PH-003 splits it first** into `Shared/Protocol/` with one file per domain (`InputMessage`, `AppsMessage`, `ContextMessage`, `CaptureMessage`, `MirrorMessage`, `SessionMessage`, `ShareMessage`, `DeckMessage`). After that a lane edits only its domain file; the envelope changes by one line when a *new domain* appears. Every protocol change also edits a golden fixture and bumps `PixelHandProtocol.version` in one place, so **protocol PRs merge one at a time**: rebase on `main`, run `swift test --package-path DeckHand/Core`, merge, next. |
| `DeckHandMac/ControlReceiver.swift` | One dispatch switch for all messages | **PH-005 splits it** into `Handlers/*Handler.swift` per domain plus a thin router. After that each lane owns its handler. |
| `DeckHandiOS/ControlView.swift`, `QuickActionsBar.swift` | ~1,000 lines each; touched by most iOS features | **PH-010 splits them** (`ControlSessionModel`, `CaptureCoordinator`, `ControlToolbar`, chip files). Until PH-010 merges, no other ticket edits these files. |
| `DeckHandiOS/DeckHandSettings.swift` | Each feature adds keys | PH-010 also splits it into `Settings+Input.swift`, `Settings+Mirror.swift`, `Settings+Capture.swift`, … owned by the matching lane. |
| `project.yml` | XcodeGen spec | Sources are included **by folder**, so new files need no edit. Only new targets, packages or build settings touch it: PH-004 (Core), PH-008 (Sparkle), Sentry (already on `app-store-prep`), PH-050 (UI tests), 1.2 widget extension. These go through the CORE lane, in that order. |
| `Info.plist` ×2, entitlements | Usage strings, Bonjour types, keys | REL lane only. Other lanes request a change in their PR description; REL batches them. |
| `Package.swift` / Loom | Loom merge in progress | REL lane only, and only PH-001/PH-002 in 1.0. Loom stays product-agnostic (`AGENTS.md`). |

**Coordination:** the coordinating session keeps the order of hot-spot
tickets. A session whose ticket is marked ★ asks the coordinator before
starting and announces the merge when done.

## 3. Milestone M0 — Foundation (week 1, days 1–3)

Goal: the merged Loom works, the protocol is reset for 1.0, and the hot spots
are split so week 2 can run five lanes in parallel.

**PH-001  Land the day-one branches**  REL · S · Mac-verify
- Scope: merge `claude/affectionate-euler-0yuyqm` (LoomHost blocking-IO fix), `claude/happy-lovelace-jso3t1` (CI), raise `swift-nio-ssh` to `from: "0.14.1"`.
- Files: `Package.swift` ★, `Package.resolved`, `.github/workflows/*`, `Sources/LoomHost/**`.
- Depends: rename landed (may already be done by the merging session — check first).
- Accept: `swift test --scratch-path .build-local` passes on the Mac; resolved nio-ssh ≥ 0.14.1.
- Tests: existing Loom suite.

**PH-002  Merge Loom 2.2.16 and keep first-time pairing working**  REL · M · Mac-verify
- Scope: take `scratch/trial-merge-loom-2.2.16` (16 conflicts resolved, `DeckHandHandshakeTrustProvider` wired). Run §3.6 of the comparison report; fix what the Mac build finds.
- Files: `Sources/**`, `Tests/**`, `DeckHandMac/DeckHandHandshakeTrustProvider.swift`, `MacHostApp.swift`.
- Depends: PH-001.
- Accept: 460 Loom tests pass (or known flakes skipped with an issue); first-time device → Allow connects; Deny refuses; a `main` build and a merged build refuse each other.
- Tests: `DeckHandHandshakeTrustProviderTests` (trusted only with authenticated identity and matching key ID).

**PH-003  Reset the app protocol and split it by domain**  CORE · M · Linux (after PH-004) ★
- Scope: move `ControlMessage` into `Shared/Protocol/` as a top-level envelope over domain enums. Since there are no users, drop all back-compat defaults. Replace strings with types: `AuthState` (pending/granted/denied), `MediaKey`, `SystemAction` (missionControl, appExpose, showDesktop, launchpad→"Apps" on 26+, spaceLeft/Right, lockScreen, sleepDisplay, locateCursor), `KeyChord`. Replace `macroButton` with `system(SystemAction)` (fixes the showdesktop id bug). Replace `hostCapabilities` + `hostFeatures` with `hello` (PH-006). Replace `tracked`/`commandReceipt` with `run(requestID, action)` / `receipt(requestID, outcome)`, `outcome = delivered | refused(reason) | failed(reason) | completed`. Separate `mirrorError` from `screenshotError`. Add size limits to decoding (strings ≤ 64 KB, arrays ≤ 5,000).
- Files: `Shared/ControlMessage.swift` ★ → `Shared/Protocol/*.swift`, `Shared/AppShortcut.swift`, all senders/handlers (mechanical), `DeckHandTests/*`.
- Depends: PH-004 (same session can do both, 004 first).
- Accept: both apps compile; every case has a golden fixture; no `String`-typed enums remain on the wire.
- Tests: round-trip + golden fixtures for every case; hostile-input tests (nested `run`, oversize, unknown type); migrate the 18 XCTest tests to Swift Testing.

**PH-004  Extract `PixelHandCore` (Linux-testable)**  CORE · M · Linux + Mac-build ★
- Scope: new SwiftPM package `DeckHand/Core` (separate from the Loom package) holding the protocol, `Action`, `KeyChord`, key tables, capture types, display/app info models. Foundation only. Both app targets depend on it via `project.yml`.
- Files: `DeckHand/Core/**` (new), `project.yml` ★, moves from `Shared/`.
- Depends: rename landed.
- Accept: `swift test --package-path DeckHand/Core` passes on Linux; both apps build on the Mac.
- Tests: package skeleton with one suite per model.

**PH-005  Split `ControlReceiver` into domain handlers**  MAC-IN · S · Mac-build ★
- Scope: thin router + `InputHandler`, `SystemHandler`, `AppsHandler`, `ContextHandler`, `CaptureHandler`, `SessionHandler`. Each handler is a non-`@MainActor` type that hops to main only for AppKit calls. Remove dead `removeConnection(id:)`.
- Files: `DeckHandMac/ControlReceiver.swift` ★ → `DeckHandMac/Handlers/*`.
- Depends: PH-003.
- Accept: behaviour unchanged (manual smoke: trackpad, chip, capture, mirror); router < 150 lines.
- Tests: router test with a fake handle: each message reaches the right handler.

**PH-006  Version handshake and "Please update"**  CORE+REL+IOS-SHELL · M · Mac-verify
- Scope: Mac advertises `ph-proto=<n>` via `advertisementMetadata`; picker shows an incompatible Mac greyed with "Update Pixel Hand on this Mac" (QR + URL). After connect both sides send `hello { appVersion, build, protocol, features: Set<Feature>, macName, model }`. A newer Mac seeing an older remote shows "Update Pixel Hand on <device>" in the panel; the remote shows the same for an older Mac whose `features` lack something it needs.
- Files: `Shared/Protocol/SessionMessage.swift`, `MacHostApp.swift`, `PeerPickerView.swift`, `MacMenuBarView.swift`.
- Depends: PH-003, PH-002.
- Accept: a build with `ph-proto=0` shows the update card and can't be tapped; matched builds connect.
- Tests: Core `VersionCompatibilityTests` (matrix), TXT parsing.

**PH-007  AWDL off and Wi-Fi keep-alive**  REL · S · Mac-verify
- Scope: `enablePeerToPeer: false` in both apps; replace the 2 s ping with a light 250 ms tick while a session is in front (tiny `tick(seq)`; host answers every 8th as liveness); keep 8 s silence timeout. Remote handles `scenePhase` (pause tick and mirror in background; reset liveness clock on resume).
- Files: `MacHostApp.swift`, `DeckHandApp.swift`, `Shared/Protocol/SessionMessage.swift`, `TrackpadSender.swift` (ping code), `ControlView.swift` ★ (heartbeat; after PH-010 it's `ControlSessionModel`).
- Depends: PH-003, PH-010.
- Accept: RTT p90 under 15 ms on a normal Wi-Fi network (stats from PH-026); backgrounding 30 s and returning does not show "disconnected".
- Tests: Core liveness-clock unit test; manual RTT check.

**PH-008  Sparkle in the Mac app**  REL · M · Mac-verify ★
- Scope: add Sparkle 2 via SwiftPM; EdDSA key (private key in the owner's keychain, never committed); `SUFeedURL` to the site's `appcast.xml`; "Check for Updates…" in the panel; automatic checks on, automatic install off; "Updating disconnects connected devices" confirmation when sessions are live.
- Files: `project.yml` ★, `Info.plist` ★, `DeckHandAppDelegate.swift`, `MacMenuBarView.swift`.
- Depends: PH-004 (project.yml order).
- Accept: build N finds build N+1 from a test appcast and installs it; signature mismatch is refused.
- Tests: manual (checklist A).

**PH-009  Notarized DMG and release runbook**  REL · M · Mac-verify
- Scope: `Scripts/release-mac.sh` (archive, Developer ID sign, notarize with `notarytool`, staple, DMG with Applications link and dot-hand background, `generate_appcast`), `DeckHand/Product/Release.md` runbook. Re-implemented from Sill's documented behaviour, not copied.
- Files: `Scripts/**`, `DeckHand/Product/Release.md`.
- Depends: PH-008.
- Accept: DMG opens on a clean Mac with no Gatekeeper warning; appcast entry generated.
- Tests: `spctl -a -vv` and `stapler validate` in the script.

**PH-010  Split the big iOS files; add `LayoutMetrics`**  IOS-SHELL · M · Mac-build ★
- Scope: no behaviour change. `ControlView` → `ControlSessionModel` (@Observable: message loop, heartbeat, auth poll, mirror control, app cache), `CaptureCoordinator`, `ControlToolbar`, `CaptureCapsule`, `HostCapabilityBanner`. `QuickActionsBar` → bar + `QuickActionsChips`, `QuickActionsDialog`, `EditFAB`, `AppSwitcherMenu`, shared `PressableButtonStyle` (replaces the ten `DragGesture(minimumDistance: 0)` copies). Split `DeckHandSettings` by domain. Add `LayoutMetrics` environment value (03-UX-Guidelines §1). Replace string auth state with `AuthState`.
- Files: `ControlView.swift` ★, `QuickActionsBar.swift` ★, `DeckHandSettings.swift` ★, new files beside them.
- Depends: PH-003.
- Accept: `ControlView` ≤ 250 lines; manual smoke of every tab and sheet; taps in horizontal scrollers no longer missed.
- Tests: new iOS test target `DeckHandiOSTests` (Simulator) with `ControlSessionModelTests` using a fake connection (auth transitions, heartbeat timeout, stale capture token).

## 4. Milestone M1 — Sill quick wins and must-fix (week 2)

Lanes run in parallel: MIRROR (020, 021, 026), MAC-IN (022, 024, 025, 031, 032-Mac), MAC-CTX (023, 034, 037), IOS-SHELL (027, 028, 030), IOS-INPUT (032-iOS, 033), IOS-DECK (035, 038), IOS-CAP (039).

**PH-020  Mirror on its own binary stream**  MIRROR · L · Mac-verify
- Scope: open a dedicated Loom stream `"mirror"` per session; frames as binary: 16-byte header (magic, version, flags, seq, capture timestamp µs, width, height) + JPEG. Stop sending `mirrorFrame` on the input stream. Make `MirrorStreamService` an actor: serialised start/stop, one capture per display, **per-subscriber** fps/size and in-flight flag with a 1 s send timeout (drop frames, never block). iOS decodes off-main into a `CALayer`.
- Files: `MirrorStreamService.swift`, `Handlers/CaptureHandler.swift`, `Shared/Protocol/MirrorMessage.swift`, `Core/MirrorFrameHeader.swift`, iOS `Mirror/MirrorStreamReceiver.swift`, `MirrorThumbnailView.swift`.
- Depends: PH-003, PH-005, PH-010.
- Accept: two remotes can mirror different sizes; trackpad latency unaffected while mirroring at 30 fps; killing one remote doesn't freeze the other's mirror.
- Tests: Core header encode/decode/truncation; Mac actor test: concurrent start/stop leaves exactly one stream.

**PH-021  Cursor drawn on the device**  MIRROR · M · Mac-verify
- Scope: `showsCursor = false`; Mac sends `cursor(position normalized, shapeID)` at ≤ 60 Hz while mirroring and `cursorShape(id, png, hotspot)` once per new shape (`NSCursor.currentSystem`, hashed); iOS draws a sprite over the mirror, positioned from local trackpad deltas immediately and corrected by Mac updates.
- Files: `MirrorStreamService.swift`, new `DeckHandMac/CursorTracker.swift`, `Shared/Protocol/MirrorMessage.swift`, iOS `Mirror/CursorOverlay.swift`.
- Depends: PH-020.
- Accept: cursor moves with no visible lag at 15 fps mirror; I-beam over text fields; hidden when the Mac hides it.
- Tests: Core shape-cache tests; manual.

**PH-022  Mission Control and Spaces via the user's own shortcuts**  MAC-IN · M · Mac-verify
- Scope: `SymbolicHotKeys` reads bindings through `CGSGetSymbolicHotKeyValue`/`CGSIsSymbolicHotKeyEnabled` (approved private API, `dlsym`, fallback to defaults if missing) and posts the chord. Implements `SystemAction` (Mission Control, App Exposé, Show Desktop, Spaces ←/→, Launchpad/Apps). Removes all `osascript`/`open -a` paths and the Apple Events entitlement.
- Files: new `DeckHandMac/SymbolicHotKeys.swift`, `Handlers/SystemHandler.swift`, entitlements ★ (via REL).
- Depends: PH-005.
- Accept: works after rebinding Mission Control in System Settings; no Automation prompt ever appears; Show Desktop works from both remote entry points.
- Tests: reader returns defaults when symbols are absent (inject a fake loader).

**PH-023  Hardened Accessibility menu reading**  MAC-CTX · M · Mac-verify
- Scope: AX work on a dedicated serial queue/actor, `AXUIElementSetMessagingTimeout` 0.25 s per element, caps (depth 6, 1,500 items, 2 s total), no force casts, partial results returned with `truncated: true`. Don't launch an app just to read its menus: reply `refused(notRunning)`; remote offers "Open <app> and import". Apply the same timeouts to `ContextObserver` walks and to `triggerContextAction` (off main).
- Files: `MenuShortcutDiscovery.swift`, `ContextObserver.swift`, `Handlers/ContextHandler.swift`.
- Depends: PH-005.
- Accept: importing Xcode's menus completes < 3 s; a hung app returns within 2 s; cursor never stutters during import (main thread free).
- Tests: discovery against fixture trees through an `AXElementSource` protocol: caps, timeout path, modifier parsing, glyph keys mapped to names.

**PH-024  Display wake**  MAC-IN · S · Mac-verify
- Scope: on connect and on input (at most every 5 s) call `IOPMAssertionDeclareUserActivity`. If the display was asleep, the first tap only wakes (no click). Remote keeps its own screen awake while a session is in front (idle timer off, back on after 10 min without input).
- Files: new `DeckHandMac/DisplayWake.swift`, `Handlers/InputHandler.swift`, iOS `ControlSessionModel`.
- Depends: PH-005.
- Accept: sleeping display wakes on trackpad touch; no click lands on wake.
- Tests: throttle unit test.

**PH-025  Locked-Mac check**  MAC-IN · M · Mac-verify
- Scope: `LockState` from `CGSessionCopyCurrentDictionary` (`CGSSessionScreenIsLocked`, approved) plus `com.apple.screenIsLocked/Unlocked` distributed notifications; host sends `hello`-style `hostState { locked }`; while locked the host refuses context, menus, window list, app list and clipboard (`refused(locked)`), allows pointer, keys and mirror. Remote shows the lock banner and dims the deck.
- Files: new `DeckHandMac/LockState.swift`, handlers, `Shared/Protocol/SessionMessage.swift`, iOS banner in `ControlToolbar`.
- Depends: PH-005, PH-010.
- Accept: lock the Mac → banner within 1 s; type password from the remote; unlock restores chips.
- Tests: handler gating table test with a fake lock source.

**PH-026  Stats overlay (JPEG era)**  MIRROR · S · Mac-build
- Scope: client-side stats: fps received, frame age (capture timestamp vs. clock offset from ticks), RTT p50/p90 from ticks, kb/s, dropped frames, receipt latency p50/p90; one-line overlay toggle in the mirror and in Settings › Mirror.
- Files: iOS `Mirror/StatsOverlay.swift`, `Mirror/StatsModel.swift`, `Settings+Mirror.swift`.
- Depends: PH-020, PH-007.
- Accept: values update every second; hidden by default.
- Tests: percentile/rolling-window unit tests (Core).

**PH-027  Layout pass (iPhone, iPad, Split View, Stage Manager)**  IOS-SHELL · L · Mac-verify
- Scope: implement the arrangements in `03-UX-Guidelines.md` §1.2 from `LayoutMetrics`; adaptive deck grid; mirror insets from layout (drop `bottomInset: 96`); auth card max width 440; onboarding in a ScrollView; iPhone landscape trackpad-left/deck-right; Quick Actions reachable from the Trackpad tab; remove the debug "session" line.
- Files: `ControlView`/`ControlToolbar`, `StreamDeckGridView.swift`, `MirrorThumbnailView.swift`, `AuthorizationOverlay.swift`, `OnboardingView.swift`, `TrackpadView.swift` (chrome only, coordinate with IOS-INPUT).
- Depends: PH-010.
- Accept: screenshots of the control screen at iPhone SE/16 Pro Max portrait + landscape, iPad mini/13" full screen, ½ and ⅓ Split View, Stage Manager 500 pt wide: no clipping, no overlap, state kept on resize.
- Tests: XCUITest snapshot smoke for each size with the fake host (PH-050).

**PH-028  Accessibility pass**  IOS-SHELL + IOS-DECK · M · Mac-verify
- Scope: replace fixed fonts with text styles (theme first, then call sites); VoiceOver labels for `IconButton`, switcher chevron, preview close, annotation palette; receipt announcements; delivered/refused shapes (check/cross) for Differentiate Without Color; trackpad `allowsDirectInteraction` + custom actions; route inline animations through `DeckHandMotion`; contrast fixes on picker hint/footer; correct capture hint.
- Files: `Shared/DeckHandTheme.swift`, iOS views across lanes (one PR per lane, theme first).
- Depends: PH-010.
- Accept: checklist I passes at AX5; Accessibility Inspector audit has no errors on the four main screens.
- Tests: manual + one XCUITest that finds every chip by label.

**PH-030  Onboarding and permissions (1.0 level)**  IOS-SHELL + REL · M · Mac-verify
- Scope: Mac first-run window with live permission checklist (Accessibility, Screen Recording, Notifications, Open at Login via `SMAppService`); iOS onboarding copy device-neutral, "Get the Mac app" step with QR/URL, Local Network denial recovery; fix "iPad"-only copy on both apps.
- Files: new `DeckHandMac/FirstRunWindow.swift`, `PermissionsMonitor.swift`, `MacMenuBarView.swift`, `OnboardingView.swift`, `PeerPickerView.swift`.
- Depends: PH-010.
- Accept: checklist A passes on a fresh Mac and device.
- Tests: manual.

**PH-031  Validate every number from the remote**  MAC-IN · S · Mac-build
- Scope: reject non-finite floats and clamp deltas (±2,000) and scroll (±10,000) before `Int32`; region rects within 0…1 and non-empty; display/window IDs must exist; cap capture concurrency at 1 per remote, mirror at 1 per remote.
- Files: `InputInjector.swift`, `Handlers/InputHandler.swift`, `Handlers/CaptureHandler.swift`, `Core/Validation.swift`.
- Depends: PH-005.
- Accept: fuzzed messages never crash the host.
- Tests: Core validation tests (NaN, ∞, huge, negative); Mac test that feeds them to `InputHandler` with a fake injector.

**PH-032  Text typing (both apps)**  MAC-IN + IOS-INPUT · M · Mac-verify
- Scope: `Action.typeText(String)` (≤ 4 KB per message, chunked), injected with `CGEventKeyboardSetUnicodeString`; extra keys in the key table (Home, End, PgUp, PgDn, fwd-delete, F13–F20); iOS "Type" field in the context bar (sends on Return, history of last 10); hardware keyboard on iPad while the control screen is in front: `pressesBegan/Ended` → key down/up with Mac-side repeat, Esc via priority key command; OCR "Type on Mac".
- Files: `InputInjector.swift`, `Handlers/InputHandler.swift`, `Shared/Protocol/InputMessage.swift`, iOS `Keyboard/*` (new), `OCRResultView.swift` (one button; IOS-CAP agrees).
- Depends: PH-003, PH-005, PH-010.
- Accept: types "Café ☕️ 東京" into TextEdit; hardware keyboard types with repeat; ⌘-shortcuts from the hardware keyboard reach the Mac.
- Tests: Core chunking; key table completeness (every name the iOS side can send has a keycode).

**PH-033  Drag and better clicks**  IOS-INPUT + MAC-IN · M · Mac-verify
- Scope: `mouseDown/mouseUp(button)` and drag events on the Mac (`leftMouseDragged`); iOS tap-then-hold-to-drag, two-finger tap = right-click, long-press right-click as a setting; double-tap sends exactly one double-click (no extra single click); serialize sender calls through one `AsyncStream` so scroll phases stay ordered; remove dead momentum code or wire it.
- Files: `MultiTouchTrackpad.swift`, `TrackpadView.swift`, `TrackpadSender.swift`, `InputInjector.swift`, `Shared/Protocol/InputMessage.swift`.
- Depends: PH-003, PH-005.
- Accept: select text by drag, move a window, resize a window; checklist C passes.
- Tests: Core scroll-phase state machine (always balanced); gesture classifier unit tests on synthetic touch sequences.

**PH-034  Off-main app list, icons and captures on the Mac**  MAC-CTX + MIRROR · M · Mac-verify
- Scope: app scan and icon rendering off the main actor via ImageIO (PNG with alpha, 64 px), icons cached by bundle ID + version and sent lazily (`appIcon(bundleID)` on demand); window icons cached; capture encode off main; use the main display (`CGMainDisplayID`) as primary and add `displayID` to capture requests; exclude self and non-regular apps from active/running updates.
- Files: `InstalledAppScanner.swift`, `ActiveAppMonitor.swift`, `RunningAppMonitor.swift`, `ScreenCaptureService.swift`, protocol domain files.
- Depends: PH-005.
- Accept: requesting the app list doesn't stutter the cursor; Pixel Hand never appears as the front app.
- Tests: filter unit test; icon cache keying.

**PH-035  iOS crash and correctness fixes**  IOS-DECK + IOS-SHELL · S · Mac-build
- Scope: replace `Dictionary(uniqueKeysWithValues:)` (`QuickActionsBar`, `WindowPickerView`) with `uniquingKeysWith`; cache decoded app-icon `UIImage`s; `try!` container → error screen; connect timeout (10 s) + Cancel; app-list and shortcut-import timeouts with Retry; stale CloudKit settings row; mirror errors no longer titled "Screenshot Failed"; FAB respects manual toggle; editor keeps `fn` and validates the key and SF Symbol.
- Files: as listed (each in its lane; split into two PRs by lane).
- Depends: PH-010.
- Accept: each item has a regression test or a checklist line.
- Tests: `IconCacheTests`, `ShortcutEditorValidationTests`, model timeout tests.

**PH-036  Safer approval (1.0)**  REL · S · Mac-verify
- Scope: while pending, discard everything except `requestAuthorizationStatus`/`hello`; cap 3 pending requests per peer and 10 total; explicit `messageRateLimitPolicy`; show the device's key fingerprint (first 8 hex chars, grouped) on both the Mac prompt and the remote's waiting card so the user can match them; copy "wants to control this Mac" instead of "mouse access"; on-screen "being controlled" indicator (menu-bar icon pulse) while input arrives.
- Files: `DeviceAuthorizationManager.swift`, `MacMenuBarView.swift`, `AuthorizationOverlay.swift`, `MacHostApp.swift`.
- Depends: PH-002.
- Accept: input sent before Allow never runs; fingerprints match on both screens.
- Tests: auth state machine tests (expiry, stale requests, caps, discard).

**PH-037  Receipts that mean something**  MAC-CTX + MAC-IN · S · Mac-build
- Scope: `refused(reason)` for: Accessibility off, Mac locked, dialog gone, app didn't come to front within timeout (`appShortcut`), unknown key; `completed` for menu presses and launches. Every action surface (chips, sheet, deck keys, system buttons) sends `run`, so all get dots.
- Files: handlers, `AppShortcutsSheet.swift` (use confirmed send), `DeliveryDots.swift`.
- Depends: PH-003, PH-005.
- Accept: each refusal reason produces a red dot and a spoken reason.
- Tests: handler outcome table test.

**PH-038  Media and system keys on the remote**  IOS-DECK · S · Mac-build
- Scope: typed `MediaKey` incl. volume up/down/mute; `SystemAction` buttons in the Quick Actions bar (one source of truth for Show Desktop etc.); remove `MacroItem.defaultDeck` from the host.
- Files: `QuickActionsBar*`, `TrackpadView.swift` gesture bar (coordinate), `Shared/AppShortcut.swift`.
- Depends: PH-003, PH-022.
- Accept: every system button works and receipts.
- Tests: Core mapping tests.

**PH-039  Capture fixes**  IOS-CAP · M · Mac-verify
- Scope: decode screenshots off main; Save encodes off main; region crop keeps selection in normalized image space across resize/rotation; annotation exports at image resolution without letterbox, correct dot colour (move to PencilKit in image space if simpler); labels for close/palette; cancel OCR on dismiss.
- Files: `ScreenshotPreviewView.swift`, `RegionCropView.swift`, `AnnotationView.swift`, `OCRResultView.swift`, `CaptureCoordinator`.
- Depends: PH-010.
- Accept: a 5K capture annotated exports at 5K with the drawn colours; rotating during crop keeps the selection on the same content.
- Tests: normalized-rect mapping unit tests; export size test.

**PH-040  Rename-safe brand constants and copy**  DOCS + IOS-SHELL · S · Mac-build
- Scope: one `AppBrand` (name, URLs, support email, Bonjour type, store suite) used by all UI strings; String Catalog started (English only) so later localisation is mechanical.
- Files: `Shared/AppBrand.swift` (new), call sites.
- Depends: rename landed.
- Accept: `grep -r "Deck Hand"` finds nothing user-facing.
- Tests: none beyond build.

## 5. Milestone M2 — Beta and release (week 3)

**PH-050  UI-test target with a fake host**  CORE + IOS-SHELL · M · Mac-verify ★
- Scope: `-PHFakeHost` launch argument connects the remote to an in-process fake that speaks the protocol (from Core's `FakeHost`); `PixelHandUITests` with ~10 smoke flows and the layout sizes from PH-027.
- Files: `project.yml` ★, `DeckHand/UITests/**`, `Core/Tests/Support/FakeHost.swift`.
- Depends: PH-010, PH-003.
- Accept: suite runs in < 5 min on the owner's Mac.

**PH-051  Beta builds**  REL · S · Mac-verify
- Scope: TestFlight external beta for iOS; Sparkle beta channel + notarized DMG for the Mac; Sentry DSNs set (from `app-store-prep`); release notes.
- Depends: M1 merged, PH-009.

**PH-052  Full manual E2E pass**  DOCS · M · Mac-verify (devices)
- Scope: run `04-Test-Strategy.md` §5 A–E, I, J on the device matrix; file bugs as `PH-05x`.
- Depends: PH-051.

**PH-053  Store submission**  DOCS + REL · M · Mac-verify
- Scope: update `AppStore/*` for the Pixel Hand name; screenshots at 6.9" iPhone and 13" iPad from the fake-host UI tests; review video; privacy answers re-checked; submit; publish the Mac DMG and appcast on the site at the same time.
- Depends: PH-052.

**PH-054  Beta fix buffer**  all lanes · 2–3 days reserved.

## 6. 1.1 — Fast and familiar (weeks 4–6)

| Ticket | Lane | Scope | Depends |
| --- | --- | --- | --- |
| PH-101 | MIRROR | `hello.features` gains `videoCodecs`; HEVC encoder (VideoToolbox, low-latency, newest-frame mailbox) on the Mac | PH-020 |
| PH-102 | MIRROR | Backpressure: drop deltas when > 2 frames un-acked, keyframe on request, ack messages | PH-101 |
| PH-103 | MIRROR | iOS decode into `AVSampleBufferDisplayLayer`, keyframe request on gap | PH-101 |
| PH-104 | MIRROR | Quality tiers (Glance/Thumbnail/Standard/Native), Auto by tile size, per-Mac pin | PH-103 |
| PH-105 | MIRROR | Software fallback, encoder watchdog, slow-link callout "Use Standard" | PH-104 |
| PH-106 | MIRROR | Stats HUD encoder lines (codec, bitrate, encode/decode ms, keyframes) | PH-026, PH-103 |
| PH-110 | CORE | Pairing code (12 digits + Damm), QR payload, trust record model | PH-004 |
| PH-111 | REL | Mac "Pair a device" window: code, QR, 5-min single-use window, 5 tries, rate-limited device-initiated prompts; Keychain trust store keyed on Loom identity | PH-110, PH-002 |
| PH-112 | IOS-SHELL | Remote: code entry + QR scan, saved **My Macs** list with last thumbnail, Forget, auto-connect to last Mac | PH-111 |
| PH-113 | REL + IOS-SHELL | Per-capability grants (control, screen, clipboard, files) shown and enforced | PH-111 |
| PH-114 | IOS-SHELL | Per-Mac namespacing of pins, app cache, mirror layout | PH-112 |
| PH-120 | CORE | Clipboard model: text ≤ 256 KB, 4 msgs/s, skip concealed/transient pasteboard types | PH-004 |
| PH-121 | MAC-CTX | Mac pasteboard watcher → push to focused remote; receive → set + optional ⌘V (layout-aware) | PH-120 |
| PH-122 | IOS-DECK | "Paste on <Mac>" chip with `UIPasteControl`, receipts, local-only 10-min copy of Mac clipboard | PH-121 |
| PH-130 | IOS-INPUT | 3/4-finger gestures and pinch via symbolic hot keys; Pencil hover pointer; Direct mode on the expanded mirror | PH-022, PH-021 |

## 7. 1.2 — Deck 2 (epics; break into tickets when 1.1 is in beta)

- **D1 Deck model** (CORE): `DeckDocument`, pages, keys, `Action` incl. `menuCommand`, `macShortcut`, `sequence`; JSON + migration; validation.
- **D2 Deck UI** (IOS-DECK): pages with page dots, reflowing grid, key component, Follow-front-app with pin, Home/App/Context/Shortcuts pages.
- **D3 Editor** (IOS-DECK): edit mode, action library, key inspector, pixel-glyph editor, undo.
- **D4 Mac actions** (MAC-CTX/MAC-IN): press menu items by path; list and run Shortcuts (`shortcuts list/run`, 15 s timeout, exit status → receipt); URL open.
- **D5 Deck sync** between the user's remotes over Loom (needs PH-111).
- **D6 App Intents** (new IOS-INTENTS lane, new widget extension target via CORE ★ `project.yml`): entities, intents, App Shortcuts, widgets, Control Center controls, Spotlight indexing.
- **D7 Suggest a deck** (new ASSIST lane): Foundation Models `@Generable DeckProposal` constrained to discovered IDs; Mac-side model fallback; deterministic fallback.

## 8. 1.3 — Many Macs, every device

- **M1 Session manager** (IOS-SHELL): up to 4 `HostSession`s, focused vs glancing; Glance tier from PH-104.
- **M2 Switcher + overview** (IOS-SHELL): title switcher, ⌘1–4, three-finger switch, overview grid / iPad sidebar.
- **M3 Run on several Macs** (IOS-DECK): multi-target `ActionRun`, per-Mac receipt rows, confirmations.
- **M4 Host multi-remote correctness** (MAC-IN/MIRROR): input arbitration (last-writer controller), per-remote context subscriptions.
- **S1 Transfers** (CORE + REL): share manifest, Loom transfer engine, approvals, landing folders, Inbox.
- **S2 Entry points**: iOS Share extension (App Group outbox), drag to Mac card, Mac menu-bar drop + Finder Share/Services.
- **S3 iOS↔iOS and Mac↔Mac**: iOS advertises while open; Mac host discovers Macs.

## 9. 1.4 — Assist

- **A1 Command bar** with tool calling → `[ActionRun]`, preview chips, confirmations, save as key.
- **A2 Ask about this capture** (multimodal + OCRTool, OS 27).
- **A3 AX-fallback screen reading** proposing tap targets on the mirror.
- **A4 Siri onscreen awareness** annotations (OS 27).
- **A5 Evaluation suite** (`04-Test-Strategy.md` §6).

## 10. Week-by-week view for 1.0

| Day | REL | CORE | MAC-IN | MAC-CTX | MIRROR | IOS-SHELL | IOS-INPUT | IOS-DECK | IOS-CAP |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| W1 d1 | 001 | 004 | – | – | – | – | – | – | – |
| W1 d2 | 002 | 003 | – | – | – | 040 | – | – | – |
| W1 d3 | 002 | 003 | 005 | – | – | 010 | – | – | – |
| W1 d4–5 | 006, 008 | 006 | 031 | – | – | 010 | – | – | – |
| W2 d1–2 | 009, 036 | 050 | 022, 024 | 023 | 020 | 027 | 033 | 035 | 039 |
| W2 d3–5 | 007 | – | 025, 032 | 034, 037 | 021, 026 | 028, 030 | 032 | 038 | 039 |
| W3 | 051, 053 | – | fixes | fixes | fixes | fixes | fixes | fixes | fixes |

Critical path: PH-001 → PH-002 → PH-006 → beta, and PH-003 → PH-005/PH-010 →
every week-2 ticket. If PH-002 slips more than two days, ship week-2 work on
it as soon as it lands and keep PH-051 fixed; drop PH-026 and PH-030's Mac
window to 1.0.1 before moving the date.
