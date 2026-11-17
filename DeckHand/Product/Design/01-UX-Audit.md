# 01 · UX audit of today's app

State audited: `claude/pixelhand-integration` at `9c07a63` (17 Nov 2026), read
from source. Nothing was run; this container has no Xcode. Paths are relative
to `DeckHand/` and use today's file names. **[inferred]** marks a consequence
worked out from fixed sizes in the code, not seen on a device.

## 0. Summary: the ten problems the redesign must solve

| # | Problem | Evidence | Fixed by |
| --- | --- | --- | --- |
| 1 | **Nothing adapts to the space.** No size-class reads anywhere; one `userInterfaceIdiom` check only picks a word. Grids are fixed at 4 (apps) and 2 (shortcuts) columns on every device. | `StreamDeckGridView.swift:40-45`, `AppShortcutsSheet.swift:33-36`, `PeerPickerView.swift:14` | `LayoutMetrics` + arrangements (`03-Layout-Strategy.md`) |
| 2 | **Text ignores Dynamic Type.** About 130 `.font(.system(size:))` calls, labels as small as 8–9 pt. Even the theme's `TypeStyle` is fixed. Only Settings scales. | `DeckHandTheme.swift:372-378`; counts in §2 | Type tokens (`02-Design-System.md` §3) |
| 3 | **Walls of buttons.** The trackpad has a 7-button gesture bar; the Quick Actions bar can hold pill + 14 numpad keys + 6 chips + 6 icon buttons in one scroll strip; the Apps tab is a grid of every installed app. | `TrackpadView.swift:236-271`, `QuickActionsBar.swift:58-332, 728-743`, `StreamDeckGridView.swift:88-120` | Dock, context strip and Deck (§3 of the layout doc) |
| 4 | **The trackpad shrinks to almost nothing in landscape.** ~136 pt of fixed chrome under the surface plus the tab switcher and a three-line title leave roughly 100–150 pt of pad on an iPhone on its side. [inferred] | `TrackpadView.swift:123-167`, `ControlView.swift:163-166, 240-264` | Leading rail in landscape |
| 5 | **Hidden gestures, tiny targets.** Tap-hold right-click, three-finger Spaces, mirror tap/drag/pinch are explained only in a 9 pt hint or a VoiceOver hint. The mirror's close button is 18 pt; the app-switch chevron is 20 × 44 pt. | `TrackpadView.swift:104-106`, `MirrorThumbnailView.swift:196-205, 251`, `QuickActionsBar.swift:963` | Visible click strip, 44 pt minimum, first-use coach marks |
| 6 | **Too many modal layers.** Capture can stack ControlView → full-screen cover → full-screen cover (annotate) or sheet; shortcuts stack sheet → sheet. Onboarding and approval are custom overlays, not presentations. | `ScreenshotPreviewView.swift:188-215`, `AppShortcutsSheet.swift:202-211`, `ContentRootView.swift:29-37, 85-99` | One sheet level; capture as a sheet with detents |
| 7 | **The toolbar is crowded and leaks debug detail.** Four trailing items plus a principal title with peer name, status and a 9 pt `session xxxx` id; Disconnect is a red icon one tap from Settings. | `ControlView.swift:239-311` | Mac pill + two glass buttons; Disconnect moves into the Mac menu |
| 8 | **Overlaps between floating things.** The mirror's home position (bottom 96, trailing 16) is tuned to the trackpad's gesture bar, and sits on top of the two FABs on the Apps tab. [inferred] | `MirrorThumbnailView.swift:60-71`, `StreamDeckGridView.swift:132-157` | Mirror anchors to the canvas, not to a bar |
| 9 | **Copy is iPad-only and stale.** "Your iPad becomes…", "buzz the iPad", "nearby iPads"; Settings footer refers to "Not available" rows that no longer exist. | `OnboardingView.swift:116, 156`, `SettingsView.swift:96, 232`, `MacMenuBarView.swift` | Copy pass (`04-Interaction-Model.md` §9) |
| 10 | **The app looks less crafted than the website.** The site uses Geist display type, cobalt-biased neutrals, white sheets over navy, generous spacing and one spring curve. The app uses SF Rounded at fixed sizes, neutral `#0A0A0F` dark canvas, system grouped greys and per-view animation values. | `website/public/styles.css:7-78`, `DeckHandTheme.swift:210-225` | Design system (`02-Design-System.md`) |

## 1. Screen by screen

### 1.1 Control screen shell (`ControlView.swift`)

What it is: a `NavigationStack` with a segmented **Trackpad / Apps** picker
(`:799-809`), up to two warning banners above it (`:152-161`), the floating
mirror overlay (`:198-236`), and the toolbar.

