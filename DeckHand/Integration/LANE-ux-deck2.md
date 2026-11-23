# Lane: UX-020 Deck 2 UI (D2 deck surface, D3 editor)

Branch `claude/pixelhand-lane-ux-deck2`, cut from
`origin/claude/pixelhand-integration` at `f1763b7`, with the latest
integration (`92126e3`) merged in before handoff. **No protocol change**:
protocol 12 as before.

Written in a Linux container. Core was built and tested here (Swift 6.2,
**651 tests pass**, 72 of them in the deck suites, 29 new). `DeckSurfaceModel`
type-checks against the stubs (`Scripts/linux-typecheck/run.sh`, now in its
default list). **The SwiftUI files were not compiled**: they were checked by
reading them against the repo's APIs. The owner's Xcode build is the first
compile.

## 1. What changed

### The Deck tab (D2)

The shell's Deck tab (and the wide layout's deck column) now shows the
deck from `DeckStore`, not the old app grid. The classic layout
(`ControlView`) still shows `StreamDeckGridView`, unchanged.

- **Pages**: Home, then Context, then the app pages and the user's pages.
  Swipe between them, or tap the page dots under the grid. The header shows
  the page's app icon (app pages) or a pixel glyph, its title, a line like
  "Follows the front app · page 2 of 5", the dot-matrix `PageCounter`
  (`02/05`), the pin and **Edit**.
- **Follow front app**: `DeckFollower` (400 ms debounce) driven by the
  Mac's frontmost app; it goes back to your page when the app leaves. The
  pin stops it (stored in the deck). Following pauses while editing.
- **Grid**: `DeckGrid.pane` gives whole-point keys: 4 / 5–6 columns by
  width, 3 × 96 in the 336 pt deck column (and in Slide Over), 3 columns at
  AX1–AX2, and `DeckKeyRow` rows at AX3+.
- **Keys**: the design system's `DeckKey`. Glyphs come in this order: the
  user's 8 × 8 drawing, then a glyph from the 9 × 9 set, then the app's real
  icon (launch keys), then the chip's SF Symbol mapped onto the set
  (`DeckGlyphs.symbolMap`; migrated chips draw as pixels), then the
  action's own glyph. A key shows its chord (`⇧⌘K`, "3 steps"), a `?` corner
  for Ask before running, and its colour (Cobalt, Navy as the system key,
  Mint, Violet, Glow). The delivery dots come from the Mac's receipt
  (`sendConfirmed` → `DeliveryTracker`).
- **App pages** show the curated presets you haven't hidden, then the
  stored keys. **Context** shows the open dialog's buttons first (Save is
  navy, Cancel has the close glyph; they run once and are never stored),
  then the front app's keys. A deck without a Context page gets one after
  Home the first time the Deck shows (not on the free plan).
- **Long-press a key**: Edit Key, Ask Before Running, Pin to First Row,
  Duplicate, Remove (Hide for a curated preset).
- **Empty page**: a navy dot-art empty state with "Add keys".
- **Mac locked**: the deck dims; keys still send (the Mac refuses menu
  commands and Shortcuts while locked).
- **Free plan**: the Deck is a dimmed, disabled preview with an inline card
  (PRO in dot-matrix type, "Decks follow the app in front", **Try 2 weeks
  free** opens the paywall, **Not now** folds it into a "Decks · Pro"
  button). Board "Free tier". Pointer is never blocked.

### The editor (D3)

- **Edit mode**: dotted keys with remove badges; tap a key to open the
  inspector; drag a key onto another to reorder (stored keys; curated
  presets stay first); VoiceOver gets "Move earlier" and "Move later". The
  ghost **Add key** key opens the action library. The header has **Undo**
  (⌘Z), the title, a page menu (Redo; New Page; Page for the app in front;
  Context and Shortcuts pages if missing; Rename; Follow Front App; Delete
  Page) and **Done**.
- **Undo / Redo**: `DeckUndoHistory` (50 steps) of whole deck snapshots,
  for every edit while editing. Cleared on Done.
- **Action library**: "Make your own" lists every storable kind of action
  (key press, key press in an app, **menu command**, open an app, Mac
  action, media key, **Mac Shortcut**, **sequence**) and opens the
  inspector. Below that come the front app's imported chips as menu
  commands ("File › New Tab"), the app's presets, the Mac actions, the
  media keys and every app on the Mac. These are added in one tap. Search
  covers all of them. Dialog presses aren't offered because they can't be
  stored.
