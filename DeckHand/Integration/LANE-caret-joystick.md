# Lane: arrow joystick (caret-joystick)

Branch `claude/pixelhand-lane-caret-joystick`, from
`claude/pixelhand-integration` at `1fbd090` ("Record the owner's live sync
decisions"). It builds Phase 1 item 5 of `Product/Design/RD-live-sync-and-caret.md`
(§1.5 "Our own caret gestures", §5, §6), approved in `DECISIONS.md`
"2026-11-27 — Live text sync and caret gestures". Board:
https://claude.ai/artifact/GWCG3cn1GAqmD2Dyg37fq5 (section 3, "Arrow-key joystick").

**No protocol change** (still 16). The joystick sends ordinary
`input.keyboardShortcut` messages, one per step, so it works with today's
Mac in every app. The doc's `input.caretMove` (protocol 17, Mac-side
coalescing) is left to the live-sync lane's protocol bump; switching the
sender to it later is a one-line change in `TypePanel.sendJoystickStep`.
No `project.yml`, Info.plist, Mac or Loom change.

## What it does

- **Gesture.** Press and hold any arrow cap, in the inverted T or the
  one-row cluster, for **300 ms**, then drag without lifting. Engaging
  plays a light haptic. Left and right drags send ←/→ (characters). Up and
  down drags send ↑/↓ (lines). Past **60 pt** it moves by words (⌥←/→) or
  paragraphs (⌥↑/↓). The speed grows with distance. Release stops at once,
  with no inertia.
- **A tap is still a tap.** A press released before 300 ms sends one arrow,
  with the latched modifiers, exactly as before. There's no morph, so
  nothing flickers. A press held still past 300 ms and released without a
  drag is a slow tap, and it also sends one arrow. A press that moves more
  than 10 pt before 300 ms is cancelled and sends nothing, like a Button
  dragged off.
- **Modifiers.**
  - With ⇧ latched, every step goes as ⇧+arrow, so it selects. The trail
    turns accent and the readout shows ⇧.
  - With ⌥ latched, it moves by words or paragraphs from the first step.
    The doc gives words only by distance. A latched ⌥ already means "by
    word" on a tap, so the joystick keeps that meaning.
  - With ⌘, ⌃ or fn latched, it never engages and the press stays a tap.
    ⌃← switches desktops and ⌘← jumps to the line start, and neither
    should repeat 30 times a second.
  - When the joystick sent steps, once-latched modifiers are consumed on
    release, as a key press would. Locked ones stay.
- **Visual (joystick state).** The held cap turns accent and gives up its
  glyph to a white **centre dot**, the stick. A **dot-matrix trail** runs
  from the anchor along the locked axis to the finger's place on it, with
  one dot every 6 pt. The dots are glyph dots (78 % of pitch, radius 30 %),
  so there's one kind of dot (`06-Pixel-Identity.md` §0). The share of
  lit dots follows the speed, lit toward the finger, brightness
  0.25 + 0.75·t^1.6 as on the board. The far dot is phosphor (cobalt on
  light) and unlit dots are `dotOff`. The cap it's moving toward is
  tinted. A navy **readout** sits above the finger for ←/→ and beside it
  for ↑/↓, showing the chord, the arrow glyph and `14/S · CHAR` in
  dot-matrix. The trail draws over the field and keys (`zIndex`) and never
  takes touches. After release it fades over 300 ms.
- **Reduce Motion.** There's no fade after release (the trail goes at
  once), and the cap style change uses the reduced fade.
- **Terminals.** When the Mac's front app is a terminal, ↑/↓ are **shell
  history**:
  - The readout says `HISTORY`.
  - While the joystick runs, the ↑/↓ caps show the glyph over `HISTORY`.
  - The rate is 2–8 entries/s.
  - It never switches to paragraphs.

  ←/→ behave as anywhere else. Detection uses the bundle ID that the Mac
  already reports in `apps.activeAppUpdate(name:bundleID:)`, with the app
  name as a fallback (Core `TerminalApps`: Terminal, iTerm2, Ghostty,
  Warp, WezTerm, kitty, Alacritty, Hyper, Rio, Tabby). The doc's second
  heuristic (an `AXTextArea` over 100 k characters) is Mac-side
  `textState` work for the live-sync lane.
- **VoiceOver.**
  - Each arrow cap stays its own Button with its name (`ph.type.key.*`),
    and VoiceOver's activate sends one arrow.
  - Each cap gains the doc's custom action **"Move by words"** on ←/→ and
    "Move by paragraphs" on ↑/↓. A terminal's ↑/↓ don't get one.
  - New: **"Move the caret"** (`ph.type.joystick`), an **adjustable**
    element behind the caps. Swipe up steps forward (→ / ↓ / newer
    history) and swipe down steps back, by a unit you pick from its
    actions: "By characters", "By words", "By lines", "By paragraphs" (or
    "By history" in a terminal). Its value reads the unit, plus
    "Selecting …" with ⇧ latched. Full Keyboard Access and the iPad
    pointer reach the caps as before: they're still Buttons with
    `phosphorFocusable`.
