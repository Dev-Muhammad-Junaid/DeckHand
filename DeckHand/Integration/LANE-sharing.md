# Lane: Sharing (UX-031, backlog S1/S2)

Branch `claude/pixelhand-lane-sharing`, cut from integration at `5f9f104`
and merged with `origin/claude/pixelhand-integration` at `785d970` before
handoff. **Protocol 13** (integration is at 12).

Written in a Linux container. PixelHandCore was built and tested with
Swift 6.2 (820 tests, 39 new). `MacTransferService`, `TransferCenter`,
`TransferSharedContainer`, `SharingHandler` and `LockGate` were
type-checked against stubs (`Scripts/linux-typecheck/run.sh`, now in the
default list). The SwiftUI files (Mac panel section, iOS Send sheet,
Inbox, header button), `ControlSessionModel+Transfer.swift` and the Share
extension were only parsed (`swiftc -parse`). **Neither app was compiled.**

Sharing is **Pro** on iPhone and iPad (`ProFeature.sharing`). The Mac app
stays free: it doesn't check, the device does.

## 1. What changed

### Design

- **Bytes go through Loom's transfer engine**, which LoomKit already
  creates per connection (`LoomConnectionHandle.transferEngine`). It opens
  its own control stream and one data stream per transfer, chunks (512 KB),
  windows, resumes from a contiguous offset and checks a SHA-256. Nothing
  bulk ever touches the JSON control stream. No Loom change.
- The Loom offer carries a **`TransferManifest`** in its metadata
  (`ph.kind` = `file` / `photo` / `link` / `text`, `ph.m` = `1`), the clean
  file name as `logicalName`, a UTI as `contentType`. Links and text travel
  as their UTF-8 bytes, so every item gets the same progress, cancel,
  resume and receipt.
