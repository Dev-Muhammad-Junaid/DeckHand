# Lane: QA fixes A (surfaces), build 18 visual QA

Branch `claude/pixelhand-lane-qa-surfaces`, merged with the latest
`origin/claude/pixelhand-integration` (COORDINATOR.md only). No protocol
change (still 13).

Linux checks: `swift test --package-path DeckHand/Core` passes (872 tests in
155 suites, 15 tests new), and `DeckHand/Scripts/linux-typecheck/run.sh`
passes. Every app file in this lane uses SwiftUI or UIKit, so none of
them are type-checked on Linux. **The Mac build is the first compile of
the app-side changes.**

## What changed, in one paragraph

New pure layout rules in Core `Design/ShellChromePlan.swift`:
`ShellHeaderPlan` (when header circles fold into More), `DeckHeaderPlan`
(one or two header rows, subtitle without the page number) and
`AppDockFit` (whole-icon dock row). There are also
`MirrorPaneChrome.stripCandidates` and `hasFrame`, word-boundary
`dotMatrixSafe`, `ContextStripPlan.acceptsFrontApp`, a one-line
`AskStep.typeText` summary and shorter lock banner copy. Tests are in
`ShellChromePlanTests`, plus additions to `MirrorPaneChromeTests`,
`ContextStripAndDockTests`, `AskPlannerTests` and `CaptureSheetChromeTests`.
Design-system changes that affect every screen:

- Inline `PHButtonStyle` buttons never wrap. They take their label's
  width, one line. Full-width buttons may still use two lines.
- `PHEmptyState` scrolls when it can't fit, stacks its buttons when the
  row is too narrow, and can lock only its primary button (`primaryRequires`).
- The `.requiresPro` lock sits inside the control's bottom-trailing
  corner instead of hanging off its top edge.
- `StatusStrip` takes `candidates` (fallbacks, widest first).

## Findings

