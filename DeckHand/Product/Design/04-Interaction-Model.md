# 04 · Interaction model

For Option A (Dock & Canvas). Product rules come from `02-Product-Spec.md`
and the owner's decisions in `DeckHand/Integration/DECISIONS.md`.

## 1. Navigation map

```
Launch
 ├─ First run → Onboarding (§5) → Find your Mac → Pair → Control
 └─ Paired Mac reachable → Control (auto-connect to the last Mac)
                           unreachable → Control with the "not answering" state (§7)

Control (one screen, no push navigation)
 ├─ Tabs: Pointer · Screen · Deck · Ask (search role)
 ├─ Mac pill → My Macs sheet (switch, add, lock all, run on…)
 ├─ Capture button → capture sheet (preview → annotate / read text / share / send)
 ├─ More → Settings sheet · Disconnect · Help
 ├─ App dock → long-press menu (Quit, Hide, Shortcuts, Send to)
 └─ Keyboard button → keyboard + modifier bar (accessory over the keyboard)
```

Rules:

- **One sheet level.** Sheets never present sheets. Capture's annotate and
  read-text steps are states inside the capture sheet (detents medium/large),
  not new covers. The deck editor's inspector is a sheet over the deck, not
  over another sheet.
- **No full-screen covers** except full-screen Screen and the pairing camera.
- Disconnect moves out of the toolbar into More and the Mac pill's menu.
- Every root transition keeps place: switching Macs slides the canvas; leaving
  pairing grows the paired Mac card into the canvas (`hero` motion).

## 2. Surfaces and gestures

