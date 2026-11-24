# Lane: UX suggest (UX-021, backlog D7, "Suggest a deck")

Branch `claude/pixelhand-lane-ux-suggest`, merged with
`origin/claude/pixelhand-integration` at `f04976c`. This is the first AI
feature. Under an app page's deck grid, and under the Context page's grid
for the front app, a suggestions panel offers ghost keys built from that
app's real menus. The deterministic ranking is the whole feature. Apple's
on-device Foundation Models can reorder that ranking, but only by picking
from the candidates. There's no cloud, no Private Cloud Compute and no
protocol change.

## 1. What changed

### Core (`Core/Sources/PixelHandCore/`)

- **New `Assist/DeckSuggestionRanker.swift`:**
  - `DeckSuggestion` holds one binding and its score. Its `key` is the
    `appShortcut` key that Keep stores. The key's label is the menu item's
    own name ("Show Minimap", not "Editor › Show Minimap"), and the key's
    category is the menu.
  - `DeckSuggestionRanker.rank(_:bundleID:existing:limit:)` is the
    deterministic fallback. Scores, highest weight first:
    - **Well-known deck commands score up:** Build, Run, Test, Open
      Quickly, New Tab, Reload Page, New Folder, Go to Folder, Show
      Sidebar, and so on.
    - **Generic text editing scores down:** Copy, Paste, Undo, Select All.
    - **Never suggested:** Quit, Hide, Minimize and "Quit/Hide <App>". A
      Hide that targets a pane is still allowed (Hide Sidebar, Hide
      Toolbar).
    - **Menu frequency:** menus the user already keeps keys from for this
      app score up. Below that is a fixed weight per menu: the app's own
      menus (Product, Debug, History…) over File/View, over Edit/Format,
      over Window/Help.
    - **Shortcut weight:** each modifier beyond ⌘ adds a little, because
      those chords are harder to remember.
    - **Arrow and page keys** score down a little.
  - Candidates are de-duplicated against the page's existing keys by ID,
    by name+chord, and by chord alone (⇧⌘K matches ⌘⇧K). They are also
    de-duplicated against each other and against other apps' bindings. The
    list is capped at `maxSuggestions` = 24, the spec's maximum. Equal
    scores keep menu order, so the ranking is deterministic.
  - `applyingModelPicks(_:to:limit:)` puts the model's picks first. Picks
    are indices into the candidates, and indices that don't exist or
    repeat are dropped. The rest follow in ranked order. **A model can
    reorder, never add.** `promptLines(for:)` builds the numbered prompt.
  - `DeckSuggestionCopy` holds the panel copy: "3 suggestions from Xcode’s
    menus", "Reading Xcode’s menus…", "No new keys in Xcode’s menus", "The
    Mac didn’t send the menus. Try again.", "Kept 3 keys".
  - `DeckDocument.keepSuggestions(_:forApp:title:)` creates the app page
    if it's missing, appends the keys, skips duplicates and stops at a full
    page. A key whose ID is already used on another page gets a new ID, so
    the deck stays valid. `DeckDocument.existingKeys(forApp:)` returns
    what the app page shows, or only the curated presets when there's no
    page yet.
- **`Deck/DeckPresentation.swift`:** new `DeckShownKey.Source.suggested`.
  It isn't editable.
- **Tests:** `DeckSuggestionTests.swift` adds 20 tests in 4 suites.
  `swift test --package-path DeckHand/Core` → **681 tests in 121 suites
  pass**. `Scripts/linux-typecheck/run.sh` → **Build complete**, now
  including `DeckSuggestionsModel.swift`.

### iOS

- **New `Deck/DeckSuggestionsModel.swift`** (no SwiftUI, Linux
  type-checked). A shared model keeps state per app (phase, ranking,
  order), so an app page and the Context page can each show their own
  panel.
  - **Loading:**
    - It sends `TrackpadSender.requestMenuShortcuts`, which is the
      existing `deck.requestAppMenuShortcuts` → S9 menu walk.
    - Replies are cached for 10 minutes, and the Mac gets 15 s to answer.
    - The panel asks on its own only for the **front** app, because the
      Mac brings the app forward to read its menus. For any other app it
      shows a **Suggest** button.
  - **Ranking:**
    - The deterministic ranking shows as soon as the menus arrive.
    - If an on-device reorderer is set, the model's order replaces it when
      the model answers. A late answer for an older ranking is dropped.
  - **`claim(bundleID:shortcuts:)`:** a reply this model asked for is
    consumed here, so it is **not** imported into the deck the way the
    shortcut sheet's "Import from menus" is.
