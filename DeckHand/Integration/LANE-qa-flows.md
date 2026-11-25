# Lane: QA fix lane B (flows), build 18 visual QA

Branch: `claude/pixelhand-lane-qa-flows` (merged with the latest
`origin/claude/pixelhand-integration` before this handoff).

Checks run here (Linux, Swift 6.2):

- `swift test --package-path DeckHand/Core`: **882 tests in 159 suites pass**
  (857 before; new suites for path classes, pairing code format, pending
  expiry, refusal copy, connection-loss presentation, launch reconnect,
  cancel dial, panel copy and typing target).
- `DeckHand/Scripts/linux-typecheck/run.sh`: passes (covers
  `DeviceAuthorizationManager`, `PairingHandler`, `RemoteAccessGate`,
  `PairedMacsStore`, `SubscriptionStore`, `MacSwitcher` and the new
  `ConnectionDiagnostics`).
- Loom: not touched, so its tests weren't run.
- Protocol: **bumped to 14** (`pairing.refused(reason:)`; codes are eight
  digits). Fixtures re-recorded; `PROTOCOL.md` history updated. Mac and
  iPhone/iPad must ship together: a build-18 remote rejects an eight-digit
  code as malformed.

## Findings

| ID | Status | Note | Files |
| --- | --- | --- | --- |
| VQ-001 | Fixed | Loopback (incl. `::ffff:127.x`) is "same machine" and gets local rules: Allow prompt and pairing code. Tunnels, Tailscale addresses and cellular stay remote (paired + pinned only); a "loopback" link reporting a routable peer stays remote. Core tests pin every class. | `Core/.../Network/RemoteAccessPolicy.swift`, `LinkJudge.swift`, `RemoteAccessTests.swift`, `DeckHandMac/Network/RemoteAccessGate.swift`, `MAC-BUILD.md`, `LANE-network-vpn.md` |
| VQ-002 | Fixed | Protocol 14 `pairing.refused(reason:)`: `declined`, `timedOut`, `notPairedRemote`, `unverified`, `replaced`, sent before `denied`. Only `declined` is worded as a person's Deny; "Pair <Mac> first" for another network; sentence-case titles. A plain `denied` (older Mac) is neutral. | `PairingMessage.swift`, `PixelHandProtocol.swift`, `ApprovalStatusCopy.swift`, `DeviceAuthorizationManager.swift`, `PairingHandler.swift`, `ControlSessionModel(+Pairing).swift` |
| VQ-003 | Fixed | Picker's labelled **Pair** opens typed code entry (QR from there); refusal card offers "Enter pairing code" after a Deny, timeout or replacement; scanner sheet has "Enter code instead" when a caller wants it. Without a live session the code is held, the device connects, and the session sends it. | `PeerPickerView.swift`, `AuthorizationOverlay.swift`, `PairingQRScannerView.swift`, `PairingCodeEntryView.swift`, `PairedMacsStore.swift`, `MacSwitcher.swift` |
| VQ-005 | Fixed | One format: 7 random digits + Damm check digit = 8, shown "4821 0934" on the Mac, in onboarding and in the entry field. Every digit at full brightness (owner's OR-11 overrides the earlier "dim check digit"). | `PairingCode.swift`, `PairingCodeDisplay.swift`, `PairDeviceWindow.swift`, `OnboardingScene.swift` (one string) |
| VQ-006 | Fixed | "Pick the Mac to control. It needs Pixel Hand open." | `PeerPickerView.swift` |
| VQ-007 | Fixed | Scan glyph replaced by a labelled "Pair" capsule; Settings keeps its VoiceOver label. | `PeerPickerView.swift` |
| VQ-008 | Fixed | "Menu bar › Pixel Hand › Pair a device"; every pairing hint uses the Mac's label without "…". | `PairingQRScannerView.swift`, `ApprovalStatusCopy.swift`, `PairingCodeEntryView.swift` |
| VQ-020 | Fixed | Picker uses one `.sheet(item:)`; a sheet asked for while another closes is queued and shown on dismiss. | `PeerPickerView.swift` |
| VQ-021 | Fixed | Crash-report checkbox tinted cobalt; a focus sink takes the panel's first focus, so Pair a device has no ring. | `MacMenuBarView.swift` |
| VQ-022 | Fixed | "Scan with your iPhone or iPad" on one line (scales down before wrapping); "Works once, for 4:31". | `PairDeviceWindow.swift` |
| VQ-023 | Fixed | Header never says "Ready" right after a refusal ("iPhone 17 Pro couldn't connect"); an amber note says why (another network / nobody answered / not verified) with Pair a device and Dismiss; clears after a minute or on pairing. | `MacPanelCopy.swift`, `MacMenuBarView.swift`, `DeviceAuthorizationManager.swift` |
| VQ-027 | Fixed | While the switcher reconnects, no card: controls dim, toast only. The card appears when retries stop (`ConnectionLossPresentation`). | `ApprovalStatusCopy.swift`, `ContentRootView.swift` |
| VQ-028 | Fixed | Reconnect/connect toast uses an unlit pixel and sits below the header (44 + 24 pt). | `ContentRootView.swift`, `DesignSystem/Feedback.swift` (`PHToast.pixel`) |
| VQ-029 | Fixed | Entry grouped 4+4 as typed, drawn in dot-matrix with unlit cells for missing digits; title "Type the code showing on <Mac>". | `PairingCodeEntryView.swift` |
| VQ-030 | Fixed | Sends itself once the 8th digit passes the check; Pair/Connect button right under the field; a "Pair" key in the keyboard toolbar. | `PairingCodeEntryView.swift` |
| VQ-031 | Fixed | `defaultFocus` plus a focus request 350 ms after the sheet opens. | `PairingCodeEntryView.swift` |
| VQ-036 | Fixed | Keyboard bar shows "Typing into <app>"; Return (key row, hardware, or a newline) into an app the person hasn't typed into since the front app changed asks "Send Return to <app>?". | `TypingTargetGuard.swift` (Core), `Keyboard/TypingTarget.swift`, `RemoteKeyboardPanel.swift`, `ControlSessionModel.swift` (one line) |
| VQ-037 | Fixed | Mac keeps a pending request alive while a pairing code shows, up to the code's 5 min (hard cap 45 s + 5 min), re-deciding when a code appears or ends. Remote: "Connect and pair" when the session is gone (holds the code, reconnects, sends it); Pair is never enabled without a way to send. | `PendingRequestExpiry.swift` (Core), `DeviceAuthorizationManager.swift`, `PairingCodeEntryView.swift`, `PairedMacsStore.swift`, `MacSwitcher.swift` |
| VQ-040 | Fixed | "Updates" hidden when the build has no update feed. | `MacMenuBarView.swift` |
| VQ-041 | Fixed | Last seen and the device's own name refresh on every grant and every disconnect of a paired device. Devices that never reconnect keep their old name until they do. | `DeviceAuthorizationManager.swift` |
| VQ-042 | Fixed | The focus sink means no button, Forget included, has initial focus. | `MacMenuBarView.swift` |
| VQ-043 | Fixed | One request: "iPad Pro is asking to connect"; "ready" dropped beside requests; device glyph falls back to the class in the name (iPad, iPhone, Mac). | `MacPanelCopy.swift`, `MacMenuBarView.swift` |
| VQ-044 | Fixed | Searching pixel unlit; footer is "Can't find your Mac?" (opens the checks) instead of repeating the body. | `PeerPickerView.swift` |
| VQ-052 | Fixed | Touch and hold the capture button: "Tap takes full screen" section with the default first, then the other modes and Read text; VoiceOver value and hint name the default. | `Shell/ShellHeader.swift` (capture menu only) |
| VQ-054 | Partly | `SettingsDiagnosticsSection` (Mac, link, round trip, mirror quality, protocol, last 8 problems, Export logs via `OSLogStore` + ShareLink). **Not yet in Settings: lane C adds one line** (below). | `Settings/SettingsDiagnosticsSection.swift`, `Settings/ConnectionDiagnostics.swift`, hooks in `ControlSessionModel+Network/+Pairing`, `MacSwitcher`, `ContentRootView` |
| VQ-055 | Fixed | The paywall sheet sat on the Settings `Section` (which hands modifiers to every row) and closed Settings; it is on the button now. Paywall shows "Getting prices…" or "Couldn't reach the App Store" + Try again; purchase waits for a product. Manage sheet moved to its row too. | `SettingsSubscriptionSection.swift`, `PaywallView.swift`, `SubscriptionStore.swift` |
| VQ-058 | Fixed | Launch reconnect: with no Mac used last, the single paired (or own iCloud) Mac in reach is dialled; never when there are several. "Connecting to <Mac>…" has Cancel (`MacSwitchMachine.cancelDial`). | `MacSwitchMachine.swift` (Core), `MacSwitcher.swift`, `ContentRootView.swift` |
| VQ-060 | Fixed | PiP button enabled whenever the mirror runs; first tap explains PiP and offers Turn on / Just this once / Not now. Hidden only where the device can't do PiP. | `Mirror/MirrorPiPViews.swift` |
| VQ-069 | Partly | After 10 s with no Mac: the three checks (same Wi-Fi or cable, Mac app open, Local Network) with Try again and Open Settings. Not done: dialling the paired Mac's last LAN address while Bonjour is quiet (needs a saved LAN endpoint and a Loom direct dial; worth its own task). | `PeerPickerView.swift` |

Also done on the way: buttons I touched lost their "…" (Forget, Pair, Pair a
device, Turn on, Updates), per the owner's rule.

## Re-check steps

Build 19 for the Mac and the iPad, then:

1. **Simulator on the same Mac (VQ-001).** Quit any old Pixel Hand. Run the
   new Mac app. Boot the iPad Pro 11" simulator, launch Pixel Hand. The Mac
   appears in the picker; tap it. The Mac shows the Allow request (not a
   refusal). Console (`subsystem:com.widgetsflow.pixelhand category:trust`)
   shows "is on this Mac (loopback, e.g. a simulator): local rules apply".
2. **Pair by typing (VQ-003, 005, 029–031, 037).** While the request waits,
   click **Pair** on the Mac's request row. On the simulator tap **Enter
   pairing code**: field is focused, digits appear in dot-matrix as
   "4821 0", the code sends itself at the 8th digit. Repeat with a 60 s wait
   before typing: the request is still pending (it used to drop at 45 s).
   Close the Mac's Pair window after 45 s: the request ends within a second
   with "Request timed out" on the iPad, and the card offers Enter pairing
   code, which reconnects and pairs.
3. **Picker pairing.** Disconnect, open the picker, tap **Pair** (top right):
   code entry with the Mac chosen (a menu when several are nearby). Type the
   Mac's code: it connects and pairs. "Scan the QR code instead" still works.
4. **Refusal reasons (VQ-002).** Click **Deny** on the Mac: iPad says
   "Declined on <Mac>" and offers Enter pairing code. Over Tailscale with an
   unpaired device: "Pair <Mac> first", and the Mac panel shows the amber
   "tried to connect from another network" note with Pair a device.
5. **Mac panel (VQ-021–023, 040–043).** Open the panel with Full Keyboard
   Access on: no focus ring anywhere; Space does nothing. One pending iPad:
   header "iPad Pro 11-inch (M5) is asking to connect", iPad glyph. Updates
   is absent in a build without a feed. Disconnect a paired device: its
   Last seen reads "now".
6. **Mac quits mid-session (VQ-027/028).** Quit the Mac app while
   connected: only the toast "Reconnecting to <Mac>…" below the header,
   grey pixel, Cancel; no modal. After the retries (~15 s) the Disconnected
   card appears. Reopen the Mac app within 10 s: it reconnects with no card.
7. **Launch reconnect (VQ-058).** Fresh install, pair during onboarding,
   finish onboarding: "Connecting to <Mac>…" with Cancel, then the shell.
8. **Paywall (VQ-055).** Free plan (`TEST_RUNNER_PH_QA_FREE=1`), Settings ›
   Subscription › Try Pixel Hand Pro: the paywall opens over Settings. With
   no StoreKit config: "Couldn't reach the App Store" + Try again.
9. **Capture, PiP, typing, picker (VQ-052, 060, 036, 044, 069, 020).**
   Touch and hold capture: "Tap takes full screen" first. Mirror on, tap the
   PiP button: the explanation, then PiP. Keyboard bar shows "Typing into
   TextEdit"; switch the Mac's front app, press Return: the confirm. Picker
   with the Mac app quit: unlit SEARCHING, then the three checks at 10 s.
   Close a sheet and tap Settings at once: Settings opens.
10. **Diagnostics (VQ-054)** after lane C's one line: Settings › Diagnostics
    shows the Mac, link, round trip; Export logs → Share log file.
11. Run `PixelHandUITests` (the picker walk now taps `ph.connect.pair`).

## Compile risks (most likely first)

1. `PairingCodeEntryView`: invisible `TextField` (`.foregroundStyle(.clear)`,
   `.tint(.clear)`) under the dot-matrix layer; `Picker` bound to a
   `Target`; `ToolbarItemGroup(placement: .keyboard)`; `.defaultFocus`.
2. `PeerPickerView`: private `PickerSheet` enum in `.sheet(item:onDismiss:)`
   and `.onChange(of: sheet)`; `.task(id: peers.isEmpty)`.
3. `MacMenuBarView`: focus sink (`.focusable()`, `.focused`,
   `.focusEffectDisabled()`, macOS 14); `turnedAwayNote` takes a labelled
   tuple; `DeviceType.mac.systemImage`.
4. `RemoteKeyboardPanel`: `guardReturn(if:send:)` (keyword as an argument
   label), `.alert` with a computed `Binding`.
5. `ShellHeader`: new `@EnvironmentObject DeckHandSettings` (present in the
   shell's tree; a preview without it would crash, not fail to build).
6. `SettingsDiagnosticsSection`: `OSLogStore(scope: .currentProcessIdentifier)`,
   `OSLogEntryLog.composedMessage`, `ShareLink(item: URL)`.
7. `PairDeviceWindow.title(_:singleLine:)` is a `@ViewBuilder` func with a
   `let` inside.
8. Every `switch` over `PairingMessage` outside the type-checked files needs
   `.refused` (only `PairingHandler` had one; `ControlSessionModel` uses
   `default`).

## Out-of-lane edits (announced)

- **Lane C (Settings): please add one line** to `SettingsView.swift`, after
  `SettingsPrivacySection()`: `SettingsDiagnosticsSection()`. The section is
  self-contained and reads `ConnectionDiagnostics.shared` and
  `RemoteLinkStatus.shared`.
- **Lane C:** `SettingsSubscriptionSection.swift` moved its paywall and
  Manage sheets from the `Section` onto their buttons (VQ-055). If you
  restyle that section, keep sheets off the `Section`.
- **Lane A (onboarding):** `OnboardingScene.swift` example code
  "4821 0937" → "4821 0934" (one string; the old one fails the check digit).
- **Lane A (shell):** `ShellHeader.swift` capture menu only (VQ-052) and a
  new `@EnvironmentObject settings`. `DesignSystem/Feedback.swift`:
  `PHToast` gained an optional `pixel` (default unchanged).
- **Lane A (keyboard bar):** `RemoteKeyboardPanel.swift` gained the
  "Typing into" line above the field and the Return check (VQ-036). The bar
  is ~20 pt taller; if lane A rebalances the pad height with the keyboard
  up (VQ-033), count it.
- **Owner's lane 3 (Mac panel, OR-08 to OR-13):** I touched
  `MacMenuBarView.swift`, `PairingMenuSection.swift` and
  `PairDeviceWindow.swift` for my findings, including OR-11 (full-brightness
  digits) and some OR-12 ellipses. OR-08's single Devices list should keep
  the focus sink and the turned-away note.
- **Scripts:** `linux-typecheck/run.sh` checks
  `DeckHandiOS/Settings/ConnectionDiagnostics.swift`.

Lane: READY TO MERGE