- The receiver answers in the `sharing` domain with **`transferStatus`**:
  why it refused (Loom's decline has no reason) or where it landed.
- **Resume:** the sender reuses the item's id as the Loom transfer id.
  The receiver keeps the partial file under that id, and the next offer
  (after a drop and reconnect) is accepted from its size; Loom re-hashes
  the prefix. The device's outbox lives on disk (App Group) and survives
  relaunch; the Mac keeps its sends in memory while it runs. A resumed
  transfer doesn't prompt again.

### Protocol 13 (Core)

| Message | Way | What |
| --- | --- | --- |
| `sharing.transferStatus(transferID: UUID, status: TransferStatus)` | both | From the receiver of a Loom transfer to its sender. `awaitingApproval`; `refused(reason:)` `declined` / `macLocked` / `notPaired` / `needsPro` / `tooLarge` / `noSpace` / `unsupported`; `saved(landing:)` `downloads` / `browser` / `clipboard` / `inbox`; `failed(reason:)` `integrity` / `writeFailed` / `interrupted` / `cancelled`. |

- `RemoteInputValidation`: a strictly decoded UUID and closed enums, no
  free string or number, so it passes through (rule and comment added).
  The offer's own strings and numbers (name, size, content type, kind)
  arrive through Loom and are checked by `TransferManifest.read` and
  `TransferPolicy` before anything touches the disk.
- Lock gate: `transferStatus` allowed (it moves nothing); new
  `LockPolicy.allowsIncomingTransfer(state:)` refuses incoming transfers
  while locked **and** off console. The Mac cancels transfers in flight
  at the lock (`macLocked` to the sender) and checks again before landing.
- `PixelHandProtocol.version` 13, `PROTOCOL.md` history line and the
  bulk-data note, fixtures re-recorded (four new), `expectedCaseCount` 56.

### Core logic: `Core/Sources/PixelHandCore/Transfer/` (tested in `TransferTests.swift`)

| File | What |
| --- | --- |
| `TransferManifest.swift` | `TransferKind`, the manifest ↔ Loom offer fields, `read` with caps and cleaning |
| `TransferFileName.swift` | Network names → one safe path component (no `../`, control or bidi-override characters, leading dots; ≤ 200 bytes keeping the extension); `unique` ("a 2.pdf") |
| `TransferInlineText.swift` | Received text cleaned; **only plain `http(s)` addresses count as links** (no `file:`, `javascript:`, app schemes, credentials), so the Mac never opens anything else; titles and `.txt` names |
| `TransferPolicy.swift` | `TransferRefusal`, `TransferLanding`, `TransferFailure`, `TransferStatus`; `decide`: paired → unlocked → Pro → size cap (16 GB files, 1 MB text) → free space + 512 MB headroom → links/text and files ≤ 100 MB quietly, bigger ones ask, "Always from this device" up to 2 GB, ≥ 2 GB always asks; prompt timeout 100 s (< Loom's 120 s) |
| `TransferOutbox.swift` | The device's outbox (target Mac or "next Mac", pins to the first Mac it goes to, 8 attempts, 50 items, 7 days, cached SHA-256), `TransferResume` (partial names from the id only, resume offsets), `TransferMacEntry` (the Share extension's Mac list) |
| `TransferProgressMeter.swift` | Fraction, smoothed rate, time left, Finder-style sizes ("12 MB of 200 MB · 19 s left") |
| `TransferInbox.swift` | The Inbox list (newest first, 200 items, unseen count, link/text/photo helpers) |
| `TransferCopy.swift` | Every line (names the other device), `TransferBeamPhase` (the dot beam's states) |

### Mac: `DeckHandMac/Transfer/`

- `MacTransferService.swift`: per approved connection it reads
  `handle.incomingTransfers` and decides with `TransferPolicy` (paired from
  `DeviceAuthorizationManager.isPaired`, lock from `MacLockMonitor`, free
  space of Downloads). Partials in `~/Library/Application Support/Pixel
  Hand/Transfers/<id>.part` (cleaned after 3 days). Files land in
  `~/Downloads/Pixel Hand/` with a unique name and are **revealed in
  Finder**; links open in the **default browser**; text goes on the
  clipboard and into a `.txt`. Sending: files (images and movies as
  photos) with a SHA-256, or text/link; each send is re-offered with the
  same id if its device reconnects while the app runs. Cancel either way.
- `MacTransferSection.swift`: the menu-bar panel's **Send** section (after
  Devices): each paired, connected device with **Send ▸ File… /
  Clipboard**, the row is a **drop target** (files, links, text), incoming
  **prompts** (Accept / Decline / Always from this device), and the last
  20 transfers with a dot beam (mint when saved), caption, Cancel and
  Show. A **floating prompt panel** (non-activating, top right) asks
  while the menu-bar panel is closed. **Services** provider for Finder ›
  Services › "Send to iPhone or iPad with Pixel Hand" (plist below).
- `Handlers/SharingHandler.swift`: `transferStatus` → the service.

### iOS: `DeckHandiOS/Transfer/`

- `TransferCenter.swift`: outbox, Inbox, prompts and the Loom side, for
  the focused Mac (multi-Mac keeps one session; items for another Mac wait
  for it). Receives only from a paired Mac and only with Pro (else
  `needsPro` and a notice). Files land in `Documents/Pixel Hand Inbox/`.
  Without Pro nothing in the outbox is sent.
- `ControlSessionModel+Transfer.swift`: attaches the focused Mac once
  access is granted, detaches with the session.
- `TransferSheet.swift`: **Send** — Photos (PhotosPicker, 20), Files
  (file importer), Paste (PasteButton, no paste prompt) or type text/a
  link; a tray; the Mac cards (`MacCard`) send on tap and take drops (tray
  items, or files/photos/links/text from other apps on iPad). The **dot
  beam** runs from the device glyph to the Mac glyph, fills with
  progress, turns mint and collapses into a check when the Mac says it
  saved it (a cross when refused). Another Mac: "Switch to Studio"
  (`MacSwitcher.request`). Waiting items list with Cancel.
- `InboxPanel.swift`: **Inbox** — arriving items (progress, Cancel), then
  received items with an unseen dot. Tap: link opens, text copies, file
  opens the share sheet. Menu: Open Link, Copy, **Save to Photos**
  (add-only permission), Share…, Delete. Files sees the same folder. Also
  the prompt alert (Accept / Always from this device / Decline) and notices.
- `TransferHeaderButton.swift`: the header's Send button (`PixelGlyphs.send`,
  unseen dot, `.requiresPro(.sharing)`), hosts the prompt and notices, and
  takes in Share extension drops when the app becomes active.
- `TransferSharedContainer.swift`: the App Group layout (also compiled
  into the extension). The extension only **drops** folders
  (`Transfers/Dropbox/<id>/item.json` + file); the app moves them into
  its outbox, so the two processes never write the same file.

### Share extension: `DeckHandShare/`

`ShareViewController.swift`: images and movies (as photos), files, one web
link, or text from any app. Shows the items, the paired Macs (from
`macs.json`, which the app writes), and **Send**. It doesn't connect to
the Mac (memory and lifetime limits): it queues into the App Group and
Pixel Hand sends the next time it connects to that Mac. Without Pro (as
the app last saw it) it says so and disables Send.

