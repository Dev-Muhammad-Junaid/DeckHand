# R&D · Live sync and caret control

Research and design only. Nothing here is built. Branch
`claude/pixelhand-rd-live-sync`, from `claude/pixelhand-integration`.
Board: https://claude.ai/artifact/GWCG3cn1GAqmD2Dyg37fq5 · source `rd-live-sync/`.

## 0. The ask, and the short answer

The owner asked (lightly edited):

> "Can Live show exactly what's in the [Mac] text field so I can modify it
> as well? Even when I Tab-accept a suggestion, the Type panel field still
> shows empty while it's being written. Can we make it work in real time?
> This might also help with the iPhone/iPad keyboard feature: holding the
> space bar lets you drag to move the cursor. Or maybe the arrow keys:
> holding one gives a similar effect, where the cursor moves freely left
> and right with a drag."

**Short answer.**

1. **Yes, for native Mac fields, in real time.** The Mac already reads
   native `AXTextField`/`AXTextArea` text reliably (OT-13). Two changes make
   it live. First, the Mac watches the field with `AXObserver` (value and
   selection notifications) and doesn't rely on the 8 Hz poll alone.
   Second, the iPad field holds that text (a window around the caret) and
   doesn't keep its own empty buffer. Then a Tab-accepted suggestion shows
   up in the iPad field as soon as the Mac app commits it.
2. **Two-way editing works.** The iPad sends *anchored edits* (replace this
   range of revision N with this text). The Mac applies an edit by setting
   the selection through Accessibility, then **typing** the replacement
   with the existing keystroke path. It never sets `AXValue`, which web
   apps ignore and which breaks undo.
3. **The space-bar trackpad comes free once the text is synced.** It moves
   the iPad caret in real text, and we mirror the selection to the Mac.
   We also found an extra: `UITextInput`'s *floating cursor* callbacks
   fire during that gesture. They could drive the Mac caret with arrow
   keys even in fields we can't read. That needs measuring.
4. **The arrow joystick** (hold an arrow, then drag) works in every app,
   terminals included, because it only sends arrow keys. We recommend
   building it first, together with native sync.
5. **Web and Electron text** (Safari, Chrome, Claude, Slack) stays off by
   default, as decided in OT-13. It becomes a per-app opt-in. Chrome stays
   unreadable because it needs `AXEnhancedUserInterface`, which has side
   effects for window managers.

## 1. Findings

Tags: **[doc]** = Apple or vendor documentation; **[known]** = widely
reported behaviour of shipping software (assistive apps, window managers,
open-source code); **[measure]** = must be measured on a Mac or iPad
before we rely on it.

### 1.1 Reading the Mac field in real time

**What we have (OT-12/OT-13).** `FocusReader` polls the system-wide focused
element 8×/s while something is changing and 4×/s when quiet. It reads the
role, the frame, the caret (`kAXSelectedTextRangeAttribute` +
`kAXBoundsForRangeParameterizedAttribute`), and, for native non-secure
fields only, up to 1 000 UTF-16 units around the caret. It sends
`system.focusState` when something moved by more than 0.75 pt. At 8 Hz
the worst-case lag is about 125 ms plus transport. That's fine for a
loupe, but a field you type in feels laggy at that rate, and it echoes
back stale text.

**`AXObserver` [doc].** `AXObserverCreate(pid, callback)` makes one observer
per process. `AXObserverAddNotification(observer, element, name)`
registers notifications, and its run-loop source
(`AXObserverGetRunLoopSource`) delivers them on the thread whose run loop
we add it to. The relevant notifications:

| Notification | Register on | Fires when |
|---|---|---|
| `kAXFocusedUIElementChangedNotification` | the app element | focus moves inside that app |
| `kAXValueChangedNotification` | the focused text element | its value changes (typing, paste, accepted suggestion) |
| `kAXSelectedTextChangedNotification` | the focused text element (or app) | caret or selection moves |
| `kAXUIElementDestroyedNotification` | the focused text element | the field goes away |
| `NSWorkspace.didActivateApplicationNotification` | (AppKit) | the front app changes, so re-create the observer for the new pid |

- **Latency [known/measure].** AppKit posts these synchronously from
  `NSAccessibilityPostNotification`, and they reach the observer's run
  loop within a few ms. We should measure it with TextEdit, Notes and
  Mail. The cost of reading the value afterwards is the real cost: a
  1 MB `NSTextView` value is slow, so we read a window with
  `kAXStringForRangeParameterizedAttribute`, as OT-13 already does.
- **Throttling.** Coalesce on the Mac. On the first notification, read and
  send at once (leading edge). Then send at most one update every 33 ms
  (30 Hz) while notifications keep coming, plus one trailing update
  after the last. Keystroke-rate updates never queue up.