- **Confusing.** "Apps" is really the deck plus an app launcher plus the
  Quick Actions bar; the name hides the shortcuts. The capture button is a
  `Menu` whose tap does one thing and long-press another (`:952-1002`): a
  hidden gesture on a primary control.
- **Cramped.** Principal title has three lines (`:241-264`); on 320–375 pt
  widths with four trailing items the Mac name truncates almost at once.
  [inferred]
- **Landscape.** Segmented picker + divider + banners cost ~70 pt of a 375 pt
  height before any content. [inferred]
- **Split View / Stage Manager.** No reaction to width; a 320 pt Slide Over
  window gets the same layout as a 13″ iPad.
- **Banners** are full-width paragraphs at 12 pt (`:933-946`) with no action.
  The website would put one line and a button.

### 1.2 Trackpad tab (`TrackpadView.swift`, `MultiTouchTrackpad.swift`)

- **Good.** The navy surface with `DotField` is the strongest brand moment in
  the app and should survive intact.
- **Wall of buttons.** Seven equal buttons (Scroll, Left, Right, Double,
  Locate, Mission, Desktop) at ~40 pt wide on a 320 pt phone, with 8.5 pt
  labels (`:236-297`). Three duplicate surface gestures; two duplicate the
  Quick Actions bar.
- **Sensitivity slider on the main screen** with tick labels aligned by magic
  paddings (`:157-158`); also in Settings. A setting, not a control.
- **Hints.** 9 pt, 45 % opacity, can collide with the gesture indicator
  (`:104-106`). [inferred]
- **Scroll mode** silently remaps one finger (`MultiTouchTrackpad.swift:195-198`).

### 1.3 Quick Actions bar (`QuickActionsBar.swift`)

- **Too many segments in one strip:** app pill, chips, global macros, media,
  optional text-edit row (8) and numpad (14). Global and media icons have no
  labels or accessibility labels (`:302-330`).
- **Dialog takeover can't scroll** (`:156-173`); three buttons with long
  titles clip on small iPhones. [inferred]
- **Fixed 64 pt height** (`:119`) would clip if text ever scaled.
- **Delivery dots** are 2.5 pt squares (`DeliveryDots.swift:45-53`), easy to
  miss; colours hard-coded, not tokens (`:42`).
- **The idea is right.** Dialog buttons first, then front-app chips, is the
  product's best feature and becomes the context strip.

### 1.4 Apps tab (`StreamDeckGridView.swift`) and shortcuts sheet (`AppShortcutsSheet.swift`)

- **Wall of apps.** Every installed app as a 52 pt tile in a fixed 4-column
  grid; on iPad landscape the tiles float in empty space.
- **One tap does two things:** launches the app *and* opens the shortcuts sheet
  (`:220-226`).
- **FABs** for keyboard and numpad float over the last rows, and their state is
  re-seeded from Accessibility on every context change, overriding the user
  (`:166-177`).
- **Hide app** is long-press only; undo only in Settings.
- **Shortcuts sheet:** fixed 2 columns, categories collapsed by default
  including Edit; headers are tap gestures without button traits (`:272-277`);
  the editor asks people to type SF Symbol names (`:528`); a second sheet on a
  sheet.

### 1.5 Floating mirror (`MirrorThumbnailView.swift`)

- Good: draggable, pinchable, remembers layout, re-negotiates stream width.
- Space chevrons (28 pt) sit *on* the picture's edges (`:183-188`).
- Close is an 18 pt glyph (`:196-205`).
- Tap-to-minimise, drag and pinch are only in the VoiceOver hint.
- Bottom inset 96 assumes the gesture bar exists; wrong on the Apps tab.
- Mirror errors arrive as "Screenshot Failed" (`ControlView.swift:625-631`
  path via `requestID == "mirror"`).

### 1.6 Capture (`ScreenshotPreviewView`, `RegionCropView`, `AnnotationView`, `OCRResultView`, `WindowPickerView`)

- OCR is reachable twice (capture menu and preview "Text").
- Preview has no swipe-to-dismiss; zoom gestures hidden.
- Region crop: reset disabled until the selection is valid (`RegionCropView.swift:166`); bars cover the image's edges.
- **Annotation colour row is wider than every iPhone:** 9 × 30 pt + spacing +
  padding ≈ 422 pt (`AnnotationView.swift:138-221`). [inferred]
- Clear has no confirmation; pen only.
- Window picker is the only adaptive grid in the app (min 110 / max 140): good
  pattern to reuse.