- **New `Deck/DeckSuggestionsPanel.swift`** follows the board's "Deck"
  screen:
  - An `accentTint` panel with the `ask` glyph, the title "N suggestions
    from <App>’s menus", **Keep all** (`.ph(.tint)`) and a close ×.
  - The suggestions show as `DeckKey(kind: .ghost)`. At AX3+ they become
    dashed `DeckKeyRow`s.
  - Tap a ghost key to keep it. Long-press offers Keep and Hide
    Suggestion.
  - After a Keep, the panel shows "Kept N keys" with **Undo**. Undo uses
    `DeckSurfaceModel.history`, and one Keep (including Keep all) is one
    undo step. Undo shows only while nothing else was recorded since the
    Keep. It is also available in the editor's Undo.
  - Subtitle while the model runs: "Sorting on this device…". After it
    answers: "Sorted on this device by Apple Intelligence". The fallback
    shows no subtitle.
  - When everything is already kept, the panel becomes the quiet line "No
    new keys in <App>’s menus".
- **New `Assist/OnDeviceDeckRanker.swift`:** the thin Foundation Models
  wrapper.
  - `#if canImport(FoundationModels)`, `@available(iOS 26.0, *)`, and
    `SystemLanguageModel.default.isAvailable` must all hold.
  - It sends a `@Generable DeckProposal { picks: [Int] }` prompt that
    lists at most 40 candidates, with an 8 s timeout. On any error or
    timeout it returns `nil`, and the deterministic order stays.
  - `makeIfAvailable()` returns `nil` on iOS 17.4–18 and on devices
    without Apple Intelligence.
- **`Surfaces/DeckSurface.swift`:** `suggestionTarget(page)` is the app
  page's app, or the front app on the Context page. It is `nil` on Home,
  Shortcuts and custom pages, and in the free plan.
  - The panel sits under the grid inside the page's scroll view.
  - An empty app page shows its empty state with the panel under it.
  - `onAppear` sets `DeckSuggestionsModel.shared.reorderer` to
    `OnDeviceDeckRanker.makeIfAvailable()`, but only when the user has
    Pro.
- **Pro gate:** like decks (`entitlements.allows(.decks)`). In the free
  plan there's no panel, no menu request and no reorderer. The lock card
  covers the surface as before.

## 2. iPhone / iPad checks

Use a Pro build (trial or the StoreKit config) unless a check says
otherwise.

1. **Xcode:**
   - Make Xcode frontmost on the Mac. The Context page shows "Reading
     Xcode’s menus…", then "N suggestions from Xcode’s menus".
   - Build ⌘B, Run ⌘R and Test ⌘U should lead. Quit Xcode, Hide Xcode and
     Minimize must not appear.
   - Add an Xcode app page through page menu › "Page for Xcode". It shows
     the same panel under its keys.
2. **Safari:** with Safari in front, expect New Tab, Reload Page, Show All
   Tabs, Reopen Last Closed Tab and Show Sidebar near the top. Safari's
   curated presets must not be suggested again.
3. **Finder:** with Finder in front, expect New Folder, Go to Folder, Get
   Info and Move to Trash near the top.
4. **Keep one:**
   - Tap a ghost key. It leaves the panel and appears on the app page,
     labelled with the item's own name and showing its chord.
   - The panel says "Kept 1 key" with Undo.
   - Tap the new key: it runs on the Mac.
5. **Keep all:**
   - Tap **Keep all**. Every visible suggestion moves onto the app page.
     If there's no app page, one is created, titled with the app name.
   - The panel collapses to "Kept N keys · Undo".
   - Tap **Undo**. All of them go back into the panel in one step, and the
     app page is removed if Keep all created it.
6. **Undo from the editor:** Keep one, tap Edit, then tap Undo in the
   editor header. The key is removed and the suggestion is back.
7. **Not the front app:**
   - Page to an app page whose app isn't in front. The panel shows "Suggest
     keys from <App>’s menus" with **Suggest**.
   - Tapping Suggest brings that app forward on the Mac and fills the
     panel.
8. **Mac doesn't answer:** quit the Mac app mid-request. After 15 s the
   panel shows "The Mac didn’t send the menus. Try again." with **Try
   again**.
9. **Hide and close:**
   - Long-press a ghost key and choose Hide Suggestion: it leaves the panel.
   - Tap × on the panel: it's gone for that app until the next launch.
10. **Apple Intelligence on** (iPhone 15 Pro or later / M-series iPad, iOS
    26+, AI enabled):
    - The subtitle shows "Sorting on this device…" and then "Sorted on
      this device by Apple Intelligence". The order may change. Every key
      must still be a real menu item from that app.
    - Turn on airplane mode: it still works, because it's on-device.