- **Keep the poll.** OT-12's reasons still hold. Nothing notifies when a
  field moves because its window was dragged or scrolled, and Chromium's
  notifications are unreliable. So the observer drives *text and
  selection*, and the existing 4–8 Hz poll keeps driving *geometry*. It
  also acts as a safety net that catches any notification we missed.
- **Timeouts.** Every call keeps the 0.1 s
  `AXUIElementSetMessagingTimeout` [doc] and runs on `FocusReader`'s serial
  queue. A hung app can never stall the main actor.

**Native vs WebKit vs Chromium/Electron.**

| Engine | Text and selection | Notes |
|---|---|---|
| **AppKit** (`NSTextField`, `NSTextView`, TextEdit, Notes, Mail's compose body, Xcode's Find, most Mac apps) | `AXValue`, `AXSelectedTextRange`, `AXNumberOfCharacters`, `AXStringForRange`, `AXBoundsForRange`: reliable [doc]. Notifications fire [known]. | Mail's compose body is WebKit, not AppKit: see the next row. |
| **WebKit** (Safari, Mail's message body, any `WKWebView`) | The AX tree is always on. `<input>`/`<textarea>` expose `AXValue` and `AXSelectedTextRange`. `contenteditable` exposes them unevenly, so the reliable path is **text markers** (`AXSelectedTextMarkerRange`, `AXStringForTextMarkerRange`, `AXTextMarkerRangeForUnorderedTextMarkers`, `AXLengthForTextMarkerRange`) [known: WebKit's `WebAccessibilityObjectWrapperMac`, used by VoiceOver]. Value-changed notifications fire [known]. | Today we deliberately don't read web text (OT-13 privacy decision). |
| **Chromium** (Chrome, Edge, Arc, Brave) | Chrome builds its native AX tree only for an assistive client. It turns it on when someone sets `AXEnhancedUserInterface = true` on the app element, or when VoiceOver runs [known: Chromium's Mac accessibility code]. After that, it supports the same text-marker attributes as WebKit. | `AXEnhancedUserInterface` has a known side effect, so we don't set it (see below). |
| **Electron** (Claude, Slack, VS Code, Discord, Notion) | Same engine as Chromium. Electron also honours **`AXManualAccessibility`**, which turns on the tree without the side effect [doc: Electron "Accessibility" tutorial; electron/electron#7206]. We already set it while a loupe watches (OT-12). | VS Code then offers its screen-reader mode [known]. |

**`AXEnhancedUserInterface` side effects [known].** VoiceOver sets this
undocumented attribute. Apps that see it switch to "a screen reader is
here" behaviour. In Chromium and in AppKit windows that observe it, that
**breaks or animates programmatic window moves and resizes**. People
reported it for Magnet on Apple's accessibility-dev list. Hammerspoon
reported Chrome windows animating when moved (Hammerspoon #3224), and
its usual workaround turns the attribute off around a move and then puts
it back. It also costs CPU, because Chrome keeps a full AX tree for every
tab. Window managers (Rectangle, Magnet, Hammerspoon users) and our own
window features would be hit. **Recommendation: never set it** (OT-12
already decided this). Chrome stays "can't read", unless VoiceOver
happens to be on, in which case we can read it.

**`AXManualAccessibility` [doc].** Electron only. It's cheap to turn on
for one app while a remote watches and off after, which OT-12 already
does. It doesn't affect window positioning. Once it's on, the Chromium
tree supports text markers.

**Text markers vs `AXSelectedTextRange` (web).** For `<input>` and
`<textarea>`, `AXSelectedTextRange` is an index into the control's value
and is enough. For `contenteditable` (Claude's composer, Slack's message
box, Gmail, Notion), indexes aren't stable across the tree. The
dependable way is to take the selection marker range, expand it to the
paragraph or line (`AXLineTextMarkerRangeForTextMarker`,
`AXParagraphTextMarkerRangeForTextMarker`) and read the string for that
range. **We'd sync a window: the current paragraph, capped at 1 000 UTF-16
units.** These attribute names are public strings that VoiceOver uses.
They're read by name, the way OT-12 already reads
`AXSelectedTextMarkerRange`, so there's no `dlsym` and no private symbol.
**[measure]** how stable this is in Claude and Slack.

**Long documents: a window around the caret.** We keep OT-13's window:
1 000 UTF-16 units, about a third before the caret and two thirds after,
`truncatedBefore`/`truncatedAfter`. We add `windowStart`, the window's
offset in the field. Edits and selections can then be sent as absolute
offsets, and the Mac checks them against the field's current text. When
the caret moves within 150 units of a window edge, the Mac slides the
window and sends it again.

**Code editors and terminals [known/measure].**

| App | What AX gives |
|---|---|
| Xcode source editor | An `AXTextArea` with the whole file as `AXValue`. The selection range works. Value notifications fire, but only after a keystroke settles. |
| VS Code, Cursor (Monaco) | A hidden `<textarea>` that holds only the current line, or about 10 lines in screen-reader mode. Editing it doesn't map to the document. |
| JetBrains IDEs | Java Access Bridge: sparse, often no value. |
| Sublime, Zed, Nova | Little or nothing (custom text views). |
| Terminal.app, iTerm2 | An `AXTextArea` whose value is the **entire scrollback**. The selection is the terminal's own selection, not the shell's line-editing cursor. Ghostty, Warp, WezTerm and Kitty expose little. |

So **terminals are "keys only".** Editing a shell line isn't text editing,
because the shell owns the cursor. We never show a terminal's scrollback
in the Type panel. We'd match them by bundle ID (an app-side list, kept
out of Loom) and by an `AXTextArea` larger than 100 k characters with no
`AXInsertionPointLineNumber`. **Code editors are read-only at most.**
Xcode can sync like a native field. Monaco-based editors get "keys only",
with the joystick and the loupe.

### 1.2 Writing back (two-way editing)

There are three ways to put an iPad edit into the Mac field.

| Method | How | Good | Bad |
|---|---|---|---|
| **A. Set the value** | `AXUIElementSetAttributeValue(el, kAXValueAttribute, newString)` | One call, exact | Native: replaces the whole text storage, which **breaks undo** (no undo group) and fires no `NSTextDidChange` delegate in some apps. **Web: React/Vue/Lexical controlled inputs ignore it or revert it**, because no `input` event fires [known: every web automation tool hits this]. |
| **B. Set selected text** | Set `kAXSelectedTextRangeAttribute`, then set `kAXSelectedTextAttribute` to the replacement | Minimal change. `NSTextView` applies it through its text-replacement path [known] | Undo grouping varies by app. Web apps ignore it, as with A. Secure fields refuse it. |
| **C. Select, then type** | Set the selection (via AX where it's settable, else arrow keys), then replay the replacement through the existing `TypingPlanner` (⌫ for a deletion, layout keys or Unicode events for text) | **Every app takes it** (it's real input). Undo and autocorrect on the Mac behave as if a person typed. Web frameworks see real `input` events. Same code path as Live today | Slower for long text (2 ms per event; a 1 000-character paste takes about 2 s). Arrow-key positioning needs a known starting caret. |

**Recommendation: C, with B only for the caret.** We set
`kAXSelectedTextRangeAttribute` where it's settable
(`AXUIElementIsAttributeSettable` [doc]). That's true for native fields,
and **[measure]** for Safari `<input>`/`<textarea>`. Otherwise we move
there with ←/→ key presses, starting from the last caret the Mac
reported. Then we type. Text longer than 200 characters goes through the
existing paste path (save the clipboard, paste, put the clipboard back,
as `LANE-paste-control.md` already does). We never use A.

**Minimal edits.** Core already has `TypingEdit.between(old, new)`, which
assumes the caret is at the end. We'd generalize it to
`TextEdit(range: NSRange, replacement: String)`: the common prefix and
suffix between the field before and after a commit. Autocorrect replacing
"teh" → "the" three words back becomes {range: 12..<15, "the"}: one
selection plus three characters, not 40 backspaces.

**IME and marked text.** We keep today's rule: nothing goes to the Mac
while `markedTextRange != nil`. When the input method commits, we diff
and send. The synced text is held back while text is marked, so a Mac
update never yanks the composition. It's applied when the composition
ends.

**Autocorrect, predictions, smart punctuation on the iPad field.** Today
smart quotes, dashes and insert/delete are off, and autocorrect and
predictions are on. With synced text, autocorrect **gets better**: it sees
the real words around the caret, not an empty buffer. Its replacements
become small range edits. We recommend keeping autocorrect and
predictions on, keeping smart punctuation off, and turning the
**spell-check underline** off (`spellCheckingType = .no`), because a Mac
app usually has its own spell check. That's owner decision 2.

**Undo.** Path C lands in the Mac app's own undo stack. ⌘Z sent from the
key row undoes on the Mac, and the next sync shows the result. The iPad
field's own undo (shake, three-finger swipe) would undo only local text
that the Mac has since replaced. **We turn the field's local undo off in
synced mode** and route ⌘Z, and the iPad's undo gestures where we can
catch them (`undoManager` override), to the Mac.

**Conflicts: the Mac is the source of truth.**

- The Mac stamps every `textState` with a **revision**, a counter per field
  identity that goes up on every value or selection change it sees.
- The iPad shows its own edits right away (**local echo**) and sends each
  as `input.textEdit(field, baseRevision, range, replacement)`. One edit is
  in flight at a time; later ones queue and merge.
- The Mac applies an edit only if the text at `range` still matches what
  the iPad based it on. It checks a short hash of the replaced text plus
  10 units of context on each side. If it matches, the Mac applies the
  edit and answers `textEditResult(applied, revision)`. If the person
  typed on the Mac meanwhile, the offsets move, so the Mac rebases by the
  difference when the context is found nearby. Otherwise it answers
  `conflict` and sends its current state.
- On `conflict`, the iPad drops its unsent queue, shows the Mac's text,
  plays the refused haptic and flashes the sync badge amber for 1.4 s.
  Nothing is silently lost on the Mac. The iPad's lost keystrokes were at
  most one in-flight edit.
- **Echo suppression.** The Mac's own notifications for our edit come back
  as a new revision. The iPad recognizes its own edit (the same text at
  the same place) and doesn't move the caret, so you never see a jump.

### 1.3 Privacy and safety

- **Never read secure fields.** That covers `AXSecureTextField`, any role
  or subrole containing "secure" or "password" (OT-12's `isSecure`), and
  **secure event input**. `IsSecureEventInputEnabled()` [doc: TN2150, "Using
  Secure Event Input Fairly"] is true while any app has a password prompt,
  and also during `sudo` in Terminal. While it's on, the Mac sends
  `readable: .secure` and **refuses `textEdit`/`textSelect`**. Key presses
  still go (they're needed to type the password), as today.
- **Web and Electron text: per-app opt-in, off by default.** The Mac app
  keeps a list of apps you allowed (Mac › Settings › Privacy › "Show text
  from web apps"). The iPad's "can't read" card offers **Allow for Claude**,
  which asks the Mac. The Mac shows a one-time confirmation with the app's
  icon, the way pairing does, and remembers the choice. Within an allowed
  app we still refuse secure fields and anything with `AXSubrole` =
  `AXSecureTextField`. Chrome isn't offered (see 1.1).
- **Locked Mac:** unchanged (`LockPolicy.withholdsFocus`). One `.none`, then
  nothing until unlock. `textEdit` while locked is dropped.
- **What goes over the wire:** only the text window, only while Live is
  open and the panel is on screen, and only over the authenticated Loom
  session. Nothing is logged. Text never goes into diagnostics or Sentry
  (a scrubber test asserts this).
- **What you see when a field can't be read.** The field shows a dim
  placeholder line with the reason in plain words. Live typing works
  exactly as today (blind diff at the end), and the joystick and the loupe
  still work. The reasons, from the Mac:
  `secure` "Password field: the text stays on the Mac" ·
  `webOff` "Web text is off for Claude" + **Allow** ·
  `unsupported` "Chrome doesn't share its text" ·
  `terminal` "Terminal: keys only" · `noField` "No text field" ·
  `locked` "Mac is locked" · `tooLarge` (never: we window).

### 1.4 The iOS space-bar trackpad

**The exact gesture [doc: iPad User Guide, "Type with the onscreen
keyboard"; TidBITS 2024].**
- **iPhone (iOS 12+):** touch and hold the **space bar**. The letters fade
  out and the keyboard turns into a blank grey pad. Drag to move the
  insertion point freely in two dimensions. While still holding, **tap
  with a second finger** to start a selection, then drag to extend it.
  (3D Touch phones also used a firm press anywhere.)
- **iPad:** the same space-bar hold, **or two fingers anywhere on the
  keyboard**. With two fingers, a short hold before dragging starts a
  selection.
- **Floating keyboard** (iPad, pinched small): it behaves like the iPhone
  keyboard, so the space-bar hold works [known].
- **Stage Manager / Slide Over:** the keyboard is the same system keyboard,
  so it works [known/measure].
- **Hardware keyboard:** no on-screen keyboard, so **no gesture**. The
  minimised bar has no space bar. Arrow keys on the hardware keyboard
  already go to the Mac (Live today).

**Which fields [doc/known].** The gesture is the keyboard's own. It works in
any first responder that adopts `UITextInput`, which includes every
`UITextView`/`UITextField`. It needs no opt-in.

**What the app sees [doc].**
- The caret moves through ordinary selection changes:
  `textViewDidChangeSelection(_:)` fires as the caret moves (UIKit
  updates `selectedTextRange` as you drag), and the `inputDelegate`'s
  `selectionWillChange`/`selectionDidChange` fire.
- **`UITextInput` floating cursor:** `beginFloatingCursor(at:)`,
  `updateFloatingCursor(at:)`, `endFloatingCursor()`. UIKit calls these
  when the cursor is picked up for the drag (Apple: "the system's
  cursor-manipulation gesture"; `endFloatingCursor` "at the end of the
  two-finger pan gesture used to pick up the cursor"). `UITextView`
  implements them to draw the floating caret. **A subclass can override
  them and still call `super`.** Flutter's iOS engine does exactly this
  to drive its own caret from the keyboard trackpad [known:
  `FlutterTextInputPlugin`].

**The key insight: verified in principle, measure on device.**
- **With synced text:** the iPad field holds the Mac's real text, so the
  system gesture moves a real caret through real words.
  `textViewDidChangeSelection` gives the new range, and we send
  `input.textSelect(field, rev, range)`. The Mac sets
  `kAXSelectedTextRange` (native) or presses arrows (fallback). It's
  free, it feels exactly like iOS, and selection with a second finger
  works too.
- **Without synced text** (Chrome, terminals, opt-out): the field is
  empty, so the system caret has nowhere to go, and today
  `textViewDidChangeSelection` snaps it back to the end anyway. **But** we
  still get `begin/update/endFloatingCursor(at:)` with the finger's
  position [measure: whether UIKit sends updates when the text is empty.
  If it doesn't, we keep a few hidden spaces of padding in the blind
  field and strip them from diffs]. We can turn the change in
  `point.x` into ←/→ presses (one per ~8 pt, the width of a character on
  the Mac) and `point.y` into ↑/↓ (one per line height). That gives a
  **"blind trackpad"**: the same gesture, moving the Mac caret where we
  can't read the text. We'd still mark it as experimental, because it
  can't show selection and has no feel for where words start.

### 1.5 Our own caret gestures

**Arrow-key joystick (recommended: build).**
- **Gesture:** **press and hold** any arrow cap for **300 ms** (shorter = a
  normal tap and auto-repeat, as today). The cluster lights up, and the
  pressed cap becomes the joystick's **anchor**. Then **drag** without
  lifting.
- **Axis lock:** the first 10 pt of movement picks the axis. Horizontal
  moves by **characters** (←/→); vertical moves by **lines** (↑/↓).
  Dragging past 60 pt along an axis switches to **words** (⌥←/→) or
  **paragraphs** (⌥↑/↓), the Mac's own modifiers.
- **Speed grows with distance:** 0–12 pt is a dead zone. Past that, the
  rate is 4 Hz at 12 pt, rising linearly to 30 Hz at 120 pt
  (`rate = 4 + 26 × clamp((d − 12)/108)`). Each step is one key press with
  a light haptic (`selectionChanged`), throttled to 15 haptics/s.
- **Select:** with ⇧ latched in the key row (or a second finger on the
  panel), each step goes as ⇧+arrow. The joystick's trail turns accent.
- **Trail:** a dot-matrix trail from the anchor to the finger, with dots
  every 6 pt. The lit dots match the current rate (the further, the more
  lit), the far one phosphor, fading 300 ms after release. It uses the
  existing `DotField` lighting maths and only one kind of dot
  (`06-Pixel-Identity.md` §0).
- **Release:** stops at once (no inertia; a caret overshooting is worse
  than a short one).
- **Works everywhere:** it's only key presses. Terminals, Chrome, VS Code
  and remote desktops all take it. In synced fields the iPad caret follows
  the Mac's reported selection, so you see where you are.
- **VoiceOver:** the arrow caps keep their names. The joystick is a custom
  action, "Move by words", on each arrow. No new rotor.

**Tap or drag in the loupe (recommended: phase 3).**
- **Tap** a point in the loupe → the Mac **clicks** at the mapped point.
  Core's `FocusLoupe` already maps loupe → mirror → display points. The
  pointer then goes back to where it was (`CGWarpMouseCursorPosition`, no
  event) so the trackpad doesn't jump. The click puts the caret there
  natively in *every* app (web, Electron, terminals with mouse support).
- **Drag** → a mouse drag (down, move, up) = select. Hold-then-drag avoids
  fighting the loupe's pan.
- Needs the mirror (Pro). It's the only way to place the caret precisely in
  an unreadable field, which is why it's worth doing, but after the
  joystick.

**Mouse pointer vs text caret, for this panel.** The owner's "drag to a
specific point" could mean either. **Build the text caret for the Type
panel.** The pointer already has two good tools (the Pointer surface
trackpad and OR-16's picture pointer), and moving the pointer doesn't move
the caret until you click. Inside the Type panel you're editing text, so
the gestures should move the thing that edits: the caret. The loupe tap
bridges the two (a click at a point = caret at a point) without adding a
third pointer mode.

## 2. Feasibility matrix

✅ works · 🟡 works with a caveat or after measuring · ❌ not possible or not
offered · — not applicable.

| App type | Read text | Write (select + type) | Mirror selection | Space-bar trackpad | Arrow joystick | Loupe tap/drag |
|---|---|---|---|---|---|---|
| **Native AppKit** (TextEdit, Notes, Pages fields, Xcode Find, Messages) | ✅ value + range, observer | ✅ AX selection + keys | ✅ `kAXSelectedTextRange` settable | ✅ synced text | ✅ | ✅ |
| **Safari / WebKit** `<input>`/`<textarea>` | 🟡 opt-in; value + range | ✅ keys; 🟡 AX selection settable [measure] | 🟡 AX or arrows | 🟡 synced (opt-in), else blind | ✅ | ✅ |
| **WebKit `contenteditable`** (Mail compose, Gmail in Safari) | 🟡 opt-in; text markers, paragraph window | ✅ keys; selection by arrows from the known caret | 🟡 arrows | 🟡 synced (opt-in), else blind | ✅ | ✅ |
| **Chrome / Chromium browsers** | ❌ needs `AXEnhancedUserInterface` (not set); ✅ only if VoiceOver is on | ✅ keys (blind diff, as today) | ❌ | 🟡 blind (floating cursor) | ✅ | ✅ |
| **Electron: Claude, Slack, Discord, Notion** | 🟡 opt-in; `AXManualAccessibility` + text markers [measure per app] | ✅ keys | 🟡 arrows | 🟡 synced (opt-in), else blind | ✅ | ✅ |
| **Code editors**: Xcode | ✅ (large value, windowed) | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Code editors**: VS Code / Cursor / JetBrains / Sublime | ❌ (no useful value) | ✅ keys (blind) | ❌ | 🟡 blind | ✅ | ✅ |
| **Terminals** (Terminal, iTerm2, Ghostty, Warp) | ❌ by design (scrollback, not a field) | ✅ keys | ❌ | 🟡 blind (←/→ only; ↑/↓ = shell history, so off) | ✅ ←/→; ↑/↓ = history, labelled | 🟡 only with mouse reporting |
| **Secure fields / secure input on** | ❌ never | ✅ keys only | ❌ | ❌ (field shows nothing) | ✅ | ✅ |

## 3. Recommended design

### Phase 1: build first (native sync + joystick)

1. **Mac:** `FocusTextObserver`, an `AXObserver` per front-app pid
   (value, selection, focus, destroyed), re-created on app activation,
   coalesced to 30 Hz, feeding the existing reader. Geometry keeps the
   poll.
2. **Mac:** `textState` with revision, window offset, selection, readability
   reason, and capabilities (`canSetSelection`, `canEdit`).
3. **iPad: synced Live field.** When the Mac sends text, `LiveTypingField`
   shows it with the caret at the Mac's selection. Local edits become
   `TextEdit`s, with local echo and one in flight. The caret is free (no
   snap to the end): taps, the space-bar trackpad and the system selection
   handles all send `textSelect`. When text isn't readable, the field
   falls back to today's blind buffer and shows the reason line.
4. **Sync badge** (dot-matrix, in the field's top-trailing corner):
   `SYNC` mint pixel (live) · `SENDING` glow pixel while one is in flight ·
   `MAC WINS` amber for 1.4 s after a conflict · `BLIND` dim when not
   readable.
5. **Arrow joystick** on the existing cluster (one-row and inverted-T
   shapes both).
6. **Tab-accept:** Accept ⇥ stays. The accepted text now appears in the
   field from the Mac's next value change, which answers the owner's
   "shows empty" directly.

### Phase 2: web and Electron opt-in

Text markers for `contenteditable`, the per-app allow list, the "Allow for
Claude" flow, Safari `<input>` AX selection [measure]. The blind floating-cursor
trackpad for unreadable fields [measure first; a half-day spike].

### Phase 3: loupe tap and drag

A click or drag at the mapped point, with the pointer restored.

### Deferred / not doing

- Chrome text (needs `AXEnhancedUserInterface`), revisit only if Chromium
  ships a lighter switch.
- Ghost-suggestion text (OT-13 finding stands; the loupe shows it as
  pixels).
- Setting `AXValue` (A above), never.
- Terminal line editing as text.

## 4. Protocol (version 17)

All new messages are Core `Codable` types with fixtures, like protocol 16.
Offsets are UTF-16 (`NSRange` style) and **absolute in the field**.

```
// remote → Mac
system.watchFocus(on: Bool, wantsText: Bool)        // wantsText = Live open; extends 16
input.textEdit(TextEditRequest)
  { field: FieldToken, baseRevision: UInt32,
    range: {start, length}, replacement: String,     // ≤ 4 KiB, else paste path
    context: {beforeHash: UInt32, afterHash: UInt32} }
input.textSelect(TextSelectRequest)
  { field: FieldToken, baseRevision: UInt32, range: {start, length} }
input.caretMove(CaretMove)                            // joystick + blind trackpad
  { direction: .left/.right/.up/.down, unit: .character/.word/.line/.paragraph,
    count: UInt8, extend: Bool }                      // Mac coalesces; ≤ 30/s
system.allowTextReading(app: BundleID)                // asks the Mac (Phase 2)

// Mac → remote
system.focusState(focus: FocusedFieldSnapshot)       // unchanged geometry
system.textState(FocusedTextState)
  { field: FieldToken,            // opaque: hash(pid, AX element identity, focus epoch)
    revision: UInt32,
    readable: .yes | .secure | .webOff(app) | .unsupported | .terminal | .noField | .locked,
    window: {start, value: String} | nil,           // ≤ 1 000 units, nil unless .yes
    length: Int,                  // field length, for "…" and bounds checks
    selection: {start, length},
    canSetSelection: Bool, canEdit: Bool }
system.textEditResult { field, request: UInt32, outcome: .applied | .rebased | .conflict | .refused(reason), revision }
```

- `caretMove` could be plain key messages. A dedicated message lets the
  Mac **coalesce** (it sends "→ ×7" as seven presses spaced 2 ms) and
  refuse it under secure input without refusing every key.
- `LockPolicy`: `textState` is withheld while locked; `textEdit`,
  `textSelect` and `caretMove` are dropped. `RemoteInputValidation`
  refuses a `textState` sent *to* the Mac.
- A 16 and a 17 can't talk; `PeerCompatibility` says "Please update".

## 5. Risks and edge cases

| Risk | Mitigation |
|---|---|
| Echo loop (our edit → Mac notification → iPad overwrites the caret) | Revision + "my own edit" recognition; hold remote updates while composing |
| Person types on the Mac at the same time | Mac is the source of truth; context-hash rebase; `conflict` → iPad adopts the Mac's text with an amber badge |
| Huge fields (an Xcode file, a long Notes note) | 1 000-unit window, `AXStringForRange`, slide near edges; never read `AXValue` of a field larger than 20 k units |
| A slow or hung app | 0.1 s AX timeout, serial queue, observer callbacks only enqueue |
| Observer leaks across app switches | One observer per pid, torn down on deactivate and on `destroyed` |
| Web framework reverts our edit | We only type (path C), so frameworks see real input |
| Autocorrect edits mid-word on the iPad | Range edits; Mac checks context first |
| Mac autocorrect changes what we typed | It's a new Mac revision; the iPad simply shows it |
| Bidirectional text, emoji, combining marks | Offsets in UTF-16 on both sides; never split a grapheme (Core helper, tested) |
| Arrow-key positioning drifts (fields with hidden text, soft wraps) | Use AX selection where settable; else re-read the caret after each move batch and correct |
| `AXManualAccessibility` left on after a crash | Mac resets it on the next launch for apps in its "turned on by us" list |
| VS Code's screen-reader prompt | Known from OT-12; documented in the opt-in sheet |
| Battery on the iPad | Text updates only while Live is open and the panel is on screen |
| A Mac that reads text while you look away | Nothing reads unless `wantsText` is on; the Mac's menu-bar hand shows "being controlled" as today |

## 6. Test strategy

- **Core (Linux, `swift test`):** `TextEdit.between` for range edits
  (prefix, suffix, autocorrect mid-text, emoji, CJK, RTL); the window
  slider; revision and rebase rules (`TextSyncReconcilerTests`: applied,
  rebased, conflict, echo suppression, composition hold); joystick maths
  (dead zone, axis lock, rate curve, unit switch, haptic throttle);
  floating-cursor delta → `caretMove` steps; protocol fixtures and
  `ProtocolContractTests` for every new message; `LockPolicy` and
  `RemoteInputValidation` cases; a diagnostics scrubber test that text
  never reaches logs.
- **Mac (on device):** a scripted harness that opens TextEdit, Notes, a
  Safari `<textarea>`, Mail compose, Claude and Slack (opt-in), types and
  edits from a fake remote, and checks the field's AX value afterwards,
  undo (⌘Z) and the round-trip latency (target: p95 under 80 ms on
  Wi-Fi). Instruments to confirm low CPU with a 5 000-line TextEdit
  document.
- **iPad (UI tests + hand checks):** `test25_LiveSyncedField` (a stub Mac
  sends `textState`; the field shows it; an edit goes out as `textEdit`);
  `test26_ArrowJoystick` (hold, drag, assert the `caretMove` count grows
  with distance); hand checks for the space-bar trackpad (iPhone, iPad
  two-finger, floating keyboard, Stage Manager, hardware keyboard = no
  gesture), IME (Japanese, Pinyin), dictation, and autocorrect.
- **Measurements to report back (Mac check list):** observer latency per
  app; Safari `<input>` selection settable; Claude's and Slack's
  text-marker windows; floating-cursor callbacks with empty text;
  `AXManualAccessibility` cost.

## 7. Effort

| Piece | Estimate |
|---|---|
| Phase 1 Mac: observer, `textState`, apply edits/selection, secure input | 3–4 days |
| Phase 1 Core: protocol 17, `TextEdit`, reconciler, joystick maths, tests | 2–3 days |
| Phase 1 iPad: synced field, badge, reason line, joystick + trail | 3–4 days |
| Phase 1 Mac/iPad measurement pass and fixes | 1–2 days |
| **Phase 1 total** | **≈ 9–13 days** |
| Phase 2: text markers, opt-in list and flow, blind trackpad spike | 4–6 days |
| Phase 3: loupe tap/drag | 2–3 days |

## 8. Decisions for the owner

1. **Web and Electron text (Claude, Slack, Safari pages): per-app opt-in?**
   *Recommended: yes.* It's off by default, and you allow it per app from
   the "can't read" card, with a confirmation on the Mac. It keeps OT-13's
   privacy rule for everyone who doesn't ask. Chrome stays keys-only.
2. **The iPad keyboard in synced Live: what stays on?**
   *Recommended:* autocorrect and predictions **on** (they now see real
   words), smart quotes and dashes **off** (as today), the spell-check
   underline **off** (the Mac app has its own), and local undo **off**
   (⌘Z goes to the Mac).
3. **What to build first?**
   *Recommended:* Phase 1, **native sync plus the arrow joystick**.
   Together they cover the Tab-accept complaint and give a caret gesture
   that works in every app. Then web opt-in with the blind trackpad
   spike, then the loupe tap.

## Sources

- Apple, `AXObserverCreate`, `AXObserverAddNotification`,
  `AXUIElementSetMessagingTimeout`, `AXUIElementIsAttributeSettable`,
  `kAXValueChangedNotification`, `kAXSelectedTextChangedNotification`
  (ApplicationServices / HIServices `AXUIElement.h`, `AXNotificationConstants.h`):
  https://developer.apple.com/documentation/applicationservices/axuielement_h
- Apple, Technical Note TN2150, "Using Secure Event Input Fairly":
  https://developer.apple.com/library/archive/technotes/tn2150/_index.html
- Apple, `UITextInput.beginFloatingCursor(at:)`:
  https://developer.apple.com/documentation/uikit/uitextinput/beginfloatingcursor(at:)
  · `endFloatingCursor()`:
  https://developer.apple.com/documentation/uikit/uitextinput/endfloatingcursor()
- Apple, `UITextViewDelegate.textViewDidChangeSelection(_:)`:
  https://developer.apple.com/documentation/uikit/uitextviewdelegate/textviewdidchangeselection(_:)
- Apple, iPad User Guide, "Type with the onscreen keyboard" (turn the
  keyboard into a trackpad):
  https://support.apple.com/guide/ipad/type-with-the-onscreen-keyboard-ipad997da459/ipados
- TidBITS, "Use Trackpad Mode When Editing Text on the iPhone and iPad"
  (2024): https://tidbits.com/2024/08/31/tipbits-use-trackpad-mode-when-editing-text-on-the-iphone-and-ipad/
- Electron, Accessibility tutorial (`AXManualAccessibility`):
  https://www.electronjs.org/docs/latest/tutorial/accessibility ·
  electron/electron#7206: https://github.com/electron/electron/pull/7206
- Apple accessibility-dev list, "AXEnhancedUserInterface breaks window
  managers like Magnet" (2020):
  https://lists.apple.com/archives/accessibility-dev/2020/Sep/msg00007.html
- Hammerspoon #3224 (Chrome window moves animate):
  https://github.com/Hammerspoon/hammerspoon/issues/3224
- Apple Developer Forums, "AX elements in some apps only exposed when using
  VoiceOver or Accessibility Inspector":
  https://developer.apple.com/forums/thread/756895
- Flutter iOS embedder, `FlutterTextInputPlugin` (floating cursor driven
  from the keyboard trackpad):
  https://api.flutter.dev/ios-embedder/protocol_flutter_text_input_delegate-p.html
- Repo: `Integration/LANE-owner26.md` (OT-12, OT-13), `LANE-owner24.md`
  (Live `TypingEdit`), `Core/Input/TextTyping.swift`,
  `DeckHandiOS/Keyboard/LiveTypingField.swift`,
  `Core/System/FocusReading.swift`.

---

R&D: READY FOR OWNER REVIEW

Board: https://claude.ai/artifact/GWCG3cn1GAqmD2Dyg37fq5 (private; source `DeckHand/Product/Design/rd-live-sync/index.html`)
