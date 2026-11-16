# Pixel Hand feature inventory (state of `main` at `b920181`)

Reviewed 16 Nov 2026 by reading every file in `DeckHand/DeckHandMac`,
`DeckHand/DeckHandiOS` and `DeckHand/Shared`. Nothing was compiled or run;
this container has no Xcode. Paths are relative to `DeckHand/` and use
today's names. **[spec]** marks a likely consequence that was not run.

Ratings: **●●●** strong, **●●○** works with rough edges, **●○○** weak or broken.

## 0. The ten findings that matter most

| # | Finding | Where | Fix ticket |
| --- | --- | --- | --- |
| 1 | **A remote can crash the Mac host** with one scroll message: `Int32(-dy * 3)` traps on NaN, ∞ or values beyond ±7e8. No float input is validated. | `DeckHandMac/InputInjector.swift:144-145`, `:103-107` | PH-031 |
| 2 | **No text typing and no hardware keyboard.** No message carries text; nothing uses `pressesBegan`/`UIKeyCommand`. You still have to walk to the Mac to type a URL. | `Shared/ControlMessage.swift`, `DeckHandiOS/*` | PH-032 |
| 3 | **No click-and-drag.** Long-press is hard-wired to right-click; you cannot select text or move a window. | `DeckHandiOS/MultiTouchTrackpad.swift:489-498` | PH-033 |
| 4 | **Main-actor blocking on the Mac**: dialog presses (`AXUIElementPerformAction`, up to ~6 s), app-list icon rendering, window icons and native capture encoding all run on the main actor, which also injects the cursor. | `ControlReceiver.swift:217, 489-492`; `InstalledAppScanner.swift:44-55`; `ScreenCaptureService.swift:197-198, 323-327` | PH-023, PH-034 |
| 5 | **Mirror start race / shared stream**: two `startMirror`s can both build an `SCStream`; one remote's display or size retargets everyone; a hung `send` freezes the mirror for all. | `MirrorStreamService.swift:92-145, 247-255` | PH-020 |
| 6 | **"Show Desktop" never works** from the Quick Actions bar: remote sends `macroButton("showdesktop")`, host looks up ids prefixed `shortcut-`. Also "Launchpad" maps to ⌘Space (Spotlight). | `ControlReceiver.swift:470`; `Shared/AppShortcut.swift:55-60, 119-122` | PH-003, PH-022 |
| 7 | **Crash on duplicate bundle IDs** (two copies of an app): `Dictionary(uniqueKeysWithValues:)`. | `DeckHandiOS/QuickActionsBar.swift:95`; `WindowPickerView.swift:389-391` | PH-035 |
| 8 | **Approval trusts a self-chosen name**, buffers all of a pending device's messages for 45 s and replays its queued input on Allow; no cap on pending requests; Loom rate limit is unlimited. | `DeviceAuthorizationManager.swift:24-56, 216`; `MacHostApp.swift:34-54` | PH-036 |
| 9 | **Dynamic Type is unsupported**: 102 fixed `.font(.system(size:))` sites, labels down to 8–9 pt; no size-class reads; 4 fixed grid columns. | `DeckHandiOS/*`; `Shared/DeckHandTheme.swift:373-378`; `StreamDeckGridView.swift:40-45` | PH-027, PH-028 |
| 10 | **Single-Mac, session-only model**: one `activeConnection`, no saved Macs, no auto-reconnect; per-Mac data (pins, app cache, mirror layout) stored globally. | `ContentRootView.swift:12`; `StreamDeckGridView.swift:28-29`; `ControlView.swift:977` | 1.1/1.3 |

## 1. Mac host (`DeckHandMac`)

### 1.1 Hosting and Loom configuration ●●○
**How:** `MacHostApp.swift:34-54` builds a `LoomContainer` with service
`_deckhand._tcp`, the computer name, store suite `DeckHandLoomStore`, CloudKit
config (`Shared/DeckHandCloud.swift`), no remote signalling, retry disabled.
Not overridden, so defaults apply: **`enablePeerToPeer = true` (AWDL on)**,
`trust = .manualOnly`, rate limit unlimited. With CloudKit configured LoomKit
installs `LoomCloudKitTrustProvider` (`Sources/LoomKit/Public/LoomContainer.swift:84-89`).
Incoming-connection loop `:127-143`; a 5 s `while true` pruning loop `:159-170`.
**Assessment:** simple and works. AWDL costs latency (Sill measured p90 48–67 ms
vs ~4 ms off).
**Rough edges:** stale comment promising iCloud auto-allow
(`DeckHandCloud.swift:15-16`); synthesized snapshot hard-codes `.tcp`
(`MacHostApp.swift:132-140`); uncancellable loop.
**Improve:** `enablePeerToPeer: false` + keep-alive tick (PH-007); explicit
`messageRateLimitPolicy`; version TXT record (PH-006).