## 2. Integration: `project.yml`, entitlements, plist keys

### New target (add after `DeckHandWidgets`)

```yaml
  # ─────────────────────────────────────────────────────────────
  # iOS Share extension: send to a paired Mac (S2)
  # ─────────────────────────────────────────────────────────────
  DeckHandShare:
    type: app-extension
    platform: iOS
    deploymentTarget: "17.4"
    sources:
      - path: DeckHandShare
        type: group
      # The App Group layout, shared with the app.
      - path: DeckHandiOS/Transfer/TransferSharedContainer.swift
      # `@_exported import PixelHandCore` for the shared file.
      - path: Shared/PixelHandCoreExports.swift
    dependencies:
      - package: PixelHandCore
      - sdk: SwiftUI.framework
      - sdk: UniformTypeIdentifiers.framework
    info:
      path: DeckHandShare/Info.plist
      properties:
        CFBundleDisplayName: Pixel Hand
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        NSExtension:
          NSExtensionPointIdentifier: com.apple.share-services
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).ShareViewController
          NSExtensionAttributes:
            NSExtensionActivationRule:
              NSExtensionActivationSupportsImageWithMaxCount: 20
              NSExtensionActivationSupportsMovieWithMaxCount: 20
              NSExtensionActivationSupportsFileWithMaxCount: 20
              NSExtensionActivationSupportsWebURLWithMaxCount: 1
              NSExtensionActivationSupportsText: true
    entitlements:
      path: DeckHandShare/DeckHandShare.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.widgetsflow.pixelhand
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.widgetsflow.pixelhand.share
        PRODUCT_NAME: PixelHandShare
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: 1
        TARGETED_DEVICE_FAMILY: "1,2"
        IPHONEOS_DEPLOYMENT_TARGET: "17.4"
        SWIFT_VERSION: 6.0
        APPLICATION_EXTENSION_API_ONLY: YES
        SKIP_INSTALL: YES
        CODE_SIGN_STYLE: Automatic
        DEVELOPMENT_TEAM: DD5AWPLT2V
    attributes:
      SystemCapabilities:
        com.apple.ApplicationGroups.iOS:
          enabled: 1
    scheme: {}
```

In the `DeckHandiOS` target's `dependencies`, after `- target: DeckHandWidgets`:

```yaml
      - target: DeckHandShare
```

Register the App ID `com.widgetsflow.pixelhand.share` with the App Groups
capability (`group.com.widgetsflow.pixelhand`) in the developer portal,
like the widgets. The app's own entitlements already have the group.

### iOS `DeckHandiOS/Info.plist` (Files sees the Inbox)

```xml
    <key>UIFileSharingEnabled</key>
    <true/>
    <key>LSSupportsOpeningDocumentsInPlace</key>
    <true/>
```

`NSPhotoLibraryAddUsageDescription` is already there; suggested new text
so it covers the Inbox: "Pixel Hand saves screenshots and photos your Mac
sends you to your Photos library."

### Mac `DeckHandMac/Info.plist` (Finder › Services)

```xml
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Send to iPhone or iPad with Pixel Hand</string>
            </dict>
            <key>NSMessage</key>
            <string>sendToDevice</string>
            <key>NSPortName</key>
            <string>Pixel Hand</string>
            <key>NSSendFileTypes</key>
            <array>
                <string>public.item</string>
            </array>
            <key>NSSendTypes</key>
            <array>
                <string>public.utf8-plain-text</string>
                <string>public.url</string>
            </array>
            <key>NSRequiredContext</key>
            <dict/>
        </dict>
    </array>
```

