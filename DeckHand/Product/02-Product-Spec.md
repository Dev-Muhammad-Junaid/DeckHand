# Pixel Hand product spec: 1.0 and beyond

Owner: product/UX lead. Status: draft for the owner, 16 Nov 2026.
Paths are given with today's names (`DeckHand/…`, `DeckHand*`). The rename
session maps them to `PixelHand/…`; read every path through that mapping.

## 0. The product in one paragraph

Pixel Hand turns an iPhone or iPad into the place you run your Macs from. It
started as a Stream Deck-style surface, and it stays one: one tap does the thing
you would otherwise walk to the Mac for. What makes it more than a button box is
that it **knows what is on the Mac**. It reads the real menus and dialogs of the
front app, sees the screen, and (from 1.3) can build and run actions from plain
language with an on-device model. It works with **any Mac you pair**, can show
and drive several of them, and moves clipboard, files, photos and links between
**every device paired through Pixel Hand**, iCloud or not.

### Product principles

1. **One tap beats a trip.** Every screen is judged by how many things a user
   no longer needs the Mac for.
2. **Real, not guessed.** Actions come from what the Mac actually exposes
   (menus, dialogs, Shortcuts, displays). Guesses (AI, heuristics) are always
   shown as proposals with a preview, never fired blind.
3. **Lit dots mean live.** The dot-matrix identity is a status language, not
   decoration. If dots are lit, the device is talking to a Mac.
4. **Confirmed, not hoped.** Every command that changes something gets a
   delivery receipt (mint) or a refusal (red). No silent failure.
5. **Private by construction.** Screen, input, clipboard, files and AI
   prompts travel only between the user's own devices. No account, no relay,
   no third-party AI.
6. **Each new feature must compose with the old ones.** A deck key, a Siri
   phrase, a widget and a natural-language command all resolve to the same
   typed `Action`, run through the same receipt path, and respect the same
   per-Mac trust.

## 1. Release map

| Release | Theme | Scope (detail in `05-Backlog.md`) |
| --- | --- | --- |
| **1.0** (≈3 weeks, Option C) | Solid core | Loom 2.2.16 merge (protocol v3), app-protocol reset and version handshake with "Please update", Sparkle + notarized DMG, AWDL off + keep-alive, cursor drawn on device, mirror on its own binary stream, Mission Control shortcuts read directly, hardened AX menu reading, display wake, locked-Mac check, layout and accessibility pass, bug fixes from the inventory. **Proposed additions** (owner decision §12.8): text typing + hardware-keyboard basics, and tap-hold-drag, about 3 days together. |
| **1.1** (weeks 4–6) | Fast and familiar | HEVC mirror with quality tiers and stats HUD; persistent pairing (code/QR, "Forget device"); saved Macs list; clipboard text sync. |
| **1.2** | Deck 2 | Pages, per-app context decks, editor, menu-command and Mac-Shortcuts actions, macros, App Intents/Shortcuts/widgets/Control Center. AI-lite: "Suggest a deck for this app" (on-device). |
| **1.3** | Many Macs, every device | Multiple live sessions, Mac switcher + overview, per-Mac decks, run on several Macs, sharing files/photos/links, Share extension, Mac drop target. |
| **1.4** | Assist | Natural-language command bar, "ask about this screen", AX-fallback screen reading. |

The order of 1.2/1.3/1.4 is an owner decision (§12). The recommendation puts
Deck 2 first because every later feature (Siri, widgets, AI, multi-Mac
broadcast) is "an action from the deck, run somewhere", so the action model
must exist first.

## 2. Core model every feature shares

Three types carry the whole product. Defining them early (ticket PH-003/PH-004)
is what makes later features combine safely.

- **`Mac`** (host record): stable ID = the Loom identity key ID; user-editable
  name; model/icon; last-seen; trust grant (§6.3); per-Mac settings (mirror
  tier, deck set). Persisted on the remote once persistent pairing lands (1.1);
  before that it lives for the session only.