- **Key inspector**: a live key preview, the label, the glyph (**Glyph**
  is a picker of the 40 set glyphs, **Pixels** is the 8 × 8 editor and
  **App icon** is the app's icon), the colour, and the action. The action
  section has a kind picker plus that kind's fields: ⌘ ⇧ ⌥ ⌃ toggles and
  a key, an app picker, a menu path typed as `File › Export › PDF…`, a
  Shortcut name, or the sequence editor. The sequence editor has steps
  you can add, reorder and delete, each step's action, and pauses in
  0.1 s steps. Below come Ask before running and Pin to first row.
  Problems show in plain words (`DeckValidation.keyIssues` →
  `inspectorMessage`) and turn off Save.
- **8 × 8 pixel glyph editor**: tap a dot or drag to paint; the first dot
  you touch decides whether the drag draws or erases. An Accent tool marks
  the glowing dot. Mirror, Move (up, down, left, right), Start from (any
  set glyph, cropped to 8 × 8), Clear and its own Undo. A live preview
  at key pitch, a dot-matrix count of lit dots, and the "strokes one dot
  wide" warning, which never blocks saving.

### Files

| File | What |
| --- | --- |
| `Core/…/Deck/DeckPresentation.swift` | `DeckGlyphs` (resolve, symbol map, action glyphs), `PixelGlyphData` → `GlyphBitmap` and editor ops, `Action.chordText` / `summary`, `SystemMacro.title`, `MediaKey.title`, `DeckShownKey` + `shownKeys(on:frontBundleID:dialog:)`, `orderedPages`, `addingStandardPages`, `displayTitle`, `deckStyle(for:)`, `deckGrid(for:)`, `DeckGrid.pane` |
| `Core/…/Deck/DeckEditing.swift` | Page and key edits (add, rename, delete, pin, add/update/remove/duplicate/move/nudge keys; editing a curated preset stores a copy and hides the preset), `DeckKey.draft(for:)`, `DeckUndoHistory` |
| `Core/…/Deck/ActionLibrary.swift` | `ActionKind`, `ActionPreset`, `ActionLibrary.sections/filter`, `Action.converted(to:)`, `ChordParsing`, `MenuPathText`, inspector copy for validation issues |
| `Core/Tests/…/DeckUITests.swift` | 29 tests |
| `DeckHandiOS/Surfaces/DeckSurface.swift` | The Deck tab |
| `DeckHandiOS/Deck/DeckSurfaceModel.swift` | Follow, pin, edit mode, undo/redo (shared) |
| `DeckHandiOS/Deck/DeckKeyButton.swift` | A key from the model, its receipt and Ask-first confirmation; `DeckKeyTint`, `DeckKeyFace` |
| `DeckHandiOS/Deck/ActionLibrarySheet.swift` | The action library |
| `DeckHandiOS/Deck/KeyInspectorSheet.swift` | The inspector, `ActionFields`, the chord, menu path and sequence editors |
| `DeckHandiOS/Deck/PixelGlyphEditor.swift` | The 8 × 8 editor |

`QuickActionsBar`, `QuickActions/**`, `StreamDeckGridView`,
`AppShortcutsSheet` and `DeliveryDots` are unchanged. The context strip
still reads `ShortcutStore.bindings(for:)`, which reads the same deck, so a
key added on an app page shows as a chip, and the reverse.

## 2. iPhone / iPad checks

Install the iOS build (the Mac build is unchanged; any protocol 12 Mac).
Use a Pro account or the StoreKit config's trial, except in check 9.

1. **Migrated chips appear as keys.** On a device that had chips before
   Deck 2: open the Deck tab. Home has launch keys with the real icons of
   the apps that were pinned in the grid. Swipe to an app page (Safari,
   Xcode): its curated presets come first, drawn as pixel glyphs, then your
   custom and imported chips. A preset you hid is still hidden. Tap a key:
   the Mac runs it and the dots go mint.
2. **Follow and pin.** Cmd-Tab on the Mac between two apps that have pages.
   About 0.4 s later the deck shows that app's page with its icon and
   "Follows the front app". Switch to an app with no page: it goes back to
   the page you were on. Tap the pin: "Pinned", and switching apps no
   longer moves it. Tap it again to unpin.
3. **Create a page.** Edit → ••• → New Page: a "Page N" appears and shows,
   with the empty state. ••• → Rename. ••• → "Page for Safari" (with Safari
   in front). The page dots and `03/05` counter update. ••• → Delete Page
   asks first. Undo brings it back.
4. **Edit a key.** In edit mode tap a key: the inspector opens. Change the
   label and colour, choose a set glyph, then Save: the key updates. Turn on
   Ask before running: the key shows `?`, and tapping it (out of edit mode)
   asks "Run “…”?". Drag one key onto another to reorder. Remove a key with
   its badge.
5. **Menu-command key.** Add key → Menu command. Pick Safari, type
   `File › New Private Window`, then Add. Tap the key: Safari comes forward
   and opens a private window; the dots go mint. Change the path to
   `File › Nope`: the dots go red. The front app's imported chips also
   appear in the library under "… menu commands".
6. **Sequence key.** Add key → Sequence. The template opens TextEdit (pick
   TextEdit as the app in step 1), pauses 0.5 s and presses ⌘N. Add a step
   (Menu command: `Format › Make Plain Text`), reorder with Edit, change
   the pause with the stepper, then Add. The key shows "3 steps" (or 4). Tap
   it: TextEdit opens with a new plain-text document. The dots show
   delivered or confirmed.
7. **Mac Shortcut key.** Add key → Mac Shortcut. Save stays off with "Type
   the Shortcut’s name…". Type an existing shortcut's name, then Add. Tap
   the key and the shortcut runs on the Mac.
8. **Glyph editor and undo.** Inspector → Pixels. Draw with a finger; a
   drag that starts on a lit dot erases. Use Accent and tap a dot: it
   glows. Mirror, Move → Left, Start from → Build. Draw a 2 × 2 block: the
   one-dot-wide warning shows and Save still works. The editor's Undo steps
   back through the strokes. Save: the key draws your glyph at key pitch.
   Then, in edit mode, Undo in the header steps back through the deck
   edits (glyph, then label, …) and Redo is in the ••• menu. Done clears
   the history.
9. **Free tier lock.** Without Pro (StoreKit config: expire or cancel the
   subscription): the Deck tab is a dimmed, grey preview and can't be
   tapped. The card reads "Decks follow the app in front". Try 2 weeks free
   opens the paywall; Not now folds it into "Decks · Pro". Pointer and
   Screen work as before. Buying Pro unlocks the deck in place.
10. **Context page and dialogs.** On the Mac, open a document and press ⌘W
    with unsaved changes. The Context page shows Don’t Save / Cancel / Save
    keys first (Save is navy). Tap Save: the dialog closes. Then the front
    app's keys follow.
11. **Layouts.** iPad landscape: the deck column shows 3 keys of 96 pt.
    iPad portrait and iPhone landscape: Deck tab, 5–6 and 4 columns. Set
    Dynamic Type to AX1: 3 columns. Set AX3: rows with the glyph, label and
    chord. VoiceOver reads a key as its label with the action as its hint;
    page dots read the page names.

## 3. Compile risks (most likely first)

1. `KeyInspectorSheet.swift`: the generic `Form` sections, `ChordField` /
   `MenuPathField` returning two views from `body`, and `SequenceEditor`'s
   `ForEach(...).onMove/.onDelete` inside a `switch`. If the type checker
   gives up ("unable to type-check this expression"), split
   `glyphSection` / `ActionFields.body` into smaller computed views.
2. `DeckSurface.swift`: `.sheet(item:)` and `.alert` / `.confirmationDialog`
   chained on a `GeometryReader`, and the `TabView(selection:)` binding to a
   `String` tag. Also the `ReorderModifier` `dropDestination` closure (Swift
   6 isolation of the haptic and `onDrop` calls, if the SDK marks the
   closure `@Sendable`).
3. `DeckKey` name clash: the app's view `DeckKey` vs Core's model. The new
   files write `PixelHandCore.DeckKey` for the model. If the module
   qualifier isn't visible through `@_exported import`, the files already
   `import PixelHandCore` explicitly.
4. `DeckKeyButton.swift`: `DeckKey(... icon:tint:onRemove:action:)`
   memberwise order after the new `icon` / `tint` properties (added between
   `delivery` and `onRemove`).
5. `PixelGlyphEditor.swift`: the `Canvas` closure captures only local
   copies (Sendable). `DragGesture` state updates are on the main actor.
6. `DeckSurfaceModel.swift`: type-checked here against stubs; the real
   Combine `@Published` with a `didSet` should be fine.

## 4. Out-of-lane edits

- `DeckHandiOS/Shell/PixelHandShell.swift` (UX arrangements / shell):
  `deck(sender:)` now returns `DeckSurface(session:sender:)` instead of
  `StreamDeckGridView(...)` (one line, marked `// Deck 2 UI lane (UX-020)`).
  This is the swap the shell left for this lane; the classic layout is
  untouched.
- `DeckHandiOS/DesignSystem/DeckKey.swift` (design foundation): `DeckKey`
  and `DeckKeyRow` gained optional `icon: Image?` (draws an app icon
  instead of the glyph) and `tint: Color?` (the glyph colour). Defaults
  keep every existing call working.
- `Scripts/linux-typecheck/run.sh` (shared tooling): `DeckSurfaceModel.swift`
  added to the default list.

## 5. Follow-ups

- **UX-021 Suggest a deck**: ghost keys already exist (`DeckKey(kind:
  .ghost)`). Show suggestions as `DeckShownKey`s with a new `.suggested`
  source in a panel under the grid (board "Deck": "3 suggestions from
  Xcode’s menus", Keep all). `DeckDocument.addKey` and `DeckUndoHistory`
  cover "Keep" and its undo.
- **D4 Shortcuts page**: the page exists and is empty. Fill it from a Mac
  `shortcuts list` message (a protocol change), as `macShortcut` keys.
- **Move the app grid onto the deck**: the old grid's pinned/hidden apps
  still live in `StreamDeckGridView`'s `@AppStorage` (only the classic
  layout uses it now). Drop those keys when the classic layout goes.
- **Multi-Mac "Run on…"** (spec §2 Deck long-press) waits for 1.3.
- The 8 × 8 editor can grow to 9 × 9 without a schema change
  (`PixelGlyphData.size`). The editor's grid follows `glyph.size`.
- A per-key "running…" state for sequences longer than 1.2 s would need a
  progress receipt (a protocol change). Today they show `delivered`.
- Keys can't be dragged from one page to another yet (Duplicate + Remove
  works).

Lane: READY TO MERGE
