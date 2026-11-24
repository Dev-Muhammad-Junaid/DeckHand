# Lane: Ask (UX-022, backlog A1)

Branch `claude/pixelhand-lane-ask`, merged with
`origin/claude/pixelhand-integration` at `0114c91` (already up to date).

Ask turns a typed or dictated request into a numbered plan of typed steps.
The person can edit the plan, then **Run** it or **Save as key**. Nothing
runs before the plan shows. Destructive and typing steps ask once more.
Planning happens on the device with Foundation Models when Apple
Intelligence is available. Otherwise a deterministic parser in Core makes
the plan. There's no cloud, no Private Cloud Compute and no protocol change
(still protocol 12). Ask is Pro.

## 1. What changed

### Core (`Core/Sources/PixelHandCore/Assist/`)

- **`AskPlan.swift`:**
  - `AskStep` is one of: `.action(Action)` (any existing case, Deck 2
    included), `.typeText(String)`, or `.delay(milliseconds:)`.
  - `AskPlan` holds the request, the steps, notes and a source
    (`onDevice`, `parser` or `edited`). It can remove, move, replace and
    append steps.
  - **`AskPlanValidation`:**
    - A plan has 1–20 steps.
    - Each action must pass `ActionValidation` with `storable: true`.
      Dialog presses and nested sequences are refused.
    - Typed text is limited to `TypingPolicy.maxMessageBytes`.
    - Delays are limited to the sequence limits.
  - **`AskSafety`:** decides which steps ask before running:
    - typing text;
    - ⌘Q and ⌘W;
    - ⌘⌫ (deletes);
    - ⌃⌘Q (lock) and ⇧⌘Q (log out);
    - ⌥⌘⎋ (Force Quit);
    - menu items whose titles start with Quit, Close, Log Out, Shut Down,
      Restart or Lock, or contain Delete, Trash, Erase, Discard, Revert or
      Remove;
    - any Mac Shortcut.

    It also writes the confirmation message, for example "This plan quits
    an app and types on Studio."
  - **Save as key:** `savedAction` is the single action, or a `.sequence`
    of every step. A plan with typed text can't be saved, because
    `SequenceStep` has no text case. Adding one would be a protocol change.
- **`AskVocabulary.swift`:**
  - `ChordParser` reads chords written many ways: "cmd shift p", "⌘⇧P",
    "Control-Command-F", "Command+T", "page down". The result is the wire
    names that `KeyTable` accepts.
  - `AskAppCatalog` maps app names to bundle IDs. It checks the Mac's
    installed apps first, then aliases ("chrome", "vs code", "settings"),
    then a built-in list of about 35 common apps, then a prefix match.
