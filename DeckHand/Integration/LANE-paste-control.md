# Lane: paste-control (Send sheet Clipboard chip → system paste control)

Branch `claude/pixelhand-lane-paste-control`, from `claude/pixelhand-integration`
at `e017feb` (build 27 queued). Decision: `DECISIONS.md`, 2026-11-26,
"Send sheet clipboard uses the system Paste button".

## What changed

- **`DeckHandiOS/Transfer/SendPasteChip.swift` (new).** The Clipboard chip is
  now `UIPasteControl` wrapped in `UIViewRepresentable`. iOS only shows "Allow
  Paste" when the app reads the clipboard itself, and this control's paste
  doesn't count as that, so the prompt doesn't appear.
  - **Why `UIPasteControl` and not SwiftUI `PasteButton`:** `PasteButton`
    only takes a tint, a label style and a border shape. The chip spec
    (`07-Polish-Spec.md`, Sources) needs a `raised` background, a cobalt
    foreground and radius 14, and only `UIPasteControl.Configuration` has
    settings for all three. Settings used:
    - `cornerStyle = .fixed`, `cornerRadius = PixelHandTheme.Radius.chip` (14)
    - `baseBackgroundColor` = `raised`, `baseForegroundColor` = `accent`
      (cobalt). Both are dynamic `UIColor`s built from `PaletteTokens`, so
      light, dark and Increase Contrast all apply.
    - `displayMode = .iconAndLabel`
  - **Size and hairline:** 44 pt tall and a third of the row. The 0.5 pt
    hairline is drawn *behind* the control, with the control inset 0.5 pt
    so the ring shows around it, because nothing may cover a paste control.
  - **Limits set by the system:** iOS draws the control's own icon and
    localized "Paste" label. A pixel dot-glyph or the title "Clipboard"
    isn't possible, so the third chip now reads "Paste" with the system
    clipboard icon, in cobalt on `raised`. If the design pass wants it
    flagged, it's a deviation from the "glyph + label" line in the spec.
  - **Accessibility ID:** the control keeps `ph.send.source.clipboard`.
    VoiceOver reads the system "Paste" label.
  - The paste target accepts links, text and images
    (`SendPastePlan.acceptedTypeIdentifiers`). It loads each pasted item
    provider's representations in order, falls through when one gives
    nothing usable, and reports everything that loaded, in clipboard order,
    once all items are done. A newer paste cancels an earlier one that is
    still loading.
