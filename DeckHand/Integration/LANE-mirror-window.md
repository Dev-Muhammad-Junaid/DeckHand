# Lane: Mirror window — S14 single-window streaming

Branch `claude/pixelhand-lane-mirror-window`, from
`origin/claude/pixelhand-integration` and merged with it up to `8c47c3d`.
`git diff origin/claude/pixelhand-integration` shows only this lane's work.
Scope: `LANE-mirror-2.md` §8 / `LANE-mirror.md` §8 "mirror-window", item S14
of the upstream comparison (§4). Re-implemented from Sill's documented
behaviour; no Sill code copied.

Written in a Linux container: PixelHandCore built and tested with Swift
6.2, Mac handler files type-checked against stubs (§3). **The apps were
not compiled.** The Mac session must run §6 and §7.

## 1. What changed

### Protocol 9 (Core)

| Change | Where |
| --- | --- |
| `mirror.start` gains `windowID: UInt32?` (a `CGWindowID` from `capture.windowListResponse`; `nil` mirrors a display) | `Protocol/MirrorMessage.swift` |
| `mirror.displayList` gains `window: MirroredWindow?` (window ID, title, app name, frame size in points): what the stream shows. Sent to **every** watching remote when the capture's target changes, and again when a mirrored window is resized | `Protocol/MirrorMessage.swift`, `Models/DisplayInfo.swift` (`MirroredWindow`) |
| `mirror.error` gains `fallbackDisplayID: UInt32?` (Swift default `nil`, so existing `error(message:)` call sites still compile). Set: the window ended and the mirror **carries on** with that display; the remote shows the message as a notice and keeps the mirror open. Unset: as before, the mirror stopped | `Protocol/MirrorMessage.swift` |
| Cursor frames: while a window is mirrored, `x`/`y` are fractions of the window's frame and `isOnMirroredDisplay` means "over the window" (no layout change) | `Mac/Mirror/MirrorCursorSampler.swift` |
| Lock gate: `mirror.start` with a window ID is refused while locked or off console (`.refuse(reply: .none)`) | `System/LockPolicy.swift` (one `case`, §4) |
| `RemoteInputValidation`: `windowID` 0 → `nil` | `Input/RemoteInputValidation.swift` |
| Version 8 → **9**, fixtures re-recorded (3 new samples: `mirror.start.window`, `mirror.displayList.window`, `mirror.error.windowFallback`; case count unchanged at 52), history line, domain table | `PixelHandProtocol.swift`, `MANIFEST`, `PROTOCOL.md` |

### New pure logic (Core, `Mirror/MirrorWindow.swift`, all tested)

- `MirrorTarget` (`.display(id?)` / `.window(id)`) and
  `needsNewCapture(current:requested:)`: a different window, a window →
  display (even `displayID: nil`), or a different display replaces the
  capture; same target → reconfigure in place.
- `MirrorWindowGeometry`: `captureSize` (as wide as `maxWidth` allows but
  never wider than the window's own pixels, window aspect, height capped at
  1920, even sides, min 32), `sizeChanged` (≥ 2 pt), `cursor` (fractions of
  the window, half-open bounds), `homeDisplay` (largest overlap).
- `MirrorWindowTracker` (Mac, fed twice a second): moves only update the
  pointer frame; resizes at most every 0.5 s, the last size of a drag wins;
  missing from two looks in a row → `closed`; minimised → `minimized` at
  once; off screen and not minimised (another Space, app hidden) → keep;
  off screen with "can't tell" for 3 s → `hidden`; `end(.locked)` /
  `end(.captureFailed)`; after an end it is silent.