### 1.2 Device authorization (Allow/Deny) ●●○
**How:** `DeviceAuthorizationManager.swift:78-121` sends `pending`, posts a
notification with Allow/Deny (`:213-229`), expires after 45 s (`:231-248`);
newest request per peer wins (`:124-169`); menu-bar rows mirror it
(`MacMenuBarView.swift:332-386`). Grants live in memory for the session.
**Assessment:** clear and safe-by-default, but re-prompts on every Mac launch,
and the request shows only the peer's self-reported name.
**Bugs:** unbounded pending queue and buffered input replay (§0 #8); denial
relies on a 100 ms sleep before disconnect; "Requesting mouse access"
(`MacMenuBarView.swift:352`) understates what is granted;
`removeAndDisconnect` cancels only one of a peer's connections (`:182-192`).
**Improve:** drop pre-approval input except status queries; cap pending per
peer; persistent pairing with a code (1.1, PH-110–PH-113).

### 1.3 Liveness (ping/pong) ●●○
**How:** remote pings ~2 s; host replies inline and resends capabilities every
5th ping (`ControlReceiver.swift:239-247`); a 3 s sweep drops peers silent > 8 s,
but only ones that have pinged (`:89-110`).
**Rough edges:** pong awaited inside the serial input loop (backpressure
stalls input); non-pinging peers never reaped; iOS has no `scenePhase`
handling, so returning from background can falsely declare the Mac gone
**[spec]** (`DeckHandiOS/ControlView.swift:453-456`).
**Improve:** fold into the keep-alive tick (PH-007); scenePhase-aware resume.

### 1.4 Input injection ●●○
**How:** absolute `mouseMoved` from `NSEvent.mouseLocation` with mild
acceleration (`InputInjector.swift:82-124`); phased pixel scrolling with
momentum fields (`:137-169`); clicks and double-click via clickState
(`:184-205`); chords press modifiers, key, release in reverse (`:218-257`);
ANSI keycode table a–z, 0–9, punctuation, arrows, F1–F12 (`:399-418`); every
call checks `AXIsProcessTrusted()`.
**Assessment:** the pointer and scroll feel is well thought out.
**Bugs/gaps:** the Int32 trap (§0 #1); no drag, no text; only the last
non-modifier key used (`:385-395`); unknown keys dropped silently; no
Home/End/PgUp/PgDn/fwd-delete/F13+; ANSI positions mean ⌘Z hits the wrong
key on AZERTY/Dvorak **[spec]**; `AXIsProcessTrusted()` at 120 Hz.
**Improve:** validate/clamp floats; `mouseDown/Up/drag`; `typeText` via
`CGEventKeyboardSetUnicodeString`; layout-aware chords via `UCKeyTranslate`;
cache trust state.

### 1.5 Media keys ●○○
`mediaCommand` handles only "playpause", "next", "prev" as system-defined
events (`ControlReceiver.swift:187-193`, `InputInjector.swift:274-306`).
Strings, unknown values ignored silently. **Improve:** typed `MediaKey` enum
with volume up/down/mute and brightness.

### 1.6 Macros and system triggers ●○○
**How:** `ControlReceiver.swift:440-467`: `locate_cursor`,
`missioncontrol_trigger` (`open -a "Mission Control"`), `expose_trigger`
(osascript), `launchpad_trigger` (`open -a Launchpad`), else
`MacroItem.defaultDeck`.
**Bugs:** showdesktop id mismatch and Launchpad→⌘Space (§0 #6); the default
deck's ctrl+↑ and fn+F11 are symbolic hot keys that CGEvent posts don't fire
(the code says so at `:362-367`); Launchpad no longer exists on macOS 26
**[spec]**; `Process.run()` errors swallowed.
**Improve:** typed `SystemAction` executed via symbolic hot keys (PH-022).

### 1.7 Spaces switching ●○○
Warps the cursor to the display, runs `osascript` ctrl+←/→, waits for
`activeSpaceDidChangeNotification` (`ControlReceiver.swift:368-419`).
Needs Automation permission that the app neither tracks nor explains
(`NSAppleEventsUsageDescription` missing) and only works with default
bindings. **Improve:** PH-022.

### 1.8 App launching and app list ●●○
`AppLauncher.swift:25-77` (launch, activate-and-wait polling 20 ms);
`InstalledAppScanner.swift:22-121` scans app folders, 64 px JPEG icons, 5 min
cache, ~1.5 MB single message. **Rough edges:** scan on the main actor; JPEG
drops icon alpha **[spec]**; any bundle ID launchable; uninstalls missed for
5 min. **Improve:** off-main scan with ImageIO thumbnails, PNG/HEIC with
alpha, icons cached by bundle version and fetched lazily.

### 1.9 Running and active app updates ●●○
`RunningAppMonitor.swift:31-128`, `ActiveAppMonitor.swift:19-56`.
**Bug:** opening the menu-bar popover activates the host
(`DeckHandAppDelegate.swift:122`), and neither monitor filters by activation
policy, so **Pixel Hand itself shows up as the front app** on the remote.
Broadcasts await each peer in turn. **Improve:** filter `.regular` apps,
exclude self, send concurrently.

### 1.10 Menu shortcut discovery ●●○
`MenuShortcutDiscovery.swift:33-213`: activates (or **launches**) the app, then
walks `kAXMenuBar` in a detached task reading CmdChar/VirtualKey/Modifiers.
**Assessment:** a real differentiator; Sill reads menus too but has no
one-tap chips.
**Risks:** no depth/count cap, no `AXUIElementSetMessagingTimeout`,
`as! AXUIElement` force cast (`:55`), glyph keys (`+`, `←`) may not map to
InputInjector names **[spec]**, id slug only replaces spaces.
**Improve:** PH-023 (timeouts, caps, off-main, no launch side effect).

### 1.11 Context observer: dialog chips and field kind ●●●
`ContextObserver.swift`: AXObserver on the front app (`:73-194`), debounced
recompute (`:271-302`), layered sheet/dialog search (`:383-454`), up to 12
buttons, default/cancel tagged, revision-scoped button IDs (`:477-548`),
text/numeric/secure field classification (`:645-709`).
**Assessment:** the strongest feature; nothing in Sill compares.
**Risks:** AX walks and presses on the main thread with no messaging timeout;
keeps observing after every remote disconnects; per-window notifications never
removed (`:196-207`); 20 debug prints incl. tree dumps.
**Improve:** dedicated AX thread with timeouts, detach when no remotes,
`refused(reason)` receipt for failed presses.

### 1.12 Screenshots ●●○
Modes full/region/window (`Shared/CaptureMode.swift`), quality tiers
(`:79-103`), GPU downscale, `SCShareableContent` cache
(`ScreenCaptureService.swift:55-288`).
**Bugs:** "primary" display is `displays.first`, not the main display, and
capture has no display choice (`:350-361`); `captureWindowJPEG` returns PNG
(`:209`); every load failure reported as "permission denied" (`:92-95`);
region rects not validated (`:183-190`); PNG-encode-then-decode in
`downscale` (`:428-455`); no concurrency limit or size cap.

### 1.13 Window list ●●○
`ScreenCaptureService.swift:294-346`: layer-0 titled windows ≥ 80×60, 48 px
icons rebuilt on every request on the main actor. Window titles go to the
remote (privacy note for the policy).

### 1.14 Live mirror ●○○ (for 1.0; the feature is good, the pipeline is not)
`MirrorStreamService.swift:149-338`: `SCStream` at the requested width, 1–30
fps, `queueDepth 3`, **`showsCursor = true`**, JPEG q0.5 on a sample queue,
newest frame wins via one `busy` flag; frames are base64 inside JSON on the
input stream (`Shared/LoomConnectionHandle+ControlMessage.swift:38`).
**Bugs:** start race, shared settings across remotes, no send timeout, old
stream's `finishFrame` clears new stream's flag (`:176`), mirror errors sent as
`screenshotError("mirror")` and shown as "Screenshot Failed"
(`DeckHandiOS/ControlView.swift:625-631`).
**Improve:** PH-020 (dedicated binary stream, actor-serialised lifecycle,
per-subscriber backpressure), PH-021 (cursor on device), HEVC in 1.1.

### 1.15 Cursor locator ●●●
`CursorLocator.swift`: non-activating panel with a 1.5 s ring at the pointer.
Nice. Colours duplicated inline instead of the theme (`:136-145`).

### 1.16 Capabilities, permissions, receipts ●●○
`hostCapabilities` + `hostFeatures(commandReceipts:)` at session start and
every 5th ping (`ControlReceiver.swift:426-435`); `PermissionsMonitor.swift`
tracks Accessibility, Screen Recording, Notifications with deep links;
`tracked` → `commandReceipt` (`:252-267`).
**Rough edges:** receipt reports AX state even for non-input commands, and an
`appShortcut` whose app never came to front still reads "delivered";
Automation not tracked; the panel polls every 2 s possibly while closed
**[spec]**.

### 1.17 Menu-bar UI and status item ●●○
`DeckHandAppDelegate.swift:39-125` (`NSStatusItem` + `NSPopover`),
`StatusItemIcon.swift` (dot-hand template in ready/request/connected states,
Reduce Motion aware), `MacMenuBarView.swift` (pending, authorized devices,
permissions, quit). **Gaps:** no settings (login item, updates, crash-report
toggle lives on `app-store-prep`), no first-run window, iPad-only copy
("iPad connected", "nearby iPads"), deprecated `activate(ignoringOtherApps:)`.

### 1.18 Packaging ●●○
Not sandboxed, hardened runtime on; a sandbox-only accessibility exception
entitlement that does nothing; Apple Events entitlement without
`NSAppleEventsUsageDescription`. **Security posture:** an approved remote can
type anything (so effectively run commands), launch apps, capture any window,
press dialog buttons. That is the product, but there is no on-screen "being
controlled" indicator beyond the menu-bar icon and no log of remote actions.
**Improve:** a subtle cobalt dot-border overlay or menu-bar pulse while input
is arriving; a "Recent activity" list in the panel (1.1).

## 2. iPhone/iPad remote (`DeckHandiOS`)

### 2.1 Navigation
```
ContentRootView
├─ OnboardingView (until done)
├─ PeerPickerView (no connection) ─ sheet: Settings
└─ ControlView (connected)
   ├─ AuthorizationOverlay
   ├─ Trackpad | Apps (segmented)
   ├─ MirrorThumbnailView (overlay)
   └─ sheets/covers: Settings, capture loading → preview → annotate/OCR/share,
      region crop, window picker, app shortcuts → editor
```
Routing is state only (`ContentRootView.swift:41-121`); auth state is a string
("pending"/"granted"/"denied"/"host_disconnected").

### 2.2 Launch and root ●●○
`try!` container creation (`DeckHandApp.swift:15`) crashes on config errors; a
Loom start failure leaves "Looking for your Mac" forever
(`ContentRootView.swift:122-130`); `.task(id: connection.peerName)` keyed on
name not id (`:90`); empty `UILaunchScreen`; no scenePhase handling.

### 2.3 Onboarding ●●○
Five pages (`OnboardingView.swift:112-159`), forced dark, replayable. Copy says
"iPad" though iPhone is supported; no ScrollView so iPhone landscape likely
clips **[spec]**; page position hidden from VoiceOver (`:75`).

### 2.4 Peer picker ●●○
`@LoomQuery` peers, same-iCloud first with a "My Mac" badge
(`PeerPickerView.swift:121-123, 250-259`), one connect at a time, error banner
4 s, DotScan empty state. Width capped 520 pt: adapts well.
**Bugs:** no connect timeout or cancel (`:202`); raw `localizedDescription`
errors (`:213`); footer/hint text at 32–42 % white on navy fails contrast
(`:151, :187`); "Remote" badge implies WAN that isn't wired.

### 2.5 Authorization overlay ●●○
PixelMorph glyph per state, Disconnect/Dismiss (`AuthorizationOverlay.swift`),
status polled every 3 s × 20 (`ControlView.swift:433-439`). No max width
(≈1300 pt card on a 13" iPad); "Unknown state" copy reachable; no VoiceOver
announcement on grant/deny.

### 2.6 Control screen ●○○ (layout)
`ControlView.swift` (995 lines, ~30 `@State`s): banners, Trackpad/Apps
segmented control, toolbar with name + live pixel + front app + **a debug
"session <uuid>" line in production** (`:259-261`), mirror toggle, capture
capsule, settings, disconnect. No size-class logic; iPhone landscape leaves a
short trackpad **[spec]**; capture hint says "full-screen" whatever the default
is (`:968`). Split per `05-Backlog.md` PH-010.

### 2.7 Trackpad ●●○
`MultiTouchTrackpad.swift` + `TrackpadView.swift` + `TrackpadSender.swift`:

| Input | Result |
| --- | --- |
| 1-finger drag | pointer × sensitivity (default 1.5) |
| 2-finger drag | scroll ×0.5, natural toggle |
| 3-finger swipe | Spaces ←/→, Mission Control ↑, App Exposé ↓ |
| tap / double-tap | click / click **+** double-click (may triple-click **[spec]**) |
| long-press 400 ms | right-click |

Sender: actor with coalescing at 60/120 Hz, phased scroll, receipts with a
1.5 s timeout. **Bugs:** each callback spawns its own `Task` into the actor, so
order is not guaranteed and a scroll `.end` can precede the last `.changed`,
leaving a dangling phase **[spec]**; momentum path is dead (always zero);
no drag, no 2-finger-tap right-click, no pinch; touch surface has no
accessibility element. Gesture bar: seven 62 pt buttons with 8.5 pt labels;
Desktop sends fn+F11 here but `macroButton("showdesktop")` in Quick Actions.

### 2.8 Quick Actions bar ●●○
`QuickActionsBar.swift` (997 lines): app pill + running-apps menu, up to 6
context chips with delivery dots, text-edit/numpad row by field kind, Mission
Control/Launchpad/Desktop, media. Dialog takeover replaces the bar with dialog
buttons (`:156-173`). Only on the Apps tab.
**Bugs:** duplicate-bundle crash (§0 #7); app icons decoded from `Data` on every
body evaluation (also in 4 other files); `IconButton` and the switcher
chevron have no accessibility labels (`:960-997`); FAB auto-mode overrides the
user's manual toggle despite the comment (`StreamDeckGridView.swift:171-211`);
the `DragGesture(minimumDistance: 0)` press-state hack that
`WindowPickerView.swift:360-363` removed for eating taps is still used in 10
places.

### 2.9 Apps grid ("Stream Deck") ●●○
`StreamDeckGridView.swift`: search, Quick Actions, pinned, all apps; always 4
columns; tapping an app always opens its shortcuts sheet; pin/hide in global
`@AppStorage`; app list cached to a global file with synchronous main-thread
I/O (`ControlView.swift:975-994`). No timeout if the Mac never answers.

### 2.10 App shortcuts sheet and store ●●○
`AppShortcutsSheet.swift`: My Shortcuts + menu categories, import from the
Mac's menus, restore curated. Store: `ShortcutStore.swift` in UserDefaults
(`customShortcuts.v1`, `hiddenCuratedShortcuts.v1`); curated library for 9
apps (`Shared/CuratedShortcuts.swift`).
**Bugs:** shortcuts fired from the sheet are unconfirmed (no receipts,
`:362-367`); editor takes a free-text SF Symbol name and key with no
validation and **drops `fn`** on edit (`:574-582`); import spinner never times
out (`:376-383`); no favourites or ordering: the first six become the chips.

### 2.11 Capture, preview, region, window picker ●●○
Request tokens drop stale replies; 8 s timeout (`ControlView.swift:795-839`).
**Bugs:** full-resolution `UIImage(data:)` decode on the main actor (`:592`);
Save encodes on main (`ScreenshotPreviewView.swift:233-263`); region crop
selection drifts on rotation/resize (`RegionCropView.swift:77-79`); region
takes two captures so the screen can change in between; preview close button
unlabeled. Window picker is the best-adapted screen (adaptive grid).

### 2.12 Annotation ●○○
Freehand only (`AnnotationView.swift`). **Bugs:** exports at canvas size with
letterbox bars, not image resolution (`:705-718`); single-tap dots export black
(`:723, 732-733`); strokes not remapped on rotation; palette unlabeled.
**Improve:** PencilKit canvas in image space, arrows/boxes/text.

### 2.13 OCR ●●○
Vision `.accurate` off-main (`OCRResultView.swift:515-542`), copy text. Not
cancelled on dismiss. Missing the obvious "Type on Mac" action (needs PH-032).

### 2.14 Mirror tile ●●○
`MirrorThumbnailView.swift`: drag + pinch, sizes 200/340/94 %, stream width
tiers 640/1024/1440/1920 by on-screen width, sharpness and fps settings,
remembered layout. **Gaps:** `bottomInset: 96` hard-coded (`:69`); view-only
(tapping doesn't click there); display list received but **no display picker
UI** (`ControlView.swift:686-687`).

### 2.15 Settings ●●○
`DeckHandSettings.swift`, `SettingsView.swift`:

| Setting | Default |
| --- | --- |
| Pointer sensitivity | 1.5 |
| Input send rate | 120 Hz |
| Haptics | Full |
| Natural scrolling | Off |
| Mirror frame rate | 20 fps |
| Mirror sharpness | Auto |
| Remember mirror layout | On |
| Screenshot quality | Standard |
| Capture button default | Full screen |
| Auto-save to Photos | Off |
| Appearance | System |

Stale "Recognize my own devices — Not available" row contradicts the enabled
CloudKit (`SettingsView.swift:545-556`). No reset, no per-Mac settings.

### 2.16 Visual identity ●●●
`DotField`, `DotScan`, `PixelMorph`, `DeckHandMark`, `DeliveryDots`,
`LivePixel`, `DeckHandMotion`: efficient, Reduce Motion aware, on brand.
**Rough edges:** delivery dots are colour-only (2.5 pt, mint vs red);
`DeckHandMotion` tokens underused (inline animations ignore Reduce Motion in
`ContentRootView.swift:54,114,121`, `QuickActionsBar.swift:127-129`);
`DeckHandMark` accessibility label hard-codes "Deck Hand" (`:54`).

### 2.17 Haptics ●●●
Pre-warmed generators scaled by setting (`TrackpadView.swift:348-399`). Move
`GestureHaptic` to its own file.

### 2.18 CloudKit ●●○
Only used for the "My Mac" badge and sort order. Settings, decks and pins are
not synced.

## 3. Shared code and protocol

- `ControlMessage` has **35 cases** (`Shared/ControlMessage.swift`), all used.
  Weak spots: free strings for auth status, media and macros; `Data` as
  base64 JSON; mirror frames and screenshots on the input stream;
  `screenshotError("mirror")` overloaded; back-compat defaults that are no
  longer needed before launch.
- Contract tests: 18 XCTest tests (`DeckHandTests/ControlMessageContractTests.swift`),
  covering round-trips, back-compat defaults and hostile input (nested
  `tracked`). Not covered: key mapping, float validation, macro lookup, auth
  state machine, capture rect maths, mirror lifecycle, all iOS logic.
- Theme, motion and pixel art are well structured
  (`Shared/DeckHandTheme.swift`, `DeckHandMotion.swift`, `PixelArt.swift`).

## 4. Rename hazards (for the rename session)

Changing these changes identity, so treat them as one coordinated migration.
Since there are no users, the clean choice is to change them all at once and
accept that dev devices must re-pair:

`_deckhand._tcp` (both Info.plists, `MacHostApp.swift:36`, `DeckHandApp.swift:17`),
`DeckHandLoomStore`, `iCloud.com.deckhand.shared`, bundle IDs `com.deckhand.*`
(`app-store-prep` already moves to `com.widgetsflow.deckhand*`), keychain group,
log subsystem `com.deckhand`, `DeckHandStatusItem`, `com.deckhand.mirror.frames`,
notification name `DeckHand.appMenuShortcutsImported`, cache file
`deckhand_installed_apps.json`, UserDefaults keys. About 16 user-facing Mac
strings and ~10 iOS strings say "Deck Hand"; several say "iPad" where iPhone
is also meant. No strings are localized.

## 5. How it compares with Sill (v0.6.2)

| Area | Pixel Hand today | Sill | Take |
| --- | --- | --- | --- |
| Shortcut chips from menus, favourites | Yes | Menus mirrored, no chips | Keep our lead |
| Dialog-button chips | Yes | No | Keep |
| Receipts | Shortcuts and dialogs | Menu presses only | Extend to all actions |
| OCR, annotation, captures | Yes | No | Keep, fix export |
| Mirror | JPEG base64 ≤ 30 fps, cursor baked in | HEVC ~58 fps, local cursor, stats | 1.0 binary stream + cursor; 1.1 HEVC |
| Typing / hardware keyboard | None | Full, incl. CJK, key repeat by the Mac | 1.0 basic, 1.1 full |
| Drag | None | Trackpad hold-drag, Pencil | 1.0 |
| Pairing | Allow/Deny each launch | 12-digit code + QR, 5 min, pinned keys | 1.1 |
| Clipboard | None | Text, Paste control chip, receipt | 1.1 |
| Locked Mac, display wake | None | Yes | 1.0 |
| Updater | None | Custom signed | Sparkle in 1.0 |
| Multi-Mac | One at a time | Saved list with tiles, one session | 1.1 list, 1.3 multi-session |
| Layout | Fixed sizes | Width-driven, iPhone portrait laptop mode | 1.0 layout pass |