- **`Action`** (what a key, chip, intent, widget or AI proposal does): a
  `Codable` enum in `PixelHandCore`, independent of transport:
  - `keyChord(KeyChord)`, `appKeyChord(bundleID, KeyChord)`
  - `menuCommand(bundleID, path: [String])` (press a real menu item via AX,
    robust when the user rebinds the shortcut; 1.2)
  - `launchApp(bundleID)`, `quitApp`, `hideApp`
  - `macShortcut(name)` (run a Shortcuts.app shortcut on the Mac, with a
    timeout; 1.2)
  - `media(MediaKey)`, `system(SystemAction)` (Mission Control, App Exposé,
    Show Desktop, Space left/right, lock screen, sleep display, volume)
  - `typeText(String)` (snippets)
  - `openURL(URL)` on the Mac
  - `capture(CaptureMode)`
  - `sequence([Step])` where `Step = action | delay(ms)` (macros; max 20 steps)
  - `contextButton(id)` (ephemeral, from a dialog snapshot; never stored)
- **`ActionRun`**: `{ action, targetMacs: [Mac.ID], requestID, confirm: Bool }`.
  The single path every surface uses. It produces one receipt per Mac.

The wire protocol carries `run(requestID, action)` → `receipt(requestID,
outcome)`. `outcome` is `delivered | refused(reason) | failed(reason) |
completed`. `completed` is used where the Mac can observe the result
(menu press, launch, Shortcut exit code).

## 3. Deck

### 3.1 What exists today

`StreamDeckGridView.swift`, `QuickActionsBar.swift`, `AppShortcutsSheet.swift`
and `ShortcutStore.swift` already give: per-app shortcut chips from the real
menus (`MenuShortcutDiscovery.swift`), curated defaults (`CuratedShortcuts.swift`),
dialog-button chips (`ContextObserver.swift`), running apps in Cmd-Tab order,
media keys, per-shortcut confirmation, and delivery dots. See
`01-Feature-Inventory.md` for the assessment.

### 3.2 1.0 deck (keep, polish)

- Keep the chip bar and grid as they are; fix the rough edges in the inventory.
- The chip strip is the **Context bar**: dialog buttons first (they are the
  most urgent), then the front app's pinned shortcuts, then suggestions.
- Every chip and key shows delivery dots; VoiceOver announces the outcome.

### 3.3 Deck 2 (1.2)

**Structure.** A *deck* is an ordered list of *pages*; a page is a grid of
*keys*. Grid sizes adapt to the space (§ layout rules in `03-UX-Guidelines.md`),
so a page stores *order*, not coordinates: 3×4 on iPhone portrait reflows to
5×3 in landscape and 6×4 on iPad without the user re-arranging anything. Users
can pin a key to "first row" to keep it in reach.

**Kinds of page.**

| Page | Content | Who maintains it |
| --- | --- | --- |
| **Home** | User's global keys (launchers, media, system) | User |
| **App page** (per bundle ID) | Keys for one app | User, seeded from menus + curated list or AI |
| **Context page** (automatic) | Dialog buttons + the app page of the front app | Pixel Hand, live |
| **Shortcuts page** | The Mac's Shortcuts.app shortcuts, by folder | Pixel Hand, from the Mac |

**Context-aware switching.** With "Follow front app" on (default), the deck
opens the front app's page when the Mac's frontmost app changes, and returns
to the previous page when it goes away. A small app badge on the page title
shows why it switched. A pin icon locks the current page (no auto-switching)
for the session. Switching is debounced (400 ms) so Cmd-Tab cycling does not
make the deck flicker.

**Editing.** Long-press a key or tap **Edit** in the page header:
- keys show a dot-matrix outline and can be dragged; a trash target appears;
- **+** opens the *Action library*: Menu commands of this app (searchable,
  grouped by menu), Curated, Apps, Shortcuts (Mac), Media & System, Text
  snippet, URL, Macro builder;
- the key inspector edits label, glyph (SF Symbol, app icon, or a 8×8 pixel
  glyph drawn on a dot grid — Pixel Hand's signature), colour from the brand
  palette, and "Ask before running";
- undo is one tap (shake-to-undo and a toolbar Undo while editing).

**Storage and sync.** Decks are JSON documents (`DeckDocument`, versioned,
validated) stored on the remote. Global pages are shared by every Mac; app
pages are global by default, with "Only on this Mac" as an option (1.3). Decks
sync between the user's remotes via Pixel Hand sharing (§5), not only iCloud:
any paired device can push "deck updated" to the others; last-writer-wins per
page with a 30-day page history for undo.

### 3.4 AI-assisted decks and commands

**Where AI runs.**

1. **On the remote**, with Apple Foundation Models (`SystemLanguageModel`),
   when `availability == .available` (Apple Intelligence devices, iOS/iPadOS
   26+; image input needs 27).
2. **Else on the paired Mac**, with the Mac's Foundation Models (macOS 26+,
   Apple silicon, Apple Intelligence on). The remote sends the request over the
   authenticated Loom session; the Mac runs the model and returns typed output.
   This makes AI work from an older iPhone if the Mac is capable.