| ID | Sev | Status | Note | Files |
| --- | --- | --- | --- | --- |
| VQ-024 | P1 | Fixed | Deck header goes to two rows below 340 pt of content or at Large/Huge type (name, then counter · pin · Edit). Buttons never wrap. | Core `ShellChromePlan.swift`; `Surfaces/DeckSurface.swift`; `DesignSystem/PHButton.swift` |
| VQ-025 | P1 | Fixed | Free plan deck is one state (empty state with "Show decks" carrying the Pro lock). The upsell card is gone (OR-03 direction), so nothing overlaps. | `Surfaces/DeckSurface.swift`, `DesignSystem/Feedback.swift` |
| VQ-045 | P1 | Fixed (re-check) | The rail's header folds circles so the pill keeps ≥ 168 pt. The deck column header uses two rows. Empty-state buttons stack instead of clipping, and the text wraps or scrolls. No new rail geometry. | `Shell/ShellHeader.swift`, `Surfaces/DeckSurface.swift`, `DesignSystem/Feedback.swift` |
| VQ-059 | P1 | Fixed | Under the docked mirror: `PointerSurface` (dot field, click strip, caption), not `TrackpadView`. No slider, no legacy action row. | `Surfaces/ScreenSurface.swift`, `Shell/PixelHandShell.swift` |
| VQ-064 | P1 | Fixed | At accessibility sizes, onboarding's dots and buttons scroll after the text instead of being pinned over it. | `OnboardingView.swift` |
| VQ-065 | P1 | Fixed | Huge band: the header is the Mac pill (name on up to two lines, tail truncation) plus one More menu. The deck and edit headers use two rows. Undo is glyph-only with the Large Content Viewer. Done and Edit never wrap. | Core `ShellChromePlan.swift`; `Shell/ShellHeader.swift`, `DesignSystem/MacPill.swift`, `Surfaces/DeckSurface.swift` |
| VQ-066 | P1 | Fixed | The upsell card is removed. The Screen and deck empty states scroll rather than truncate, and their buttons stack. | `DesignSystem/Feedback.swift`, `Surfaces/DeckSurface.swift`, `Surfaces/ScreenSurface.swift` |
| VQ-026 | P2 | Fixed | Screen empty state: the lock is on the "Show screen" button, not the whole state. All locks sit inside the control's bottom-trailing corner. | `Store/RequiresPro.swift`, `DesignSystem/Feedback.swift`, `Surfaces/ScreenSurface.swift` |
| VQ-032 | P2 | Fixed | iPhone portrait header is pill · capture · More (spec Option A). Screen and Send move into More. The name truncates at the tail. | `Shell/ShellHeader.swift`, `DesignSystem/MacPill.swift` |
| VQ-033 | P2 | Fixed | While typing, the strip and tab bar step aside (the dock stays, it holds the keyboard toggle). The clipboard caption is shorter ("at the Mac’s cursor") and wraps. | `Shell/PixelHandShell.swift`, `Clipboard/PasteToMacControl.swift` |
| VQ-038 | P2 | Fixed | The mirror strip drops whole segments, the Mac's name first (first word, then no name). `dotMatrixSafe` cuts at a word. The apostrophe glyph itself is lane C (VQ-071). | Core `MirrorPaneChrome.swift`; `DesignSystem/StatusStrip.swift`, `Mirror/MirrorPane.swift` |
| VQ-039 | P2 | Fixed | The dock row snaps to whole 44 pt slots, rests on whole icons (`.viewAligned`), and fades only when more apps wait. | Core `ShellChromePlan.swift`; `Shell/AppDock.swift` |
| VQ-046 | P2 | Fixed | Choosing Screen starts the mirror. After the person stops it, that session keeps the empty state. The title is the Mac's name plus a one-line status. | `Surfaces/ScreenSurface.swift` |
| VQ-047 | P2 | Fixed | Search is pinned under the title (`.navigationBarDrawer(.always)`). Row descriptions wrap up to three lines. | `Deck/ActionLibrarySheet.swift` |
| VQ-049 | P2 | Fixed | "Type “apple.com” then Return"; inner line breaks show as ↩. | Core `Assist/AskPlan.swift` |
| VQ-051 | P2 | Fixed | The preview well hugs the picture at its aspect, with the dock right under it and the spare space below. | `ScreenshotPreviewView.swift` |
| VQ-056 | P2 | Fixed | Media chips are labelled Previous / Play/Pause / Next. The grey dots under chips are OR-02, not changed here. | `Shell/ContextStrip.swift` |
| VQ-067 | P2 | Fixed (re-check) | An open Duo puts the scene on the first pane and the step counter, text, dots and buttons on the second, using `DuoPoseMachine.band` and `DuoPanes` (nothing in the crease band). | `OnboardingView.swift` |
| VQ-080 | P2 | Fixed (compile risk 1) | The header starts after Stage Manager's window controls, measured from UIKit's `.safeArea(cornerAdaptation: .horizontal)` guide (iOS 26; 0 elsewhere). | `Shell/WindowControlsInset.swift` (new), `Shell/ShellHeader.swift` |
| VQ-081 | P2 | Fixed | At about 375 pt, circles fold into More (`ShellHeaderPlan`) and the name truncates at the tail. Also OR-07. | `Shell/ShellHeader.swift`, `DesignSystem/MacPill.swift` |
| VQ-004 | P2 | Fixed | The scene glow moved outside the page's pixel-dissolve mask (`OnboardingSceneGlow`). The square mask had been cutting the glow into a hard-edged square. | `Onboarding/OnboardingScene.swift`, `OnboardingView.swift` |
| VQ-018 | P3 | Fixed | "LIVE · 30 FPS". | `Onboarding/OnboardingScene.swift` |
| VQ-019 | P3 | Fixed | Single-column onboarding: title, body and bullets are leading-aligned, and only the scene is centred. | `OnboardingView.swift` |
| VQ-034 | P3 | Fixed | "esc" and "tab" show as text. The key row fades at its trailing edge. | `Keyboard/RemoteKeyboardPanel.swift` |
| VQ-035 | P3 | Fixed | More shows "Disconnect" (VoiceOver: "Disconnect from <Mac>"). The classic layout item is `#if DEBUG` only, "Classic layout (debug)". | `Shell/ShellHeader.swift` |
| VQ-048 | P3 | Fixed | In edit mode, dashed ghost slots fill the row after "Add key" (a full first row on an empty page). Tapping one opens the library. | `Surfaces/DeckSurface.swift` |
| VQ-050 | P3 | Fixed | The title is "Ask" (VoiceOver: "Ask <Mac>"). The placeholder is "What should your Mac do?". | `Surfaces/AskSheet.swift` |
| VQ-057 | P3 | Fixed | A dashed "Add another Mac" card fills the grid. Disconnect is a plain red row, not a full-width button. | `Macs/MyMacsSheet.swift` |
| VQ-061 | P3 | Fixed | The mirror toolbar fades after 3 s without a touch, and a tap on the picture brings it back. It stays visible under VoiceOver, with the picker open, or before the first frame. | `Mirror/MirrorPane.swift` |
| VQ-062 | P3 | Fixed | Before the first frame the strip is dim and reads "<MAC> · CONNECTING", never a lit "0 FPS". | Core `MirrorPaneChrome.swift`; `Mirror/MirrorPane.swift` |
| VQ-063 | P3 | Fixed | Front-app reports naming `com.widgetsflow.pixelhand.mac` are ignored, so the previous app stays. | Core `ContextStripPlan.swift`; `Control/ControlSessionModel.swift` |
| VQ-068 | P3 | Fixed | "<Mac> is locked. Type the password to unlock." with a Keyboard button that opens the keyboard panel (not in the landscape rail, which has no panel). | Core `System/LockPolicy.swift`; `Shell/PixelHandShell.swift` |
| VQ-082 | P3 | Fixed | The subtitle no longer repeats the page ("Pinned", "Follows the front app", "Following off", or nothing). The dot-matrix 01/02 stays. | Core `ShellChromePlan.swift`; `Surfaces/DeckSurface.swift` |

