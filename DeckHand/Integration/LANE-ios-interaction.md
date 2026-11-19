# Lane: iOS interaction (typing, click-drag, S11, S12, S10)

Branch: `claude/pixelhand-lane-ios-interaction`, from
`origin/claude/pixelhand-integration` at `2464a70`, with `d6f2d76` (tick 2)
merged in. **Protocol 6** (integration is at 5).

Written in a Linux container: PixelHandCore built and tested with Swift
6.2; the Mac handlers, `LockGate`, `DragGuard`, `TypingQueue`,
`TrackpadSender` and `RemoteClipboard` type-checked against stubs
(`Scripts/linux-typecheck/run.sh`); `TouchTrackingView` type-checked once
against throwaway UIKit stubs (not committed). Every other app file was
only parsed (`swiftc -parse`). The apps were **not** compiled.

Behaviour re-implemented from Sill's README and
`docs/trackpad-gestures-plan.md` (no code copied).

## 1. What changed

### Protocol 6 (Core)

| Message | Way | What |
| --- | --- | --- |
| `input.typeText(text:)` | remote → Mac | Unicode text typed at the Mac's cursor. `\n` = Return, `\t` = Tab. ≤ 4 KB a message (`TypingPolicy.maxMessageBytes`); the remote cuts long text with `TextChunker` (1 KB pieces, never inside a character). |
| `input.mouseDown(button:)` | remote → Mac | Press and hold; moves become drags. Repeated every 1 s as a keep-alive while held. |
| `input.mouseUp(button:)` | remote → Mac | Release. |
| `sharing.clipboardSync(enabled:)` | remote → Mac | Turn the Mac's clipboard feed to this remote on/off. |
| `sharing.setClipboard(text:paste:)` | remote → Mac | Put text on the Mac's clipboard; `paste` also presses ⌘V. |
| `sharing.macClipboard(text:)` | Mac → remote | The Mac's clipboard text (on subscribe and on change). |

The `sharing` domain is activated (one decode line in `ControlMessage.swift`,
its handler in `ControlRouter` and `MacHandlers`). S11 gestures send the
Mac system control lane's existing `system.run(action:)` and
`system.switchSpace`; **no `SystemMacro` case was added**.

Validation (`RemoteInputValidation.sanitize`, tested):
- `typeText`: over 4 KB → dropped; control characters other than `\n`/`\t`
  removed, CR/CRLF → `\n` (`TypingText.normalized`); empty after that →
  dropped.
- `setClipboard`: empty or over 64 KB (`ClipboardPolicy.maxTextBytes` =
  `ProtocolLimits.maxStringLength`) → dropped.
- `sharing.macClipboard` from a remote → dropped.
- `mouseDown` / `mouseUp` / `clipboardSync`: no numbers or strings.

Lock gate (`LockPolicy.decide`, tested), one announced case each:
- `input.mouseUp`: **always allowed**, so a drag can never stay stuck.
- typed text, `mouseDown`: follow the existing `.input` rule (allowed at
  the lock screen so the password can be typed; refused off console).
- `sharing.setClipboard`: refused while locked (both states).
- `sharing.clipboardSync`: allowed (a subscription only; the Mac withholds
  the clipboard itself while locked).

### Core logic (Linux-tested, 63 new tests; 285 total)