3. **Else** AI features are hidden and the deterministic fallback (ranked
   by curated priority and local usage counts) is used. No third-party cloud.
   Private Cloud Compute (27) is an opt-in toggle, off by default (owner
   decision §12).

**Privacy.** Inputs are app names, menu titles, Shortcut names, the user's typed
command and, for screen questions, a capture the user explicitly took. They
are processed on the user's own devices only and never logged to Sentry
(breadcrumbs strip prompt text). The privacy policy and App Privacy answers do
not change while PCC stays off; turning PCC on is covered by Apple's own PCC
terms, and the toggle explains this in one sentence.

**Feature A, "Suggest a deck" (1.2).** On an app page, **Suggest** sends the
app's discovered menu commands (title, path, chord, menu name) to the model
with a `@Generable` schema `DeckProposal { pages: [PageProposal { title,
keys: [commandID] }] }`. The model can only pick from IDs it was given, so it
cannot invent shortcuts; output is validated (unknown IDs dropped, max 24 keys).
The user sees the proposal as a ghosted page and taps **Keep**, edits, or
discards. Fallback without a model: top commands by curated rank and menu
(File/Edit/View first), so the button never disappears for an app with menus.

**Feature B, natural-language command bar (1.4).** A field at the top of the
deck ("Tell your Mac…", also reachable by ⌘K on a hardware keyboard and by
Siri). Tool-calling session with tools `listApps`, `frontAppCommands`,
`listShortcuts`, `listMacs`, `listDisplays`, returning a typed
`[ActionRun]`. The plan is always shown as chips ("Open Safari → ⌃⌘F
Full screen") with **Run**. Safe, single-step actions on the current Mac may
run immediately if "Run simple commands without asking" is on; anything
destructive (quit, close, delete, empty, log out, shutdown, typing into a
password field) or multi-Mac always asks. A run can be saved as a key with one
tap, which is how the deck learns.

**Feature C, ask about the screen (1.4).** In the capture preview, "Ask"
attaches the capture to an on-device multimodal prompt with `OCRTool`. When
AX finds no dialog buttons for the front app (Electron, games), the context bar
offers "Read this screen", which proposes clickable targets as coordinates on
the mirror; the user taps to confirm. It never clicks on its own.

## 4. Multi-Mac (1.1 foundations, 1.3 full)

**1.1: saved Macs.** With persistent pairing, the picker becomes **My Macs**:
paired Macs first (name, model glyph, online dot, last thumbnail), then
"Nearby" unpaired Macs, then "Add a Mac" (download link/QR). Tap to connect.

**1.3: several at once.**

- **Session manager.** The remote holds up to 4 live sessions. One is
  *focused* (full input, mirror at the chosen tier); others are *glancing*:
  liveness, front app, context-dialog alerts and a thumbnail at ~1 fps,
  480 px. Each extra session costs one Loom connection and a trickle of
  frames; the Mac host already accepts several remotes, but must key state per
  remote (see inventory).
- **Mac switcher.** The title of the control screen is the focused Mac's name
  with a chevron. Tap: a menu of Macs with online dots and front app. Swipe
  with three fingers left/right on the trackpad area, or ⌘1…⌘4 on a hardware
  keyboard, to switch. Switching keeps each Mac's deck page and mirror state.
- **Overview.** A grid of Mac cards (live glance thumbnail, name, front app,
  alert badge when a dialog is waiting or the Mac is locked). Tap focuses;
  long-press offers Lock, Sleep display, Capture, Run…, Disconnect. On iPad
  the overview can sit in a sidebar (regular width ≥ 900 pt).
- **Run on several Macs.** In the command bar or a key's menu: "Run on…"
  with Mac checkboxes. Results show a per-Mac receipt row. Allowed actions:
  everything except `contextButton` and pointer input. Destructive actions
  require confirmation listing the Macs by name.
- **Per-Mac decks.** App pages default to global; a page or key can be set to
  "Only on <Mac>". The Home page can have a per-Mac variant.

## 5. Sharing between paired devices (1.1 clipboard, 1.3 files)

**Who takes part.** Every device running Pixel Hand that is paired with this
device through Pixel Hand pairing: Mac↔iPhone/iPad from 1.1, Mac↔Mac (both
run the host) and iPhone↔iPad (the receiving iOS device advertises while
Pixel Hand is open) from 1.3. iCloud is not required. CloudKit "same account"
recognition, when enabled, only pre-fills trust prompts, it never grants trust.

**What moves.**

| Item | 1.1 | 1.3 |
| --- | --- | --- |
| Clipboard text (≤256 KB) | Mac→device push while focused; device→Mac via `UIPasteControl` (no paste prompt) | + images, rich text, "Universal-style" auto-sync toggle per device |
| Links | – | Open on target device (default browser) or save |
| Files | – | Any size, resumable (`LoomTransferEngine`), progress as a dot "beam" |
| Photos/video | – | From Photos picker or Share sheet; HEIC kept, optional convert to JPEG |

**Where it lands.** Mac: `~/Downloads/Pixel Hand/` and a notification with
Reveal/Open. iOS: an Inbox sheet in the app (Save to Files, Save to Photos,
Copy, Open in…); files are kept 7 days.

**Entry points.** iOS Share extension "Pixel Hand" (picks a device, hands the
item to the main app via an App Group outbox and opens it if the session is not
live); drag and drop onto a Mac card (iPad); Paste button in the context bar;
Mac: drop onto the menu-bar icon, Finder Share menu and Services "Send to
<device>".

**Trust and approval UX.** Each paired device has per-capability grants,
shown in the Mac panel's device list and the remote's My Macs:

| Capability | Default after pairing |
| --- | --- |
| Control this Mac (input, deck actions) | On |
| See the screen (mirror, capture) | On |
| Clipboard | Ask once |
| Send files to this device | Ask each time; "Always allow from <device>" after the first |
| Receive files from this device | On |

Incoming transfer prompt (Mac notification / iOS banner): device name and dot
glyph, item kind and size, **Accept** / **Decline**, with "Always from this
device". Transfers over 2 GB always ask. Received filenames are sanitized,
quarantine attribute set on the Mac, and nothing auto-opens.

## 6. Connection, pairing and trust

### 6.1 1.0 (per-launch approval, as today)

Keep the Allow/Deny on the Mac (`DeviceAuthorizationManager.swift`) with the
new `DeckHandHandshakeTrustProvider` from the trial merge, so Loom v3 does not
deny first-time devices. Add the version handshake: the Mac advertises
`ph-proto=<n>` in its Bonjour TXT record; the picker greys out an incompatible
Mac with "Update Pixel Hand on this Mac" (and shows the download URL as QR and
text). After connecting, both sides exchange `hello { appVersion, protocol,
features }`; a newer Mac that sees an older remote shows "Update Pixel Hand on
<device>" in its panel.

### 6.2 1.1 persistent pairing

- Mac panel: **Pair a device** shows a 12-digit code (with a Damm check digit,
  so typos are caught before a round trip) and a QR. The window is 5 minutes
  and single device.
- Remote: picking an unpaired Mac asks for the code, or scans the QR.
- Trust record keyed on the Loom identity key; stored in the Keychain on both
  sides. No per-launch prompt for paired devices.
- **Forget device** on both sides; forgetting on one side makes the other
  side's next connection fall back to the code flow.
- An unpaired device can still use the 1.0 Allow/Deny flow (useful for a
  quick guest session), labelled "Allow once".

### 6.3 Locked Mac

When the Mac is locked (approved private check), the host reports `locked`;
the remote dims the deck, shows a lock banner, withholds menus, dialogs,
clipboard and window lists, and only allows: mirror of the lock screen,
pointer and keyboard (to type the password), display wake.

## 7. Mirror and control

### 7.1 Mirror quality tiers

| Tier | Codec | Size | fps | Use |
| --- | --- | --- | --- | --- |
| Glance | JPEG | 480 px | 1 | Overview cards, background sessions |
| Thumbnail | JPEG (1.0) / HEVC (1.1) | 640–960 px | 15–30 | Floating tile |
| Standard | HEVC (1.1) | 1920 px | 60 | Expanded mirror |
| Native | HEVC (1.1) | Display native | 60 | iPad full screen, Wired/strong link |

"Auto" picks the tier from the tile size and link quality (S13 link judge,
later); users can pin a tier per Mac. 1.0 keeps today's JPEG tiers but moves
frames to a dedicated binary stream and draws the cursor on the device.

### 7.2 Pointer and touch

- **Trackpad mode** (default): today's multi-touch trackpad with phased
  scrolling. 1.0 adds **tap-then-hold to drag** (the Mac's own "drag lock"
  feel) and two-finger tap for right-click, keeping long-press right-click as
  an option; a single double-tap sends exactly one double-click. 1.1 adds 3/4-finger swipes mapped to the Mac's own Mission
  Control/Spaces shortcuts (read directly, S7/S11) and pinch.
- **Direct mode** on the expanded mirror: tap where you want to click
  (absolute pointing); two-finger drag scrolls. Toggle in the mirror toolbar.
- **Pencil** (iPad): absolute pointing on the mirror; hover moves the cursor
  without clicking (S12); squeeze/double-tap = secondary click (configurable).
- **Cursor** is drawn on the device from the Mac's real cursor shape (S3),
  which removes cursor lag from the video path.

### 7.3 Keyboard

- **Typing.** Today's build cannot type text at all (inventory §0 #2). 1.0
  adds a `typeText` action (Unicode, via `CGEventKeyboardSetUnicodeString`)
  and a "Type" field in the context bar that sends on Return; OCR results
  and snippets get "Type on Mac".
- **Hardware keyboard** on the iPad: when the mirror is expanded and "Send
  keyboard to Mac" is on, all key presses go to the Mac with key repeat; the
  Globe key and ⌘Tab stay on the iPad unless captured (system limits).
- **Modifier bar** for on-screen typing: ⌘ ⌥ ⌃ ⇧ latching keys, Esc, Tab,
  arrows.

### 7.4 Displays and Spaces

Display picker (exists); Space left/right via the user's real shortcuts (S7
replaces `osascript`); "Show Desktop" and Mission Control keys. The virtual
display is on hold.