- **`AskCommandParser.swift`**, the deterministic planner:
  - **Splitting:** it splits on commas, `;`, `.`, "and", "then" and "after
    that". Quoted text is never split.
  - **Grammar:**
    - open or quit an app;
    - press a written chord;
    - about 60 everyday app commands (new tab, reload, select all, zoom
      in…). These go to the app named earlier in the request as
      `appShortcut`;
    - media keys;
    - system actions (Mission Control, Show Desktop, App Windows,
      Launchpad, Find Pointer), plus lock, log out, screenshot, Spotlight,
      the emoji picker and the app switcher;
    - "type …" / "write …";
    - "run the shortcut X";
    - "wait N seconds";
    - "go to apple.com" (⌘L, then the address and Return);
    - "File > Export > PDF in Pages".
  - **Typed text:** a later clause that is itself a command ends the text
    ("type hi and press return"). Anything else stays in the text ("type
    salt and pepper").
  - **Unsupported requests** become notes, never guesses: volume or mute,
    brightness, sleep, shut down and restart. Anything unrecognised becomes
    "Didn't understand …".
- **`AskPlanDraft.swift`:**
  - `AskDraftStep` is the model's flat, string-typed step.
  - `AskPlanResolver.resolve` turns draft steps into real steps using the
    parser's vocabulary. It drops invented apps, fake chords, unknown kinds
    and invalid menu paths, each with a note. It clamps waits, then runs
    `AskPlanValidation` again and removes any step that still fails.
- **`AskPlan+Deck.swift`:** `DeckDocument.saveAskPlan` chooses the page:
  - a plan that talks to exactly one app goes on that app's page, created
    if it's missing;
  - any other plan goes on Home, or on the first custom page with room.

  A plan with a destructive step is saved with "Ask before running" on.
- **Tests:** `AskPlannerTests.swift` adds 28 tests in 5 suites.
  `swift test --package-path DeckHand/Core` → **730 tests in 130 suites
  pass**. `Scripts/linux-typecheck/run.sh` → **Build complete**, now
  including every file in `DeckHandiOS/Assist/`.

### iOS

- **New `Assist/OnDeviceModel.swift`:** the code shared by both AI
  features:
  - `isAvailable`: iOS 26 and `SystemLanguageModel.default.isAvailable`;
  - `withDeadline`.

  `OnDeviceDeckRanker` (from the suggest lane) now uses it instead of its
  own copy. Its behaviour is unchanged.
- **New `Assist/OnDeviceAskPlanner.swift`:**
  - It uses guided generation: `@Generable AskProposal { steps:
    [AskProposalStep] }`. Each step has `kind`, `app?`, `keys?`, `text?`,
    `menuPath?` and `seconds?`.
  - The prompt lists the step kinds, up to 60 of the Mac's app names and
    the front app. The timeout is 10 s.
  - On any error or timeout it returns `nil`.
- **New `Assist/AskModel.swift`** (no SwiftUI, Linux type-checked):
  - **Planning:** it uses the on-device plan when the model returns at
    least one valid step. Otherwise it uses `AskCommandParser`.
  - **Running:**
    - Steps run in order. Actions go through `sendConfirmed`, which is
      `deck.run` with a receipt. Text goes through `typeText`, in chunks.
      Delays wait.
    - It waits 0.7 s after opening an app and 80 ms after any other step.
    - It stops at the first step that fails or times out.
    - Before every step it checks `macLockState`. If the Mac is locked, it
      stops with "<Mac> is locked…".
  - **Save as key:** saving through `DeckSurfaceModel.edit` is one undo
    step in the deck editor.
- **New `Surfaces/AskSheet.swift`**, following the board's "Ask" screen:
  - **Title:** "Ask <Mac>" with the Ask glyph. An "On device" pill shows
    while Apple Intelligence can plan.
  - **Field:** "Tell <Mac> what to do". It has an arrow button, and Return
    submits. The person can speak with the keyboard's mic.
  - **Before a request:** "Try" chips with example requests.
  - **While planning:** a dot scan over the plan area.
  - **The plan:**
    - The label reads "Plan · N steps on <Mac>", with " · Apple
      Intelligence" or " · edited" added when that applies.
    - Each step shows its number, a summary, a chord chip (or "menu"), and
      "Asks first" when it will ask. After a run it shows a check or a
      cross.
    - Steps that don't validate show in red.
  - **Buttons:** **Run**, **Save as key**, and **Edit / Done**. While a
    plan runs, **Stop** replaces Run.
  - **Edit:** move a step up or down, remove it, edit typed text, and
    "Add step" (Type text, Press Return, Wait 1 second, Play/Pause).
  - **Confirmation:** a `confirmationDialog` titled "Run this plan on
    <Mac>?" with the `AskSafety` message. Its Run button is destructive
    unless the only reason is typing.
  - **Locked Mac:** the lock banner shows and Run is disabled.
  - **Free tier:** the sheet shows a Pro card with "Try 2 weeks free",
    which opens `PaywallView(reason: .feature(.ai))`. In the free plan
    there is no planner, no field and nothing to send.

## 2. Checks (iPhone and iPad, Pro build unless a check says otherwise)

Open Ask in any of these ways: the Ask circle in the tab bar, the Ask
field (iPad landscape), the circle beside the dock (iPad portrait), or
**⌘K** on a hardware keyboard.

### Ten example requests

Run each request **twice**:

- **With Apple Intelligence:** iOS 26+, AI on. The "On device" pill and
  "· Apple Intelligence" show.
- **Without it:** an iOS 17/18 device, or AI turned off in Settings. There's
  no pill, and the deterministic plan below must match exactly.

With Apple Intelligence, the plans may be worded or ordered differently,
but every step must be a real app, chord or action, and nothing runs until
you tap Run.

| # | Request | Plan without AI | Asks first |
| --- | --- | --- | --- |
| 1 | Open Safari and make a new tab | Open Safari · ⌘T in Safari | no |
| 2 | mute and lock | ⌃⌘Q, plus the note "can't change the Mac's volume yet" | yes (locks) |
| 3 | paste my last screenshot | ⌘V, plus a clipboard note | no |
| 4 | press cmd shift p | ⇧⌘P | no |
| 5 | pause the music, then next song | Play/Pause · Next Track | no |
| 6 | show mission control then show desktop | Mission Control · Show Desktop | no |
| 7 | open Notes and type Hello World and press return | Open Notes · Type "Hello World" · ↩ in Notes | yes (types) |
| 8 | quit Slack | ⌘Q in Slack | yes (quits) |
| 9 | run the shortcut <one of your Shortcuts>, wait 2 seconds, then go to apple.com | Run the Shortcut · Wait 2 s · Open Safari · ⌘L in Safari · Type "apple.com↩" | yes |
| 10 | choose File > Export > PDF… in Pages | Menu › File › Export › PDF… in Pages | no |

Also try "fly me to the moon": there are no steps, the note says "Didn't
understand…", and Run is disabled.

### The other checks

1. **Run:**
   - Request 1 opens Safari on the Mac and opens a new tab.
   - Each step gets a check, and the footer reads "Ran 2 steps on <Mac>."
   - The current step's number is lit while it runs.
2. **Edit a plan:**
   - For request 7, tap Edit and change the typed text.
   - Move ↩ above the Type step, then back.
   - Remove a step.
   - Add step › Wait 1 second.
   - Tap Done. The label shows "· edited", and Run uses the edited plan.
3. **Save as key:**
   - **Request 1:** "Saved as a key on Home." A Home key labelled "Open
     Safari and make a new tab" runs the macro.
   - **"reload the page in Safari":** the key lands on Safari's app page,
     which is created if it's missing.
   - **Request 7:** saving is refused with "Keys can't type text yet…".
   - **Undo:** in the deck editor, Undo removes the saved key.
   - **Request 8:** the saved key has "Ask before running" on.
4. **Confirmation:**
   - Request 8 shows "Run this plan on <Mac>?" with "This plan quits an
     app." and a red Run. Cancel sends nothing.
   - Request 7 says "types on <Mac>", and its Run button isn't red.
5. **Locked Mac:**
   - Lock the Mac. The sheet shows the lock banner and Run is disabled.
   - Unlock the Mac: Run comes back.
   - Lock the Mac during request 9's wait: the run stops with "<Mac> locked
     at step N".
   - The Mac's log shows the gate refusing anything that was already in
     flight.
6. **Free tier:**
   - Sign out of Pro, or let the trial expire in the StoreKit config.
   - Opening Ask shows the Pro card with no field. "Try 2 weeks free" opens
     the paywall.
   - Buy Pro: the field appears.
7. **The Mac doesn't answer:** quit the Mac app mid-run. That step's
   receipt times out, the footer says it "wasn't confirmed", and later
   steps don't run.
8. **A host without receipts:** on a Mac build without receipts, actions
   send without confirmation, and the Deck 2 steps (menu, Shortcut) fail
   the way deck keys do.
9. **Airplane mode** with AI on: planning still works, because it runs on
   the device.

## 3. Compile risks (most likely first)

1. **`OnDeviceAskPlanner.swift`, Foundation Models guided generation:**
   - `@Generable` on a struct with **optional** properties (`String?`,
     `[String]?`, `Double?`) and a nested `@Generable` array.
   - `@Guide(description:)` on each property.
   - `session.respond(to:generating:)` and `response.content.steps`.
   - **If optionals aren't accepted:** make them non-optional with empty
     defaults ("" / [] / 0). `AskPlanResolver` treats empty values the
     same as missing ones.
   - **If it won't compile at all:** change `makeIfAvailable()` to return
     `nil`. Ask still works fully with the parser.
2. **`OnDeviceModel.withDeadline`:**
   - It's generic over `T: Sendable` and takes an `@escaping @Sendable`
     closure that returns `T?`.
   - Both wrappers pass closures that capture `prompt`, `limit` and
     `request` (all Sendable).
   - **If Swift 6 complains** about the generic task group, inline it back
     into each wrapper as before.
3. **`AskSheet.swift`, SwiftUI that Linux can't check.** In order of
   likelihood:
   - `ToolbarItem` inside an `if` in `.toolbar`.
   - `TextField(..., axis: .vertical).lineLimit(1...4)`.
   - `Button("Run", role: cond ? nil : .destructive)`.
   - `DotScan(columns:rows:pitch:plateCornerRadius:platePadding:)`, the
     memberwise init.
   - The `Binding(get:set:)` text field for typed steps.
4. **Weak linking FoundationModels on iOS 17.4:** this is the same risk as
   in the suggest lane. If an iOS 17/18 device crashes at launch with
   "Library not loaded: FoundationModels", add `OTHER_LDFLAGS:
   -weak_framework FoundationModels` to DeckHandiOS in `project.yml`.
5. **Behaviour, not a compile risk: launch timing.** The 0.7 s pause after
   Open App might be short for a cold launch before a Type step. App
   shortcuts aren't affected, because `appShortcut` activates and waits on
   the Mac. If typing lands in the wrong app, raise
   `AskModel.afterLaunchPause`.

## 4. Out-of-lane edits

- **`DeckHandiOS/Shell/PixelHandShell.swift`:** 1 line. The Ask sheet
  presents `AskSheet(session: session, macName: peerName)` instead of
  `AskPlaceholderSheet`. `AskPlaceholderSheet.swift` is now unused and
  left in place for the shell lane to delete.
- **`DeckHandiOS/Shell/SurfaceTabBar.swift`:** 1 line.
  `.keyboardShortcut("k", modifiers: .command)` on the Ask circle, so ⌘K
  also works in the tabbed layouts (iPad Split View or Slide Over with a
  keyboard). `AskField` and `AskCircleButton` already had ⌘K.
- **`Scripts/linux-typecheck/run.sh`:** 1 line, adding
  `DeckHandiOS/Assist/*.swift` to the default list.
- **`DeckHandiOS/Assist/OnDeviceDeckRanker.swift`** (from the suggest lane,
  in Ask's `Assist/**`): now uses the shared `OnDeviceModel`. Its behaviour
  is unchanged.
- **No changes** to Intents, Macs, `ContentRootView`, the sidebar, the Mac
  app or the protocol.

## 5. Follow-ups

- **Paired-Mac planner** (between on-device and the parser,
  `DECISIONS.md`): this isn't cheap. It needs a `DeckMessage` that plans
  on the Mac, which is a protocol change (13), plus a Mac handler.
- **Mute and volume:** `MediaKey` has no mute or volume case. Adding them
  is a protocol change, plus NX system-defined events in the Mac's
  `InputHandler`. Until then the parser says so in a note.
- **Typed text on keys:** a `SequenceStep.typeText` case (a protocol
  change) would let typing plans be saved as keys.
- **"Run simple commands without asking"** (`04-Interaction-Model.md`
  §3), **Run on…** across several Macs (M3), and **A2/A3** (Ask about a
  capture, reading the screen through Accessibility) aren't built.
- **Siri and App Intents** can reuse `AskCommandParser` and
  `AskPlanResolver` once the Intents lane lands.

Lane: READY TO MERGE