### 1.7 Device picker (`PeerPickerView.swift`) and root (`ContentRootView.swift`)

- Strong brand screen: navy background, mark, DotScan.
- ~290 pt of header before the first Mac; in landscape the list starts below
  the fold. [inferred]
- Settings gear floats in its own layer over the scroll view (`:78-100`).
- Every root transition is an opacity cross-fade; no sense of place.

### 1.8 Onboarding (`OnboardingView.swift`) and approval (`AuthorizationOverlay.swift`)

- Pages are not scrollable; on iPhone landscape content clips. [inferred]
- 36 pt title at a fixed size; iPad-only copy; no Back button.
- Approval card has no max width, so it stretches across an iPad (`:37-39`).

### 1.9 Settings (`SettingsView.swift`)

- The only screen that uses text styles: keep its structure.
- Mixes live-control settings (mirror sharpness, fps) with app settings; no
  subscription row, no per-Mac section, no version line.
- Stale copy (§0 #9).

### 1.10 Mac menu-bar panel (`DeckHandMac/MacMenuBarView.swift`)

- Fixed 270 pt wide, 30 fixed font sizes (9–14 pt), so it ignores the Mac's
  text size setting.
- Disconnect appears **only on hover** and replaces the live dot (`:392-406`):
  not discoverable, not keyboard-reachable.
- Debug session ids in user UI (also on iOS).
- No pairing, capability or settings sections yet (needed by 1.1).

## 2. Fixed font sizes per file

QuickActionsBar 22 · MacMenuBarView 30 · AppShortcutsSheet 14 · PeerPickerView 14 ·
TrackpadView 12 · OCRResultView 8 · OnboardingView 7 · ScreenshotPreviewView 5 ·
AnnotationView 5 · RegionCropView 4 · WindowPickerView 4 · StreamDeckGridView 3 ·
MirrorThumbnailView 2 · DeckHandEmptyState 1 · plus the 5 theme `TypeStyle`
constants used by AuthorizationOverlay and others.

## 3. Breakage matrix

| Screen | Small iPhone (375 × 667) | iPhone landscape | iPad landscape | Split View ½ / ⅓ | AX text sizes |
| --- | --- | --- | --- | --- | --- |
| Control shell | Title truncates | Chrome eats height | Sparse | Same as full | Title fixed |
| Trackpad | Gesture labels shrink | Pad ~100–150 pt | Fine, wasted width | Same | Nothing scales |
| Quick Actions | 2–3 chips visible, rest hidden | Fine | Fine | Fine | Fixed 64 pt clips |
| Apps grid | 58 pt columns | FABs cover grid | 4 sparse columns | 4 columns at 320 pt | Labels fixed |
| Mirror tile | 62 % of width | Clamped small | Fine | Overlaps FABs | – |
| Annotation | **Colour row overflows** | Fine | Fine | Overflows | – |
| Onboarding | Tight | **Clips** | Fine | Clips at ⅓ | Fixed |
| Picker | Fine | List below fold | Fine | Fine | Fixed |
| Mac panel | – | – | – | – | Ignores Mac text size |

## 4. What the website does better (and the app should take)

| Website (`website/public/styles.css`) | App today | Take |
| --- | --- | --- |
| Geist display at weight 500 with tight tracking (-1.4 px at 48 px) for headings; plain sans for body | SF Rounded at fixed sizes everywhere | Geist for display only; SF Pro text styles for reading |
| Cobalt-biased neutrals (`#121522` ink, `#F3F4F9` muted, `#E3E6EF` hairline) | Neutral system greys and `#0A0A0F` | Navy-biased canvas, ink and hairlines in both themes |
| White sheets with 30 px radius stacked over navy bands; one card style per role | Cards, wells, pills with mixed radii 9–28 | Radius by role: 14 chip, 18 key, 24 card, 30 pane, 36 sheet |
| One spring (`--ease-spring`) and one long ease (`--ease-hero`) for everything | Ad-hoc `.easeInOut(0.18)`, `.snappy(0.2)`, `.spring(0.28, 0.82)` | Four motion tokens |
| The dot grid fades in behind headlines and lights around the pointer | DotField only on the trackpad | Dot grid on every navy surface; lit only when live |
| Pills (`pill--accent`, `pill--teal`) with one clear meaning each | Badges ad hoc | Status pill and badge components |
| Plain, specific copy: "Open it on both. Approve once. Done." | Technical and iPad-only | Copy rules in `04-Interaction-Model.md` §9 |
| Generous whitespace; one idea per block | Dense bars | Fewer, larger controls; progressive disclosure |