## 8. System integration (1.2)

All built on App Intents over the shared `Action` model, so one integration
feeds Siri, Shortcuts, Spotlight, widgets and Control Center.

| Surface | Items |
| --- | --- |
| **App Intents** | `RunDeckKeyIntent(key)`, `RunActionIntent` (parameterised: launch app, media, lock, sleep display, capture), `ConnectToMacIntent(mac)`, `SendClipboardIntent(mac)`, `SendFileIntent(file, device)`, `AskMacIntent(text)` (1.4). `AppEntity`s: `MacEntity`, `DeckKeyEntity`, `MacAppEntity`. |
| **App Shortcuts** | "Capture my Mac with Pixel Hand", "Lock my Mac", "Play/pause on my Mac", "Send clipboard to my Mac". |
| **Widgets** | Small: one key. Medium: 4 keys of a page. Large: Mac status (online, front app, last capture). Interactive (button intents), configurable by App Intents. Lock Screen: one key. |
| **Control Center** | Controls for a chosen key, "Play/Pause on Mac", "Lock Mac". |
| **Spotlight** | Index deck keys and Macs (`IndexedEntity`), so "Pixel Hand Save" or the key name finds and runs it. |
| **Siri / onscreen awareness (27)** | Annotate the deck grid, app grid and window list with entity identifiers. |