- **Everywhere.** It's only arrow keys, so it works in native fields,
  web, Electron, Chrome, code editors, terminals and remote desktops. The
  loupe and the Live field are untouched.

## Design numbers (Core `CaretJoystick.Tuning`, each justified in code)

| Number | Value | Why |
|---|---|---|
| Hold | 300 ms | Longer than any deliberate tap (80–150 ms), shorter than iOS's long-press (500 ms) (doc §1.5) |
| Tap slop before the hold | 10 pt | UIKit's tap slop; further means the finger is going elsewhere |
| Axis lock | first 10 pt, larger component | Doc §1.5 |
| Axis release | back within 6 pt of the anchor | Lets you go right, come back, go down without lifting; below the lock distance so it doesn't flap |
| Dead zone | 0–12 pt | A resting thumb drifts 4–8 pt; about a quarter of a 44 pt cap (doc) |
| Rate | 4 → 30 steps/s, linear from 12 to 120 pt, flat beyond: `4 + 26·clamp((d−12)/108)` | Doc; 4/s lets you stop on a character (250 ms per step), 30/s is the Mac's fastest key repeat and leaves link headroom; 120 pt is about 2.5 caps, still inside an iPhone panel. Matches the board (52 pt → 14/s, 96 pt → 24/s) |
| Words / paragraphs | from 60 pt, back below 54 pt | Doc's 60 pt; 6 pt of hysteresis so the unit (and its label) doesn't flicker on the boundary |
| First step | as soon as the finger leaves the dead zone | Leading edge, so the joystick answers at once and not a period later |
| Burst cap | ≤ 3 steps per tick | A clock hitch never fires a burst |
| Terminal history | 2 → 8 entries/s | Each ↑ redraws the shell line over the link; above about 8/s you can't read what you pass |
| Step haptic | `selectionChanged`, ≤ 15/s | Doc; faster taps blur into a buzz |
| Trail | dot every 6 pt, lit share = speed, fade 300 ms | Doc and board |

The iPad drives Core with a 16 ms `Task` clock. Core integrates the real
elapsed time, so clock jitter changes when a step goes, not how many.

## Files

| File | Change |
|---|---|
| Core `Input/CaretJoystick.swift` (new) | `CaretJoystick` (hold, slop, axis lock/release, dead zone, rate curve, word switch with hysteresis, ⇧/⌥/⌘⌃fn rules, terminals, haptic throttle, burst cap, readout, trail), `CaretStepper` (VoiceOver), `TerminalApps` |
| Core tests `CaretJoystickTests.swift` (new) | 31 tests in 7 suites |
| iOS `Keyboard/ArrowJoystick.swift` (new) | `ArrowJoystickModel` (touches → Core, hold timer, 60 Hz clock, haptics), the cap gesture, `ArrowJoystickOverlay` (trail + readout), `CaretStepperElement`, `ArrowJoystickQAProbe` |
| iOS `Keyboard/TypePanel.swift` | `arrowCluster` uses `arrowButton` (gesture, joystick styles, VoiceOver actions) and holds the stepper, overlay and probe; `keyButton` takes an optional style/legend; its action moved to `press(_: TypeKey)`; `KeyCap.Legend.glyphWord`, `KeyCap.arrowGlyph`; `zIndex` on the cluster while engaged |
| iOS `Keyboard/TypingTarget.swift` | `frontBundleID`, `isTerminal` |
| iOS `Control/ControlSessionModel.swift` | one line: stores the front app's bundle ID beside its name |
| `PixelHandUITests/PixelHandUITests.swift` | `-qa.exposeJoystick YES` launch argument; `test27_ArrowJoystick` |

## Tests

- `swift test --package-path DeckHand/Core`: **1333 tests pass**,
  including the 31 new ones:
  - taps and jitter taps, the 300 ms edge, a late timer;
  - slop cancel, slow tap, release with no inertia;
  - ⌘/⌃/fn blocking, non-arrow keys ignored;
  - dead zone, leading edge, axis lock and release;
  - the rate curve with the board's values, steps growing with distance,
    the burst cap, all four directions;
  - the word/paragraph switch and its hysteresis, ⇧ selecting, ⌥ words,
    ⌥⇧ (board j2: `24/S · WORD`);
  - terminal history rates and labels, terminal detection;
  - the haptic throttle (15/s at 30 steps/s);
  - trail shape and projection, lit share growing with speed;
  - VoiceOver stepper chords and units.
- `DeckHand/Scripts/linux-typecheck/run.sh`: passes, also with
  `DeckHandiOS/Keyboard/TypingTarget.swift` added. The SwiftUI files
  (`ArrowJoystick.swift`, `TypePanel.swift`) can't be type-checked on
  Linux. They pass `swiftc -parse`.