Owner items touched in passing: OR-07 is done (it is VQ-080 plus VQ-081).
OR-03 is done only for the deck and the Screen empty state (no upsell card,
lock on the control). Ask and Settings were not touched. OR-01, OR-02,
OR-04, OR-05 and OR-06 were not started: they weren't assigned to this
lane.

## Re-check steps

Use the iPad Pro 11" simulator, per the owner, plus the iPhone where a
finding was iPhone-only. Run the `PixelHandUITests` walk (updated: the deck
walk now ends edit mode with `ph.deck.done`; the Screen walk no longer
needs "Show screen").

1. **iPad portrait (820 × 1180), light, free plan** (`TEST_RUNNER_PH_QA_FREE=1`):
   - Deck column: a single empty state with "Show decks" and a lock in the
     button's corner, nothing overlapping (VQ-025).
   - Header circles: the lock sits inside the circle (VQ-026).
   - Screen empty state: the lock is on "Show screen" only (VQ-026).
2. **iPad portrait, Pro**:
   - Deck column header on two rows. The name isn't truncated to "Ho…",
     and Edit sits on one line (VQ-024). With two or more pages the
     subtitle has no "Page 1 of 2"; only 01/02 shows (VQ-082).
   - Edit: Undo, title, ⋯ and Done; no wrapping. On an empty page, a row
     of dashed slots (VQ-048).
3. **iPad landscape (1180 × 820)**: the header keeps every circle; the
   deck column header has two rows.
4. **Stage Manager window**: drag it to iPhone width (about 375 pt), then
   medium, then full.
   - The window controls never cover the Mac pill (VQ-080).
   - At iPhone width the header is pill · capture · More. The name ends in
     "…" at the tail. Screen and Send and Inbox are in More (VQ-081).
5. **iPhone 17 Pro portrait**:
   - Header shows pill · capture · More (VQ-032). More shows "Disconnect"
     on one line, and no classic layout in Release (VQ-035).
   - Screen tab: the mirror starts by itself, and the dot-field pad with
     its click strip sits under it (VQ-046, VQ-059). The strip reads
     CONNECTING dim until the picture comes (VQ-062). The toolbar fades
     after 3 s; a tap brings it back (VQ-061).
   - Keyboard: the tab bar and strip step aside and the pad stays usable.
     The key row shows "esc" and "tab" and fades at the end. The paste
     caption isn't clipped (VQ-033, VQ-034).
   - Free plan context strip: labelled Previous / Play/Pause / Next (VQ-056).
   - Add key: search at the top, descriptions wrap (VQ-047). Ask: title
     "Ask", placeholder "What should your Mac do?", and a typed step shows
     "Type “apple.com” then Return" (VQ-049, VQ-050).
   - Capture: picture full width with the dock under it (VQ-051).
   - My Macs: Mac card and dashed "Add another Mac" card side by side, with
     a plain Disconnect row (VQ-057).
   - Open the Mac's menu-bar panel: the strip keeps the previous app's
     chips (VQ-063).
6. **iPhone 17 Pro landscape (874 × 402)**: the rail header pill is
   readable, the deck header uses two rows, "Add keys" isn't clipped, and
   the empty-state text wraps (VQ-045).