Constraint: an intent that needs a live session connects in the background
(App Intents get ~10 s). If the Mac cannot be reached, the intent fails with a
clear message ("Your Mac isn't reachable. Open Pixel Hand to connect.").
Requires persistent pairing (1.1); before it, intents are not shipped.

## 9. Onboarding and permissions

### 9.1 iPhone/iPad (first run)

1. **Welcome**: the dot hand assembles (PixelMorph), one line: "Run your Mac
   from here." Continue.
2. **Get the Mac app**: QR and short URL, "Send link to my Mac" (share sheet),
   "I already have it".
3. **Local network primer** (one sentence why) → system prompt. If denied,
   show the fix (Settings deep link) and keep it visible on the picker.
4. **Find your Mac**: the DotScan picker. If nothing appears in 10 s, show
   three checks (same Wi-Fi, Mac app open, Local Network allowed).
5. **Pair**: 1.0 "Click Allow on your Mac"; 1.1 enter code or scan QR.
6. **Three-card tour** (trackpad, context bar, mirror), skippable, replayable
   from Settings.

### 9.2 Mac (first launch)

A real window (not only the menu-bar panel), with a dot-matrix checklist:
Accessibility (required for input), Screen Recording (mirror, capture),
Notifications (incoming files, pairing; 1.3), Open at Login (recommended).
Each row shows live state via `PermissionsMonitor.swift` and a button that
opens the exact System Settings pane. Automation is no longer requested once
S7 removes `osascript`. When done, the window shows "Ready. Open Pixel Hand on
your iPhone or iPad." and closes on first connection.