- **UI walk `test27_ArrowJoystick`** (needs a paired Mac):
  1. Opens the Type panel and checks that each arrow is its own hittable
     button and that "Move the caret" exists.
  2. Holds → for 0.6 s, drags 30 pt left and holds 1 s, then does the same
     with a 110 pt drag. Asserts both ran the joystick
     (`ph.type.joystick.last` = `joystick N`), that the short one sent at
     least 3 presses, and that the long one sent more.
  3. Taps ← and asserts `tap left`. Screenshots at each step.

  The presses are ←/⌥← in the Mac's front app, so the caret moves and
  nothing is typed.

## iPad checks (on device)

1. **Tap:** tap each arrow quickly in TextEdit. It sends one arrow, with no
   accent flash or trail, and the cap dims for the press as before. Tap
   with ⇧ latched: it selects one character.
2. **Hold and drag**, inverted T, iPad Air 11" landscape and portrait:
   - Hold → for 300 ms: a light tap, then the cap goes accent with the
     centre dot.
   - Drag right slowly: about 4/s near the cap, faster further out, and
     the readout climbs to `30/S`.
   - Past about 60 pt, `WORD`: the caret jumps by words.
   - Release: it stops dead and the trail fades.
3. **Axis lock:** drag right, wander up and down a little (still ←/→ only),
   come back to the cap, then drag down (↑/↓, `LINE`, then `PARA`).
4. **One-row cluster** (resize the panel to its shortest): any cap anchors
   the same way, and the trail can run over the field and keys.
5. **⇧ latched:** the trail turns accent, the selection grows with ⇧→ /
   ⌥⇧→, and the once-latched ⇧ goes off on release. **⌥ latched:** words
   from the start. **⌘ latched:** a long press is just ⌘→ once.
6. **Terminal.app and iTerm2:**
   - ←/→ move along the line.
   - Drag ↑: `HISTORY` on the caps and the readout, stepping through
     history at 2–8/s, never ⌥↑.
   - Check that ⌥←/→ jump words there (Terminal maps it by default;
     iTerm2 depends on the profile).
7. **Haptics:** steps tick at most 15/s at full speed, and the Settings
   haptics strength scales them.
8. **Reduce Motion on:** the trail vanishes on release, with no fade.
9. **VoiceOver:**
   - Swipe through the caps (Up, Left, Down, Right, each its own button),
     then "Move the caret, adjustable".
   - Swipe up and down moves the caret. The actions rotor offers By words
     and the other units.
   - Each arrow has "Move by words" or "Move by paragraphs".
10. **Full Keyboard Access / pointer:** Tab to an arrow and press Space:
    one arrow. A click-hold-drag with the trackpad pointer also runs the
    joystick.
11. **iPhone** (panel docked top or bottom): same as 2, with the trail
    staying readable at the panel's edges.

## Compile risks (unverified on the Mac)

1. **`highPriorityGesture(DragGesture(minimumDistance: 0))` on a
   `Button`.**
   - Expected: touches go to the gesture, so the Button's own tap never
     fires, while VoiceOver and Full Keyboard Access activation still call
     the Button's action.
   - If a touch tap *also* fires the Button (double arrow), change the
     arrow caps to a non-Button view with `.accessibilityAddTraits(.isButton)`
     and `.accessibilityAction { press(key) }`.
2. **`Task { @MainActor in … }` in `ArrowJoystickGesture.onChange`**
   captures the modifier's `self` (a View, MainActor). It should be fine
   under Swift 6 with the iOS 18 SDK.
3. **`zIndex` inside the custom `PanelBodyLayout`**: SwiftUI layouts
   honour `zIndex` for drawing order. If the trail still draws under the
   key block, move `ArrowJoystickOverlay` to an `.overlay` on the
   `PanelBodyLayout`.
4. **`Color.clear` as an accessibility element** (`CaretStepperElement`).
   If VoiceOver skips it, swap it for `Rectangle().fill(.clear)`.
5. **`ArrowJoystickOverlay`'s 440 pt `Canvas`** is offset −220 pt inside
   the cluster's frame (it draws past the cluster). The `KeyGrid` frame
   doesn't clip, and the panel has no `clipShape`.
6. **`@ViewBuilder arrowButton` with `let`s** inside an `if case`:
   supported since Swift 5.4.

## Coordination

- **Live-sync lane** (`claude/pixelhand-lane-live-sync`), in parallel:
  - `LiveTypingField`, the loupe and sync are untouched here.
  - Likely touch points are `TypingTarget.swift` (two added members,
    `frontBundleID` and `isTerminal`) and `TypePanel.swift`'s
    field/actions blocks (this lane changed only the arrow cluster,
    `keyButton` and `KeyCap`).
  - If that lane adds `input.caretMove`, point `sendJoystickStep` at it
    and keep the Core rate (the Mac coalesces).
  - In synced fields the iPad caret follows the Mac's reported selection,
    with nothing more to do here.
- Out-of-lane edits: `ControlSessionModel.swift` (one line) and
  `PixelHandUITests.swift` (launch argument and new test).

Lane: READY TO MERGE
