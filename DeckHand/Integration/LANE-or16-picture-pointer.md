# Lane: OR-16, pointer control on the mirror picture

Branch `claude/pixelhand-lane-or16-picture-pointer`, from
`origin/claude/pixelhand-integration` at `537e21c` (the owner's OR-16
answers). No protocol change, no `project.yml` or Info.plist change, no Mac
change. Spec: `OWNER-REVIEW-visual-qa-build18.md` "OR-16"; answers:
`DECISIONS.md` 2026-11-25. **OR-16: done** (pending the Mac build checks
below).

## What changed

### The toggle (`DeckHandiOS/Mirror/MirrorPane.swift`)

- A pointer-glyph button in the mirror's glass toolbar, between sound and
  PiP (order: display picker · ‹ dots › · sound · **pointer** · PiP · stop).
  Lit (phosphor glyph, white fill) when on. ID `ph.mirror.pointerControl`;
  VoiceOver "Control the pointer from the picture", toggle trait, value
  On/Off, and an announcement when it changes.
- Shown only where the pane has no trackpad beside it
  (`PicturePointerControl.isOffered`):
  - iPad and wide windows: the **Screen focus** preset (`dockedScreen(screenOnly: true)`
    in the side-by-side and columns forms).
  - Tabbed windows (iPhone, ½ Split View, narrow Stage Manager): the
    **Screen tab** when the pad doesn't fit under the pane
    (`ScreenSurface.split` says no trackpad, e.g. iPhone landscape).
  - Not in Split (pad under the pane) or the Duo book/laptop panes
    (`dockedScreen()` there keeps `screenOnly: false`), so the Duo layouts
    are unchanged.
- **Default and memory** (answer 1): off the first time for each Mac, then
  the last choice for that Mac (`PicturePointerMemory`, JSON in
  `@AppStorage("pixelhand.mirror.pointerControl")`, keyed by
  `MacSwitcher.shared.focusedDeviceID`, at most 16 Macs).
- **Free plan**: nothing new. The pane only exists with the mirror on, which
  is `.requiresPro(.mirror)`; `isActive` also checks
  `entitlements.allows(.mirror)` so a stored "on" never drives anything
  without Pro.

### When on: trackpad style only (answer 3)

`MirrorPicturePointerLayer` (new, `DeckHandiOS/Mirror/MirrorPicturePointer.swift`)
lies over the picture. It **is** the Pointer surface's input path:
`TrackpadInputLayer` → `MultiTouchTrackpad` → `TrackpadSender`, unforked. So
a finger anywhere moves the pointer relative to where it is with the same
sensitivity setting and the Mac's acceleration; a tap clicks, double-tap
double-clicks, rest until the haptic then move drags (drag lock with a
second finger), two fingers scroll (natural scrolling setting honoured),
three/four fingers run Mission Control, Spaces, etc., Pencil hover moves the
pointer.

Two small, opt-in additions to that shared code (off for the Pointer
surface, so UX-004 behaves exactly as before):

- `TrackpadInputLayer.sensitivityScale` (default 1). The picture passes
  `1 / zoom` (`PicturePointerMapping.sensitivity`), so zoomed in, the same
  finger travel moves the pointer less: finer control, same feel on screen.
- `TrackpadInputLayer.picture` / `MultiTouchTrackpad.arbitratesTwoFingers`:
  two fingers go through Core `TwoFingerArbiter`; new callbacks
  `onPictureZoom`, `onPictureZoomEnded`, `onTwoFingerTap` (right click +
  filled pulse, gesture map forgotten, like the long-press right click).

### Pinch vs two-finger scroll vs pan (answer 2), Core `Input/TwoFingerArbiter.swift`

- Nothing is sent until the two-finger touch is decided; then it stays
  decided until the fingers lift.
- **Scroll** (to the Mac): the midpoint travels ≥ 10 pt and the gap changes
  by ≤ ½ of that travel. The travel buffered while undecided is sent with
  the first scroll step.
- **Pinch** (zooms the picture): the gap changes ≥ 20 pt and by more than
  ½ of the midpoint's travel. One cut-off (½), so nothing can be both; the
  undecided band ends by 40 pt of travel.
- **Pan**: sliding a pinch. Once a touch is a pinch, midpoint movement pans
  the zoomed picture (zoom around the previous midpoint, then pan, so the
  content stays under the fingers). A finger left behind after a pinch does
  nothing until all lift (it never jerks the pointer).
- **Two-finger tap** (right click): both fingers down < 0.3 s, travel and
  gap change ≤ 8 pt.