## 10. Settings, diagnostics and stats overlay

### 10.1 Remote settings, by section

| Section | Items |
| --- | --- |
| **Macs** | My Macs (rename, Forget, per-Mac mirror tier and deck options) |
| **Deck** | Follow front app, Ask before running destructive keys, Show suggestions, AI (on-device / via Mac / off), PCC (off) |
| **Trackpad & Keyboard** | Sensitivity, natural scrolling, input rate 60/120 Hz, gestures, Pencil behaviour, send hardware keyboard |
| **Mirror** | Auto / pinned tier, frame rate, show stats overlay |
| **Capture** | Default action, quality, auto-save to Photos |
| **Sharing** | Clipboard sync per device, Inbox retention, file approval defaults |
| **Haptics & Appearance** | Haptics off/light/full, System/Light/Dark |
| **Privacy** | Share crash reports (Sentry, default on), what is never sent |
| **Diagnostics** | Connection test, export logs (redacted), reset onboarding |
| **About** | Versions (remote and each Mac), acknowledgements, support link |

### 10.2 Mac panel

Status (dot hand + Mac name + "N devices connected"), device list with
per-capability toggles and Forget, Pair a device (1.1), permissions summary,
Check for Updates (Sparkle), Share crash reports, Open at Login, Quit.

### 10.3 Stats overlay

Toggled from the mirror toolbar or Settings. One line, monospaced dot-matrix
numerals, top-left of the mirror:
`60 fps · 9 ms frame · 4/11 ms RTT p50/p90 · 18 Mb/s · HEVC 1920 · Wi-Fi`.
Tap to expand: dropped frames, decode time, keyframe requests, receipt latency
p50/p90, link type (Wi-Fi/Wired/AWDL), Loom protocol, Mac app version.

## 11. Non-goals for 1.x

Internet relay; Windows/Linux hosts; audio streaming; virtual display; invoking
other apps' App Intents directly (no public API); sending anything to a
third-party AI service.

## 12. Decisions the owner must make

1. **Order after 1.1**: Deck 2 (1.2) → Multi-Mac + Sharing (1.3) → Assist
   (1.4) (recommended), or Multi-Mac first.
2. **Persistent pairing in 1.0 or 1.1?** Recommended 1.1, as planned; the
   per-launch Allow/Deny is acceptable for a short beta but is the biggest
   friction for a paid app. If beta feedback says so, pull it forward (+4–5
   days).
3. **Private Cloud Compute** for AI: off by default with an opt-in toggle, or
   never. Recommended: opt-in toggle in 1.4, not before.
4. **AI via the Mac's model** when the phone can't run it: recommended yes.
5. **iPhone↔iPad sharing** needs the iOS app to accept connections while open.
   Recommended yes in 1.3.
6. **Price and free trial** for the paid app (not covered here).
7. **Store name**: "Pixel Hand: Remote for Mac" (26 chars) to replace the
   draft "Deck Hand: Remote for Mac" in `AppStore/StoreListing.md`.
8. **Add typing and drag to 1.0** (≈3 days, inside week 2). Recommended
   yes: without them the app fails its own vision of not walking to the Mac.
9. **Rename identifiers**: change the Bonjour service, store suite, CloudKit
   container and bundle IDs all at once now (dev devices re-pair). Recommended
   yes; there are no users.
