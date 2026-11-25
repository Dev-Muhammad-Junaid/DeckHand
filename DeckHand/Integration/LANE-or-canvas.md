# Lane: owner review, canvas, sidebar and right column (or-canvas)

Branch `claude/pixelhand-lane-or-canvas`, merged with the latest
`origin/claude/pixelhand-integration` (bce0e75, "Record build 19 and the
owner review lanes"). No protocol change (still 13).

## What changed, in one paragraph

Core gets the rules: `LayoutMetrics.sidebarWidth` is 176 (was 232) with a
16 pt leading margin, and a new `Design/RightColumn.swift` holds
`RightColumnMode` (Deck | Ask), `ArrangementPreset` (form + preset, the
memory key), `RightColumnPlan` (which arrangements have the column, which
can collapse it, its width, and where Ask opens) and `RightColumnMemory`
(collapsed arrangements as JSON for `@AppStorage`). `CanvasPlan` takes
`rightColumnCollapsed`, so a collapsed wide column gives the centre its
room and can bring the sidebar back. On iOS, Ask's content is now one view,
`AskPanel`, used both by `AskSheet` and by the column. Both read
`AskModel.shared`, so nothing is forked. The right column has a Deck | Ask
switch and, on iPad, a collapse button that leaves a slim edge handle.

## Findings

| ID | Status | Note | Files |
| --- | --- | --- | --- |
| OR-04 | Fixed | Sidebar 232 → 176 pt (16 pt leading margin included), with `CompactMacCard`: a 44 × 28 navy tile with the Mac or lock glyph and the live pixel, then the name and one status line. The selected Mac has the cobalt ring and an accent-tint fill (colour and fill only). A Mac not covered by the free plan shows the small Pro lock in the tile's corner. My Macs keeps the full `MacCard`. Canvas at 1180 × 820: the centre is 612 pt (was 556). The sidebar now shows down to 1048 pt wide (was 1104). | Core `Design/LayoutMetrics.swift`, `Design/CanvasPlan.swift`, `CanvasPlanTests`; `Shell/MacsSidebar.swift`; `Product/Design/07-Polish-Spec.md` §1 |
| OR-06 | Fixed (re-check) | **Collapse:** on iPad (sideBySide Split/Pointer, columns), a sidebar-glyph button folds the column to a 20 pt edge handle with a 44 pt touch target. A tap on the handle brings it back. The state is remembered per arrangement (`columns\|split`, `sideBySide\|pointer` …) in `@AppStorage("pixelhand.layout.rightColumn")`. When the wide column collapses, the front app's strip moves under the header in the centre, and the centre grows by 316 pt. **Deck \| Ask:** a two-way switch; the selected half is accent-filled with white text, nothing slides and there's no dot. Ask (⌘K, the Ask field, the Ask circle) opens **in the column** wherever one exists, expanding it and focusing the field. Elsewhere it opens the sheet as before: compact, ½ Split View, Stage Manager at iPhone width, iPad portrait's Screen preset, iPhone SE landscape and Duo. The column shows the typed request (the field), the plan, and the step-by-step run. The running step shows the `DotWave`, and planning keeps the `DotScan`. A run in the column keeps going while you switch to Deck; closing the sheet still stops it. **iPhone landscape (rail):** the column holds the header, so it switches Deck \| Ask but doesn't collapse. **Motion:** the column, switch content, sidebar and keyboard panel fade (180 ms ease-out, `Animation.phPanelFade`). Under Reduce Motion they change at once. The sidebar no longer slides in from the leading edge, and the keyboard panel no longer rises from the bottom. | Core `Design/RightColumn.swift` (new), `Design/CanvasPlan.swift`, `RightColumnTests` (new), `CanvasPlanTests`; `Shell/PixelHandShell.swift`, `Shell/RightColumnChrome.swift` (new), `Surfaces/AskSheet.swift` |
| OR-03 (remainder) | Fixed | Ask's free plan: the large "Try 2 weeks free" lock card is gone. The field shows dimmed, with the small Pro lock inside its bottom-trailing corner (`.requiresPro(.ai)`), and a tap opens the paywall for Ask. This works the same in the sheet and in the column. Other free-plan surfaces checked: no other upsell cards remain in `DeckHandiOS` (the deck and Screen were done by qa-surfaces). Settings › Subscription opens the paywall (VQ-055, already fixed there). `RequiresPro.swift` and `PaywallView.swift` needed no change. | `Surfaces/AskSheet.swift` |

## Linux results

- `swift test --package-path DeckHand/Core`: **923 tests in 166 suites
  passed**. Of these, 7 are new in `RightColumnTests`; in `CanvasPlanTests`,
  one test is new and the sidebar test was rewritten for 176 pt.
- `DeckHand/Scripts/linux-typecheck/run.sh`: passes.
- The iOS files are SwiftUI, so none of them are type-checked on Linux.
  **The Mac build is their first compile.**

## Re-check steps (iPad Pro 11" simulator)

Run the `PixelHandUITests` walk. Then:

1. **Landscape (1180 × 820), Pro:**
   - The sidebar is narrow, with compact cards. The name and status sit on
     one line each, and the focused Mac has the ring and a tint fill (OR-04).
   - At the top of the right column is Deck | Ask plus the collapse button.
     Tap Ask: the plan field shows in the column with the keyboard up.
     Type "Open Safari and go to apple.com", then Plan, then Run. The
     running step shows the dot wave, and finished steps show ticks.
   - Tap Deck while it runs: the deck shows, and switching back shows the
     run still going.
   - Collapse: the column fades to a slim handle, and the strip appears
     under the header. Press ⌘K: the column comes back on Ask with the field
     focused.
   - Collapse again, switch to the Pointer preset, then back to Split: Split
     stays collapsed and Pointer is not (per arrangement). Relaunch: still
     remembered.
2. **Portrait (820 × 1180):**
   - In Split and Pointer, the column beside the pad has the switch and the
     collapse button. The handle sits beside the pad, which widens. The
     Screen preset has no column, so the Ask circle opens the sheet.
3. **Stage Manager**, dragged from full width down to iPhone width:
   - Wide: as in step 1. Under 1048 pt the sidebar hides. With the column
     collapsed it comes back, and it stays at every wide width (≥ 900 pt).
   - Medium ≥ 700 pt: as in step 2. Below 700 pt (stacked) and at iPhone
     width: no column; Ask is the sheet, as today.
4. **Free plan** (`TEST_RUNNER_PH_QA_FREE=1`): Ask, in the column or the
   sheet, shows only the dimmed field with the small lock. No card. Tapping
   it opens the paywall.
5. **Reduce Motion on:** collapsing, expanding and switching change at once.
6. On iPhone landscape (or the rail at short heights), the column shows
   Deck | Ask and no collapse button.

## PixelHandUITests changes

- New identifiers: `ph.column.deck`, `ph.column.ask`,
  `ph.column.collapse`, `ph.column.expand`. Existing `ph.ask`,
  `ph.ask.field`, `ph.ask.submit`, `ph.ask.example` and `ph.sidebar.mac`
  are unchanged.
- `test07_Ask` and `test12_FreePlanAndPaywall` open Ask with `ph.tab.ask`
  on compact or `ph.ask` on iPad (new `openAsk()`). They close it by
  switching the column back to Deck, or by dismissing the sheet
  (`closeAsk()`).
- New `test13_RightColumn`: in landscape, then portrait, it snaps the
  column on Deck, then on Ask, collapsed, and expanded.

## Compile risks (most likely first)

1. `RightColumnChrome.swift`: `.contentShape(Rectangle().inset(by: -12))`
   widens the handle's touch target past its frame. If hit-testing ignores
   the outside area, widen the frame instead (`RightColumnPlan.handleHitWidth`).
2. `PixelHandShell.swift`: `.animation(Animation.phPanelFade(reduceMotion:), value:)`
   takes an `Animation?`. This should resolve to the
   `animation(_: Animation?, value:)` overload.
3. `AskSheet.swift`: the `ToolbarItem` inside `if` in `AskSheet.toolbar` is
   unchanged in shape from before. `AskPanel` is a new top-level type name,
   so check it doesn't clash elsewhere (a grep found none).
4. `MacsSidebar.swift`: `CompactMacCard` reads
   `SubscriptionStore.shared.isLockedMac(deviceID:)` the way
   `FreeMacBadge` does. `DynamicTypeSize.isAccessibilitySize` needs
   iOS 15+.
5. The body's `CanvasPlan` is now built twice when the wide column is
   collapsed (cheap pure maths), and `rightColumn(plan)` decodes a small
   JSON string per evaluation.

## Out-of-lane edits

- `DeckHand/Product/Design/07-Polish-Spec.md` §1: sidebar width 232 → 176,
  one line.
- No edits to `ShellHeader.swift`, `SurfaceTabBar.swift`,
  `ContextStrip.swift`, `DesignSystem/*`, `Pairing/*` or `DeckHandMac/`. The
  header's existing `onAsk` and `onShowSidebar` were enough. The fade helper
  `Animation.phPanelFade` lives in `Shell/RightColumnChrome.swift` (mine),
  not in `DesignSystem`, so the or-ios-chrome lane may move it there later.

Lane: READY TO MERGE
