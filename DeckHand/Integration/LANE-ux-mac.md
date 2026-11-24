# Lane: UX Mac (UX-012 Mac panel, UX-019 menu-bar hand and launch screen)

Branch `claude/pixelhand-lane-ux-mac`, from `claude/pixelhand-integration`
at `9bbac4d`, merged up to the latest integration at handoff. No protocol
change (still 12). No private API.

Checks run here (Linux, Swift 6.2):

- `swift test --package-path DeckHand/Core`: 675 tests pass (11 new in
  `MacPanelDesignTests.swift`).
- `DeckHand/Scripts/linux-typecheck/run.sh`: clean, now including
  `DeckHandMac/UI/MenuBarActivity.swift` (the handlers call it).
- `swiftc -parse` on every changed Mac file. The SwiftUI/AppKit files
  can't be type-checked on Linux, so the Mac build is the first real
  compile for them (see "Compile risks").

## What changed

### UX-012 Mac menu-bar panel (`MacMenuBarView.swift`, `Pairing/PairingMenuSection.swift`)

- 340 pt wide (was 270), `PixelHandTheme` tokens throughout, system text
  styles only (`.headline`, `.body`, `.callout`, `.caption`), so the
  panel follows the Mac's text size. No fixed font sizes are left.
- **Header**: the icon's cobalt tile with the dot hand and the mint pixel
  (`MacHandTile`), this Mac's name, and a status line from Core's
  `MacPanelCopy` ("2 devices connected · ready", "Starting…", "Failed to
  start"). Trailing: a breathing mint pixel while something is connected,
  an unlit dot when idle, `LOCKED` (amber, dot-matrix) while the Mac is
  locked with a device connected, `ERROR` on a failed start.
- **Asking to connect**: amber card per request; Deny (destructive, on its
  own at the leading edge), Pair… (opens the pairing window), Allow
  (primary).
- **Devices**: each connected device has a 28 pt device icon with a live
  pixel, name, "Connected 5 minutes ago", the Network lane's
  `HostLinkBadge` (kept, same line), a `LOCKED` badge while the Mac is
  locked, the session id, and a **visible Disconnect** button (was
  hover-only). When locked, an amber note above the list says the devices
  can type the password. Lock state is `MacLockMonitor.shared.state`,
  re-read each second while the panel is open (it isn't observable).
  Empty state: hand on a navy plate, "No device connected", "Open Pixel
  Hand on your iPhone or iPad and choose <Mac>."
- **Paired**: each paired device with a visible **Forget…** that confirms in
  place (Cancel / Forget, destructive). A status line while a code is
  showing (small dot beam + "Code showing · 3:41 left"), during a lockout
  (lock glyph, amber) and just after pairing. **Pair a device…** (primary)
  opens the window; **Show code** brings it forward while a code is live.
  Pair a device… is disabled during a lockout.
- **Permissions**: a live mint pixel when granted ("On"), an amber dot and
  a labelled **Turn On…** button when not. Same 2 s TCC polling.
- **Footer**: Share crash reports checkbox (unchanged behaviour), the
  version line in dot-matrix with its spoken label (`VersionLine`),
  Updates… and Quit (⌘Q) buttons.

### "Pair a device" window (new `Pairing/PairDeviceWindow.swift`, board `v2PairMac`)

- An `NSWindow` (titled, closable) hosting `PairDeviceView`, opened by
  `PairDeviceWindow.shared.open(authManager)` from the panel. It issues a
  code unless one is already live, activates the app and centres the
  window. Closing it cancels the code (as closing the old inline code did).
- Left: the QR code drawn in dots (`UI/QRDotsView.swift`): round data
  modules, **square finder patterns**, a white plate in both appearances,
  and the pointer glyph on a navy tile in the cleared centre. The code is
  generated at **level H** (was M) so the centre tile stays inside error
  correction; the cleared centre is Core's `QRDotPlan` (≤ about 6 % of the
  modules).
- Right: Geist title "Scan this with your iPhone or iPad", "Or open Pixel
  Hand there, choose <Mac> and type the code.", the code in dot-matrix
  numerals at pitch 3 on a navy plate (`1234 567`, the check digit dimmer;
  spoken digit by digit; right-click → Copy Code), the **countdown beam**
  (10 cells over the 5-minute window, Core's
  `PairingCodeDisplay.beamLitCells`) with "Code works for 3:41 more, for
  one device", wrong-attempt warning, New code / Cancel (Esc).
- Paired: "Paired" + `PAIRED`, closes itself after 2 s. Expired: "The code
  has expired" with New code (Return). Lockout: "Pairing is paused" with
  the remaining time.

### UX-019 Menu-bar hand (`StatusItemIcon.swift`, new `UI/MenuBarActivity.swift`)

- Which dots each state lights is Core data (`MenuBarHand`, tested): a
  17 × 20 dot canvas, the icon's hand plus two rows for the tap rays,
  drawn as a template image (follows light, dark and tinted menu bars).

  | State | When | Look |
  | --- | --- | --- |
  | Not ready | Loom not running yet, or a fatal start error | whole hand at 50 % |
  | Ready | running, nothing connected | outline |
  | Asking | a pending request | fingertip fill blinks at 1 Hz |
  | Locked | a device connected and the Mac locked | outline + a padlock in the palm |
  | Receiving | 1.5 s after clipboard text arrives | fill + a 3-dot beam running along the cuff |
  | Being controlled | 2 s after any input message | fill + tap rays |
  | Connected | a device connected, idle | fill at 45 % |

- Reduce Motion holds frame 0: a steady lit fingertip, a still beam.
- `StatusItemIconController` keeps its `init(button:)` and
  `update(pendingRequests:liveConnections:)`; it gains `readiness` and a
  0.5 s tick (0.1 s while the beam runs) that re-reads the lock state and
  ends the active/receive holds. It only redraws when the picture changes.
- The VoiceOver label follows the state ("Pixel Hand, being controlled").
- Each dot is a whole point, not 78 % of the pitch: at one point per dot a
  gap would vanish or blur. This is the one place the dot rule bends;
  `06-Pixel-Identity.md` §8 may want a line saying so.
- "Receiving a file": the Mac has no file receive yet, so the clipboard
  arriving (`sharing.setClipboard`) drives it. A future file transfer
  calls `MenuBarActivity.shared.noteReceive()` too.

### UX-019 iOS launch screen

- New `DeckHandiOS/Assets.xcassets/LaunchBackground.colorset` (#060A2A,
  `Brand.screen`, both appearances) and `LaunchHand.imageset` (@1x/2x/3x):
  the icon's screen area (220 × 168 pt, transparent) with the hand and its
  tap rays centred at pitch 5 and the mint pixel at the top-trailing
  corner, in the brand palette with the glow.
- Generated by the new `DeckHand/Scripts/make-launch-image.py` from Core's
  `MenuBarHand.handRows` (Pillow). No change to the app icon artwork.
- **Needs the plist keys below** to take effect.

## project.yml / Info.plist keys for the integration session

`DeckHandiOS/Info.plist`, replace the empty `UILaunchScreen` dict:

```xml
<key>UILaunchScreen</key>
<dict>
    <key>UIColorName</key>
    <string>LaunchBackground</string>
    <key>UIImageName</key>
    <string>LaunchHand</string>
    <key>UIImageRespectsSafeAreaInsets</key>
    <false/>
</dict>
```

No `project.yml` change: the new Mac files are under `DeckHandMac/` and the
assets are in the existing iOS catalog, both picked up by the existing
`sources` groups. Run `xcodegen` as usual for the new files.

## Checks on the Mac build

Menu-bar hand (look in both a light and a dark menu bar, and with a
coloured wallpaper so the bar is tinted):

1. Launch: the hand is dimmed (50 %) for the moment before Loom starts,
   then a plain outline (Ready). With a forced start failure it stays dim.
2. Connect from the iPhone without pairing: the fingertip blinks once a
   second while the request waits. System Settings › Accessibility ›
   Display › Reduce Motion on: the fingertip is lit and still.
3. Allow: the hand fills (Connected). Move the pointer from the iPhone:
   tap rays light above the fingertip and go out 2 s after you stop.
4. Send clipboard text from the iPhone: a short beam runs along the cuff
   for 1.5 s.
5. Lock the Mac (⌃⌘Q) with the iPhone connected, unlock: on the way back,
   while the lock monitor still reads locked, the palm shows a padlock.
   (The menu bar isn't visible on the lock screen itself; the Debug
   override `defaults write com.widgetsflow.pixelhand.mac
   PixelHandTestLockState screenLocked` shows it while unlocked.)
6. VoiceOver on the status item reads the state.

Panel (light and dark appearance; System Settings › Accessibility ›
Display › Text size / larger text where available):

7. Header shows this Mac's name, the status line and a breathing mint
   pixel only while connected. No text clipped at a larger text size.
8. A pending request shows the amber card; Deny, Pair…, Allow all work
   with the mouse and with Tab + Space (Full Keyboard Access on).
9. A connected device shows Wired/Wi-Fi (`HostLinkBadge`) and a
   Disconnect button without hovering; Disconnect ends the session.
10. With the lock override above: `LOCKED` in the header and on the row,
    and the amber note.
11. Paired list: Forget… → Cancel / Forget in place; Forget on a connected
    device disconnects it and it moves to the Allow prompt next time.
12. Permissions: turn Screen Recording off in Settings; within 2 s the row
    shows an amber dot and Turn On…, which opens the right pane.
13. Footer: version line reads e.g. `PIXEL HAND 1.0 - 1`; Updates… and
    Quit work; the crash-report checkbox still persists.

Pairing window (light and dark):

14. Pair a device…: the window opens centred and in front, QR in dots with
    square corners and the pointer tile in the middle. **Scan it with the
    iPhone's Camera app and with Pixel Hand's scanner, at 1× and on a 2×
    display**; both must read it.
15. The code shows as `1234 567` in dot-matrix with the last digit dimmer;
    VoiceOver reads the digits one by one; right-click › Copy Code copies
    seven digits.
16. The beam starts full (10 cells), loses one every 30 s, and the text
    counts down; at 0:00 the window says the code has expired and New code
    issues a fresh one.
17. Type a wrong code on the iPhone: the warning shows attempts left.
    Five wrong codes: "Pairing is paused" with the time left, and the
    panel's Pair a device… is disabled until it ends.
18. Pair successfully: "Paired" for 2 s, then the window closes and the
    device is in the panel's Paired list.
19. Close the window with the red button or Esc mid-code: the code stops
    working (the iPhone is refused), and the panel's status line goes.

iOS launch (after applying the plist keys; delete the app first, the
launch screen is cached):

20. Cold launch on iPhone and iPad, portrait and landscape, light and
    dark: navy full-bleed, the hand with its rays centred, the mint pixel
    up and to the right of it. No white flash.
21. The first frame after launch (picker or onboarding) doesn't jump in
    colour: both are navy.

## Compile risks (most likely first)

1. `PairDeviceView.macName` is a `static let` on a SwiftUI `View`
   (MainActor-isolated in the Xcode 16+ SDK) read from `MacMenuBarView`;
   fine on the main actor, but if Swift complains about isolation, make it
   `nonisolated static let`.
2. `StatusItemIconController.readiness` closure in `DeckHandAppDelegate`
   reads `daemon.container?.mainContext.isRunning`. If `isRunning` isn't
   synchronously readable there, change it to whatever the panel uses
   (`loomContext.isRunning`).
3. `MacPanelButtonStyle` reads `@Environment(\.isEnabled)` inside a
   `ButtonStyle`; supported on macOS 14, but if not, drop the opacity line.
4. `QRMatrix.make` draws a `CGImage` into an 8-bit grey `CGContext`; a
   colour-space mismatch would return `nil` and the window shows the
   pointer placeholder instead of the QR (no crash). The orientation is
   checked and flipped if needed.
5. `MenuBarActivity.onChange` is a non-Sendable closure set from the
   MainActor controller; both are `@MainActor`, so it should be fine.
6. `NSRect(x:y:width:height:)` with `Int` arguments in `StatusItemIcon`
   (CGRect has the Int initialiser).

## Out-of-lane edits

| File | Owner | Edit |
| --- | --- | --- |
| `DeckHandMac/Handlers/InputHandler.swift` | iOS interaction | One line at the top of `handle`: `MenuBarActivity.shared.noteInput()`. |
| `DeckHandMac/Handlers/SharingHandler.swift` | iOS interaction | One line after `setClipboard`: `MenuBarActivity.shared.noteReceive()`. |
| `DeckHandMac/DeckHandAppDelegate.swift` | Integration / Mac system | Three lines after creating the icon controller: `iconController?.readiness = { … }`. |
| `DeckHandMac/StatusItemIcon.swift` | UX-019 names it; Mac system owns its neighbours | Rewritten: states from Core, same public entry points. `StatusItemState` is gone (only this file used it). |
| `DeckHandMac/Pairing/PairingMenuSection.swift` | Pairing | Restyled; the inline QR/code panel moved to the new window; `QRCodeImage` removed (only this file used it). Same `DeviceAuthorizationManager` calls. |
| `DeckHand/Scripts/linux-typecheck/run.sh` | shared | Added `DeckHandMac/UI/MenuBarActivity.swift` to the default list. |
| `Core/Sources/PixelHandCore/Design/{MenuBarHand,PairingCodeDisplay,MacPanelCopy}.swift`, `Core/Tests/…/MacPanelDesignTests.swift` | Design (new files) | New pure logic + tests. |

Not touched: `DesignSystem/**`, `Shell/**`, the Deck, `HostLinkBadge`.

## Not done / follow-ups

- **First-frame zoom** from the launch hand into the trackpad's dot grid
  (`06-Pixel-Identity.md` §8) is a Shell transition: UX motion lane.
- **Capability chips** per device in the panel (Control · Screen ·
  Clipboard · Files) need per-connection capability data the Mac doesn't
  keep yet.
- **Open at login** and **Settings…** from the board's footer: no Mac
  setting or Settings window exists yet.
- `HostLinkBadge` still uses SF Symbols and `DeckHandTheme`; the board's
  link badge (glyph + dot-matrix label, 20 pt capsule) is the Network
  lane's file.
- Menu-bar asset catalog: not needed, the hand is drawn at runtime from
  Core's dot map (can't fail to resolve).
- Widgets and Control Center: later, with App Intents.

Lane: READY TO MERGE