### Pointer
| Gesture | Result | Discoverable via |
| --- | --- | --- |
| Tap | Click | Click strip (labelled) |
| Two-finger tap | Right-click | Click strip "Right-click" |
| Tap then hold, move | Drag (drag-lock feel, 1.0 PH-033) | First-use coach mark |
| Long press (option) | Right-click (setting, off by default once drag ships) | Settings |
| Two fingers | Scroll with momentum | Caption on the pad |
| Three-finger swipe ← → | Spaces (or Macs when 2+ paired and enabled) | Coach mark, Help |
| Three-finger swipe ↑ / ↓ | Mission Control / App Exposé (Mac's own shortcuts, S7) | Help |
| Pinch | Zoom on the Mac (1.1, S11) | Help |

The 7-button gesture bar is removed. The **click strip** (Click | Right-click)
stays as an accessible fallback and can be hidden in Settings. Sensitivity
moves to Settings. Mission Control and Show Desktop become deck keys and
three-finger gestures.

### Screen
- **Follow-cursor zoom** on compact widths: the mirror shows 2× around the
  pointer and pans as it moves; a minimap shows the viewport. Pinch changes
  zoom; double-tap toggles fit/2×.
- **Direct** (tap where you point) vs **Trackpad** mode in the glass toolbar;
  Pencil is always direct, hover moves without clicking (S12).
- Toolbar: Direct/Trackpad · zoom · display picker · keyboard · stats · PiP ·
  full screen. Auto-hides after 3 s in full screen; tap the top edge to show.
- Hardware keyboard: when Screen is focused and "Send keyboard to Mac" is on,
  every key goes to the Mac (Globe and system shortcuts excepted).

### Deck
- Follows the front app (debounced 400 ms), pin to stop following.
- Swipe between pages; page dots under the grid.
- Long-press a key: Edit, Run on…, Ask before running, Remove.
- Edit mode: dotted outlines, drag to reorder, **+** opens the action library,
  undo in the toolbar. AI proposals appear as ghost keys (§3).

### Context strip
- Dialog visible → its buttons take over. On compact widths the **default
  button comes first** (thumb reach); on wide, macOS order.
- Otherwise: pinned chips for the front app → recents → "+ Suggest".
- Long-press a chip: Pin to deck, Run on…, Edit.
- Every chip shows the delivery strip and announces the receipt.

### App dock
- Tap: bring the app to front on the Mac. Long-press: Quit, Hide, Show
  shortcuts (opens Deck on that app's page), Send to (1.3).
- An app with a dialog shows a warning dot on its icon.
- Apps that aren't running: Ask ("open Figma") or the action library.

### Keyboard
- The keyboard button sits in the app dock, above the system keyboard's top,
  so the keyboard can never cover its own toggle (Sill's lesson).
- Modifier bar above the keyboard: ⌘ ⌥ ⌃ ⇧ (tap = once, double-tap = lock),
  esc, tab, arrows, and a **Type** field that sends text on Return (PH-032).

## 3. Apple Intelligence

Where it runs (product spec §3.4): on-device Foundation Models → the paired
Mac's model → deterministic fallback. Never a third-party cloud; Private Cloud
Compute is an opt-in toggle, off.

| Feature | Release | Entry point | How it looks | Guard rails |
| --- | --- | --- | --- | --- |
| **Suggest a deck** | 1.2 | "+ Suggest" chip; "Suggestions" panel on an app page | Ghost keys in an `accentTint` panel with "Keep all", tap one to keep it | Model picks only from discovered menu IDs (`@Generable DeckProposal`); max 24 keys; deterministic fallback by curated rank |
| **Ask (command bar)** | 1.4 (search-only in 1.2) | Ask tab / ⌘K / Siri | Sheet with a field, then a numbered **plan** of typed steps with chords; Run · Save as key · Edit | Tool calling returns `[ActionRun]`; nothing runs before the plan shows unless "Run simple commands without asking" is on and the step is single, safe and on the focused Mac; destructive or multi-Mac always asks |
| **Ask about the screen** | 1.4 | "Ask" in the capture sheet; "What's on screen?" in Ask | Answer card with highlights drawn on the capture; "Type on Mac" / "Copy" | Uses a capture the user took; image input needs OS 27; Vision OCR tool |
| **Read this screen** | 1.4 | Strip offers it when AX finds no buttons | Proposed targets as dotted rings on the mirror; tap to confirm | Never clicks on its own |
| **Siri and onscreen awareness** | 1.2 / 1.4 | Siri, Shortcuts, Spotlight | App Intents over the same `Action` model; deck grid annotated with entities | Needs persistent pairing |

Visual language: thinking = cyan **dot scan** across the plan area; proposals =
dashed cobalt outlines; the Ask glyph is a 3 × 3 dot square with a lit centre.
No sparkles, no gradients that read as "magic". AI features are **Pro**.

## 4. Multi-Mac and sharing (1.3)

- **My Macs** sheet (compact) / sidebar (wide): Mac cards with glance
  thumbnails, live pixel, front app, badges (Dialog, Locked, Update). Actions:
  Lock all, Pause media on all, Run on…
- **Run on…**: from a key, chip or Ask plan; Mac checkboxes; per-Mac receipt
  rows; destructive actions list the Macs by name before running.
- **Send**: Share extension, drag onto a Mac card (iPad), "Send to" on an app
  or capture, Paste chip. The sheet shows the item, a row of paired devices
  (Mac, iPad, iPhone) with status, and a **dot beam** between two device
  glyphs that fills, turns mint and collapses into a check. Lands in
  `~/Downloads/Pixel Hand/` on the Mac and the in-app **Inbox** on iOS.
- Incoming items: banner with Accept / Decline and "Always from this device";
  over 2 GB always asks.

## 5. Onboarding and permissions

iPhone/iPad, scrollable pages, works in landscape:

1. **Welcome**: the dot hand powers on (as on the website hero); "Run your Mac
   from here."
2. **Get the Mac app**: QR + `pixelhand.app/mac`, "Send link to my Mac" (share
   sheet), "I already have it".
3. **Local network**: one sentence why, then the system prompt. If denied, a
   status pill with a Settings link stays on the picker.
4. **Find your Mac**: DotScan; after 10 s, three checks (same Wi-Fi, Mac app
   open, Local Network allowed).
5. **Pair**: 1.0 "Click Allow on your Mac"; 1.1 the 12-digit code in dot-matrix
   numerals, or scan the QR.
6. **Three coach marks in place** (not a carousel): the click strip, the chips,
   the Screen tab. Replayable from Help.
7. **Soft paywall** once (§6), then Control.

Mac first run: a real 560 × 460 window with a dot checklist (Accessibility,
Screen Recording, Notifications, Open at Login), live state, a button per row
that opens the exact pane, and "Ready. Open Pixel Hand on your iPhone or iPad."

Permissions missing later show a **status pill** under the header with one
sentence and a Fix button, never a paragraph banner.

## 6. Paywall and free tier

From `DECISIONS.md` (2026-11-17): subscription "Pixel Hand Pro", $2.99/month
or $19.99/year, 2-week free trial on both, Family Sharing on. **Free** =
trackpad, keyboard and media keys with one Mac. **Pro** = decks and chips,
mirror (and PiP), capture/OCR, multiple Macs, sharing, AI.

| Moment | Behaviour |
| --- | --- |
| After onboarding | One soft paywall with "Try 2 weeks free" and "Not now". |
| Tapping a Pro surface in free | Screen and Deck tabs stay visible; the surface shows a dimmed preview and an inline card (title, one sentence, "Try 2 weeks free", "Not now"). Never blocks Pointer. |
| Context strip in free | Shows media keys (free) and a dashed "App chips · Pro" chip. |
| Second Mac in free | My Macs shows it with a PRO badge; connecting asks. |
| Trial ending | One reminder 2 days before (local notification, opt-in), and a Settings row "Trial ends 1 Dec". |
| Never | Mid-gesture interruptions, countdown timers, or hiding the close button. |

Paywall sheet: navy brand background, Geist headline, four benefits with
glyphs, plan cards (Yearly selected, "Save 44%"), primary "Try 2 weeks free",
then Apple's required text: price and period after the trial, auto-renewal,
how to cancel, links to Terms of Use (standard EULA), Privacy Policy and
Restore Purchases. "Free forever: trackpad, keyboard and media keys for one
Mac." Settings gets a subscription row (status, renewal date, Manage, Restore).

## 7. Empty, loading and error states

| State | What people see | Action |
| --- | --- | --- |
| Searching | DotScan on navy; after 10 s the three checks | Help |
| Mac not answering | Pad shows the dimmed hand, "Studio isn't answering", last seen, three checks with live/off pixels | Try again · Wake Studio |
| Mac locked | Status pill "Studio is locked. Type the password to unlock."; deck dimmed; pointer and keyboard still work | Keyboard |
| Permission missing on the Mac | Status pill "Accessibility is off on Studio. Clicks and keys won't reach it." | Fix (explains the Mac steps) |
| Needs an update | Mac card greyed with "Update Pixel Hand on Studio" and the download QR | Show QR |
| Command refused | Chip/key dots turn red with a cross, toast with the reason, VoiceOver announcement | – |
| No chips for this app | Strip shows "No menu shortcuts found" + "Suggest" | Suggest |
| Empty deck page | Empty state with dot art, "Add keys from Xcode's menus" | Add keys |
| Capture failed | Toast with the reason (Screen Recording off, timeout) | Fix |
| Lost connection mid-gesture | Pad dots go grey (never cyan or mint while disconnected), header pixel grey | Reconnects automatically; Try again after 10 s |

Rule: a disconnected state never shows lit cyan or mint dots.

## 8. Accessibility

1. **Dynamic Type** to AX5 on every screen (rules in `02-Design-System.md` §3).
2. **VoiceOver**: chip/key label = action, value = chord and target ("Save,
   Command S, on Studio"); receipts announced; the trackpad is a direct-touch
   area with custom actions (Click, Right-click, Double-click, Scroll up/down,
   Drag); the mirror is "Screen of Studio" with a rotor action "Read text on
   screen"; the strip is a container "Actions for Xcode"; the Mac pill
   announces "Studio focused, Xcode".
3. **Large Content Viewer** on the tab bar, dock icons and chips at AX sizes.
4. **Switch Control / Voice Control**: every gesture has a button equivalent
   (click strip, deck keys for Mission Control, Spaces, Show Desktop); names
   match visible labels.
5. **Reduce Motion**: cross-fades, frozen dots. **Reduce Transparency**: solid
   chrome. **Increase Contrast**: stronger strokes, solid chip borders.
   **Differentiate Without Color**: receipts change shape (check / cross).
6. **Hit targets** ≥ 44 pt; no hover-only controls (fixes the Mac panel).
7. **Keyboard** on iPad: ⌘K Ask, ⌘1–4 Macs, ⌘⇧S capture, ⌘, Settings, arrow
   keys move focus through deck keys.

### 8.4 Review and platform risks to track

- **PiP**: Apple requires PiP to start only from user action or automatic
  start on leaving the app. Declaring the audio background mode for a
  non-audio app has drawn 2.5.4 rejections for others. Mitigation: PiP is
  clearly user-facing ("Keep watching your Mac"), off until the user turns it on
  once, and the review notes explain it.
- **4.2.7 remote desktop**: keep the remote's app list a searchable list and
  dock, not a home-screen-like icon grid of the Mac's apps.

## 9. Copy rules

Plain, specific, from the user's side (03-UX-Guidelines §6), plus:

- Device-neutral: "your iPhone or iPad", never "the iPad" only.
- Name the Mac: "Send to Studio", "Studio is locked".
- Buttons say what happens: "Try 2 weeks free", "Wake Studio", "Keep all".
- No debug text in UI (session ids go to Diagnostics only).