`NSPortName` must match the app's process name (`PRODUCT_NAME`, "Pixel
Hand"). The Mac app isn't sandboxed, so `~/Downloads` needs no
entitlement; macOS asks once ("Pixel Hand would like to access files in
your Downloads folder").

## 3. Checks (owner's builds)

Pair the iPad or iPhone with the Mac first (S4); Pro on (trial is fine).
Watch Console for `Transfer:` lines (category `connection`).

| Check | Expected |
| --- | --- |
| Photo, device → Mac | Header Send ▸ Photos ▸ pick one ▸ tap the Mac card. Beam fills, turns mint, check; caption "Saved to Downloads on Studio." On the Mac: `~/Downloads/Pixel Hand/IMG_….HEIC` selected in Finder; the menu-bar hand shows receive. |
| File, device → Mac | Send ▸ Files ▸ a PDF ▸ tap the card. Same, Finder reveals it. A second send of the same name lands as "name 2.pdf". |
| Link, device → Mac | Type `https://apple.com` ▸ Add ▸ tap the card. Opens in the Mac's default browser; caption "Opened on Studio." `file:///etc/hosts` or `javascript:…` is saved as text, never opened. |
| Text, device → Mac | Type a sentence ▸ Add ▸ card. On the Mac's clipboard and in Downloads as `<first words>.txt`; caption "On Studio's clipboard." |
| Photo, Mac → device | Menu bar ▸ Send ▸ next to the device ▸ Send ▸ File… ▸ a JPEG (or drag it onto the device row). Device: Inbox dot on the header Send button; Inbox row "From Studio"; menu ▸ Save to Photos asks for add-only access once, then "Saved to Photos." The Mac's row turns mint, "In iPad's Inbox." |
| File, Mac → device | A ZIP via File…: Inbox row; tap ▸ share sheet (Save to Files works); Files app ▸ On My iPad ▸ Pixel Hand ▸ Pixel Hand Inbox shows it. |
| Link, Mac → device | Copy a URL on the Mac ▸ Send ▸ Clipboard. Inbox row shows the host; tap opens Safari. |
| Text, Mac → device | Copy text ▸ Send ▸ Clipboard (or drag selected text onto the device row). Inbox row; tap copies ("Copied."). |
| 200 MB, prompt | Send a 200 MB file device → Mac. The Mac asks (floating panel top right, and the menu-bar section): "iPad wants to send you “….mov” (200 MB)." Device caption "Waiting for Studio to accept". Decline → device "Studio declined it.", item gone. Again, Accept → progress with rate and time left on both sides. |
| 200 MB, cancel | Mid-transfer, Cancel on the device: both rows stop ("Cancelled."), the Mac's partial in `~/Library/Application Support/Pixel Hand/Transfers/` is deleted. Same with Cancel on the Mac's row. |
| 200 MB, resume | Mid-transfer, turn the device's Wi-Fi off (or quit the Mac app's connection by walking away) for ~15 s, then back. After reconnect the item is offered again, the Mac **doesn't ask again**, and progress continues from where it stopped (Console: "Transfer: resuming at N of M B"); the file is intact (opens). Kill and relaunch the iPad app mid-transfer: the item waits in Send ▸ Waiting and resumes on connect. |
| Always from this device | Accept a 200 MB item with "Always from this device": the next 200 MB item lands without a prompt; a 2.5 GB item still asks. |
| Share extension, Photos | Photos ▸ a photo ▸ Share ▸ Pixel Hand. Sheet lists the photo and the paired Macs; Send ▸ "Queued". Open Pixel Hand connected to that Mac: it sends (Send ▸ beam, Mac reveals it). With the app already connected in the background, it sends when you return to it. |
| Share extension, Safari | Safari ▸ Share ▸ Pixel Hand on a page ▸ Send. Next connect: the page opens in the Mac's browser. |
| Share extension, no Mac / no Pro | Before any pairing: "Pair a Mac in Pixel Hand first." With Pro expired (Store checks): "Sending to your Mac is part of Pixel Hand Pro…", Send disabled. |
| Locked Mac | Lock the Mac (⌃⌘Q), send a photo from the device: caption and alert "Studio is locked. Unlock it and send again."; nothing lands. Start a 200 MB send, lock the Mac mid-way: the device shows the same line, the Mac's partial is deleted. Another user at the login window (fast user switching): same. |
| Unpaired device | A device allowed once (not paired) sends: "Studio only takes items from paired devices…"; the Mac's Send section doesn't list that device. |
| Free tier lock | No Pro: the header Send button is dimmed with a lock; tapping opens the paywall "…part of Pixel Hand Pro". Mac ▸ Send to the device: the Mac's row says "Sending to iPad needs Pixel Hand Pro on it."; the device shows "Studio tried to send you something. Receiving needs Pixel Hand Pro." Items queued by the extension stay waiting until Pro is on. |
| Two Macs (multi-Mac) | Send ▸ tap the other Mac's card: the item waits ("Waiting for Laptop"), "Switch to Laptop" switches and it sends there. |
| Services | Finder ▸ right-click a file ▸ Services ▸ Send to iPhone or iPad with Pixel Hand (enable it once in System Settings › Keyboard › Shortcuts › Services if hidden): it goes to the connected paired device. |
| VoiceOver | Header button "Send and Inbox, 2 new"; Mac card "Send to Studio"; beam row reads its caption; Inbox rows read title, sender, "New". |