11. **No Apple Intelligence** (an iOS 17/18 device, or AI turned off in
    Settings): there's no subtitle and the deterministic order shows.
    Keep, Keep all and Undo work the same.
12. **Free tier:**
    - Sign out of Pro, or let the trial expire in the StoreKit config. The
      Deck surface is the dimmed preview with the lock card. There's no
      suggestions panel, and the Mac gets no menu request (check the Mac
      log).
    - Buy Pro: the panel appears.
13. **The shortcut sheet still imports:** AppShortcutsSheet's "Import from
    menus" still adds keys to the app page as before. Suggestions don't
    affect it unless both request the same app at the same moment (see
    risk 4).
14. **AX3+:** at AX3+, ghost keys are dashed rows, and the panel title
    wraps to two lines.

## 3. Compile risks (most likely first)

1. **`OnDeviceDeckRanker.swift`, Foundation Models API spelling.**
   - **What it uses:** `@Generable` and `@Guide(description:)` on an
     `@available(iOS 26.0, *)` struct; `SystemLanguageModel.default.isAvailable`;
     `LanguageModelSession(instructions: "<literal>")`;
     `session.respond(to: String, generating: DeckProposal.self)`; and
     `response.content.picks`.
   - **If the SDK spells something differently:** fix the call. The rest of
     the feature doesn't depend on the wrapper.
   - **If it won't compile at all:** change `makeIfAvailable()` to return
     `nil` and the feature still works fully.
2. **Weak linking FoundationModels on iOS 17.4.**
   - The import is guarded and every use is `@available`, so the linker
     should weak-link the framework.
   - **If an iOS 17/18 device crashes at launch with "Library not loaded:
     FoundationModels":** add `OTHER_LDFLAGS: -weak_framework
     FoundationModels` to the DeckHandiOS target in `project.yml`.
3. **`DeckSuggestionsPanel.swift`, SwiftUI that Linux can't check.** In
   order of likelihood:
   - `ProgressView().tint(...)`.
   - The `@ViewBuilder` `switch` with two `if`s in `.ready`.
   - `DeckKey(title:glyph:chord:size:kind:icon:action:)`, which relies on
     memberwise defaults for `asksFirst`, `delivery`, `tint` and
     `onRemove`. If the UX motion lane changes `DeckKey`'s stored
     properties, fix the labels here.
   - `DeckKeyRow(title:glyph:chord:icon:action:)`.
4. **Behaviour, not a compile risk: the reply is claimed by bundle ID.** If
   the shortcut sheet and the suggestions panel request the same app at
   the same moment, the suggestions model consumes the one reply and the
   sheet's import never finishes. The sheet's spinner then needs another
   tap. This is rare. The proper fix is a request ID in the message, which
   is a protocol change and was left out.
5. **`DeckSurface.pageContent` restructure.** It's now one `ScrollView`
   with a `VStack` around the grid and the panel. `LazyVGrid` inside a
   `VStack` inside a `ScrollView` is standard, but check that drag to
   reorder still works in edit mode.

## 4. Out-of-lane edits

- **`DeckHandiOS/Control/ControlSessionModel.swift`** (the shell, not this
  lane): 2 lines at the top of the
  `.deck(.appMenuShortcutsResponse)` case.
  `if DeckSuggestionsModel.shared.claim(bundleID:shortcuts:) { break }`
  skips the deck import for replies the suggestions model asked for.
- **`Scripts/linux-typecheck/run.sh`:** 1 line, adding
  `DeckHandiOS/Deck/DeckSuggestionsModel.swift` to the default list.
- **No Mac changes and no protocol change** (still protocol 12). The
  existing `AppShortcutBinding.category` (the top menu) is enough metadata
  for menu frequency.

## 5. Follow-ups

- **Mac-side model fallback:** backlog D7 lists one between on-device and
  deterministic. It isn't built. It would need a `DeckMessage` that ranks
  on the Mac, which is a protocol change.
- **A request ID on `requestAppMenuShortcuts`** would make claiming exact
  (risk 4).
- **"+ Suggest" chip in the context strip** (`04-Interaction-Model.md`
  §2, "No chips for this app"): it can call `DeckSuggestionsModel.load`
  for the front app.
- **Menu frequency is limited by the menu walk:** it only returns items
  that have shortcuts. Ranking items without a shortcut would mean
  returning `menuCommand` candidates from the walk.

Lane: READY TO MERGE