7. **AX3** (`simctl ui <dev> content_size accessibility-extra-large`,
   on iPhone 17 Pro and iPad):
   - Onboarding scrolls to its buttons after the text (VQ-064).
   - Header is the pill (name on two lines) plus More. Deck and edit
     headers use two rows; Done and Edit don't wrap; Undo is a glyph
     (VQ-065).
   - Free plan deck and Screen empty states scroll, with nothing clipped
     (VQ-066).
8. **iPad mini portrait**:
   - Dock: the last icon is whole and the end fades only when more apps
     wait (VQ-039).
   - Mirror strip: "MUHAMMADS · DESK 1/2 · 20 FPS", or without the name;
     never cut mid-word (VQ-038).
9. **Onboarding on iPad**:
   - No square behind the scene cards (VQ-004).
   - Page 3 reads LIVE · 30 FPS (VQ-018).
   - Portrait body text is leading-aligned (VQ-019).
10. **iPhone Duo open (951 × 669)**: in onboarding, the scene is on the
    left pane and the text and buttons on the right; nothing on the crease
    (VQ-067).
11. **Locked Mac**: the banner shows one sentence and a Keyboard button
    that opens the keyboard panel (VQ-068).

## Compile risks (most likely first)

1. `Shell/WindowControlsInset.swift`: `UIView.layoutGuide(for:
   .safeArea(cornerAdaptation: .horizontal))` (iOS 26 UIKit, behind
   `#available(iOS 26.0, *)` and `#if compiler(>=6.2)`). If the SDK spells
   it differently, fix the call or return 0. The only effect is VQ-080.
2. `Shell/ShellHeader.swift`:
   - `.onGeometryChange(for:of:action:)`. It is back-deployed in the
     Xcode 16+ SDK; if it complains on 17.4, wrap a `GeometryReader`
     background.
   - `Picker` inside the More `Menu`.
   - `lockable(_:content:)` (a generic `@ViewBuilder`).
   - `let fit = self.actions` inside `body`.
3. `Surfaces/DeckSurface.swift`:
   - Large restructure (header helpers, `lockedState`, `ghostSlot`).
   - `PHEmptyState(..., primaryAction: {}, primaryRequires: .decks)`
     depends on memberwise order (primaryRequires was declared after
     secondaryAction).
4. `Shell/AppDock.swift`:
   - `.contentMargins(_:_:for:)`, `.scrollTargetLayout()` and
     `.scrollTargetBehavior(.viewAligned)` (iOS 17).
   - The `if`/`else` inside `.mask { }`.
5. `OnboardingView.swift`:
   - `duoPage` uses `DuoCrease.input` and `DuoPoseMachine.band`.
   - The ternary `Edge.Set` in `.padding(panes.pose == .book ? .trailing : .horizontal, …)`.
   - The `metrics` parameter is unused (a warning only).
6. `DesignSystem/StatusStrip.swift`: a new trailing `candidates` property.
   Existing call sites pass the earlier parameters in order, so they're
   unaffected.
7. `Surfaces/ScreenSurface.swift`: `@MainActor enum ScreenAutoStart` with
   a static `Set<ObjectIdentifier>` (Swift 6 isolation should be fine).

## Out-of-lane edits

- `DeckHandiOS/Transfer/TransferHeaderButton.swift` (Sharing): adds
  `var openRequest = 0` and an `onChange`, so the folded More menu can open
  Send and Inbox. When folded, the header keeps a hidden instance for the
  sheet and its alerts.
- `DeckHandiOS/Control/ControlSessionModel.swift` (lane B touches this
  file): one `guard` in `.apps(.activeAppUpdate)` to ignore Pixel Hand's
  own Mac app (VQ-063). A merge conflict there would be trivial.
- `DeckHandiOS/Store/RequiresPro.swift` (Store, lane B's paywall area):
  the lock badge moved to bottom-trailing inside the control (VQ-026).
- `Core/.../System/LockPolicy.swift`: shorter `screenLocked` banner copy
  (VQ-068). The Mac side doesn't show this string.
- `PHButtonStyle` now uses one line and fixed width for inline buttons.
  This affects every screen, Settings and the paywall (lanes B and C)
  included. Look for any inline button row that now overflows instead of
  wrapping.
- Lane C: VQ-038's apostrophe is theirs (VQ-071). `dotMatrixSafe` keeps
  ’ automatically once `DotMatrixFont.characters` contains it.

Lane: READY TO MERGE