## 4. Compile risks (most likely first)

1. **`ControlSessionModel+Transfer.swift`**: `withTaskCancellationHandler`
   inside a `@MainActor` method, with an `@MainActor` closure capturing
   `weak self`. If Swift 6 complains about isolation, make `onCancel`
   `{ Task { @MainActor in … } }` (it is) and mark the `isPaired` closure
   `@Sendable @MainActor`.
2. **`TransferSheet.swift` `PickedPhotoFile`**: two `FileRepresentation`s
   in one `transferRepresentation`, and `PasteButton(payloadType:)`'s
   closure isolation. If PhotosPicker can't load as `.image` for HEIC,
   switch the first to `importedContentType: .item`.
3. **`MacTransferService` cross-actor `handle.transferEngine`** is a `let`
   on LoomKit's actor: `try await handle.transferEngine.offerTransfer(…)`
   relies on one `await` covering the property read and the call. If the
   compiler wants it split: `let engine = await handle.transferEngine`.
4. **`MacTransferServicesProvider.sendToDevice(_:userData:error:)`** is
   `@MainActor` and `@objc`; the error parameter is
   `AutoreleasingUnsafeMutablePointer<NSString?>`. If AppKit doesn't call
   it, check the selector matches `NSMessage` (`sendToDevice`).
5. **`MacTransferService.init` sets `NSApp?.servicesProvider`**: `shared`
   is first touched when the first device connects, so Services only work
   after that. Fine for the feature (nothing to send to before), but set
   it from the app delegate if you want the menu item to answer earlier.
6. **`InboxPanel`** uses `UIPasteboard`, `UIDevice`,
   `PHPhotoLibrary.performChanges` (async) and the app's existing
   `ShareSheet` (from `ScreenshotPreviewView.swift`); `MacDotBeam` and
   `MacSectionLabel` signatures on the Mac.
7. **Share extension**: `@Observable` + `@Bindable` (iOS 17),
   `NSItemProvider.loadItem` async overloads returning `NSSecureCoding`
   cast to `URL` / `String`; `APPLICATION_EXTENSION_API_ONLY` (nothing
   here uses `UIApplication`).

## 5. Out-of-lane edits

| File | Owner | Edit |
| --- | --- | --- |
| `Core/…/System/LockPolicy.swift` | Mac system control | `case .transferStatus: return .allow` in the sharing switch; new `allowsIncomingTransfer(state:)` |
| `Core/…/Input/RemoteInputValidation.swift` | iOS interaction | `case .sharing(.transferStatus): return message` with the rule comment |
| `Core/…/Protocol/PixelHandProtocol.swift`, `Core/PROTOCOL.md`, protocol fixtures + `MANIFEST`, `ProtocolContractTests.swift` | shared protocol | version 13, history line, bulk-data note, four samples, case name, count 56 |
| `DeckHandMac/LockGate.swift` | Mac system control | 3 lines marked `// Sharing lane`: `MacTransferService` add / remove connection in `MacSystemSession`, and `lockStateChanged` |
| `DeckHandMac/MacMenuBarView.swift` | Pairing / UX Mac | `MacTransferSection()` after the Devices section |
| `DeckHandiOS/Shell/ShellHeader.swift` | Shell (UX) | `TransferHeaderButton()` after `captureMenu` |
| `DeckHandiOS/Control/ControlSessionModel.swift` | Integration | the `runTransfers()` task in `run(settings:)` (3 lines) |
| `DeckHandiOS/Control/ControlSessionModel+Input.swift` | iOS interaction | `case let .transferStatus` → `TransferCenter.shared.receivedStatus` (needed: the switch is exhaustive) |
| `Scripts/linux-typecheck/run.sh`, `Stubs.swift` | shared tooling | `MacTransferService`, `TransferCenter`, `TransferSharedContainer` in the default list; stubs for Loom transfers, `NSPasteboard`, `UTType`, `SHA256`, `containerURL`; `CryptoKit`, `UniformTypeIdentifiers`, `Photos`, `PhotosUI` imports stripped |

`SharingMessage.swift` and `Handlers/SharingHandler.swift` were extended
(this lane's per the brief); clipboard sync is unchanged. No Duo or PiP
files touched. The classic layout (`ControlView`) has no Send button;
transfers still run there, and prompts auto-decline after 100 s.

Lane: READY TO MERGE