- Three fingers cancel the arbiter (no tap); the system gesture takes over.
- While zoomed, the picture also **follows the Mac's pointer**: when it
  comes within 32 pt of the pane's edge the picture pans the least needed
  (`PictureZoom.follow`), so driving off the visible part never loses it.

### Picture zoom and pan (`PictureZoom`, `PictureFrame`, Core `Mirror/PicturePointer.swift`)

`screen = centre + (content − centre) × scale + offset`, 1×–4×, clamped so
the zoomed picture always covers the pane (a letterboxed axis stays
centred), anchor-preserving zoom, back to fit at 1×. The pane applies it as
`.scaleEffect(scale).offset(offset)` on `MirrorPicture`, so the Mac's
cursor (`MirrorCursorLayer`, fed by the cursor stream) is drawn through the
same zoom and pan. Zoom resets to fit on a new display, window or desktop
(`scanKey`), and is re-clamped when the pane resizes.

### Feedback

- The Mac's pointer: the existing cursor layer on the picture, now through
  zoom and pan.
- A faint dotted ring (44 pt, `glow` at 50 %, 2 pt dots on a 4 pt rhythm,
  soft bloom: pixel identity §5's focus-ring dots) under each finger, from
  the same `DotFieldModel` touches the Pointer surface uses. Reduce Motion:
  rings appear and go without the 150 ms fade. Taps pulse nothing on the
  picture (the dot field isn't drawn over the Mac's screen).
- The toolbar still fades after 3 s so the Mac's Dock shows. While on, a tap
  on the picture clicks the Mac, so the hidden toolbar comes back from its
  own spot (a tap where it sits); the pointer is relative, so that spot
  costs no reach.

### When off

At fit size, exactly as before: a tap shows the toolbar, nothing else. One
addition, because the owner's spec describes the off state as "pinch to
zoom, pan" and the docked pane had no zoom yet: **pinch zooms the picture
and, once zoomed, a one-finger drag pans it** (SwiftUI `MagnifyGesture` +
`DragGesture(minimumDistance: 10)`, the same `PictureZoom`). The floating
tile (`MirrorThumbnailView`) is untouched: there pinch still resizes the
tile. If the owner wants the off state with no zoom at all, drop
`pictureGestures` from the pane's `.gesture(…)` (one line).

## Tests

- Core (Swift Testing, `PicturePointerTests.swift`): 3 suites, 26 tests.
  Relative mapping through zoom and pan (unzoomed = Pointer surface; zoom
  divides; pan never changes it; cursor drawn through zoom/pan and back;
  anchored zoom; limits; clamping; letterbox; pointer follow), gesture
  arbitration (scroll with nothing lost, pinch sticks and then pans,
  lopsided pinch, wobbly scroll, bounded undecided band, the single
  cut-off over a grid, pinch disabled, two-finger tap and not-a-tap,
  cancel), pinch-and-slide keeps the content under the fingers, and the
  per-Mac default and memory (off first, per Mac, round trip, bounded,
  offered/active rules, the toggle's label and ID).
- `swift test --package-path DeckHand/Core`: **996 tests pass**.
- `DeckHand/Scripts/linux-typecheck/run.sh`: passes. `MultiTouchTrackpad.swift`
  was also type-checked against throwaway UIKit stubs (not committed): it
  builds. Every changed SwiftUI file passes `swiftc -parse`.
- `PixelHandUITests.test16_PicturePointer`: screen-only arrangement (iPad:
  "Screen focus" preset; iPhone: Screen tab in landscape), captures
  `screen-only`, turns the toggle on (`pointer-control-on`), drags a finger
  (`pointer-control-moved`), pinches (`pointer-control-zoomed`), turns it
  off (`pointer-control-off`), then restores Split / portrait.

## Checks on the Mac build

iPad Pro 11″ simulator and device, portrait, landscape and a Stage Manager
window dragged to iPhone width; light and dark; then Reduce Motion and
VoiceOver.

1. Layout › **Screen focus**, mirror running: the toolbar shows the pointer
   glyph between sound and PiP, unlit. Split and Pointer presets: no
   pointer button (Split has the pad). Toolbar fits 375 pt wide (polish
   spec) with the extra button — check the narrow Stage Manager window.
2. Tap it: lit. Put a finger anywhere on the picture and move: the Mac's
   pointer moves relative (it doesn't jump to the finger), at the same speed
   as the Pointer tab. A faint dotted ring follows the finger.
3. Tap → click. Two-finger tap → right click (context menu on the Mac).
   Two fingers up/down → the Mac scrolls (natural scrolling as set),
   momentum ends cleanly when lifting. Rest a finger until it buzzes, move →
   drags a window; second finger → drag lock; tap → drop. Three fingers up →
   Mission Control.
4. Pinch out: the picture zooms around the fingers, the Mac doesn't scroll
   or zoom. Keep the pinch and slide: the picture pans. Lift, then two
   fingers up/down: the Mac scrolls (not a pan). Move the pointer towards
   the edge while zoomed: the picture pans to keep it in view; the drawn
   cursor sits exactly where the Mac's pointer is. Pinch back in to fit.
5. Wait 3 s: toolbar fades. Tap the picture: the Mac clicks, the toolbar
   stays hidden. Tap where the toolbar was: it comes back. Toggle off: taps
   bring the toolbar back again.
6. Memory: turn on, switch to Split and back: still on. Quit and relaunch:
   still on for this Mac. Switch to another Mac (My Macs): off there until
   turned on. A new Mac starts off.
7. Off: at fit, a tap shows the toolbar and nothing else changes. Pinch
   zooms the picture, a one-finger drag pans it (see "When off" above).
8. Free plan (`PH_QA_FREE=1`): the Screen focus pane shows the "Show screen"
   empty state with the Pro lock, as before; no pointer button anywhere.
9. iPhone 17 Pro: Screen tab portrait — pad under the pane, no pointer
   button. Landscape — pane alone, pointer button present, 2–5 as above.
10. Duo (book and laptop): no pointer button; mirror and pad unchanged.
11. Reduce Motion: rings appear/disappear instantly; the toggle's state
    change is instant. VoiceOver: the button reads "Control the pointer from
    the picture, Off/On, toggle"; with control on, the picture is a direct
    touch area "Trackpad on the screen of Studio" with Click, Double-click,
    Right-click actions.

## Compile risks (most likely first)

None of the SwiftUI can be type-checked on Linux.

1. `MirrorPane.body`: the `GeometryReader` closure grew (two `let`s, the
   pointer layer, the follower, `.gesture(_:including:)` with a ternary
   mask, three `onChange`s). If it exceeds the type checker's budget, move
   the `ZStack` into a `private func picture(frame:controlling:)`.
2. `pictureGestures`: `MagnifyGesture.Value.startLocation` (iOS 17) and the
   `_EndedGesture<_ChangedGesture<MagnifyGesture>>.simultaneously(with:)`
   chain returned as `some Gesture`.
3. `MirrorPicturePointerLayer.input`: the `.accessibilityAction(named:)`
   chain on `TrackpadInputLayer` (same shape as `PointerSurface.touchSurface`),
   and `TrackpadInputLayer`'s memberwise init with the new
   `sensitivityScale` and `picture` arguments in declaration order.
4. `MirrorFingerRings`: `ForEach(touches.indices, id: \.self)` over
   `[CGPoint]` and `.position(touches[index])`.
5. Toolbar button: `.accessibilityAddTraits(.isToggle)` (iOS 17) and
   `.accessibilityValue(Text(verbatim:))` on `MirrorToolButton`.
6. `ScreenSurface` → `MirrorPane(session:macName:offersPointerControl:)`:
   memberwise init with the new `@AppStorage`/`@State` private properties
   (same pattern as the existing `@State private` ones).

## Out-of-lane edits

- `DeckHandiOS/Shell/PixelHandShell.swift` (Design lane): `dockedScreen` is
  now `dockedScreen(screenOnly:)`; the two Screen-focus call sites pass
  `true`, the Split/book/laptop ones keep the default; the tabbed
  `surfaceView` passes `screenOnly: true` to `ScreenSurface`.
- `DeckHandiOS/MultiTouchTrackpad.swift` and `TrackpadView.swift` (UX-004):
  the opt-in arbitration and sensitivity scale above. Default off; the
  Pointer surface and classic trackpad don't pass them.

## Follow-ups

- **Pointer surface two-finger tap.** The interaction model lists
  "Two-finger tap → Right-click" for the pad too, but the pad still
  right-clicks only by an armed press. Turning on `arbitratesTwoFingers`
  with pinch off there would add it (scrolls would start after 10 pt of
  travel instead of at once); an owner call.
- **"Tap where you touch" mode** (answer 3: later, as a setting).
  `PictureZoom.toContent` already maps a touch to the Mac's display.
- **Double-tap to fit / 2×** on the pane when off (interaction model §Screen).

Lane: READY TO MERGE