- **`DeckHandiOS/Transfer/TransferSheet.swift`.** The old `Button` +
  `stageClipboard()`, which read `UIPasteboard.general` directly, is gone.
  `SendPasteChip(onPaste: stagePasted)` replaces it.
  - Text and links go through `stageText`, the same path the chip used
    before. They become `.text` staged items and are sent by
    `center.send(text:)`.
  - Images are staged as `.file(kind: .photo)`, the same as the Photos
    chip, and sent by `center.send(fileAt:)`. Each image is written to its
    own `send-<uuid>` temp folder as "Pasted Image.png" (or "Pasted Image
    2.jpg" and so on when several are pasted).
  - When nothing usable was pasted, the field note reads "The clipboard
    has no text, link or image."
- **Core: `Transfer/SendPastePlan.swift` (new)** holds the pure logic. For
  each provider it chooses which representations to load and in what order:
  - Order: a web link, then text, then an image. When a provider has an
    image but no text, the image goes first (for example, "Copy Image" in a
    browser, which also carries the image's address).
  - Image types are preferred in this order: PNG, JPEG, HEIC, HEIF, GIF,
    TIFF. Generic `public.image` is converted to PNG.
  - Only plain web links (`TransferInlineText.webLink`) are staged as links,
    never `file:`, `javascript:` or other schemes.
  - Text is trimmed, and empty text is dropped.
  - At most 20 items are taken from one paste.
  - It also holds the file names and the "nothing to send" line.
  - Tests are in **`Core/Tests/PixelHandCoreTests/SendPastePlanTests.swift`**:
    12 Swift Testing tests.

Not touched: `ScreenshotPreviewView`, `InboxPanel`, `RemoteClipboard` /
`PasteToMacControl`, the Type panel, the capture preview and the protocol.
`PixelHandUITests.swift` isn't touched either: nothing in it references the
chip.

### Other pasteboard reads in the Send flow

There are none. Every remaining `UIPasteboard` use in `DeckHandiOS` is a
write (`ScreenshotPreviewView` :344 and :371, `InboxPanel` :95 and :109,
`RemoteClipboard` :29), and writes don't prompt. The Send field is a plain
`TextField`, and its edit-menu Paste is the system's own, so it doesn't
prompt either.

## Re-check on the iPad

Use a build from this branch, a paired Mac that's online, and the Send
sheet open (header Send button).

1. **No prompt.** Copy text in Notes, open the Send sheet and tap the third
   chip, the cobalt "Paste". Expected: no "Allow Paste" alert. The text
   appears in the tray as a "Text" row. If the alert was allowed or denied
   in an earlier build, reset it first under Settings › Pixel Hand › Paste
   from Other Apps › Ask, then check again.
2. **Text sends.** Tap the Mac card. Expected: the beam runs, and the text
   arrives on the Mac as before.
3. **URL sends.** In Safari, long-press a link and choose Copy Link, then
   tap Paste. Expected: the tray row has the link glyph, the host as its
   title and "Link" as its subtitle. Send it: the Mac opens or saves it as
   before.
4. **Image sends.** In Photos, Copy a photo (or take a screenshot and copy
   it), then tap Paste. Expected: the tray row reads "Pasted Image.png"
   (or .jpg / .heic) with "Photo · size". Send it: the Mac saves it as a
   photo. Also try "Copy Image" from a Safari page: expect the image, not
   its URL.
5. **Empty or disabled state.** Copy a PDF file from Files. The control
   should show dimmed (disabled), because the clipboard has nothing it
   accepts. With mixed content that has nothing usable, the field note
   reads "The clipboard has no text, link or image."
6. **Look.** In light, dark and Increase Contrast, the three chips should
   be equal size on one line. The Paste chip should be `raised` with a
   hairline, radius 14 and a cobalt icon and label. At AX sizes the system
   label scales by itself, and it won't shrink to 80 % like the other chip
   labels.
7. **UI test hook.** `app.buttons["ph.send.source.clipboard"]` should still
   resolve.

## Compile risks (not built on Xcode here)

- **Swift 6 sendability.** The provider callbacks capture `[weak self]`
  (a `UIView`, which is `@MainActor`), an `ArraySlice<SendPastePlan.Candidate>`
  (`Sendable`) and `UUID` / `Int` / `String`, then hop back with
  `Task { @MainActor in … }`. This is the same pattern as
  `PasteToMacControl`, which builds today. `SendPasteFiles.write` is
  `nonisolated` and runs inside the `loadDataRepresentation` callback.
- **API names to confirm in the build.** All are public UIKit, iOS 16+,
  and the target is 17.4:
  - `UIPasteControl.Configuration.cornerStyle = .fixed`, `cornerRadius`,
    `baseBackgroundColor`, `baseForegroundColor`
  - `NSItemProvider.loadObject(ofClass: URL.self)`
  - `loadDataRepresentation(forTypeIdentifier:)`
- **`SendPastePlan` without an import in `TransferSheet.swift`:** it
  resolves the way the file's other Core types already do.
- **The paste control's validation.** If iOS judges the cobalt-on-`raised`
  contrast too low, or treats the 0.5 pt inset as obscuring the control,
  the paste silently does nothing. Step 1 above catches that. The fallback
  is to drop the custom colours (system tint) and keep the shape.
- **Name clash.** There's a private `UIColor(token:)` extension in
  `SendPasteChip.swift`. If another `UIColor(token:)` with the same
  signature lands on integration, delete this one.

## Linux results

Swift 6.2 was installed at `/opt/swift-dl/swift-6.2-RELEASE-ubuntu24.04`
(it wasn't present).

- `swift test --package-path DeckHand/Core`: **1265 tests in 224 suites
  passed**, including the 12 new `SendPastePlanTests`.
- `DeckHand/Scripts/linux-typecheck/run.sh`: **Build complete, 0 errors.**
  The new iOS file uses UIKit and SwiftUI, so it can't go in that list.
- `swiftc -parse` on `SendPasteChip.swift` and `TransferSheet.swift`: OK.

Lane: READY TO MERGE