| File | What |
| --- | --- |
| `Input/KeyTable.swift` | Key names → macOS virtual key codes (moved out of `InputInjector`), `KeyModifier`, `KeyChord`, `RemoteKey` (Esc, Tab, Delete, Forward Delete, Return, arrows, Home/End, Page Up/Down) |
| `Input/TextTyping.swift` | `TypingPolicy`, `TypingText.normalized`, `TextChunker`, `TypingPlanner` (layout keys vs Unicode runs ≤ 20 UTF-16 units), `TypingEdit` (diff of the typing field → Backspaces + text) |
| `Input/DragStateMachine.swift` | `DragPolicy`, `DragStateMachine` (press-hold-move, two-finger drag lock, tap to drop, lock timeout, cancel releases), `HeldButtonWatchdog` (the Mac's release on disconnect / 5 s unrefreshed) |
| `Input/TrackpadGestures.swift` | `GestureClassifier` (swipe/pinch/spread from net travel at lift, 3+ fingers), `GestureStroke`, `GestureMap` (natural Spaces direction, toggle-back) |
| `Input/HoverPointer.swift` | `HoverPointerTracker` (Pencil hover → deltas, no jump on entry or re-entry) |
| `Sharing/ClipboardPolicy.swift` | size cap, private pasteboard types (nspasteboard.org concealed/transient/auto-generated), `ClipboardEcho` |

### Mac

- `InputInjector`: moves post `leftMouseDragged` (etc.) while a remote
  holds a button; `mouseDown` / `mouseUp`; typing primitives `typeKey`,
  `typeNamedKey`, `typeUnicode` (`keyboardSetUnicodeString`, own
  `.privateState` source so a physically held modifier doesn't leak in);
  chords now resolve through Core's `KeyTable`.
- `Input/KeyboardLayoutMap.swift` (new): which key + Shift/Option types
  each character on the **current** layout (`TIS…` + `UCKeyTranslate`,
  public APIs). Dead keys skipped; main keys before keypad; rebuilt when
  the input source changes. An input method (Japanese, Chinese, …) as the
  current source → everything goes as Unicode.
- `Input/TypingQueue.swift` (new): types text and posts chords **in
  arrival order**, 2 ms between events, at most 64 KB waiting.
  `input.keyboardShortcut` now goes through it so Return after a sentence
  can't overtake the sentence.
- `Input/DragGuard.swift` (new): `HeldButtonWatchdog` + a 1 s sweep;
  `InteractionSession.connectionRemoved` releases a vanished remote's
  buttons, drops its clipboard subscription and, if nobody is left, the
  typing backlog.
- `Clipboard/MacClipboardSync.swift` (new): polls
  `NSPasteboard.changeCount` every 0.5 s only while a remote subscribes;
  skips private items and > 64 KB; sends nothing while locked (the change
  goes out at the unlock); doesn't echo its own writes; `setClipboard`
  with `paste` presses ⌘V through the typing queue.
- `Handlers/SharingHandler.swift` (new), `Handlers/InputHandler.swift`
  (new cases).

### iOS

- **Typing** (`Keyboard/`): the trackpad's new **Keyboard** button opens a
  panel with a live text field (every committed change goes to the Mac;
  autocorrect, dictation, QuickPath and CJK input methods work because a
  real `UITextView` composes locally and only commits are diffed and
  replayed), a key row (Esc, Tab, ← ↓ ↑ →, ⌫, Return) with latching
  ⌘ ⌥ ⌃ ⇧ (latched + a letter typed in the field = that chord), and
  Paste to Mac. A hardware keyboard: arrows, Esc, Tab, Home/End, Page
  Up/Down, Forward Delete and every ⌘/⌃ chord go to the Mac; Backspace in
  an empty field still deletes on the Mac.
- **Click-drag** (`MultiTouchTrackpad`): rest a finger 0.4 s (heavy
  haptic, indicator "Move to drag"), move → the Mac's left button goes
  down and the finger drags; lift → up. While dragging, a second finger →
  drag lock (indicator "Drag locked · tap to drop"): lift, come back,
  keep dragging; a quick tap drops; 4 s with no finger drops. A held press
  lifted without moving still right-clicks (now on lift). A cancelled
  touch or the trackpad leaving the screen releases the button.
- **S11 gestures**: three fingers (four where iPadOS lets them through),
  decided when the first finger lifts: swipe up Mission Control, down App
  Exposé, left/right Spaces (natural: fingers left → next Space), pinch
  Apps (Launchpad), spread Show Desktop. Toggle-back: the opposite gesture
  closes what this remote opened; the same gesture again does nothing
  once, then runs again. A click, drag, key or text forgets. Setting:
  Settings › Pointer and gestures › Mac gestures.
- **S12 Pencil hover**: `UIHoverGestureRecognizer` on the trackpad; only a
  hovering Pencil (`zOffset > 0`) moves the pointer, no jump on entry.
  Setting (iPad only): Apple Pencil hover moves the pointer.
- **S10 clipboard**: Settings › Clipboard › Share clipboard (off by
  default) and Paste on the Mac right away (on). With sharing on, Mac text
  lands on the device's clipboard (writing never prompts). Paste to Mac is
  a `UIPasteControl` (no paste prompt); the app never reads the clipboard
  by itself.
- `TrackpadSender`: `typeText`, `sendKey`, `sendTypingEdit`,
  `sendMouseDown` (keep-alive task) / `sendMouseUp` (flushes pending moves
  first), `sendGesture`, `setClipboardSync`, `setMacClipboard`.
  `sendThreeFingerSwipe` removed.
- Text-field chips (`TextFieldAction`): Left and Right arrows added.

### Behaviour changes to notice

1. Long-press right-click fires when the finger lifts (after the 0.4 s
   buzz), not at 0.4 s, because hold-then-move is now a drag.
2. Three-finger swipes are decided at lift (a swipe taken back does
   nothing) and the Spaces direction is now the Mac's natural one: fingers
   **left → next** Space (was previous).
3. A chord with two non-modifier keys is no longer sent (it used to press
   the last one). No built-in chip does this.

## 2. Checks on the Mac and iPad

Build both apps, connect, approve. On the Mac, `log stream --predicate
'subsystem CONTAINS "pixelhand"' --level info` shows the lines quoted.

| Area | Check |
| --- | --- |
| Typing | Trackpad › Keyboard. TextEdit frontmost on the Mac. Type `Hello, world` → appears as you type. Type `héllo 世界 👋🏽` → exact text. Backspace in the field deletes on the Mac; with the field empty, Backspace still deletes on the Mac. Return in the software keyboard → new line. |
| Autocorrect | Type `teh ` → the Mac shows `the ` (two Backspaces + `he `). Dictate a sentence → it appears on the Mac once dictation commits. |
| Input methods | iPad Japanese (Romaji) keyboard: type `nihon`, pick 日本 → only 日本 reaches the Mac. Mac set to Japanese input: typed Latin text still arrives as typed (log `Typing: input source … is an input method`). |
| Layouts | Mac set to German (QWERTZ): type `zy` → `zy` (not `yz`). Mac set to French AZERTY: `aq` → `aq`. Log `Typing: layout … maps N characters to keys`. |
| Key row | Esc closes a Mac dialog; arrows move the caret; ⌘ latched + `a` in the field → Select All, latch clears; ⌥ latched + ← → word left. |
| Hardware keyboard | Magic Keyboard on the iPad: arrows, Esc, Tab go to the Mac; ⌘C/⌘V/⌘Z act on the Mac, not the field. |
| Ordering | Paste a long paragraph (~5 KB) into the field: it types in order; immediately press Return in the key row → Return lands after the paragraph. |
| Drag | Finder: rest a finger on a file icon's spot until the buzz, move → the file drags; lift → drops. Select text in TextEdit by hold-and-move. Window title bar drag works. |
| Drag lock | During a drag put a second finger down (buzz), lift both, put one back and keep moving → still dragging. Quick tap → drops. Lock and leave it 4 s → drops by itself. |
| Drag safety | Start a drag, then force-quit the iPad app (or toggle Wi-Fi off) → within 5 s the Mac's button is up (log `Drag: released …`). Lock the iPad mid-drag → released. |
| Right click | Rest a finger 0.4 s, lift without moving → context menu (on lift). |
| S11 | Three-finger swipe up → Mission Control; swipe down → closes it. Swipe down → App Exposé; swipe up → closes. Pinch → Apps/Launchpad; spread → closes. Spread → Show Desktop; pinch → windows back. Fingers left → next Space. Swipe up twice → second does nothing, third opens again. A swipe taken back before lifting does nothing. Off in Settings → nothing. Four fingers: works where iPadOS gestures are off (Settings › Multitasking). |
| S12 | iPad with Pencil hover (M2+ iPad Pro / M2+ iPad Air / iPad mini A17 Pro): hover over the trackpad → the Mac pointer follows; touch down → tap clicks. A trackpad/mouse pointer over the view does **not** move the Mac pointer. Setting off → nothing. |
| S10 Mac → iPad | Settings › Clipboard › Share clipboard on. Copy text on the Mac → within ~0.5 s pastes on the iPad (Notes); the panel shows "Copied on the Mac: …". Copy a password from 1Password / Passwords → not sent (log `Clipboard: not shared`). While the Mac is locked nothing is sent: in a DEBUG build run `defaults write com.widgetsflow.pixelhand.mac PixelHandTestLockState screenLocked`, copy text on the Mac → nothing arrives; `defaults delete com.widgetsflow.pixelhand.mac PixelHandTestLockState` → about 2 s later that copy arrives. Share clipboard off → nothing arrives. |
| S10 iPad → Mac | Copy on the iPad, Keyboard panel › Paste → **no "Allow Paste" prompt**; text pasted at the Mac's cursor (log `Clipboard: set N B from a remote and pasted`). Paste on the Mac right away off → only on the Mac's clipboard. The Mac doesn't echo it back. While the Mac is locked → nothing set (log `Lock gate: refused sharing.setClipboard`). |
| Locked Mac | At the lock screen: type the password in the field + Return → unlocks. Drag start at the lock screen works; a mouseUp is always accepted. |
| Unchanged | Pointer, scroll with momentum, taps, double-taps, media keys, chips (including text-field chips with the new ← →), capture, mirror. |

## 3. Compile risks (most likely first)

1. **`Keyboard/LiveTypingField.swift`** (not type-checked): `UITextView`
   subclass that is its own delegate; `presses.filter` returning
   `Set<UIPress>`; `UIKey.keyCode` cases; `text ?? ""` on `String!`.
2. **`DeckHandMac/Input/KeyboardLayoutMap.swift`**: Carbon signatures —
   `TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()`,
   `TISGetInputSourceProperty` → `Unmanaged.fromOpaque`, `LMGetKbdType()`,
   `UCKeyTranslate` argument types (`Int` lengths), `shiftKey`/`optionKey`
   as `Int`. Needs `import Carbon.HIToolbox` (auto-linked; add
   `Carbon.framework` only if the linker asks).
3. **`Clipboard/PasteToMacControl.swift`**: `[weak self]` inside
   `NSItemProvider.loadObject`'s `@Sendable` completion then a
   `Task { @MainActor in self?.onPaste(text) }` (Swift 6 may want a local
   `let`); `UIPasteControl.Configuration` properties.
4. **`InputInjector.swift`**: `keyboardSetUnicodeString(stringLength:unicodeString:)`
   inside `withUnsafeBufferPointer`; `private lazy var typingSource` on a
   `@MainActor` class.
5. **`ControlSessionModel+Input.swift`**: `settings.$clipboardSync.removeDuplicates().values`
   iterated on the main actor (Swift 6 sendability of `AsyncPublisher`).
6. **`MultiTouchTrackpad.swift`**: `static func dismantleUIView(_:coordinator: ())`;
   `UIHoverGestureRecognizer.zOffset` (iOS 16.1+, target is 17.4).
7. **`SettingsPointerSection.swift`**: `body` now holds two `Section`s
   (fine inside the parent `Form`); `UIDevice` needs the added `import UIKit`.

## 4. Out-of-lane edits

| File | Owner | Edit |
| --- | --- | --- |
| `Core/System/LockPolicy.swift` | Mac system control | `case .input(.mouseUp): return .allow`; `case .sharing` now switches: `clipboardSync` allow, `setClipboard` refuse, `macClipboard` allow (was: refuse everything). |
| `Core/Protocol/ControlMessage.swift` | hot spot | `sharing` decode line (activates the domain); the `.v` case comment; the doc line on `case sharing`. |
| `Core/Routing/ControlRouter.swift` | hot spot | `sharing` handler: property, init argument, assignment, `route` line (the reserved `case .sharing: break` removed). |
| `Core/Protocol/PixelHandProtocol.swift`, `Fixtures/protocol/*` + `MANIFEST`, `Core/PROTOCOL.md` | hot spot | Version 6, fixtures re-recorded (every file's `"v"`), domain table rows for `input`/`sharing`, history line. |
| `Core/Tests/…/ProtocolContractTests.swift`, `ControlRouterTests.swift`, `LockPolicyTests.swift` | protocol / Mac system | Samples and case names (47 cases), "reserved domain" test → "unknown sharing case is refused"; router recorder for `sharing`; lock tests for typed text, `mouseDown`, `mouseUp`, clipboard. |
| `DeckHandMac/Handlers/MacHandlers.swift` | hot spot | `let sharing = SharingHandler()` and `sharing: sharing`. |
| `DeckHandMac/LockGate.swift` | Mac system control | One line at the end of `MacSystemSession.connectionRemoved`: `InteractionSession.connectionRemoved(id: id)`. |
| `DeckHandiOS/Control/ControlSessionModel.swift` | hot spot (§2.7) | `// MARK: iOS interaction` (`clipboard`, `interactionSettings`); in `run`, one task + `defer` for `runInteraction`; one `case let .sharing(m)` in `handleOnMain`. |
| `DeckHandiOS/ControlView.swift` | integration | `TrackpadView(…, clipboard: session.clipboard)` (one line). |
| `DeckHandiOS/DeckHandSettings.swift` | hot spot | Four settings under `// MARK: iOS interaction (lane)` (keys, `@Published`, init). |
| `Scripts/linux-typecheck/Stubs.swift`, `run.sh` | shared | Stubs for this lane's types and `UIPasteboard`; `TrackpadGestureKind` stub removed; `DragGuard`, `TypingQueue`, `RemoteClipboard` added to the default list. |

`Handlers/InputHandler.swift`'s header now says it is owned by iOS
interaction (`LANES.md` §2.5 lists it here; the header said Mac system
control).

New files: Core `Input/KeyTable.swift`, `Input/TextTyping.swift`,
`Input/DragStateMachine.swift`, `Input/TrackpadGestures.swift`,
`Input/HoverPointer.swift`, `Sharing/ClipboardPolicy.swift` (new folder);
tests `TextTypingTests`, `DragStateMachineTests`, `TrackpadGestureTests`,
`ClipboardPolicyTests`. Mac `Input/KeyboardLayoutMap.swift`,
`Input/TypingQueue.swift`, `Input/DragGuard.swift`,
`Clipboard/MacClipboardSync.swift`, `Handlers/SharingHandler.swift`. iOS
`Keyboard/LiveTypingField.swift`, `Keyboard/RemoteKeyboardPanel.swift`,
`Clipboard/RemoteClipboard.swift`, `Clipboard/PasteToMacControl.swift`,
`Control/ControlSessionModel+Input.swift`. All folders are picked up by
`project.yml` as they are.

## 5. Info.plist, entitlements, project.yml

None. `UIPasteControl`, `UIHoverGestureRecognizer`, `NSPasteboard` and the
Text Input Sources APIs need no usage strings or entitlements. The Mac
app's existing Accessibility grant covers typing and drags.

## 6. Follow-ups

1. **Privacy, for the integration session (`ControlReceiver.swift`, hot
   spot):** `consumeMessages` logs every non-pointer message at debug
   level with `String(describing: message), privacy: .public`, which now
   includes typed text (a password typed at the lock screen) and clipboard
   text. Suggested edit: add `.input(.typeText), .sharing:` to a case that
   logs only `message.domain` (or the byte count), next to the sampled
   `.mouseDelta` / `.mouseScroll` case. I didn't make it: the file allows
   no edits from this lane.
2. A Mac-side "Share clipboard" switch in the menu bar panel (Sill has one
   in both apps); today the remote's opt-in alone decides.
3. With a Mac input method active, Unicode events carry key code 0, which
   some input methods may read as "a". If testing shows it, post those
   events with the IME bypassed (switch to the ASCII-capable source for
   the duration) or a different carrier key code.
4. Apps-tab chips and the deck don't call `GestureMap.forget()`; a chip
   pressed between two gestures can make a toggle-back gesture open
   instead of close. Low impact; needs a shared signal.
5. Settings for autocapitalization/autocorrect in the typing field
   (currently: no autocapitalization, autocorrect on, smart quotes off).
6. Four-finger gestures can only reach the app with iPadOS's multitasking
   gestures off; consider saying so in onboarding.

Lane: READY TO MERGE