- `MirrorWindowCopy`: the notice for each end reason ("The Notes window
  closed. Showing Built-in Retina Display instead.") and for a start whose
  window is already gone.
- `MirrorWindowSelection` (remote): the requested window (sent with every
  re-negotiation) and the one the Mac reports; `pointWidth` for the
  pointer sprite's scale.
- `MirrorDisplayChrome.make(…, mirroringWindow:, cursorOverWindow:)`: no
  "Cursor on <display>" badge for a window; new `cursorOutsideWindow`.
  `MirrorSpaceStrip.window`: no dots, ‹ › hidden.

### Mac

- `MirrorStreamService.swift`:
  - `start(…, windowID:)`; `currentTarget` decides new capture vs in-place
    reconfigure (`MirrorTarget.needsNewCapture`).
  - Window capture: `SCContentFilter(desktopIndependentWindow:)`,
    `pointPixelScale` for pixels per point, `scalesToFit` +
    `preservesAspectRatio`, `ignoreShadowsSingleWindow` (the frame is the
    window's frame, so pointer fractions match pixels), `showsCursor =
    false`, NV12/BGRA as before. The JPEG and HEVC paths are unchanged:
    a new frame size makes `MirrorHEVCEncoder` start a new session, whose
    first frame is a key frame with parameter sets, and every subscriber
    gets `markFormatChanged`.
  - The shared stream setup moved into `runCapture(filter:config:)`.
  - In the 60 Hz cursor loop: every 30th tick `MirrorWindowProbe` →
    `MirrorWindowTracker`; every tick, a lock (`MacLockMonitor.shared.state`)
    ends a window mirror at once (frames stop immediately, then fallback).
  - Resize → `updateConfiguration` with the new size, new `displayList`.
  - End → teardown, capture the window's home display, `mirror.error(…,
    fallbackDisplayID:)` to every remote, then `displayList`.
  - A start whose window is gone, can't be captured, or arrives while
    locked → the display (`displayID` from the start, else the window's
    home) with the matching `mirror.error(…, fallbackDisplayID:)`.
  - `didStopWithError` from a window capture (window closed under it)
    → fallback, not "mirror stopped" for everyone. Errors from a stream
    that has since been replaced are now ignored (`from: source`).
  - Screen changes while a window is mirrored only recompute its home
    display.
- `Mirror/MirrorWindowProbe.swift` (new): `CGWindowListCopyWindowInfo`
  (`.optionIncludingWindow`) for frame, on-screen and owner; minimised only
  asked when off screen: hidden app → not minimised; else the AX window
  matched by `CGWindowID` through **`_AXUIElementGetWindow` via `dlsym`**
  (private, Mac only, approved class of use), `kAXMinimizedAttribute`.
  Missing symbol or no Accessibility access → "can't tell" (tracker's 3 s
  grace decides). Logged once.
- `Mirror/MirrorCursorSampler.swift`: `state(in: MirrorRect, shapeID:)`;
  the display variant calls it.
- `ScreenCaptureService.swift`: `window(matching:)` (cached if on screen,
  else a fresh listing).
- `Handlers/MirrorHandler.swift`: passes `windowID`.

### iPad

- Display picker chip (`Mirror/MirrorOverlay.swift`): now shown whenever
  the Mac has listed displays (also with one display, for "Window…").
  Menu: the mirrored window (✓) if any, the displays (✓ only when no
  window), **Window…** (disabled while the Mac is locked), Follow Cursor
  (two+ displays, not while a window is mirrored). Chip shows `macwindow`
  + app name while a window is mirrored.
- **Window…** opens the existing `WindowPickerView` (titled "Mirror
  Window") through `CaptureCoordinator.openWindowPicker(purpose: .mirror)`;
  a pick calls `onPickMirrorWindow` → `ControlSessionModel.mirrorWindow`.
  Capture's own "Window…" is unchanged (`purpose` defaults to `.capture`).
- `ControlSessionModel+Mirror.swift`: window ID in every `start` (pinch,
  settings, HEVC fallback) until a display is picked or the Mac falls
  back; picking the window's own display leaves the window; Follow cursor
  paused for a window; dots and ‹ › hidden; pointer sprite scaled by the
  window's width; `mirror.error` with `fallbackDisplayID` → notice for 5 s
  in the bottom chrome, mirror stays open; "Pointer outside the window"
  capsule when the cursor isn't over the mirrored window.
- The thumbnail's aspect already follows the frame size (image size, or
  `videoSize` from the HEVC parameter sets), so it reshapes to the window.

## 2. Commits

| Commit | What |
| --- | --- |
| `6ffd69c` | Core: protocol 9, window rules, tests, lock gate |
| `c2099f3` | Mac capture/tracker/fallback, iPad picker/notice |
| merge | `origin/claude/pixelhand-integration` `8c47c3d` (no conflicts, still protocol 9) |
| (this doc) | `LANE-mirror-window.md` |

## 3. Tests (Linux)

```sh
swift test --package-path DeckHand/Core     # ✔ 389 tests in 67 suites (integration: 368)
DeckHand/Scripts/linux-typecheck/run.sh     # Build complete, no errors
```

New suites: `MirrorTargetTests`, `MirrorWindowGeometryTests`,
`MirrorWindowTrackerTests`, `MirrorWindowCopyAndSelectionTests`; new tests
in `LockPolicyTests` (window mirror refused while locked) and
`RemoteInputValidationTests` (window ID pass-through, 0 → nil); three new
contract samples.

Type-checked: `MirrorHandler` (and the other handlers), `TrackpadSender`,
`MirrorSubscriber`, `MirrorStreamReceiver`. Parsed only (`swiftc -parse`,
ScreenCaptureKit/AppKit/AX/SwiftUI can't be stubbed sensibly):
`MirrorStreamService`, `MirrorWindowProbe`, `MirrorCursorSampler`,
`ScreenCaptureService`, `ControlSessionModel(+Mirror)`,
`CaptureCoordinator`, `ControlCaptureSheets`, `MirrorOverlay`,
`WindowPickerView`.

## 4. Out-of-lane edits

| File | Owner | Edit |
| --- | --- | --- |
| `Core/System/LockPolicy.swift` | Mac system control | one `case let .start(_, _, _, _, windowID?) where windowID != 0: return .refuse(reply: .none)` before the existing `.start` case. Announced in the brief. |
| `Core/Input/RemoteInputValidation.swift` | iOS interaction | `mirror.start` case binds and passes `windowID` (0 → nil) |
| `Core/Protocol/PixelHandProtocol.swift`, `MANIFEST`, every fixture's `v`, `PROTOCOL.md` | hot spot | version 9, history line, domain-table wording |
| `Core/Tests/…/ProtocolContractTests.swift`, `LockPolicyTests.swift`, `RemoteInputValidationTests.swift` | shared | `windowID: nil` added to existing `mirror.start` samples, `window: nil` / `fallbackDisplayID: nil` to the existing samples, new samples and tests |
| `DeckHandiOS/TrackpadSender.swift` | iOS interaction | `startMirror(…, windowID: UInt32? = nil)` |
| `DeckHandiOS/Control/ControlSessionModel.swift` | hot spot (Mirror section) | four stored properties under `// MARK: Mirror`; the two existing mirror cases in `handleOnMain` bind the new fields (no new case, no new loop) |
| `DeckHandiOS/WindowPickerView.swift` | Mirror (capture views) | in lane; listed because Capture shares it: new `title` property, default "Capture Window" |
| `Scripts/linux-typecheck/Stubs.swift` | integration | `MirrorStreamService.start` gains `windowID` |

`LockGate.swift` (Mac system) was **not** edited: its off-console
`mirror.error(message:)` call still compiles thanks to the default.
No `project.yml`, Info.plist, entitlement or Loom changes;
`MirrorWindowProbe.swift` lands in the existing `DeckHandMac/Mirror/`
folder (needs `xcodegen generate`). ApplicationServices is linked by
AppKit.

## 5. Protocol version at merge

Integration is at 8; this lane takes **9**. If another lane lands a bump
first: keep both sides' changes, take the next number, merge the history
lines, set `expectedCaseCount` to the sum of new *cases* (this lane adds
none), then
`PH_RECORD_FIXTURES=1 swift test --package-path DeckHand/Core --filter ProtocolContractTests`
and `swift test --package-path DeckHand/Core`. Watch for another lane
touching `mirror.start` / `displayList` / `error` patterns (Swift needs
every associated value bound in `case let`).

## 6. Mac build: compile risks (most likely first)

1. **`MirrorWindowProbe.swift`**: `unsafeBitCast(dlsym(…), to:
   AXGetWindowFunction.self)` with `@convention(c) (AXUIElement,
   UnsafeMutablePointer<CGWindowID>) -> AXError`; the `private static let`
   of that function type on a `@MainActor enum` (if Swift 6 calls it
   non-Sendable, mark it `nonisolated(unsafe)`); `CGRect(dictionaryRepresentation:)`
   from an `NSDictionary` cast to `CFDictionary`; `minimized as? Bool`
   from `CFTypeRef?`; `kAXWindowsAttribute as CFString`.
2. **`MirrorStreamService.windowConfiguration`**: `scalesToFit`,
   `preservesAspectRatio`, `ignoreShadowsSingleWindow` (all macOS 14,
   the deployment target); `Double(filter.pointPixelScale)` (Float).
3. **`MirrorStreamService`** nested awaits:
   `await sendWindowEnded(message: MirrorWindowCopy.ended(…, displayName: await currentDisplayName()))`;
   `throw ScreenCaptureService.CaptureError.windowNotFound` from a
   `@MainActor` type; `SCWindow.isOnScreen` / `.frame` / `.title` /
   `.owningApplication?.applicationName` reads.
4. **`MirrorFrameOutput.stream(_:didStopWithError:)`**:
   `Task { @MainActor [weak self] in … handleStreamFailure(error, from: self) }`
   — captures the `@unchecked Sendable` output weakly; `handleStreamFailure`
   is `fileprivate` with a defaulted `from:`.
5. **`MirrorMessage.error(message:fallbackDisplayID: UInt32? = nil)`**:
   a defaulted associated value; synthesized `Codable` handles it on
   Linux; should be identical on Apple platforms. Any pattern
   `case let .mirror(.error(message))` elsewhere would now bind a tuple —
   all known sites are updated.
6. **iOS `MirrorOverlay`**: `let window = …` and `let chrome = …` inside
   `body`; a non-button `Label` inside `Menu`; `.animation(_:value: chrome)`
   (`MirrorDisplayChrome` is `Equatable`).
7. **iOS `CaptureCoordinator`**: `@ObservationIgnored var onPickMirrorWindow:
   ((WindowInfo) -> Void)?` in an `@Observable` `@MainActor` class; the
   session sets it with `[weak self]`.
8. `WindowPickerView` memberwise init: `title` comes after `onCancel`
   (defaulted, so the capture call site needs no change).

## 7. What the owner's Mac build must check

```bash
git fetch origin claude/pixelhand-lane-mirror-window   # or the integration merge
cd DeckHand && xcodegen generate                        # new Mirror/MirrorWindowProbe.swift
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandMac -destination 'platform=macOS' -allowProvisioningUpdates build
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandiOS -destination 'generic/platform=iOS' -allowProvisioningUpdates build
swift test --package-path Core                          # expect 389 (more after other lanes)
```

Both devices must run this build (protocol 9). Turn on Settings › Live
mirror › Show stream stats.

| Area | Check |
| --- | --- |
| Picker | Start the mirror. With **one** display the top-left chip now appears; its menu lists the display, **Window…**, (no Follow Cursor). With two displays Follow Cursor is still there. |
| Pick a window | Window… → sheet titled **Mirror Window** (same grid as Capture › Window). Pick a Notes or Safari window: within a second the mirror shows only that window, the thumbnail reshapes to the window's aspect, the chip shows a window icon + "Notes". No dots, no ‹ ›. Capture › Window… still captures (sheet titled Capture Window). |
| JPEG and HEVC | With Efficient video (HEVC) on: stats `HEVC <w>×<h>` with the window's size; off: `JPEG`. Both show the window crisply, no green/grey blocks. |
| Resize | Drag the window's corner on the Mac: the picture follows within ~0.5–1 s of pausing, no corrupted frames (HEVC key frame), stats show the new size; the iPad thumbnail's aspect changes. Moving the window (no resize): picture unaffected. |
| Behind other windows | Cover the mirrored window with another window: the iPad still shows the mirrored window's content. |
| Cursor | Pointer over the window: drawn at the right spot (check corners and the title bar), right shape. Move it off the window: pointer disappears from the mirror and **"Pointer outside the window"** appears; back over: it goes away. No "Cursor on <display>" badge while a window is mirrored. |
| Pinch / settings | Pinch the mirror bigger/smaller and change Sharpness / Frame rate: still the window (not the display). |
| Close | Close the mirrored window (⌘W): within ~1 s the mirror shows that window's display and a notice "The Notes window closed. Showing <display> instead." for ~5 s; the mirror stays open, chip back to the display. |
| Minimise | Mirror a window, minimise it (⌘M): fallback at once with "…was minimised…". (Without Accessibility permission for Pixel Hand, or if `_AXUIElementGetWindow` is missing — Mac log says so — the fallback comes after ~3 s with "…is no longer on screen…".) |
| Other Space / hide | Mirror a window, switch the Mac to another Space, or ⌘H its app: the mirror keeps the window (last picture, resumes when it's back), no fallback (needs Accessibility; without it, fallback after ~3 s). |
| Lock | Mirror a window, lock the Mac (⌃⌘Q): the window's picture stops at once, the mirror shows the lock screen of its display with "The Mac is locked, so the window can't be mirrored…". While locked, the picker's Window… is disabled. Unlock: Window… works again. |
| Back to a display | While a window is mirrored, pick a display in the chip (including the window's own display): the display comes back. |
| Gone before start | Open the picker, close a window on the Mac, then pick it: the mirror stays on the display with "That window isn't open any more…". |
| Two remotes | iPad mirrors a window while an iPhone mirrors the display: the shared capture follows the latest request (as for displays); both get a `displayList` saying what is shown, the iPhone's chip shows the window. |
| Regressions | Display mirror, display picker, Follow cursor, badge, dots, Bring Here, HEVC fallback all as in build 5. |

## 8. Follow-up lanes

Follow-up lanes: none

- Possible polish, not a lane: "over the window" is geometric; a window
  covering the mirrored one still counts as "over" it. A hit test with
  `CGWindowListCopyWindowInfo(.optionOnScreenAboveWindow)` would refine it.
- Not done: S16 virtual display (deferred by the owner).

Lane: READY TO MERGE
