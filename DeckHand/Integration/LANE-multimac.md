# Lane: Multi-Mac (1.3 · backlog M1/M2 · UX-030)

Branch `claude/pixelhand-lane-multimac`, merged with
`origin/claude/pixelhand-integration` at `0114c91`. No protocol change: this
lane stays on protocol 12. No `project.yml`, Info.plist or entitlement change.

## What changed

### Core (`Core/Sources/PixelHandCore/Macs/`, tests in `MultiMacTests.swift`, 28 tests)

| File | What |
| --- | --- |
| `MacRoster.swift` | The one Mac list everything shares. Order: Macs this device has used (by **first** use, so switching never reorders and ⌘2 keeps meaning the same Mac), then paired Macs not used yet (oldest pairing first), then other Macs in reach (own iCloud first, then name). First four get ⌘1–⌘4. `neighbor` (pill swipe, ⌘\`, three fingers) steps through reachable Macs and wraps. `direction` picks the slide edge. `swipeSwitchesMacs`: setting on **and** 2+ Macs in reach, otherwise three fingers stay the Spaces swipe. |
| `MacMemory.swift` | `MacMemoryBook`: per-Mac first/last use, surface, deck page, mirror (sharpness, frame rate, classic floating layout), last glance; the Mac used last (launch reconnect). Capped at 16 (LRU, never the last one); names trimmed and capped; unreadable storage starts empty. |
| `MacGlance.swift` | The card's glance tier (front app, lock state, link, time) and its copy: "Xcode", "Locked", "Nearby · last in Safari", "Not found · seen 3 h ago", "Connecting…". |
| `MacSwitchMachine.swift` | The switch: `idle → dialing(target, from) → active`. The new Mac is dialled **while the old session keeps running**; success adopts it and releases the old one, failure leaves the old one in use, a newer request supersedes (late connection discarded), going back to the Mac on screen cancels a dial. The free plan's answer (`FreeMacPolicy`, unchanged) is an input: `needsPro` → `.paywall`, nothing dialled. `MacReconnectPolicy`: launch target (last Mac, paired or own iCloud, in reach, not locked by the free plan, once per launch, after onboarding) and redial delays after a drop (1, 2, 4, 8 s; never after a verdict or Disconnect). |

### iOS

| File | What |
| --- | --- |
| `Macs/MacSwitcher.swift` (new, `.shared`) | Glue: discovery (`@LoomQuery` peers from the root) + `PairedMacsStore` + `MacMemoryBook` → `listings`. `request(_:)` checks reach and protocol compatibility, then **`SubscriptionStore.shared.admitMac`** exactly as the picker does (paywall with retry), then dials through **`RemoteConnect.connect`** (so VPN hosts stay paired-only and key-pinned, `LANE-network-vpn.md`). `switchToSlot`, `step(by:)`, `handleTrackpadGesture`. Saves/restores the deck page (`DeckSurfaceModel.select`). Quick reconnect at launch and after drops. Type-checked on Linux. |
| `ContentRootView.swift` (lane-owned) | Connection lifecycle for several Macs. The connected view is keyed by the connection ID, so every Mac gets a fresh `ControlView` → one `ControlSessionModel` and one message loop per connection. A switch slides the canvas 240 ms (forward = from trailing; Reduce Motion fades), the old connection closes 600 ms later. Approval card held back ~1 s after a switch so a paired Mac's instant grant doesn't flash it. A drop (connection event **or** heartbeat `host_disconnected`) starts the redial; Disconnect cancels it. Top toast: "Connecting to Laptop…", "Reconnecting to Studio…", or why a switch couldn't start. Hosts the ⌘ commands and the per-Mac mirror modifier. |
| `Macs/MacCard.swift` | Card with the glance tier: navy 16:10 tile, Mac glyph (lock glyph when locked), live pixel (mint = focused, dim = in reach, off = away), link badge (Wired/VPN; Wi-Fi/Direct on the focused Mac), ⌘ slot, dotted phosphor ring while connecting, cobalt ring on the focused Mac, Store's PRO badge via `.freeMacBadge`. |
| `Macs/MyMacsSheet.swift` | My Macs: cards in list order; tap switches (sheet closes once dialling starts, stays open to show why it couldn't); context menu Switch / Remove from My Macs (unpaired remembered Macs only); help line; Disconnect. Replaces `Shell/MyMacsPlaceholderSheet.swift` (deleted; `MacCardPlaceholder` went with it, its only users were the sheet and the sidebar). |
| `Shell/MacsSidebar.swift` | Same signature, now `MacCard`s with live state; tap another Mac switches, tap the focused one opens My Macs. Inline notice. `AskField` / `AskCircleButton` untouched. |
| `Macs/MacSwitchCommands.swift` | Zero-size buttons: ⌘1–⌘4 (titled with the Macs' names in the ⌘ overlay) and ⌘\` (next Mac). |
| `Macs/PerMacState.swift` | `.perMacSurface($surface)` (shell), `.perMacMirrorSettings()` (root: applies the entered Mac's sharpness / frame rate / floating layout, records changes), `.macSessionGlance(session)` (feeds front app, lock, link). |
| `Control/ControlSessionModel+MultiMac.swift` | `macDeviceID` (`connection.peer.deviceID`) and `macGlance`. No stored properties, no message cases. |
| `Macs/SettingsMultiMacSection.swift` | Settings › Several Macs: **Swipe between Macs** (default on), **Reconnect automatically** (default on). |
| `DeckHandSettings.swift` | `// MARK: Multi-Mac (lane)`: the two toggles' keys and `@Published` properties. Per-Mac state is `MultiMacSettingsKey.macMemory` (JSON, `UserDefaults`). |

Per-Mac state summary: **surface** (Pointer/Screen/Deck), **deck page**,
**mirror** sharpness + frame rate + floating layout, **layout preset** (already
per Mac name via `LayoutPresetMemory`), last **glance**.

**No warm second connection.** Only the focused Mac holds a Loom session
(plus, for ≤ 0.6 s, the Mac being left). Keeping another session up costs
radio wake-ups and heartbeats for no visible gain: a switch to a paired Mac
on the LAN takes about a second, and the old session stays usable until the
new one is up. Glances for other Macs are the last ones seen, with their age.

## Checks on the Mac build

Setup: two Macs (A "Studio", B "Laptop") running the integration Mac app, both
paired with the iPhone/iPad (Settings › Paired Macs), same Wi-Fi.

1. **Two Macs, first connect.** Picker → A. My Macs (tap pill) shows A first
   with the cobalt ring, live pixel, front app and "⌘1"; B second, dimmer
   live pixel, "Nearby · paired", "⌘2".
2. **Switch A → B from My Macs.** Tap B: sheet closes, toast "Connecting to
   Laptop…", the canvas slides in from the right, no approval card flash.
   A's Mac menu bar shows the iPhone disconnecting ~½ s later. Header pill
   says Laptop with B's front app.
3. **Switch back B → A** by swiping the pill **right** (slides in from the
   left), then A → B by swiping **left**. With only one Mac in reach the
   swipe opens My Macs as before.
4. **Three fingers.** On Pointer, three fingers left/right switch Macs (2+
   in reach). Settings › Several Macs › Swipe between Macs off → three
   fingers switch Spaces on the Mac again. With B quit, three fingers are
   Spaces even with the toggle on.
5. **⌘1–4 / ⌘\`** with a hardware keyboard: ⌘2 → B, ⌘1 → A, ⌘\` cycles.
   Hold ⌘: the overlay lists "Switch to Laptop". ⌘ on the focused Mac does
   nothing.
6. **Per-Mac deck and mirror.** On A: Deck surface, page 2, mirror Sharp at
   30 fps. Switch to B: B opens on its own last surface (first time:
   unchanged), set Screen + Battery saver 15 fps. Back to A: Deck, page 2
   (unless the follower moves to the front app's page), Settings › Mirror
   shows Sharp / 30. Back to B: Screen, Battery saver / 15. Kill and relaunch:
   still per Mac.
7. **Glance tier.** Lock B (⌃⌘Q) while on A: My Macs' B card still shows
   the last glance (it's not live); switch to B → its card and pill show the
   lock glyph / "Locked". Unlock, switch to A: B's card reads "Nearby · last
   in <app>". Quit B's app: B's card goes "Not found · seen just now",
   dimmed; tapping it says "Laptop isn't in reach…".
8. **iPad sidebar.** iPad landscape (columns): the sidebar shows both cards
   live; tap B → slide; tap the focused card → My Macs. Collapse/expand still
   work. Lock state and front app on the focused card update live.
9. **Free-tier paywall on a second Mac.** Sandbox account with no Pro (or
   expire the StoreKit test subscription), free Mac = A. In My Macs B shows
   PRO; tap B → the Store paywall "The free plan works with one Mac,
   Studio", nothing dials, still on A. Same for pill swipe, ⌘2 and three
   fingers. "Use Laptop as my free Mac" or buying Pro → B is dialled
   automatically (the paywall's retry).
10. **Quick reconnect.** Connected to A, force-quit the app, relaunch: it
    connects to A by itself (paired). Turn Reconnect automatically off →
    relaunch shows the picker. Disconnect from the pill menu, relaunch → the
    picker (Disconnect clears the reconnect target). Quit A's Mac app while
    connected: "not answering" card + toast "Reconnecting to Studio…";
    reopen A within ~15 s → it comes back by itself. Denied/forgotten
    never redials.
11. **Picker still works**: tap / QR code connect, approval card for an
    unpaired Mac, Disconnect.

## Compile risks (most likely first)

1. `ContentRootView.adopt` — the `stale` handle expression
   (`activeConnection.map { $0.handle }.flatMap { … }`) and the
   `@MainActor` closure assigned to `MacSwitcher.onAdopt` in `.onAppear`
   under Swift 6 isolation checking.
2. `MacSwitchCommands`: `KeyEquivalent(Character(String(slot)))` and
   `Button(String)` title overloads inside `ForEach`.
3. `ContentRootView.switchToast` is a `@ViewBuilder` property with `let`
   statements and three `.animation(_:value:)` on optionals.
4. `PerMacState.swift`: `MirrorLayout` encode/decode (it is `Codable,
   Equatable`), zero-argument `onChange` closures (iOS 17 API).
5. `MacCard`: `.freeMacBadge` on the tile, `LinkBadge.Kind.spoken`,
   `PixelHandTheme.Stroke.selection` / `Radius.chip` (same as the deleted
   placeholder).
6. `ShellHeader.pillSwipe`: the switch call reads `value.translation` in
   `onEnded`. Behaviour risk rather than compile: the pill is a `Button`
   with a simultaneous drag; if a long swipe also fires the tap, My Macs
   opens on top of the switch — make the drag `highPriorityGesture` if so.
7. `MacSwitcher.swift` itself type-checks on Linux (`run.sh` now includes
   it); `LoomConnectionHandle.peer`, `LoomPeerSnapshot.isSameICloudDevice`
   and `PeerCompatibility(advertisement:)` are stubbed there.

## Out-of-lane edits

| File | Owner | Edit |
| --- | --- | --- |
| `DeckHandiOS/Shell/PixelHandShell.swift` | UX shell / Integration | `MyMacsPlaceholderSheet(` → `MyMacsSheet(` (same arguments); `.perMacSurface($surfaceRawValue)` before `.onChange(of: session.runningBundleIDs…)`. Both marked `// Multi-Mac lane`. |
| `DeckHandiOS/Shell/ShellHeader.swift` | UX shell / Integration | Pill swipe end: `if !MacSwitcher.shared.step(by: …) { onMacs() }` instead of `onMacs()`; the `onMacs` doc comment. |
| `DeckHandiOS/TrackpadView.swift` | iOS interaction | First line of `onSystemGesture`: `if MacSwitcher.shared.handleTrackpadGesture(gesture) { return }`. |
| `DeckHandiOS/ControlView.swift` | Integration | `.macSessionGlance(session)` after `ControlCaptureSheets`. |
| `DeckHandiOS/SettingsView.swift` | Integration | `SettingsMultiMacSection()` after `SettingsPairingSection()`. |
| `DeckHandiOS/DeckHandSettings.swift` | shared hot spot | `// MARK: Multi-Mac (lane)` keys, two `@Published`, two init lines. |
| `DeckHandiOS/Shell/MyMacsPlaceholderSheet.swift` | (lane: My Macs sheet) | Deleted, replaced by `Macs/MyMacsSheet.swift` + `Macs/MacCard.swift`. |
| `Scripts/linux-typecheck/Stubs.swift`, `run.sh` | shared tooling | Three stub members under `// MARK: Multi-Mac`; `MacSwitcher.swift` added to the default file list. |

Nothing in `DeckHandiOS/Intents/**` or `DeckHandiOS/Assist/**`. No Store,
Pairing or Network file changed: `FreeMacPolicy`, `admitMac`,
`PairedMacsStore` and `RemoteConnect` are used as they are.

## Follow-ups

- Mac pill tap on wide windows could focus the sidebar instead of opening
  My Macs (`03-Layout-Strategy.md`); kept the sheet for now.
- Glance for non-focused Macs is last-seen only; live alerts on other Macs
  ("MacBook Air has a dialog waiting") need a glance connection or a Mac-side
  push (M1 "glancing" tier) and a battery budget.
- My Macs actions "Lock all", "Pause media on all", "Run on…" are M3.

Lane: READY TO MERGE
