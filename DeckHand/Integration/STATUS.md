# Pixel Hand integration branch: status

Branch: `claude/pixelhand-integration`, cut from `origin/main` (`b920181`) on
16 November 2026.

This branch holds all the pending work and the rename from Deck Hand to
**Pixel Hand**. It was put together in a Linux container with no Xcode, so
**none of it has been compiled**. The Mac session builds it, fixes compile
errors on this same branch, and runs the end-to-end checks below.

## 1. What was merged, in order

| # | Branch | Brought in | Merge commit |
| --- | --- | --- | --- |
| 1 | `claude/happy-lovelace-jso3t1` (`b9db419`) | CI runs on PRs only; DocC Pages workflow removed; `actions/checkout` pinned to v4.4.0 by SHA; AGENTS.md wording | `2657825` |
| 2 | `claude/affectionate-euler-0yuyqm` (`08ccca3`) | `eb916ad`: LoomHost's blocking `accept()`/`read()` move onto dispatch queues (`LoomHostBlockingIO`), plus a regression test. `08ccca3`: CI path filters, one build for both steps, 8-minute test-step limit. These are the two commits after PR #8's head `05063a0`. | `ad2f177` |
| 3 | `claude/app-store-prep` (`9ce8077`) | Release identifiers; the iPad `try!` crash fix (`StartupFailureView`); both `PrivacyInfo.xcprivacy` files; `ITSAppUsesNonExemptEncryption = NO`; Sentry in both apps (`Shared/DeckHandDiagnostics.swift`, DSN from the `SENTRY_DSN` build setting via `Info.plist`); privacy-page update; `DeckHand/AppStore/` docs | `829db3f` (no conflicts) |
| 4 | `scratch/trial-merge-loom-2.2.16` (`b672d55`) | Upstream Loom 2.2.16 (`3e005c0`) with its 16 conflicts already resolved; `DeckHandHandshakeTrustProvider` wired into `MacHostApp.swift`; `swift-nio-ssh` `from: "0.14.1"` (resolves to 0.15.1, see `Package.resolved`) | `187b3bb` |

Then, on top:

- `7b455f4`: the rename to Pixel Hand (§3).
- `fc262ec`: the "Please update" check, and running every Loom test (§4).

## 2. Conflict resolutions

### Raised by this integration

| Step | File | Resolution |
| --- | --- | --- |
| 2 | `.github/workflows/ci.yml` | Kept happy-lovelace's PR-only trigger (no `push:`) and pinned checkout. Added affectionate-euler's `paths:` filter to the `pull_request` trigger, plus `swift build --build-tests --scratch-path .build-local`, `--skip-build` and `timeout-minutes: 8`. The two comment blocks are merged into one. |
| 2 | `.github/workflows/docc-pages.yml` | Modify/delete. affectionate-euler made it manual-only; happy-lovelace deleted it. **Kept deleted**, as the owner chose. |
| 4 | `Sources/LoomHost/Internal/LoomHostSocketConnection.swift` | The October review predicted this conflict. Upstream replaced the raw file descriptor with `LoomHostSocketDescriptor`: leased reads and writes that `hardClose()` can interrupt, and a `defer { frameDispatcher.close() }`. affectionate-euler moved the blocking `read` off the cooperative pool. **Combined:** the read loop keeps upstream's `defer` and calls `descriptor.read(into:)` *inside* `LoomHostBlockingIO.perform`, so the read is both interruptible and off the pool. The `(chunk, readError)` handling after the read is affectionate-euler's. `LoomHostBroker.swift` (the accept loop) and the new test merged without conflict. |

Nothing else conflicted textually.

### Re-checked semantically against steps 1–3

- **`MacHostApp.swift`:** app-store-prep's `DeckHandDiagnostics` calls and step 4's `trustProvider:` argument auto-merged into the same `LoomContainerConfiguration(...)` call. The argument order matches upstream's initializer: `remoteSignaling`, then `trustProvider`, then `retryPolicy`.
- **iOS `DeckHandApp.swift`:** app-store-prep's `do`/`catch` container build uses only `serviceType`, `serviceName`, `deviceIDSuiteName`, `cloudKit`, `remoteSignaling` and `retryPolicy`. All of them still exist upstream in that order.
- **App code against upstream Loom:** every `Loom*` type the apps name exists after the merge. Spot-checked members that still exist: `LoomContext.connect/disconnect/publishRemoteReachability`, `LoomConnectionHandle.send/disconnect`, `LoomSharedDeviceID.getOrCreate(suiteName:)`, `LoomRetryPolicy.disabled`, `LoomPeerSource.cloudKitOwn`, `LoomIdentityManager.keyID(for:)`, `LoomPeerIdentity.isIdentityAuthenticated/identityKeyID/identityPublicKey`. This was a grep, not a compile.
- **`AGENTS.md`:** has happy-lovelace's DocC wording and upstream's "Repository Isolation" section.

### Inherited from the scratch branch (not redone)

These are the 16 conflicts of the upstream merge itself: `Package.swift`, `Logger.swift`, `BonjourBrowser.swift`, `BonjourEntitlementCheck.swift`, `LoomAsyncBroadcaster.swift`, `LoomAuthenticatedSession.swift`, `LoomSessionProtocol.swift`, `LoomIdentityManager.swift` (with the keychain fix moved into `LoomKeychainIdentityKeyStorage.swift`), `LoomTransferEngine.swift`, `LoomConnectionFailure.swift`, `LoomCloudKitManager.swift`, `LoomVirtualAppSession.swift`, `LoomTransferEngineTests.swift`, `README.md`, `AGENTS.md` and `Architecture.md`. Each one's resolution is in §3.2 of `docs/review/upstream-comparison-2026-11.md` on `origin/claude/upstream-comparison-2026-11`. Read it with `git show`, because `docs/` is gitignored.

## 3. Rename coverage

### Changed

| What | Now |
| --- | --- |
| iOS/iPadOS bundle ID | `com.widgetsflow.pixelhand` |
| Mac bundle ID | `com.widgetsflow.pixelhand.mac` |
| Tests bundle ID | `com.widgetsflow.pixelhand.tests` |
| iCloud container | `iCloud.com.widgetsflow.pixelhand` (both `.entitlements`, `Shared/DeckHandCloud.swift`) |
| Keychain access group (Mac) | `$(AppIdentifierPrefix)com.widgetsflow.pixelhand.mac` |
| Log subsystem | `com.widgetsflow.pixelhand` (`Shared/DeckHandLog.swift`) |
| Mirror queue label | `com.widgetsflow.pixelhand.mirror.frames` |
| Bonjour | `_pixelhand._tcp`, in both `Info.plist` `NSBonjourServices` and both `LoomContainerConfiguration(serviceType:)` calls |
| Remote session ID prefix | `pixelhand-<uuid>` (`MacHostApp.swift`; inert until a relay exists) |
| `PRODUCT_NAME`, `CFBundleDisplayName` | `Pixel Hand` (so the bundles are now `Pixel Hand.app`) |
| Permission usage strings | Local Network, Accessibility, Screen Capture, Photos (both plists) |
| In-app copy | Onboarding, picker, startup-failure screen, settings, menu-bar panel, status-item accessibility labels, notification title, Screen Recording error, `print` prefixes, file-header comments |
| Sentry | Projects `pixelhand-ios` / `pixelhand-mac` (`project.yml` `SENTRY_PROJECT`, `AppStore/Sentry.md`); the org slug `widgetsflow` is unchanged |
| App Store | Name "Pixel Hand: Remote for Mac" (26 characters), fallback "Pixel Hand – Mac Remote" (23), SKU `pixelhand-ios`. `StoreListing.md` now gives the reason for the new name. |
| Website | `src/index.html` and the `public/index.html` rebuilt from it with `tools/mockups/build.py`; `privacy.html`, `joined.html`, `404.html`, titles, OG/meta tags, waitlist copy, CSS/JS comments, the Bonjour diagram (`_pixelhand._tcp`). README: KV namespace `pixelhand-waitlist`. |
| Docs | `README.md`, `DeckHand/AppStore/*.md`, `AppleOS27-Support.md`, `MenuBarStatusItems-macOS26.md` |

After the change, `git grep -i "deck hand\|com\.widgetsflow\.deckhand\|_deckhand\|deckhand-"` matches only this file and the history notes listed below.

### Still says Deck Hand or deckhand, on purpose

- **Internal names, as instructed:**
  - targets `DeckHandMac`, `DeckHandiOS`, `DeckHandTests`;
  - the `DeckHand/` folder and `DeckHand.xcodeproj`;
  - every `DeckHand*` Swift type and file;
  - `project.yml` `name: DeckHand`.
- **Internal string keys** no one sees:
  - the `DeckHandLoomStore` defaults suite;
  - the `DeckHandStatusItem` autosave name;
  - the `DeckHand.appMenuShortcutsImported` notification;
  - the `deckhand_installed_apps.json` cache file;
  - the website's `deckhand.waitlist.joined` localStorage key.

  Because the bundle IDs are new, these all start out empty anyway.
- **History:**
  - the old IDs `com.deckhand.mac`/`.ios` and `iCloud.com.deckhand.shared` in `MacBuildChecklist.md`, `AppStoreConnectSetup.md` and `AppleOS27-Support.md`;
  - `AppStoreConnectSetup.md`'s note to leave alone anything already registered under `com.widgetsflow.deckhand*`;
  - "Deck Hand" as the old app's name in the checklist;
  - the old name and the DECKHAND trademark in `StoreListing.md`'s naming rationale;
  - the "formerly Deck Hand" note in `README.md`.
- **Loom sources:** "DeckHand fork" comments in `Sources/` mark the fork's patches. They're internal and left alone.
- **GitHub URLs:** the repository is still `Dev-Muhammad-Junaid/DeckHand`.
- **Support and contact email:** the placeholders are left as they are; the owner hasn't chosen an address.

## 4. Owner decisions applied (week 1, Option C)

- **"Please update" check.**
  - `Shared/PeerCompatibility.swift` compares a peer's `LoomPeerAdvertisement.protocolVersion` with this build's `Loom.protocolVersion`. A device's version comes from its Bonjour TXT `proto` key.
  - **iPad/iPhone picker** (`PeerPickerView.swift`): a mismatched Mac's card reads "Please update Pixel Hand on your Mac" (older Mac) or "…on your iPad" / "…on your iPhone" (newer Mac). Tapping it shows that message instead of dialling.
  - **Mac menu-bar panel** (`MacMenuBarView.swift`): a "NEEDS AN UPDATE" section lists nearby iPhones and iPads on another protocol, with the matching line. This works because LoomKit advertises and browses on both sides.
  - **Tests:** `DeckHandTests/PeerCompatibilityTests.swift` (XCTest, like the contract tests).
- **Tests un-skipped.**
  - The CI `--skip` flags for `invalidResumeOffsetIsRejected` and `liveSamePeerConnectionOutsideWindowIsDropped` are removed.
  - `liveSamePeerConnectionOutsideWindowIsDropped` has `.timeLimit(.minutes(1))`.
  - Apart from the step-1/2 merges, that is the only change to `ci.yml`.
- **Not done (later sessions):**
  - persistent pairing;
  - AWDL off, local cursor, the mirror's own stream, Mission Control shortcut reading, display wake;
  - Sparkle and the notarized DMG;
  - HEVC.

## 5. Unverified until a Mac build

- **Everything compiles:** the upstream merge, the 16 inherited resolutions, the LoomHost read-loop combination, Sentry under Swift 6, `PeerCompatibility` and both UI changes. Likely compile-fix spots:
  - `Shared/DeckHandDiagnostics.swift` (Sentry API and Swift 6 isolation);
  - `LoomHostSocketConnection.swift` (`descriptor` captured in a `@Sendable` closure; `LoomHostSocketDescriptor` is `@unchecked Sendable`, so it should be fine);
  - `DeckHandHandshakeTrustProvider` (`nonisolated` witnesses for `@MainActor` protocol requirements);
  - the file-scope `@MainActor private var thisDeviceKind` in `PeerPickerView.swift`;
  - the `switch` expression in `MacMenuBarView.outdatedPeers`.
- **The two un-skipped tests now pass.** `invalidResumeOffsetIsRejected` is expected to pass after upstream's transfer rewrite. `liveSamePeerConnectionOutsideWindowIsDropped` should either pass or fail within a minute, not hang.
- **The new LoomHost test passes on the merged code:** `framesArriveWithMoreWaitingReadLoopsThanCores`.
- **First-time pairing works through `DeckHandHandshakeTrustProvider`,** and Allow/Deny still gates commands.
- **The "please update" UI renders as intended.** It is hard to trigger for real, because both apps share one Loom. To see it, build one device with `PeerCompatibility.localProtocolVersion` temporarily set to `2`, then revert.
- **Old Deck Hand builds and Pixel Hand builds never see each other at all.** The Bonjour type changed, so the version check only matters for future Loom protocol bumps between Pixel Hand builds.
- **Signing and capabilities.**
  - The new IDs and container aren't registered yet. App Store Connect is out of scope here; a separate Mac task registers them. With automatic signing, Xcode may try to register them itself.
  - The README asks for `-allowProvisioningUpdates`.
- **Export compliance.** `AppStore/ExportCompliance.md` checked swift-crypto 3.15.1. After the merge, core `Loom` links swift-crypto `exact: 4.5.1`. Re-confirm that on Apple platforms it still only re-exports CryptoKit, with no bundled BoringSSL.
- **Package resolution on the Mac:** `swift-nio-ssh` ≥ 0.14.1 (0.15.1 in `Package.resolved`), with Sentry from `sentry-cocoa` 9.34.0.
- **Wire break:** pair this build against a `main` build and confirm they don't connect.

## 6. Commands for the Mac session

From the repository root, on Xcode 27 / Swift 6.4:

```bash
git fetch origin claude/pixelhand-integration
git switch claude/pixelhand-integration

# Loom package: full suite, nothing skipped
swift package resolve
swift build
swift test --scratch-path .build-local 2>&1 | tee /tmp/pixelhand-loom-test.log

# Apps
cd DeckHand
xcodegen generate
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandMac   -destination 'platform=macOS' -allowProvisioningUpdates build
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandiOS   -destination 'generic/platform=iOS' -allowProvisioningUpdates build
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandTests -destination 'platform=macOS' test
```

Expect two test bundles: the 12 contract tests and the 4 `PeerCompatibilityTests`.

Then go through `DeckHand/AppStore/MacBuildChecklist.md` §3–5 for install, permissions and the on-device checks. Also run §3.6 "manual check on hardware" in the upstream comparison doc: pairing, Deny, the 45 s timeout, re-prompt on relaunch, receipts and the mirror. Launch the Mac app with `open` or from Finder, never by running the executable directly (`MenuBarStatusItems-macOS26.md`).

## Also merged before the first Mac build (2026-11-16)

- `claude/pixelhand-m0-fixes`: remote-input validation (PH-031 host crash), Show Desktop, Launchpad, duplicate bundle-ID crash, mirror start race, pre-approval input gate, plus three small extras. Details and on-device checks: `DeckHand/Integration/M0-FIXES.md`. New XCTest files in `DeckHandTests`.
- `claude/pixelhand-release`: Sparkle 2 in the Mac target (`AppUpdater.swift`, "Check for Updates…" row), release scripts in `DeckHand/Scripts/release/`, website download section, manual `release-mac.yml` workflow. Sparkle stays inert while `SPARKLE_PUBLIC_ED_KEY` is empty. Owner guide and Mac checks: `DeckHand/Release/RELEASING.md` §5.

The two branches touched no common files and merged cleanly. Extra compile-risk spots: the Swift 6 Sendable notes at the end of `M0-FIXES.md`, and `AppUpdater`'s `nonisolated` delegate methods.

Status: READY FOR MAC BUILD

## Mac build results (2026-11-17)

Mac session on macOS 27.0 (26A428), Xcode 27.2 (27B52), Swift 6.4.2, MacBook Pro M1 Pro with two displays. Built from `4a6bcf8`; fixes pushed up to `9e3dc79`.

### Build

| Target | Result |
| --- | --- |
| Loom package (`swift build --build-tests`) | Builds after fixes 1–4 below |
| `DeckHandMac` (Debug, `-allowProvisioningUpdates`) | **Builds.** Signed by team `DD5AWPLT2V`; entitlements carry `iCloud.com.widgetsflow.pixelhand` and keychain group `DD5AWPLT2V.com.widgetsflow.pixelhand.mac`. No warnings from Pixel Hand's own sources. |
| `DeckHandiOS` (device and simulator) | **Builds.** No warnings from Pixel Hand's own sources. |

The Xcode account for Mega Creations LLC signs in fine; automatic signing created the profiles on the first build. Sparkle resolved to 2.10.1, and sentry-cocoa to 9.35.0. Note: building the app project rewrites the repo-root `Package.resolved` with the app's Sentry/Sparkle pins. Those were discarded each time and not committed; don't commit them into Loom's file.

### Tests

- **Loom, `swift test --scratch-path .build-local`, nothing skipped:** **all pass.** That is 461 Swift Testing tests in 8 runs (LoomTests 363, LoomKitTests 40, and 13 + 10 + 5 + 9 + 6 + 15 in the other targets) plus 7 XCTest, in about 20 s with no hangs.
  - The two un-skipped tests pass: `invalidResumeOffsetIsRejected` (0.14 s) and `liveSamePeerConnectionOutsideWindowIsDropped` (4.5 s).
  - The new LoomHost read-loop test passes.
- **Before the fixes**, there were 9 failures:
  - **7 in LoomKitTests**, new with the merge and fixed by 6: the fork's own lifecycle and dedup tests got `authenticationFailed`, because a receiver with no trust provider now requires approval.
  - **`peerProjection`**, upstream and machine-dependent, fixed by 7: it needs an `en7` interface.
  - **"Restarting authenticated advertising closes every previous listener generation"**, an upstream test that is load-sensitive. It failed once while an iOS build ran at the same time, then passed 3 of 3 alone and in the full run. Left as is.
- **App tests, `DeckHandTests` scheme:** **51 of 51 pass**, after fixes 8 and 9. That's ControlMessageContract, UIContextSnapshotContract, PeerCompatibility, RemoteInputValidation, SystemMacro, DuplicateBundleID, SerialTaskQueue and PreApprovalGate.

### Fixes pushed (one commit each)

1. `efa3d21` Loom merge: `randomNonce()` throws in the fork, so two call sites in `LoomSessionSecurity` were missing `try`.
2. `7b80048` Loom merge: `LoomStore`'s retry path still passed `overlayPeer:` to `signalingFallbackSessionID`, which upstream removed. It now matches the first-connect path.
3. `08e29d0` Loom merge: `LoomDiagnosticsView` used `LoomPeerSnapshot.isShared`, which upstream removed. The "Shared" badge is dropped.
4. `7dc8d0f` Fork tests: these used `LoomSession`/`rawSession:`, `shareManager:` and `isShared:`. They're updated to upstream's `connection: .tcp(_)` and `peerManager:`.
5. `f822d37` `AppUpdater`: Swift 6 rejected sending the non-Sendable `installHandler` into `MainActor.assumeIsolated`. Sparkle calls this on the main thread, so the handler is captured `nonisolated(unsafe)`.
6. `77fc62d` Fork LoomKit tests: the loopback receiver gets an explicit always-trust provider (`LoomKitTestAlwaysTrustProvider`).
7. `1a290b7` Upstream test: `fe80::4%en7` became `%lo0`. Network.framework drops the scope of an interface that doesn't exist.
8. `b71b763` `SerialTaskQueueTests`: Swift 6.4's region checker can't analyse `group.addTask { @MainActor in }`. The concurrent callers are now main-actor `Task`s.
9. `a823d97` `RemoteInputValidation`: an in-bounds region came back changed by Float rounding (0.25 → 0.24999999). An already-inside region is now returned untouched. This was found by the existing test.
10. `9e3dc79` **Runtime bug found end to end:** the pre-approval gate (M0 #6) also dropped the app-list request that `ControlView` sends on appear. After a first-time Allow, the Apps tab stayed on "Loading apps from Mac…" for good. The iPad now asks again on the first `granted`. Verified in the simulator.

### Install

- **Mac:** a signed Debug build is at `/Applications/Pixel Hand.app`, launched with `open` only (never ⌘R, never the executable). The old `/Applications/Deck Hand.app` is untouched and wasn't running. The menu-bar icon shows (owner confirmed).
- **Mac permissions granted by the owner:** Accessibility, Screen Recording and Notifications. Automation and Local Network weren't prompted during this pass.
- **iPad Air 11" (M3), physical:** installed with `devicectl`. It didn't launch because the iPad was locked. The old Deck Hand app is untouched. The iPad permissions (Local Network, Photos) haven't been granted yet.
- **iOS Simulator:** **boots now** (iPad Pro 11" M5, iOS 26.5 runtime). Every end-to-end check below was done from the simulator against the Mac host on this machine.

### End-to-end (simulator → Mac host)

| Check | Result | Notes |
| --- | --- | --- |
| Discovery (`_pixelhand._tcp`) | **Pass** | |
| Handshake via `DeckHandHandshakeTrustProvider` → "Waiting for Approval" | **Pass** | |
| Deny | **Pass** | The iPad shows "Access Denied". |
| 45 s timeout | **Pass** | At 45 s the iPad shows "Access Denied … was declined". The copy should say it timed out. |
| Prompt again after relaunching the host | **Pass** | Confirmed in the host log. |
| Allow from the notification | **Pass** | |
| Input sent before approval is dropped | **Pass** | Host log: "Dropped 5 message(s) sent before approval", then "Granting". |
| Cursor movement | **Pass** | Confirmed by the owner. |
| Fast two-finger flick | **Pass, no crash** | Not confirmed visually. |
| Locate, Mission Control | **Pass** | Confirmed by the owner. |
| **Show Desktop** | **Fail** | See bug 1. |
| **Launchpad / Apps** | **Fail** | See bug 2. |
| Shortcut chips from real menus | **Pass (display)** | Chrome and Finder chips appeared and follow the frontmost app. Pressing them wasn't tested. |
| App list after first Allow | **Fail → fixed** | `9e3dc79` |
| Mirror, one remote | **Pass** | "Mirror stream started (20 fps, 640px, display 2)". |
| Mirror, two remotes | Not tested | Needs the iPhone or a second simulator. |
| Spaces chevrons on the mirror | Inconclusive | The frontmost app changed after ›; not confirmed visually. |
| Multi-display switching | Not tested | |
| Region capture, OCR, annotation | Not tested | |
| Keyboard, media keys, dialog-button chips, delivery-receipt dots | Not tested | Skipped on purpose: from the simulator they would type into whatever app had focus on the owner's Mac. |
| Menu-bar dot-hand icon | **Pass** | |
| "Check for Updates…" | **Pass** | Greyed out while there's no key. Host log: "Sparkle not started: SUPublicEDKey or SUFeedURL is missing". |
| Share crash reports, Mac panel | **Pass** | Present and ticked. |
| Share crash reports, iPad Settings → Privacy | **Pass** | Present and on. |
| Dark mode; iPad portrait and landscape | **Pass** | |
| Light mode | Pass | |
| iPhone layouts | Not tested | |
| Real iPad | Not tested | Installed but locked. |

### Open bugs for the cloud fix sessions

1. **Show Desktop does nothing on macOS 27** (M0 #2).
   - `Mission Control.app/Contents/MacOS/Mission Control 1` is a silent no-op; run by hand from a shell, it exits 137 and shows nothing.
   - The F11 fallback can't help here: this Mac has Show Desktop disabled (`com.apple.symbolichotkeys` key 36 `enabled = 0`), and the fallback only runs when the binary is missing.
   - It needs a trigger that works on macOS 27 and doesn't depend on the user's binding.
2. **Launchpad does nothing on macOS 27** (M0 #3).
   - `open -a Apps` and `open -b com.apple.apps.launcher` exit 0, but LaunchServices logs "Asking CSUI to launch 0 items" and nothing appears.
   - Needs another way to show Apps on 27.
3. **Minor copy: the 45 s expiry reads as "was declined".** The iPad's "Access Denied" card should say the request timed out.
4. **Minor: header says "Connected" behind the denied and waiting cards.**
5. **Minor: iPad Settings header overlap.** In dark mode, scrolled content (the appearance segmented control) shows through behind the "Settings" title.
6. **Stale copy (already known from the checklist):** "Recognize my own devices — Not available … needs a CloudKit container registered to a paid developer account." The container is registered now.
7. **Simulator only: the iOS app's Bonjour advertiser loops.** LoomKit's advertiser fails with `-65563 ServiceNotRunning` about once a second and recovers, with no backoff. It's probably the simulator's mDNS. Check on a device whether Loom's recovery needs a backoff.

### Still to do on hardware (owner)

Do these on the real iPad and iPhone:

- the Local Network and Photos prompts;
- keyboard, media keys, a scroll flick, and dialog-button chips with receipt dots;
- capture, OCR and annotation;
- two remotes on the mirror at once (M0 #5 steps 1–4);
- display switching and Spaces;
- iPhone layouts;
- the Automation prompt on first Mission Control or App Exposé.

Also, quit and remove the old Deck Hand apps when ready. They were left in place.

### Real iPad pass (2026-11-17, iPad Air 11" M3, owner-reported)

The old Deck Hand app is removed from both devices: uninstalled from the iPad, and the Mac app moved to the Trash.

**Note:** the first iPad install was a device build from before `9e3dc79`. That's why the owner first saw "Loading apps from Mac…" again. After a rebuild and reinstall, the app grid loads and works.

| Check | Result |
| --- | --- |
| Discovery, connect, Allow | **Pass** |
| Trackpad | **Pass** |
| Keyboard | **Pass** |
| Media keys | **Pass** |
| Spotlight button | **Pass** |
| App grid after first Allow | **Pass, with `9e3dc79`** |
| Capture and OCR | **Pass** |
| Screen mirror | **Pass** |
| Show Desktop, from the Trackpad bar and from Quick Actions | **Fail** (bug 1) |
| Spaces switching | **Fail** (bug 8) |
| Connection stability | **Fail** (bug 9) |
| Annotation, two remotes at once, iPhone layouts, dialog chips and receipt dots | Not reported yet |

### More open bugs

8. **Spaces switching, diagnosed on 2026-11-17.** Automation for System Events is on.
   - **The mechanism works on macOS 27:** ⌃→ sent through System Events with the pointer on the built-in display moved it from desktop 2 to desktop 3.
   - **Cause on this Mac:** the HP E273 (main, display 2) has **one** desktop; the built-in display has three. The mirror always shows the main display (see 8b). Its ‹ › buttons send `switchSpace(displayID: mirrored display)`, so they target the single-desktop HP and nothing can change.
   - **Why it fought Locate:** after the 800 ms wait, the host still centred the pointer on the target display and pinged `CursorLocator`, dragging it across displays.
   - **Fixed in `1b41cdd`:** when no `activeSpaceDidChangeNotification` arrives, the host restores the pointer and skips the ping, and logs "Space switch … changed nothing". Verified from the simulator: the pointer stayed at (758, 720) and the log line appeared.
   - **Still open:** the three-finger swipe targets the display under the pointer. Confirm on the iPad that it switches the built-in display's three desktops. The simulator can't make a three-finger touch.
   - **Still open, UX:** with one desktop there's no feedback. Consider a brief "No other desktop on this display" note on the iPad, or hiding ‹ › when the mirrored display has a single Space.
8b. **The iPad can't choose which display to mirror.**
   - The host sends `displayListUpdate(displays:selectedDisplayID:)`, but `ControlView` keeps only `selectedDisplayID` and drops the list. No picker exists, so the mirror always starts on the main display (`preferredDisplayID: nil`).
   - This is the "multi-display switching" item. It needs a display picker on the mirror. The Spaces chevrons and the owner's request for a cursor-location hint (bug 10) depend on it.
9. **The iPad disconnects after a couple of minutes of use.**
   - Host log, first time: the iPad connected at 18:46:47, then "Liveness timeout … dropping" at 18:47:57.
   - Second time: the iPad's message loop ended (peer side) at 18:50:45. The simulator's connection timed out on liveness 5 s later, at 18:50:50.
   - The host logs frequent "AX recompute slow: 40–50 ms" and "Cursor delta gap 33–86 ms — possible jitter / main-thread contention", which points to main-actor stalls delaying pings and pongs.
   - Needs the iPad-side log (heartbeat: about 6 s of pong silence counts as dead) to tell which side gave up first.
10. **Feature gap: the mirror doesn't show where the cursor is.** With two displays, the iPad gives no hint when the cursor is on a display other than the one being mirrored. The owner asked for an indicator, or for the mirror to follow the cursor's display.

### New ticket: Mirror — Spaces, displays and cursor awareness (owner-requested, private API approved)

**Why.** On a two-display Mac the owner can't tell:

- which display the mirror shows;
- how many desktops it has, or which one is current;
- whether the cursor is on another display.

The ‹ › Space buttons do nothing on a single-desktop display, and Locate only flashes on the Mac. See bugs 8, 8b and 10.

**Verified on this Mac (macOS 27):** `CGSCopyManagedDisplaySpaces(CGSMainConnectionID())` returns live data per display:

- `Display Identifier` (the display UUID; `Main` for the main display on some setups);
- `Spaces`, each with `ManagedSpaceID` and `type`, where 4 means a full-screen app;
- `Current Space`.

It reported HP = 1 desktop and built-in = 3 with the 2nd current, which matched reality. Map the UUIDs to `CGDirectDisplayID` with `CGDisplayCreateUUIDFromDisplayID` (`import ColorSync`).

**Mac (host):**

1. A `SpacesMonitor` builds a snapshot of the layout and the cursor:
   - per display: `id`, `name`, `bounds`, `spaceCount`, `currentSpaceIndex`, and the index and app name of any full-screen Spaces;
   - `cursorDisplayID`.
2. It sends a new snapshot when any of these happen:
   - `NSWorkspace.activeSpaceDidChangeNotification`;
   - a screen-parameters change;
   - the cursor crosses to another display (check on the existing input path, at most about 10 per second);
   - a remote connects.
3. It sends the snapshot to authorized remotes as a new message, for example `displayStateUpdate`. Version it with the protocol reset (PH-003): `ControlMessage.swift` is reserved for that.
4. `handleSwitchSpace` uses the snapshot to refuse a switch past either end, instead of waiting 800 ms. The pointer-restore fallback from `1b41cdd` stays as a backstop.
5. If the private symbols are missing, send the snapshot without the Space fields.

**iPad (remote):**

1. **Display picker on the mirror:** list each display by name, plus a **Follow cursor** option that switches the mirrored display when `cursorDisplayID` changes. Use the existing `startMirror(displayID:)` and `displayListUpdate` path; the iPad currently drops the list.
2. **Desktop dots** under the mirror for the mirrored display, with the current one filled and full-screen apps as small app labels. Hide or dim ‹ › at either end, and hide both when there is a single desktop.
3. **"Cursor is on <display>" badge** when `cursorDisplayID` isn't the mirrored display, with a button to bring the cursor here (`moveCursorToCenter`) or to switch the mirror to it.
4. **Cursor in the mirror:** draw a marker at the cursor's position, scaled from display bounds, so Locate is visible on the iPad too. Optionally send the cursor point with the snapshot when it's on the mirrored display, throttled.

**Tests:**

- Snapshot encoding round trip.
- Index and edge rules: 1 desktop; 3 desktops at either end; full-screen Spaces.
- "Symbol missing" fallback.
- A UI check on a two-display Mac with uneven desktop counts.

Status: BUILDS AND TESTS GREEN; M0 Show Desktop and Launchpad broken on macOS 27; Spaces and connection stability need fixes; mirror Spaces/display ticket ready to schedule

## Build 2 queued (2026-11-17)

Merged `claude/pixelhand-build1-fixes` (all 8 bugs from the first Mac build;
details and Mac/iPad checks in `BUILD1-FIXES.md`). Sentry DSNs are set, so
debug builds now report to `pixelhand-ios` / `pixelhand-mac`. The site footer
no longer links to GitHub.

For bugs 1 and 2, if the default does nothing on macOS 27, try the other
mechanisms with `defaults write com.widgetsflow.pixelhand.mac
PixelHandShowDesktopMechanism dockNotification|dedicatedKey` (and
`PixelHandLaunchpadMechanism`), record which one works, and change the
default order (one line).


## Mac build results (build 2, 2026-11-18, recorded by the coordinator)

The owner's Mac build loop session ("DeckHand MAC build loop") built
`40262b1` (build 2 plus docs): Mac and iOS builds green, Loom package tests
green, 89 app tests pass. It reported this in its session but didn't write
it here. Show Desktop / Apps mechanisms on macOS 27 still need a hands-on
check by the owner.

## Build 3 queued (2026-11-18)

Merged `claude/pixelhand-foundation` (PH-003/004/005/010; see
`FOUNDATION.md`, `LANES.md`, `DeckHand/Core/PROTOCOL.md`): the
`PixelHandCore` package (protocol split per domain, versioned envelope,
models, policies), `ControlReceiver` split into `Handlers/*`, `ControlView`,
`QuickActionsBar` and Settings split into smaller views, and a Linux
type-check script. 181 files changed; merge was conflict-free.

Mac should check: full Mac and iOS build (many moves under `DeckHand/Shared/`),
`swift test --package-path DeckHand/Core`, `swift test --scratch-path
.build-local`, `DeckHandTests`, Settings screens on both platforms, connect /
Allow / trackpad / mirror / chips still work after the protocol reset.

Status: READY FOR MAC BUILD (build 3)


## Build 4 queued (2026-11-19)

Build 3 was never built on the Mac. Build 4 replaces it, so build it
instead: it holds the foundation (everything listed under build 3) plus the
first three Sill lanes. Protocol is now **version 5**, so both devices must
run this build.

Merged (each lane's handoff doc has the full check list):

- **Network** (`LANE-network.md`): S1 AWDL off (`enablePeerToPeer: false`)
  and a 0.25 s keep-alive tick on Wi-Fi with background pause; S13 link
  judge and **Wired** badge over a USB cable (IOKit CDC-NCM probe). Loom:
  `LoomSessionNetworkPathSnapshot` gains ordered `interfaces` and
  `primaryInterface` (+4 Loom tests).
- **Mac system control** (`LANE-mac-system.md`): S7 the user's real Mission
  Control / App Exposé / Spaces shortcuts via `dlsym` CGS calls (no more
  `osascript` or Automation prompt for these); Show Desktop and Launchpad
  through the same resolver; S8 locked-Mac gate (lock banner on the iPad,
  refusals while locked) and display wake; S9 bounded AX menu reads;
  `SpacesMonitor` sends `system.displayState` and refuses Space switches
  past either end.
- **Mirror** (`LANE-mirror.md`): frames on their own Loom stream
  (`pixelhand.mirror`, binary framing), S3 pointer drawn on the iPad
  (capture without cursor), display picker with Follow Cursor, "Cursor on
  <display>" badge with Bring Here / Show, S6 stats line (Settings › Live
  mirror › Show stream stats).

Coordinator merge fixes: protocol renumbered (Network 3, Mac system 4,
Mirror 5), fixtures re-recorded (41 cases); the lock gate now covers
`mirror.moveCursor` (Locate's rule) and allows `diagnostics` stats.
Linux: `swift test --package-path DeckHand/Core` 222 tests pass;
`Scripts/linux-typecheck/run.sh` clean. **The apps were not compiled
here.** Each handoff doc lists its compile risks, most likely first.

Mac should check:

1. `cd DeckHand && xcodegen generate` (new `Network/` and `Mirror/` folders), then
   build both apps; fix compile errors using the handoff docs' §"Compile
   risks" lists (note what you changed here).
2. `swift test --package-path DeckHand/Core` (expect 222),
   `swift test --scratch-path .build-local` (Loom, previous count + 4),
   `DeckHandTests`.
3. Build 3's checks: Settings screens on both platforms; connect / Allow /
   trackpad / chips work after the protocol reset.
4. The check tables in `LANE-network.md` §3, `LANE-mac-system.md` §4 and
   `LANE-mirror.md` §7. The highest-value ones: mirror with pointer and
   picker on two displays; Mission Control / Show Desktop / Launchpad on
   macOS 27 (record which mechanism works); lock the Mac and type the
   password from the iPad; Wired badge over USB-C.

Status: READY FOR MAC BUILD (build 4)

## Build 5 queued (2026-11-19)

Build 4 hasn't been built yet. Build 5 replaces it, so build this one: it
holds everything in builds 3 and 4 plus three more Sill lanes. Protocol is
now **version 8**, so both devices must run this build.

Merged since build 4 (each handoff doc has its full check list and
compile risks):

- **Mirror 2** (`LANE-mirror-2.md`): desktop dots and ‹ › edge rules under
  the mirror; **S5 HEVC** (VideoToolbox encoder, `AVSampleBufferDisplayLayer`
  on the iPad, key frame on request, delta-drop backpressure, watchdog and
  JPEG fallback); `mirror.start` gains `codec`, plus `mirror.requestKeyFrame`.
- **iOS interaction** (`LANE-ios-interaction.md`): text typing (Keyboard
  button), click-drag (`mouseDown`/`mouseUp`, auto-release), S11 gestures,
  S12 Pencil hover pointer, S10 clipboard text sync (`sharing` domain,
  `UIPasteControl`).
- **Pairing** (`LANE-pairing.md`): S4 persistent pairing keyed on the Loom
  identity key, a 6-digit code with a check digit or a QR, lockout, and
  Forget device on both sides.

Coordinator merge changes: protocol renumbered (Mirror 2 → 6, iOS
interaction → 7, Pairing → 8), fixtures re-recorded (52 cases);
`NSCameraUsageDescription` added to the iOS Info.plist (QR); the Mac's
`ControlReceiver` no longer logs typed text, clipboard text or pairing
codes. Linux: Core **368 tests pass**, `linux-typecheck/run.sh` clean.
**The apps were not compiled here.**

Mac should check:

1. `cd DeckHand && xcodegen generate`, build both apps, and fix compile
   errors using each handoff doc's "Compile risks" list. Record what you
   changed. This is the first compile of six lanes' code, so expect a few.
2. `swift test --package-path DeckHand/Core` (expect 368),
   `swift test --scratch-path .build-local` (Loom), `DeckHandTests`.
3. Build 4's checks (above) and the build 3 basics.
4. New: mirror codec shows **HEVC** in the stats line, and the picture stays
   smooth; type a sentence and a password at the lock screen; drag a window;
   four-finger swipes; clipboard round trip; pair with the code, quit both
   apps, and reconnect without the Allow prompt; Forget device on both
   sides.

Status: READY FOR MAC BUILD (build 5)

## Build 6 queued (2026-11-19)

Build 5 hasn't been built yet. Build 6 replaces it: everything in builds
3–5 plus **Mirror window** (`LANE-mirror-window.md`): S14 single-window
streaming. `mirror.start` gains an optional `windowID`; there's a "Window…"
entry in the display picker; the cursor maps into the window; and when the
window closes, the mirror falls back to its display. Protocol is now
**version 9**. Linux: Core **389 tests pass**, type check clean. The apps
were not compiled here.

Mac should check: everything listed for build 5, then `LANE-mirror-window.md`'s
check table (mirror one Safari window with JPEG and HEVC, resize it, close
it, lock the Mac while it runs).

Status: READY FOR MAC BUILD (build 6)

## Build 7 queued (2026-11-19): every Sill lane merged

Build 6 hasn't been built yet. Build 7 replaces it, and it is the **complete
Sill phase**: the foundation plus every lane. Protocol is **version 11**.

New since build 6 (each handoff doc has its check list and compile risks):

- **Network VPN** (`LANE-network-vpn.md`): S15 remote access to a *paired*
  Mac over Tailscale/VPN, pinned to the stored identity key. Loom gains
  `LoomPeerIdentityPin` and `LoomContext.connect(_:pinnedIdentity:)` (+6
  Loom tests, DocC updated). There's a "Remote access" area in Settings ›
  Connection, and the mirror uses lower quality when away.
- **Audio** (`LANE-audio.md`): S17 Mac sound while mirroring. It's off by
  default; the toggle is in Settings › Live mirror. Audio has its own Loom
  stream and a jitter buffer on the iPad.
- **Store** (`LANE-store.md`): StoreKit 2 Pixel Hand Pro (monthly/yearly,
  2-week trial), paywall with disclosures, Restore Purchases, the
  subscription row in Settings, and the free tier (trackpad, keyboard and
  media keys with one Mac). `project.yml` now runs the iOS scheme with
  `PixelHand.storekit`.

Coordinator merge changes: protocol renumbered (VPN 10, Audio 11),
fixtures re-recorded (55 cases), Store's `project.yml` change applied.
Linux: Core **497 tests pass**, `linux-typecheck/run.sh` clean (now also
checks `SubscriptionStore`). **The apps were not compiled here.**

Mac should check:

1. `cd DeckHand && xcodegen generate`, build both apps, and fix compile
   errors using each `LANE-*.md` "Compile risks" list. This is the first
   compile of eleven lanes' code, so record every fix here.
2. `swift test --package-path DeckHand/Core` (expect 497);
   `swift test --scratch-path .build-local` (Loom: previous + 10);
   `DeckHandTests`.
3. A smoke pass in this order: connect and Allow; pair with the code and
   reconnect without the prompt; trackpad, typing and drag; Mission Control
   / Show Desktop / Launchpad (macOS 27); mirror with HEVC, the pointer,
   picker, dots, one window and audio; lock the Mac and type the password;
   clipboard; Wired over USB-C; Tailscale away from home; the `.storekit`
   purchase, trial, restore and the free-tier one-Mac rule.
4. Then the detailed tables in each `LANE-*.md`.

## Mac build results (build 7, 2026-11-20)

Built on the owner's Mac (Xcode 27.2, macOS 27) by the new Mac build loop
session at `b5274b4` + `4abcab8`. Results are for `b2caaf5`.

### Build
- Mac app: **green** after fixes. iOS app (device and simulator): **green**
  after fixes.
- Signed `Apple Development`, team `DD5AWPLT2V`, bundle
  `com.widgetsflow.pixelhand.mac` / `com.widgetsflow.pixelhand`.

### Fixes pushed (one commit each)
1. `14b4780` Import Loom where the apps use its types. LoomKit doesn't
   re-export Loom, so `LoomMultiplexedStream`,
   `LoomSessionNetworkPathSnapshot`, `LoomOverlaySeed` and
   `LoomOverlayDirectoryConfiguration` weren't in scope. Mac:
   `MirrorAudioSubscriber`, `MirrorSubscriber`, `HostLinkMonitor`,
   `LinkObservation+Loom`. iOS: `LinkObservation+Loom`, `RemoteHostsStore`,
   `MirrorAudioReceiver`, `MirrorStreamReceiver`.
2. `509bad5` `LockState.swift`: `import notify` (`notify_register_dispatch`,
   `notify_get_state`, `NOTIFY_STATUS_OK`).
3. `7e07efe` `MenuShortcutDiscovery.walkAttributes` is `[String]` instead
   of `[CFString]` (Swift 6 global-state error; still bridged to `CFArray`).
4. `6284081` `SubscriptionStore`: `import SwiftUI` for `PurchaseAction`
   (StoreKit's SwiftUI overlay). Then `StoreKit.Transaction` and
   `PixelHandCore.SubscriptionRenewalState` are named by module, because
   SwiftUI made both ambiguous.
5. `b2caaf5` Loom test: "An initiator pinned to the responder's key
   completes the handshake" never passed a trust provider to the receiver.
   A receiver without one asks for approval and denies, so the test failed
   with `.authenticationFailed` on trust, not on the pin. Both pin tests now
   pass `pair.serverTrustProvider` (the other 19 handshake tests already
   do). The pin code itself was right: key ID and public key matched.

### Tests
- `swift test --package-path DeckHand/Core`: **497 / 497 pass** (87 suites).
- `swift test --scratch-path .build-local`, nothing skipped: **375 tests**
  in the main run (365 before + 10 new), plus the smaller runs (13, 10, 5, 9,
  6, 40, 15), all passing **except one flaky test** (see bugs).
- `DeckHandTests`: **8 / 8 pass** (3 suites). The rest moved to Core with the
  foundation split.

### Install
- Mac: build 7 replaced `/Applications/Pixel Hand.app` (same bundle ID and
  team, so permissions should carry over) and was launched with `open`. It
  advertises `_pixelhand._tcp` and listens. The previous build was kept
  outside the repo on the Mac.
- iPad Air 11" (M3): installed and launched with `xcrun devicectl`. It
  starts and advertises `_pixelhand._tcp`.

### Checks done here
- Mac host launches, advertises on Bonjour, and opens the control and
  overlay-probe (38450) listeners.
- iPad Pro 11" (M5) simulator: the app launches to "Looking for your Mac"
  but **can't start Loom** (bug 1), so no simulator end-to-end pass was
  possible. The Settings gear didn't respond to two taps in that state. It's
  unconfirmed whether that comes from the failed start.

### Open bugs for the cloud fix sessions
1. **iOS app opens Loom's overlay probe listener (port 38450).** Setting
   `overlayDirectory: RemoteHostsStore.overlayConfiguration` makes LoomKit
   set `overlayProbePort` on the iOS node, so the client also *listens* on
   38450. In the Simulator it shares the Mac's network stack with the Mac
   host, which already holds 38450, so `LoomContext start failed: … NWError
   48 Address already in use` and discovery never runs. Real devices aren't
   affected by the clash, but the iPad doesn't need to answer probes either.
   The fix probably needs a probe-only option in Loom's overlay directory, or
   no probe listener on the iOS side.
2. **Flaky Loom test:** "Restarting authenticated advertising closes every
   previous listener generation" (`LoomNodeAdvertisementTests.swift:199`)
   fails in full parallel runs (2 of 2) but passes alone (3 of 3). Neither
   the test nor `LoomNode` changed since the last green run. The likely cause
   is another test's listener taking the freed ephemeral port before the
   "can't connect" check.

### Hands-on checks for the owner (build 7)
Grant permissions again if asked: Accessibility, Screen Recording,
Automation, Notifications, Local Network; on iPad, Local Network and Photos.
Then, in order: connect and Allow; pair with the code and reconnect without
the prompt; trackpad, typing and drag; Mission Control / Show Desktop /
Launchpad (macOS 27); mirror with HEVC, the pointer, picker, dots, one
window and audio; lock the Mac and type the password; clipboard; Wired over
USB-C; Tailscale away from home; the `.storekit` purchase, trial, restore
and the free-tier one-Mac rule (needs a run from Xcode with the scheme's
StoreKit config). Then the tables in each `LANE-*.md`.

Status: BUILT (build 7) — 2 bugs

## Build 8 queued (2026-11-19, merged by the primary session)

Merged on top of build 7:

- **Build 7 fixes** (`LANE-build7-fixes.md`): the iOS app no longer opens
  Loom's overlay probe listener (Simulator start failure, bug 1), the
  picker shows an error state when Loom can't start, and the flaky
  advertising-restart test is made robust (bug 2). Loom tests need a run here.
- **Design foundation** (`LANE-design-foundation.md`, first redesign lane):
  design tokens from the board, the pixel/glyph/dot-matrix components,
  glass chrome, and the new app shell **on by default**. Read its
  "Compile risks" list first (iOS 26 glass APIs, `PixelHandTheme`).
- **Deck 2 model** (`LANE-deck2-model.md`): typed actions, `deck.run`
  sequences, `DeckStore`, Mac-side execution; protocol 12.

Mac should check:

1. `xcodegen generate`, build both apps, fix compile errors using each
   lane's list.
2. `swift test --package-path DeckHand/Core`, `swift test --scratch-path
   .build-local` (including the fixed advertising test, in a full parallel
   run), `DeckHandTests`.
3. The iPad Simulator now starts Loom and finds the Mac host; do a
   simulator pass of connect / Allow / trackpad / mirror.
4. Install on Mac and iPad. The owner is testing by hand right now, so
   install as soon as it builds and list the visible design changes.

Status: READY FOR MAC BUILD (build 8)


## Build 9 queued (2026-11-23)

If build 8 hasn't been built, build this instead. Build 9 holds everything
in build 8 plus the **UX Pointer lane** (`LANE-ux-pointer.md`), the first
redesigned control surface. The shell's Pointer tab is now the board's
"Control surface · Pointer":
- a navy pixel pad with the dot field;
- a dot-matrix caption that names the gesture in progress;
- a Click | Right-click strip (touch and hold it for more);
- a glass keyboard button;
- a coach mark on first use.

The classic layout still uses the old `TrackpadView` and is unchanged.
Protocol stays **12**. Linux: Core **571 tests pass**, type check clean. The
apps were not compiled here.

Mac should check:
1. Build both apps, fixing compile errors with the "Compile risks" list in
   `LANE-ux-pointer.md`. Record any fixes here.
2. `swift test --package-path DeckHand/Core` (expect 571) and `DeckHandTests`.
3. The check table in `LANE-ux-pointer.md` (iPhone portrait/landscape, iPad,
   light/dark, AX3), plus build 8's checks if 8 was skipped.

Status: READY FOR MAC BUILD (build 9)

## Build 10 queued (2026-11-23)

If build 9 hasn't been built, build this instead. Build 10 holds build 9
(the redesigned Pointer surface) plus the **UX Screen lane**
(`LANE-ux-screen.md`):
- **UX-006:** the Screen tab is a docked `MirrorPane` above the trackpad,
  with a glass toolbar, a display picker sheet and a scanline transition.
- **UX-016:** dot-matrix status strips (`LIVE · D1 · 60`), the cursor badge,
  desktop dots on navy plates, a stats strip, and pixel chrome on the
  floating tile.

Protocol is still **12**. Linux: Core **586 tests pass**, the type check is
clean. The apps were not compiled here.

The floating tile now reserves a 120 pt band at the bottom (click strip,
caption, desktop dots). It can't be dragged or pinched over the Pointer
surface's click strip or caption. This is check 10 in `LANE-ux-screen.md`.

Mac should check:
1. Build both apps and fix compile errors with each handoff's "Compile
   risks" (`LANE-ux-pointer.md`, `LANE-ux-screen.md`). Record any fixes here.
2. `swift test --package-path DeckHand/Core` (expect 586) and `DeckHandTests`.
3. The check tables in both handoffs, including the mirror regressions
   (HEVC, window mirror, audio, display picker, desktop dots).

Status: READY FOR MAC BUILD (build 10)

## Build 11 queued (2026-11-23)

If build 10 hasn't been built, build this instead. Build 11 holds build 10
(Pointer and Screen surfaces, tile anchoring) plus the **UX shell lane**
(`LANE-ux-shell.md`):
- **UX-005:** an app dock of the Mac's running apps with Dock-style
  running dots, and a context strip with dialog buttons first, then the
  front app's chips. The keyboard button now lives in the dock, and the
  dock folds into the strip under 700 pt.
- **UX-008:** tapping or swiping the Mac pill opens a My Macs placeholder;
  status pills replace the old capability banner (the locked-Mac banner is
  still shown).
- **Settings redesign:** every Settings screen uses the new building
  blocks, including other lanes' sections.

Protocol is still **12**. Linux: Core **603 tests pass** and the type check
is clean. The SwiftUI changes were parse-checked only.

Mac should check:
1. Build both apps and fix compile errors using the "Compile risks"
   sections in `LANE-ux-shell.md`, `LANE-ux-screen.md` and
   `LANE-ux-pointer.md`. Record any fixes here.
2. Run `swift test --package-path DeckHand/Core` (expect 603) and
   `DeckHandTests`.
3. Work through the check tables in the three handoffs. Do Settings on
   iPhone and iPad, light and dark, at AX3. Lock the Mac and confirm the
   lock banner still appears.

Status: READY FOR MAC BUILD (build 11)

## Build 12 queued (2026-11-23)

If build 11 hasn't been built, build this one instead. Build 12 is build 11
plus the **UX capture lane** (`LANE-ux-capture.md`):
- **UX-009:** the screenshot, annotation, OCR, region-crop and window-picker
  flows are restyled to the pixel identity. Capture still refuses while the
  Mac is locked.
- **Floating tile placement:** this replaces the fixed 120 pt band from
  build 10. The Pointer surface now reports its pad, click strip, caption
  and keyboard button (`MirrorTileKeepOut`), and Core `MirrorTilePlacement`
  clamps the tile clear of all four. That holds when dragging and pinching,
  when the keyboard panel shrinks the pad, when the strip is hidden, and
  when the keyboard button sits in the dock.

Protocol is still **12**. Linux: Core **622 tests pass**, and the type
check is clean. The apps were not compiled here.

Mac should check:
1. Build both apps. Fix compile errors using each new handoff's "Compile
   risks" section (UX Pointer, UX Screen, UX shell, UX capture), and record
   the fixes here.
2. Run `swift test --package-path DeckHand/Core` (expect 622) and
   `DeckHandTests`.
3. Go through the check table in `LANE-ux-capture.md`: the tile in each
   corner and while dragging on the Pointer tab, then every capture flow in
   light and dark. After that, the other three handoffs' tables.

Status: READY FOR MAC BUILD (build 12)

## Build 13 queued (2026-11-24)

If build 12 hasn't been built, build this one instead. Build 13 is build 12
plus three more redesign lanes:

- **UX onboarding** (`LANE-ux-onboarding.md`):
  - **UX-010:** every onboarding page has a dot-art scene, glyph bullets and
    a dot-matrix step counter, with two columns in iPad landscape. The Mac
    picker and the pairing screens are restyled.
  - **UX-011:** the paywall, Pro lock and Settings subscription row are
    restyled. StoreKit behaviour and the required disclosures are unchanged.
- **UX arrangements** (`LANE-ux-arrangements.md`, UX-007):
  - iPhone landscape has a rail.
  - iPad shows the screen over the trackpad, a deck column and a Macs
    sidebar.
  - Split View and Stage Manager fall back to simpler layouts.
  - New Split, Screen and Pointer presets.
- **Deck 2 UI** (`LANE-ux-deck2.md`, UX-020):
  - The Deck tab has pages and a dot-matrix page counter, and follows the
    front app with a pin.
  - Edit mode adds an action library (menu command, Mac shortcut and
    sequence), a key inspector, an 8 × 8 pixel-glyph editor and undo.
  - Decks are Pro-gated.

Coordinator merge fix: Deck 2 and arrangements both changed the shell's
deck slot. It now shows `DeckSurface`, which sizes its own grid, with the
arrangement's inset applied.

Protocol is still **12**. Linux: Core **661 tests pass**, and the type
check is clean. The apps were not compiled here.

Mac should check:
1. Build both apps and fix compile errors from each handoff's "Compile
   risks" list (seven UX lanes since build 8). Record the fixes here.
2. `swift test --package-path DeckHand/Core` (expect 661) and `DeckHandTests`.
3. Work through the check tables in the three new handoffs. Prioritise:
   - onboarding on iPad landscape;
   - the iPad layout with the Macs sidebar;
   - Split View at ½ and ⅓;
   - Deck: migrated chips show as keys, add a page, edit a key, run a
     menu-command key and a sequence key;
   - the free tier lock on Deck.

Status: READY FOR MAC BUILD (build 13)

## Build 14 queued (2026-11-24)

If build 13 hasn't been built, build this one instead. It is build 13 plus
three lanes:

- **UX motion** (`LANE-ux-motion.md`): UX-017 pixel-dissolve surface
  switches use a stitchable Metal shader, fade under Reduce Motion, and
  the scanline and power-on transitions are in. UX-018 replaces spinners
  with `DotWave`, adds `PHEmptyState` for empty lists, and adds
  `.phosphorFocus` on iPad. **There's a new `.metal` file, so run
  `xcodegen generate` first.**
- **UX Mac** (`LANE-ux-mac.md`):
  - UX-012: a restyled Mac menu-bar panel and a "Pair a device" window
    with QR dots, a dot-matrix code and a countdown beam.
  - UX-019: menu-bar hand states (starting, ready, waiting, connected,
    active, locked) and the iOS launch screen. The coordinator applied
    the lane's `UILaunchScreen` keys to the iOS Info.plist.
- **UX suggest** (`LANE-ux-suggest.md`): UX-021, the first AI feature.
  Deck suggestions come from the front app's menus. A deterministic
  ranker (Core) runs everywhere, Apple Intelligence (Foundation Models)
  reorders them on-device when available, and "Keep all" or tap-to-keep
  both work with undo. Pro-gated.

Protocol is still **12**. Linux: Core **702 tests pass** and the type check
is clean. The apps were not compiled here.

Mac should check:
1. `cd DeckHand && xcodegen generate`, then build both apps. Fix compile
   errors from each handoff's "Compile risks" list (ten UX lanes since
   build 8) and record the fixes here.
2. `swift test --package-path DeckHand/Core` (expect 702) and `DeckHandTests`.
3. The new handoffs' checks:
   - menu-bar hand states and the pairing window countdown;
   - delete and reinstall the iOS app, then cold launch to check the
     launch screen;
   - surface switches with Reduce Motion on and off;
   - deck suggestions for Safari, Xcode and Finder, on a device with
     Apple Intelligence and one without.

Status: READY FOR MAC BUILD (build 14)

## Build 15 queued (2026-11-24)

If build 14 hasn't been built, build this one instead. It is build 14 plus
three roadmap lanes:

- **Ask** (`LANE-ask.md`, UX-022): the Ask tab and ⌘K. A typed or spoken
  request becomes an editable plan of `Action` steps that you can Run or
  Save as key. Destructive and remote-typing steps ask for confirmation.
  The planner uses Apple Intelligence (Foundation Models) on-device first,
  with a deterministic parser as the fallback. Every plan still goes through
  validation and the locked-Mac gate. Pro-gated.
- **Multi-Mac** (`LANE-multimac.md`, UX-030, M1/M2): several paired Macs
  with fast switching (pill swipe, ⌘1–4, three-finger switch), per-Mac
  state and quick reconnect. My Macs cards and the iPad sidebar show live
  state. The free tier still allows one Mac.
- **Intents** (`LANE-intents.md`): App Intents and App Shortcuts (Siri,
  Spotlight, the Shortcuts app), Deck widgets (small, medium and lock
  screen) and Control Center controls (iOS 18+).

The coordinator applied Intents' project changes (§2): a new
**`DeckHandWidgets` app-extension target** (bundle ID
`com.widgetsflow.pixelhand.widgets`), embedded in the iOS app; the **App
Group `group.com.widgetsflow.pixelhand`** on both the app and the
extension; and the iOS entitlements file. Automatic signing should
register the App Group and the widget App ID on the first build. If it
doesn't, add them in the developer portal (see "Needs the owner").

Protocol is still **12**. Linux: Core **781 tests pass**, type check
clean. The apps were not compiled here.

Mac should check:
1. `cd DeckHand && xcodegen generate`, then build the Mac app, the iOS
   app and the widget extension. Fix compile errors from each handoff's
   "Compile risks" list and record the fixes here.
2. `swift test --package-path DeckHand/Core` (expect 781) and
   `DeckHandTests`.
3. Work through the check tables in the three handoffs. Do these first:
   - Ask with and without Apple Intelligence
   - switching between two Macs
   - adding the Deck widget and running a key from it
   - a Siri phrase
   - the Control Center control
   - the free tier on a second Mac

Status: READY FOR MAC BUILD (build 15)

## Mac build results (build 15) — 2026-11-24

Built from `785d970` (build 15) on Xcode 27.2, Release, team `DD5AWPLT2V`,
automatic signing with `-allowProvisioningUpdates`.

**Build**
- Mac app: builds after 1 fix.
- iOS app + embedded `DeckHandWidgets` extension (`PixelHandWidgets.appex`):
  builds after 3 fixes. The widget's App Group
  `group.com.widgetsflow.pixelhand` and App ID
  `com.widgetsflow.pixelhand.widgets` registered automatically; nothing to
  add in the developer portal.
- Both are signed with development profiles (`get-task-allow` is on in the
  Release product), not distribution. Fine for testing, not for upload.

**Fixes pushed** (one commit each, on `claude/pixelhand-integration`)
1. `Shared/PixelHandTheme.swift`: `Color.init(_ rgb: RGBColor)` is ambiguous
   on macOS (Carbon's `RGBColor` vs `PixelHandCore.RGBColor`); now
   `PixelHandCore.RGBColor`. Design lane's compile risk #6.
2. `PixelHandCore/Capture/CaptureSheetChrome.swift`: `CaptureStrip` had only
   an internal memberwise init, so the iOS app couldn't build one; added a
   public `init(items:spoken:)`.
3. `DeckHandiOS/Deck/DeckSuggestionsModel.swift`: unqualified `DeckKey`
   resolved to the app's view struct, not the model; now
   `PixelHandCore.DeckKey`. Deck 2 lane's compile risk #3.
4. `DeckHandiOS/DesignSystem/PixelTransitions.swift`:
   `PixelDissolveModifier: ViewModifier, @preconcurrency Animatable` (Swift 6
   conformance-isolation error).
5. Track `DeckHandWidgets/Info.plist` and `DeckHandWidgets.entitlements`
   (xcodegen generates them; the other targets' are tracked).
6. `Tests/LoomTests/LoomNodeAdvertisementTests.swift`: the build-7 test used
   `LoomTransportKind`, which is ambiguous between `Loom` and
   `LoomNetworking`; qualified it and imported `LoomNetworking`; replaced
   `allSatisfy(\.isCancelled)` with a closure (Xcode 27 reports the key path as
   throwing inside `#expect`). The Loom test target did not compile before
   this.

None of the compile-risk items for Foundation Models (Ask, Suggest), Metal
shaders, App Intents or the widget bundle needed changes.

**Tests**
- `swift test --package-path DeckHand/Core`: **781 pass**, 0 fail.
- `swift test --scratch-path .build-local`, no `--skip`: **477 Swift Testing
  tests pass** (suites: 377, 42, 15, 13, 10, 9, 6, 5), 0 failed, 0 skipped.
- `DeckHandTests` (macOS): **8 pass**.

**Install**
- Mac: `/Applications/Pixel Hand.app` replaced (old copy quit first) and
  launched with `open`; menu-bar item not yet confirmed by the owner.
- iPad (Muhammad Junaid's iPad, iPad Air 11-inch M3): installed with the
  widget extension and launched.

**Bugs found:** none by the build gate. No visual or hands-on checks done by
me; the owner is testing. Hands-on checks are listed under "Build 15 queued"
above.

**Notes**
- Root `Package.resolved` gets modified by every xcodebuild; not committed.
- The Xcode build log shows `appintentsnltrainingprocessor: Could not archive
  SSU artifacts` for the iOS app. The build still succeeds; harmless unless
  Siri/Spotlight phrases misbehave.

## Owner testing (build 15)

(One line per finding. The cloud coordinator turns these into fix sessions.)

Status: BUILT (build 15) — green

## Build 16 queued (2026-11-24)

Build 15 is green and the owner is testing it. When the owner's findings
are in, build 16: everything in build 15 plus the last three roadmap lanes.

- **Duo** (`LANE-duo.md`, UX-040): two-pane layouts for the foldable
  iPhone. In book pose the screen takes one pane and pointer + deck the
  other, with nothing on the crease. In laptop pose the screen is on top
  and the pointer below.
- **PiP** (`LANE-pip.md`, UX-041): a picture-in-picture live Mac screen on
  the Home Screen. The pointer is drawn into the frames, pause freezes the
  picture, and the connection stays alive in the background. Pro-gated.
- **Sharing** (`LANE-sharing.md`, UX-031, S1/S2): files, photos, links and
  text go both ways on their own Loom stream, chunked, resumable and capped.
  It adds a Send sheet, a Share extension, an Inbox, and a Finder
  "Send to iPhone or iPad with Pixel Hand" service. Pro-gated. Protocol
  version bumped (see `PROTOCOL.md`).

The coordinator applied these project changes:
- a new **`DeckHandShare` app-extension target** (`com.widgetsflow.pixelhand.share`,
  App Group `group.com.widgetsflow.pixelhand`), embedded in the iOS app;
- iOS Info.plist keys `UIBackgroundModes: [audio]` (PiP),
  `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` (Inbox in
  Files), plus new `NSPhotoLibraryAddUsageDescription` text;
- Mac Info.plist `NSServices` (Finder › Services).

xcodegen generates the Share extension's Info.plist and entitlements. Track
them the way build 15 did for the widget's.

Linux: Core **851 tests pass**, and the type check is clean. The apps were
not compiled here.

Mac should check:
1. Run `cd DeckHand && xcodegen generate`, then build the Mac app, the iOS
   app and both extensions. Fix compile errors with each handoff's
   "Compile risks" list. If automatic signing doesn't register the
   `com.widgetsflow.pixelhand.share` App ID, note it here.
2. `swift test --package-path DeckHand/Core` (expect 851) and
   `DeckHandTests`.
3. These checks first:
   - PiP: start it from the mirror and by going Home, with the pointer
     visible, then 10 minutes in the background.
   - Send a photo, a file and a link each way.
   - Share from Photos and Safari.
   - Finder › Services › Send to iPhone or iPad.
   - Duo poses, if a Duo device or simulator is available.

## Mac build results (build 16) — 2026-11-24

Built from `4240622` (build 16) on Xcode 27.2, Release, team `DD5AWPLT2V`,
automatic signing with `-allowProvisioningUpdates`. Results are for
`b80b02b`.

**Build**
- Mac app: **builds first time**, no fixes needed.
- iOS app with the embedded `PixelHandWidgets.appex` and the new
  `PixelHandShare.appex`: builds after 2 fixes. Automatic signing
  registered the `com.widgetsflow.pixelhand.share` App ID; the appex is
  signed `DD5AWPLT2V.com.widgetsflow.pixelhand.share`. Nothing to add in
  the developer portal.
- Development profiles again (fine for testing, not for upload).

**Fixes pushed** (one commit each, on `claude/pixelhand-integration`)
1. `5838b00` `DeckHandShare/ShareViewController.swift`: `copyFile` captured
   the non-Sendable `NSItemProvider` in `loadFileRepresentation`'s
   `@Sendable` completion (Swift 6 error). It now reads `suggestedName`
   first and captures the string.
2. `b20e334` `DeckHandiOS/Transfer/TransferCenter.swift`: `fileSize(_:)` is
   `nonisolated`. It only reads file attributes, but it inherited the
   class's `@MainActor`, so `StagedTransferItem.subtitle` couldn't call it.
3. `b80b02b` Track `DeckHandShare/Info.plist` and
   `DeckHandShare.entitlements` (xcodegen generates them), as was done for
   the widget's in build 15.

**Tests**
- `swift test --package-path DeckHand/Core`: **851 / 851 pass** (153 suites).
- `swift test --scratch-path .build-local`, no `--skip`: **477 pass**
  (377 + 42 + 15 + 13 + 10 + 9 + 6 + 5), 0 failed. The advertising-restart
  test passed in the full run.
- `DeckHandTests` (macOS): **8 / 8 pass**.

**Install**
- Mac: `/Applications/Pixel Hand.app` replaced (old copy quit first) and
  launched with `open`.
- iPad Air 11" (M3): installed with both extensions. **Not launched: the
  iPad was locked**, so open it by hand.

**Checks done here**
- Finder › Services: "Send to iPhone or iPad with Pixel Hand" is in the
  built Info.plist (`NSServices`, `sendToDevice`, text, URLs and any file)
  and in the system services list (`pbs`). Sending through it needs a
  connected device; not exercised.
- iPad Pro 11" (M5) simulator: launches and lists "Muhammad's MacBook Pro ·
  Nearby" under "Choose a Mac", so build 7's port-38450 start failure stays
  fixed. Connecting needs the owner's Allow on the Mac, so I stopped there.
- Not done here: PiP, send each way, share from Photos/Safari (all need a
  connected, allowed device), and Duo poses (the iPhone Duo simulator is
  available, but the panes need a connection to be meaningful).

**Bugs found:** none by the build gate.

**Hands-on checks for the owner (build 16)**
Grant Photos "add" access on the iPad if asked (new
`NSPhotoLibraryAddUsageDescription`). Then:
- PiP: start it from the mirror and by going Home, with the pointer
  visible, then 10 minutes in the background.
- Send a photo, a file and a link each way, and check the Inbox in Files.
- Share from Photos and Safari through the Pixel Hand share sheet.
- Finder › Services › Send to iPhone or iPad with Pixel Hand.
- Duo: book and laptop poses on an iPhone Duo (simulator `iPhone Duo` is
  installed here) once connected.
- Pro gating: PiP and Sharing should ask for Pro on the free tier.

Status: BUILT (build 16) — green

## Build 17 queued (2026-11-24, primary session)

Build 16 plus one owner request: **Settings › Subscription › "Unlock Pro
for testing"** (new `DeckHandiOS/Store/DeveloperUnlock.swift`; edits in
`SubscriptionStore.swift` and `SettingsSubscriptionSection.swift`). Every
Pro check already reads `SubscriptionStore.entitlement`, which now returns
an "active" Pro entitlement while the switch is on.

Mac should check:
1. Build the iOS app (compile risks: `AppTransaction.shared` /
   `.environment` under Swift 6, the computed `entitlement` on the
   `@Observable` store, `@Bindable` uses of `store` still compiling).
2. Install on the iPad, open Settings › Subscription: the switch shows;
   turn it on and check Pro features unlock (mirror, decks, a second Mac,
   Ask), the widget shows Pro, and turning it off restores the free plan.
3. `DeckHandTests` and Core tests unchanged.


## Build 18 queued (2026-11-24, replaces build 17)

Build 17 (Unlock Pro for testing) was never built; build 18 is build 17
plus the **UX polish** lane (`LANE-ux-polish.md`, UX-013 + UX-014): light
mode danger/warning colours darkened for contrast, VoiceOver labels,
Reduce Motion, focus rings, `ph.<area>.<name>` accessibility IDs, copy
fixes, and the compatibility shims removed. It also adds
`DeveloperUnlock.swift` to the Linux type check.

Mac should check: the build 17 list above (Settings › Subscription ›
"Unlock Pro for testing"), then the "Checks on the Mac" table in
`LANE-ux-polish.md`. Install on Mac and iPad as soon as it builds.

## Mac build results (build 18) — 2026-11-24

Built from `f8eae4d`/`e811e7f` (build 18) on Xcode 27.2, Release, team
`DD5AWPLT2V`, automatic signing with `-allowProvisioningUpdates`. Results
are for `6170ef0`.

**Build**
- Mac app: **builds first time**, no fixes needed.
- iOS app with `PixelHandWidgets.appex` and `PixelHandShare.appex`: builds
  after 1 fix. `DeveloperUnlock.swift` (`AppTransaction.shared`,
  `.environment`), the computed `entitlement` and the UX polish lane's
  ternary transitions / `accessibilityActions` all compiled as written.

**Fixes pushed** (on `claude/pixelhand-integration`)
1. `6170ef0` `DeckHandiOS/Surfaces/PointerSurface.swift`: "unable to
   type-check this expression in reasonable time" on `touchSurface` (eleven
   `.accessibilityAction` modifiers, two of them with a ternary `named:`
   choosing an overload). The two names are now typed `LocalizedStringKey`
   locals and the `TrackpadInputLayer` is its own property. No behaviour
   change; the VoiceOver actions and names are the same.

**Tests**
- `swift test --package-path DeckHand/Core`: **857 / 857 pass** (154
  suites; up from 851, the 6 new `ContrastAuditTests`).
- `swift test --scratch-path .build-local`, no `--skip`: **477 pass**
  (377 + 42 + 15 + 13 + 10 + 9 + 6 + 5), 0 failed.
- `DeckHandTests` (macOS): **8 / 8 pass**.

**Install**
- Mac: `/Applications/Pixel Hand.app` replaced (old copy quit first) and
  launched with `open`; running.
- iPad Air 11" (M3): installed with both extensions and launched. (It
  first showed as `unavailable` to `devicectl`, error 4016, until it came
  back on the network.)

**Checks done here:** none beyond the build and tests; the build 17 and
UX polish checks need the iPad or VoiceOver hands-on.

**Bugs found:** none by the build gate (the type-check timeout is fixed).

**Hands-on checks for the owner (build 18)**
- Settings › Subscription › **"Unlock Pro for testing"**: the switch shows
  on this development build; on, every Pro feature unlocks (mirror, decks,
  a second Mac, Ask, PiP, Sharing) and the widget shows Pro; off restores
  the free plan.
- The "Checks on the Mac" table in `LANE-ux-polish.md`: VoiceOver on iPhone
  and the Mac panel, AX3 text sizes, Reduce Motion, light-mode danger and
  warning colours.

## Owner testing (build 18)

(none reported yet)

## Visual QA (build 18) — 2026-11-25

Full findings: `Integration/VISUAL-QA-build18.md` (one line each, with a
suggested fix and media ref). Gallery with every screen, screenshots and
clips: https://claude.ai/artifact/EWnkLTGtb5bpXMHrGFJnzB (private).

**82 findings: P1 13 · P2 43 · P3 26.** Layout 21, Visual identity 19,
Wording 17, Behaviour 15, Accessibility 5, Responsiveness 3, Loading and
animation 2. (The second pass, VQ-070 to VQ-082, covers widgets, the Lock
Screen widget, Control Center and Stage Manager windows on the iPad.)

- Covered: iPhone 17 Pro (light, dark, AX3, landscape), iPad Pro 11" and
  iPad mini (portrait, landscape), iPhone 17, iPhone Duo (onboarding only),
  the Mac panel and pairing window, free plan.
- Biggest blocker (VQ-001): build 18's Mac refuses every unpaired
  simulator because loopback counts as a remote path, and pairing is
  refused over it too, so no simulator can connect to a Mac on the same
  machine. I paired three simulators once with a local, uncommitted Mac
  build; everything else was captured against `/Applications/Pixel Hand.app`.
- New `PixelHandUITests` target (12 walks, screenshot per step) for
  re-checking each round of fixes; how to run it is in the findings file.
- Not tested: App Shortcuts and Siri, sharing, real multi-touch gestures,
  a second Mac, running keys or Ask plans, Reduce Motion, iPhone 17 Pro
  Max (the test runner never started there), the real iPad (unavailable
  to Xcode). This Mac auto-locked near the end of the first pass, which
  stopped the last runs.
- From now on basic layout checks run on the iPad Pro 11" simulator only:
  portrait, landscape, and a Stage Manager window dragged down to iPhone
  width, instead of separate iPhone simulators.


## Build 19 queued (2026-11-25)

Build 19 is build 18 plus the three QA fix lanes from
`VISUAL-QA-build18.md` (82 findings), merged at `7679a07`:

- **A, surfaces** (`LANE-qa-surfaces.md`): header circles fold into More
  by width and text size, two-row deck header, Stage Manager window
  controls inset, iPhone Screen tab starts the mirror with the pad under
  it, keyboard layout, AX3 scrolling, onboarding on iPad and Duo.
  `PHButtonStyle` inline buttons are now one line at label width, which
  changes every screen.
- **B, flows** (`LANE-qa-flows.md`): **VQ-001 loopback counts as this
  Mac**, so a simulator on the build Mac can connect and pair (see
  `MAC-BUILD.md` › Simulators). Pairing codes are now **eight digits**
  with a check digit, plus `pairing.refused(reason:)`. **Protocol 14: the
  Mac and the iPad/iPhone must both run build 19.** Also the reconnect
  toast, the paywall opening from Settings, Diagnostics, and Mac panel
  focus and copy.
- **C, identity** (`LANE-qa-identity.md`): Settings restyle (glyph
  headers, cobalt switches, page sheet on iPad), widget strip text, Lock
  Screen widgets, Control Center dot-glyph custom symbols (new
  `.symbolset` assets in the widget extension; **run `xcodegen generate`**).

Integration also added `SettingsDiagnosticsSection()` to `SettingsView`,
with a glyph header.

Linux: Core **916 / 916 pass** (165 suites); `linux-typecheck/run.sh`
passes.

**Compile risks.** Each handoff lists them, most likely first. The
likeliest are:
- `WindowControlsInset` (`.safeArea(cornerAdaptation:)`);
- `.onGeometryChange` in `ShellHeader`;
- the `DeckSurface` restructure;
- `PairingCodeEntryView`;
- the `MacMenuBarView` focus sink;
- the generated `.symbolset` SVGs. If Xcode rejects them, re-export one
  from the SF Symbols app.

**Mac should check:**
1. The build and the tests.
2. Install on the Mac and the iPad.
3. Boot the iPad Pro 11" simulator and pair it with the Mac over loopback
   (the VQ-001 re-check).
4. Run the `PixelHandUITests` walks on the iPad Pro 11" and the iPhone 17
   Pro, plus the free-plan walk (`TEST_RUNNER_PH_QA_FREE=1`) and AX3. The
   walks now tap `ph.deck.done` and `ph.connect.pair`.
5. Work through the re-check steps in the three handoffs and mark each VQ
   ID as pass, fail or not checked in "Mac build results (build 19)".

**Left open by the lanes:**
- VQ-054 Diagnostics: was waiting for the Settings line, now added.
- VQ-069: the fallback.
- VQ-079: Pointer layout.
- Owner items OR-01, OR-02, OR-04, OR-05, OR-06 and OR-08 to OR-13 were
  partly or not covered.

See each handoff's table.

## Mac build results (build 19) — 2026-11-25

Built from `bce0e75` (build 19) in the single `pixelhand-build` worktree
with the shared `~/Developer/DeckHand-build/.derived`, Xcode 27.2,
Release, team `DD5AWPLT2V`, `-allowProvisioningUpdates`.

**Build**
- Mac app: builds first time.
- iOS app with `PixelHandWidgets.appex` (new `Assets.car`, so the
  `.symbolset` control symbols compiled) and `PixelHandShare.appex`:
  builds first time. None of the listed compile risks fired.
- Simulator `build-for-testing` (app + `PixelHandUITests`): builds.

**Fixes pushed:** none needed.

**Tests**
- `swift test --package-path DeckHand/Core`: **916 / 916 pass** (165 suites).
- `swift test --scratch-path .build-local`, no `--skip`: **477 pass**
  (377 + 42 + 15 + 13 + 10 + 9 + 6 + 5), 0 failed.
- `DeckHandTests` (macOS): **8 / 8 pass**.
- `PixelHandUITests` walks: **12 / 12 ran** on each of iPad Pro 11" (M5)
  light, iPad Pro 11" free plan (`PH_QA_FREE=1`), iPhone 17 Pro light and
  iPhone 17 Pro AX3 (243 screenshots). They are capture walks; I reviewed
  the key screens by eye.

**Install**
- Mac: `/Applications/Pixel Hand.app` replaced (old copy quit first),
  launched with `open`.
- iPad Air 11" (M3): installed with both extensions. Launch from
  `devicectl` failed (error 10002 / 4000, iPad probably locked): open it
  by hand.

**Re-checks** (pass / fail; anything not listed is not checked)
- Pass: VQ-002 (refusal reads "Pair <Mac> first", sentence case), VQ-006,
  VQ-007 (Pair capsule), VQ-009, VQ-010, VQ-011, VQ-016 (page sheet on
  iPad), VQ-019 (iPad mini), VQ-025, VQ-026, VQ-032, VQ-033, VQ-034,
  VQ-035 (Disconnect on one line; the Debug simulator build shows
  "Classic layout (debug)" as designed), VQ-036 ("Typing into Google
  Chrome"), VQ-038, VQ-044, VQ-046, VQ-049, VQ-050 (title), VQ-051,
  VQ-053, VQ-054 (Diagnostics: Mac, Link "This device", round trip,
  protocol 14), VQ-055 (paywall opens over Settings), VQ-056, VQ-057,
  VQ-059, VQ-064, VQ-068 (lock banner with Keyboard), VQ-071 (MUHAMMAD'S
  in the strip), VQ-080 (Stage Manager controls clear of the pill).
- **Fail: VQ-001** (see bug 1) and **VQ-065** (see bug 3).
- Not checked here (need the owner, the Mac panel, a real device or a
  long wait): VQ-003/005/029–031/037 pairing by code (blocked by VQ-001
  for unpaired simulators), VQ-020–023, 027/028, 039–043, 047, 048, 052,
  058, 060–063, 066, 067, 069, 070, 072–079, 082, VQ-004/018 on iPad.

**Bugs found: 5**
1. **VQ-001 still fails (P1).** An unpaired simulator is refused:
   "not paired, and it arrived over a remote path (loopback)". The
   simulator dials the Mac's Bonjour-resolved Wi-Fi address
   (`192.168.0.121`), which the kernel routes over `lo0`. In
   `RemoteAccessPolicy.pathClass` a `.loopback` link with a routable,
   non-loopback `remoteHost` returns `.remote`, so it never reaches
   `.sameMachine`. A packet over `lo0` can only come from this machine;
   either treat `.loopback` as `.sameMachine` (overlay addresses aside)
   or match `remoteHost` against this Mac's own interface addresses.
   The iPad mini simulator showed "Pair Muhammad’s MacBook Pro first".
   Simulators paired during the build 18 QA still connect.
2. **The floating screen tile covers the deck header on iPhone (P2).**
   iPhone 17 Pro, Deck tab with the mirror running: the tile sits over
   the header's counter, pin and Edit (light and AX3). The walk records
   `ph.deck.edit` as not hittable.
3. **AX3 Mac pill hyphenates the name (P2, VQ-065).** iPhone 17 Pro at
   AX3: "Muham- / mad’s Mac…". It should break at a word and truncate
   the tail.
4. **Mirror failure alert shows a raw error (P2).** With the Mac locked,
   choosing Show screen on iPad gives "Live Screen Unavailable · Live
   mirror unavailable: The operation couldn’t be completed.
   (Pixel_Hand.ScreenCaptureService.CaptureError error 2.)". It should
   say the Mac is locked (the lock banner already knows), in sentence
   case.
5. **Picker lists another iPad as a Mac (P3).** On the iPad mini
   simulator the picker showed "iPad Pro 11-inch (M5) · Please update
   Pixel Hand on your Mac" with a PRO badge and a laptop glyph; that was
   the iPad Pro simulator still running build 18. iOS devices shouldn't
   be listed as Macs. Possibly older than build 19.

**Hands-on checks for the owner (build 19)**
- **Protocol 14:** the iPad needs build 19 too (installed; open it by
  hand).
- Pairing by code on the real iPad: Pair on the Mac's request row, eight
  digits shown "4821 0934", sends itself at the eighth digit; a 60 s wait
  keeps the request alive.
- Mac panel: no focus ring, one-request header with an iPad glyph,
  Updates hidden, Last seen "now" after a disconnect.
- Quit the Mac app mid-session: only the toast, then the card after
  about 15 s.
- Widgets and Control Center: dot-glyph controls tinted cobalt, Lock
  Screen widgets, "MUHAMMAD'S" on the small widget, eight free keys.

## Owner testing (build 19)

(none reported yet)


Status after build 19: BUILT — 5 bugs (a fix session is on them; see build 21).

## Build 20 queued (2026-11-25, primary session)

Build 19 plus the three owner-review lanes (`OWNER-REVIEW-visual-qa-build18.md`):

- **or-ios-chrome** (`LANE-or-ios-chrome.md`): one fixed sidebar toggle
  (OR-05), fades instead of slides, dock dot removed, labels without
  ellipses, glyph rule lint, Pointer arrangement from Trackpad, VQ-069 Mac
  reconnect, VQ-079.
- **or-canvas** (`LANE-or-canvas.md`): narrower sidebar (176 pt) with
  compact Mac cards (OR-04), collapsible right column with a Deck | Ask
  switch and Ask in the column (OR-06), Ask paywall card removed (OR-03).
- **or-mac-panel** (`LANE-or-mac-panel.md`): Mac panel QR tile, pairing
  digits, ellipses, Transfers tab (OR-10 to OR-13).

Merge note: `MacsSidebar.swift` keeps or-ios-chrome's 24 pt leading
padding (`SidebarTogglePlacement.sidebarLeadingPadding`) so the toggle
doesn't move; or-canvas planned 16 pt. Check the compact Mac cards still
fit the 176 pt sidebar without truncating badly.

Mac should check: build all targets; Core, Loom and app tests; run the
`PixelHandUITests` walks on the iPad Pro 11" simulator (portrait,
landscape, Stage Manager at iPhone width) and re-check OR-03 to OR-06 and
OR-10 to OR-13 against each lane's table; install on Mac and iPad.


## Mac build results (build 20) — 2026-11-25

Built from `537e21c` while builds 21 and 22 were being queued; superseded
by build 22, which is being built next. Recorded for the OR re-checks.

- **Build:** Mac, iOS with both extensions, and the simulator test build
  all build first time; no fixes.
- **Tests:** Core 970 / 970; Loom 477 pass, 0 failed, no `--skip`;
  `DeckHandTests` 8 / 8. `PixelHandUITests` on iPad Pro 11": 13 / 13 ran
  with Pro and 13 / 13 on the free plan.
- **Install:** Mac replaced and launched with `open`; iPad installed and
  launched.
- **OR-02:** pass (no dot row under chips).
- **OR-03:** pass (free Ask is the dimmed field with the small lock).
- **OR-06:** pass (Deck | Ask switch, Ask in the column, collapse to the
  edge handle and back).
- **Not checked:** OR-04/OR-05 (the walks never showed the Macs sidebar),
  landscape and Stage Manager at iPhone width (captures come out rotated;
  the walk can't resize a window), OR-08 to OR-13 (Mac panel).
- **Bug (P3):** iPad Pro 11" portrait, Pointer with the keyboard panel
  open, squeezes the right column's deck empty state into a thin cobalt
  bar showing only "•••". Hide its text and button, or fold the column,
  when there isn't room.

## Build 21 queued (2026-11-25, replaces build 20)

Build 20 (the three owner-review lanes) was not built yet. **Build 21 is
build 20 plus `LANE-build19-fixes.md`**, merged at `4f2f62c`, which fixes the 5
bugs in "Mac build results (build 19)":
- VQ-001: a simulator dialling the Mac's own Wi-Fi address over `lo0` is
  now "this Mac".
- The deck tile.
- The pill name.
- Capture errors.
- An iPad listed as a Mac (new additive `ph-role` advertisement metadata;
  the protocol stays at 14).

Linux: Core **992 / 992 pass** (179 suites); `linux-typecheck/run.sh`
passes.

**Mac should check:**
1. The build 20 checks: the re-check steps in `LANE-or-ios-chrome.md`,
   `LANE-or-canvas.md` and `LANE-or-mac-panel.md`.
2. The Mac re-check steps in `LANE-build19-fixes.md`.
3. The `PixelHandUITests` walks.
4. Run `xcodegen generate` first.

OR-16 (pointer control on the picture) is in progress in its own lane and
will be build 22.


## Build 22 queued (2026-11-25, replaces build 21)

Build 21 was not built yet. **Build 22 is build 21 plus OR-16**
(`LANE-or16-picture-pointer.md`), merged at `bca7639`. OR-16 is pointer control
on the mirror picture: a toolbar toggle that makes the picture work like a
trackpad, with relative movement, tap, two-finger tap, scroll and drag, and
pinch to zoom kept. It is off the first time, then remembers the last
choice. There is no protocol, `project.yml` or plist change. Its UI walk
is `test16_PicturePointer`, renamed from test14 because the build19-fixes
walk also took test14.

Linux: Core **1018 / 1018 pass** (182 suites); `linux-typecheck/run.sh`
passes.

**Mac should check:**
- The build 21 list above.
- The OR-16 re-check steps in its handoff.

After a green build 22, the visual QA re-run follows: the same flows and
gallery as `VISUAL-QA-build18.md`, re-checking every VQ and OR ID.

## Mac build results (build 22) — 2026-11-25

Built from `dd67627` (build 22) in `pixelhand-build` with the shared
`.derived`, Xcode 27.2, Release, team `DD5AWPLT2V`,
`-allowProvisioningUpdates`. Results are for `e5cf881`.

**Build**
- Mac app and iOS app with both extensions: build first time.
- Simulator `build-for-testing`: failed in `PixelHandUITests` until fix 1.

**Fixes pushed**
1. `e5cf881` `PixelHandUITests.swift`: the OR-16 merge dropped
   `test15_PairUnpairedSimulatorByCode`'s closing brace ("Expected '}' in
   class"). I restored it as the build 19 fixes lane wrote it.

**Tests**
- `swift test --package-path DeckHand/Core`: **1018 / 1018 pass** (182 suites).
- `swift test --scratch-path .build-local`, no `--skip`: **477 pass**,
  0 failed (377 + 42 + 15 + 13 + 10 + 9 + 6 + 5).
  - A first run made while a simulator and the Mac app were busy failed
    2 tests.
  - "Realtime display queue shapes drains into bounded bursts"
    (`LoomOrderedUnreliableSendQueueTests.swift:407`) failed.
  - "iOS-shaped peers exchange messages in both directions" failed with
    `.decryptFailed` (`LoomKitIntegrationTests.swift:17`).
  - Both pass on a quiet machine, so they look timing-sensitive under
    load. They are not counted as bugs.
- `DeckHandTests` (macOS): **8 / 8 pass**.
- `PixelHandUITests`:
  - iPad Pro 11": 16 / 16 ran.
  - iPhone 17 Pro: `test14_DeckWithMirror` ran in light and AX3, plus
    `test04` at AX3.
  - **The Mac locked itself partway through**, so every walk that needs
    the mirror stopped at the "Mac is locked" alert: `test14`, `test16`.
  - `test15` skipped (no pairing-code file).

**Install**
- Mac: `/Applications/Pixel Hand.app` replaced (old copy quit first),
  launched with `open`.
- iPad Air 11" (M3): installed later with both extensions, once it was
  reachable again. The remote launch failed (error 10002, iPad probably
  locked), so open it by hand.

**Re-checks of the build 19 bugs**
- **VQ-001: pass.** On an unpaired iPad mini simulator the Mac logs "is
  on this Mac (loopback or its own address, e.g. a simulator): local
  rules apply". It then opens a pending request. The simulator shows
  "Waiting for approval" with "Enter pairing code". Pairing by code
  (VQ-003/005/029–031/037) still needs a hand on the Mac's Pair window.
- **Bug 4 (capture errors): pass** for the locked Mac. "Mac is locked ·
  Unlock the Mac to see its screen. Pixel Hand never shows the lock
  screen." The Screen Recording-off case was not checked.
- **Bug 5 (iPad listed as a Mac): pass.** The iPad mini picker listed
  only the Mac while the iPad Pro simulator was booted.
- **Bug 3 (VQ-065): partly fixed.** See bug 2 below.
- **Bug 2 (deck tile over the iPhone header): not checked.** The Mac was
  locked, so the mirror couldn't start.
- **OR-16 (pointer on the picture): not checked**, for the same reason.

**Bugs found: 3**
1. **Try again during a slow first start breaks discovery (P2).**
   - Fresh install on the iPad mini simulator, no iCloud account. The
     first `LoomContext` start waited about 45 s on the CloudKit account
     check.
   - The picker showed the "Can't find your Mac?" card. Tapping **Try
     again** started attempt 2 while attempt 1 was still pending.
   - Both failed: "LoomContext start failed: Already advertising
     service", then `CancellationError`. The picker stayed on SEARCHING
     with the Mac advertising, until a relaunch.
   - Make Try again wait for (or cancel) the start in flight, and don't
     block advertising and browsing on the CloudKit check.
2. **AX3 Mac pill still cuts the name mid-word (P2, VQ-065).**
   - iPhone 17 Pro at AX3: the pill reads "Muhamma…" on one line.
   - Expected "Muhammad’s" / "MacBook Pro" on two lines, or a tail "…"
     on line 2. The hyphen is gone.
3. **AX3 lock banner overflows into the header (P2).**
   - iPhone 17 Pro at AX3 with the Mac locked: the banner's text wraps
     "Muham-" mid-word. Its first line draws over the Mac pill in the
     header (`iphone-ax3/test04_ConnectAndPointer/01-pointer`).
   - The banner should grow downward and break at words.

Not re-checked: build 20's P3, the squeezed deck column with the keyboard
up.

**Hands-on checks for the owner (build 22)**
- **Install on the iPad:** keep it on Wi-Fi and unlocked so the Mac can
  reach it. It is on build 20.
- **OR-16:** Layout › Screen focus, then the pointer button in the mirror
  toolbar. Move, tap, two-finger tap, scroll, drag, pinch to zoom.
- **Bug 2:** iPhone, Deck with the mirror running. The tile sits below
  the header, and Edit and pin work.
- **Pairing by code:** Pair on the Mac's request row; type the code on the
  device.
- **Mac panel (OR-08 to OR-13), the Macs sidebar (OR-04, OR-05).**

## Owner testing (build 22)

(none reported yet)


## Build 23 queued (2026-11-25): fixes plus the visual QA re-run

Build 23 is build 22 plus `LANE-build22-fixes.md`, merged at `0f92060`. It
fixes the 3 bugs from build 22:

1. **Try again during a slow first start.**
   - The app runs its start in its own task, so a second tap no longer
     cancels the first.
   - Loom's `LoomStore.start()` is single-flight.
   - Advertising and discovery start before the CloudKit account check
     and peer setup.
   - This is a Loom change, with DocC updated and a new `LoomKit Store
     Start` suite.
2. **The AX3 Mac pill** breaks only at words: two lines, with a tail "…".
3. **The AX3 lock banner** sits below the header, grows downward and breaks
   at words.

Linux: Core **1031 / 1031 pass** (183 suites); `linux-typecheck/run.sh`
passes. The UI test file's braces are balanced. **Loom can't run on Linux:
run `swift test --scratch-path .build-local` here, including the new
suite.**

**Mac should do:**
1. The build and every test suite, Loom included.
2. Install on the Mac and the iPad. Keep the iPad on Wi-Fi and unlocked.
3. **Keep the Mac from locking during the walks.** Run `caffeinate -dimsu`
   alongside them. Build 22's mirror walks stopped at the lock screen.
4. Re-check the build 22 bugs (`LANE-build22-fixes.md` re-check steps),
   plus the items build 22 couldn't reach:
   - OR-16, pointer control on the picture (`test16_PicturePointer` and by
     hand);
   - bug 2 from build 19, the deck tile on iPhone (`test14`).
5. **Visual QA re-run.** Capture the same flows and sizes as
   `VISUAL-QA-build18.md`, and use the `PixelHandUITests` walks on the
   iPad Pro 11" (portrait, landscape, Stage Manager down to iPhone width),
   the iPhone 17 Pro, the free plan and AX3. Mark every **VQ-001…082** and
   **OR-01…OR-16** ID as pass, fail or not checked, in a new
   `VISUAL-QA-build23.md`, with a gallery link. List new findings as
   VQ-083 and up, with P1/P2/P3.

## Mac build results (build 23) — 2026-11-25

Built from `77d2e5c` (build 23) on Xcode 27.2, Release, team `DD5AWPLT2V`,
automatic signing with `-allowProvisioningUpdates`, in the shared
`pixelhand-build` worktree with `-derivedDataPath ~/Developer/DeckHand-build/.derived`.

**Build**
- Mac app: **builds first time**, no fixes.
- iOS app with `PixelHandWidgets.appex` and `PixelHandShare.appex`:
  **builds first time**, no fixes.
- No commits pushed except this section.

**Tests**
- `swift test --package-path DeckHand/Core`: **1031 / 1031 pass** (183 suites).
- `swift test --scratch-path .build-local`, no `--skip`: **480 / 480 pass**
  on a quiet run (377 + 45 + 15 + 13 + 10 + 9 + 6 + 5). The new
  **`LoomKit Store Start` suite passes** (the LoomKit run went from 42 to 45).
  - The first full run failed 1 test: "Declined transfers surface a
    declined terminal state to the sender" (`LoomTransferEngineTests.swift:59`,
    `.decryptFailed`). It passed 5 of 5 alone and in the second full run,
    so it's the same timing-sensitive `.decryptFailed` pattern build 22 saw
    under load. It isn't counted as a bug.
- `DeckHandTests` (macOS): **8 / 8 pass**.

**Install**
- Mac: `/Applications/Pixel Hand.app` replaced (old copy quit first; one
  previous copy kept outside the repo) and launched with `open`.
- iPad Air 11" (M3): installed with both extensions over Wi-Fi. **Not
  launched: the iPad was locked.**

**Not done yet: the walks and the visual QA re-run (steps 3–5 above)**
- The build 22 bug re-checks (`LANE-build22-fixes.md`), OR-16
  (`test16_PicturePointer`), `test14` on iPhone, and the
  `VISUAL-QA-build23.md` pass all drive the Mac through `PixelHandUITests`.
  Those walks type and click into the Mac's frontmost app and need the Mac
  unlocked under `caffeinate -dimsu`. This build ran from an unattended
  loop, so I didn't start them. They wait for the owner to be at the Mac
  (scratch TextEdit document in front, Mac unlocked, iPad unlocked).
- The build itself is green, so the status below marks it built. The visual
  QA re-run is still owed for build 23.

**Bugs found:** none by the build gate.


## Visual QA and re-checks (build 23) — 2026-11-25

Report: `DeckHand/Integration/VISUAL-QA-build23.md`. Gallery (private Artifact,
mirror pictures blurred): https://claude.ai/artifact/Gmd7tNoxKcsQ9FnMKhYmqK

**Mac-free run.** The owner was using the Mac, so after one full iPad run
no walk sent input to it: `test04`, `test05` and `test16` were left out, and
the Mac menu-bar panel wasn't opened. The first iPad run's `test04` typed
"hello" (no Return) into Chrome; nothing was submitted.

- `PixelHandUITests`: iPad Pro 11" light **17 / 17 passed**; iPad Pro 11"
  AX3 **7 / 7** (Mac-free set); iPhone 17 Pro light **9 / 9** (Mac-free
  set). Hand checks: iPad Stage Manager window at iPhone width, iPhone 17 Pro
  at AX3 and AX5.
- **Build 22 re-checks:** bug 1 (Try again) **pass**, bug 2 (AX3 pill)
  **pass**, bug 3 (AX3 lock banner) **pass**. The Mac locked itself, so the
  banner was checked without `test04`. OR-16 not checked (it drives the Mac
  pointer).
- **VQ-001…082:** 44 pass · 1 fail (VQ-058) · 37 not checked.
  **OR-01…16:** 5 pass · 11 not checked. Most "not checked" items are on the
  Mac panel, the widgets, iPad landscape (the simulator has Stage Manager on,
  VQ-092) or need input to the Mac.
- **New findings VQ-083…093:** 11 (P1 1 · P2 4 · P3 6).

**Open bugs**
1. **VQ-083 (P1), build 19 bug 2 still open:** on iPhone, in deck edit mode
   the floating mirror tile covers the deck header's Done (not hittable) and
   three key slots.
2. **VQ-058:** after onboarding and after a relaunch, the picker shows the
   paired Mac as "Paired · Nearby" and waits for a tap instead of
   reconnecting.

P2 findings for the fix lane: VQ-084 (AX3 picker truncates the Mac name in
the middle), VQ-085 (AX5 pill cuts both lines mid-word), VQ-086 (a second
floating "Connect and pair" covers the code sheet's footer).

**Still for the owner (needs the Mac to yourself):** `test04`, `test05`,
`test16` (OR-16 picture pointer), the Mac panel items (VQ-021…023,
VQ-040…043, OR-08…13), widgets and Control Center (VQ-070…079, OR-14/15).


### Second pass, Mac free (build 23) — 2026-11-25 evening

The owner freed the Mac, so the walks that type and click ran too, with a
scratch TextEdit document in front: iPad `test04`, `test05`, `test16`;
iPhone `test04`, `test05`, `test06`; the Mac menu-bar panel and pair
window; OR-16 by hand on the iPad. All walks passed. `VISUAL-QA-build23.md`
and the gallery are updated.

- **Totals now:** VQ-001…082 51 pass · 4 fail · 27 not checked;
  OR-01…16 10 pass · 6 not checked; new findings VQ-083…097: 15
  (P1 1 · P2 5 · P3 9).
- **Passed this time:** OR-08 (one Devices list), OR-10, OR-11, OR-12,
  OR-16 (the picture moves the Mac pointer), VQ-005, VQ-021, VQ-022,
  VQ-036, VQ-040, VQ-041, VQ-042, VQ-047, VQ-059.
- **Failed:** VQ-034 (iPhone modifier row runs off with no fade), VQ-060
  (no PiP button in the iPhone mirror toolbar; iPad has it), VQ-061 (the
  iPhone mirror toolbar never hides; iPad's does), plus VQ-058 from the first
  pass.
- **Another Mac is on the network** ("AH's Mac mini"). `connect()` in the
  walks taps the first Mac, so one `test04` run sent that Mac a connection
  request (never approved). The rest of the run used a local, uncommitted
  patch that picks the Mac by name (VQ-096).

**Open bugs**
1. **VQ-083 (P1):** iPhone deck edit mode: the mirror tile hides Done.
2. **VQ-058:** the picker doesn't reconnect to the paired Mac.
3. **VQ-095 (P2):** with pointer control on, a quick flick throws the Mac
   pointer off the mirrored display (210 pt flick → about 3,250 pt; a slow
   50 pt drag → 182 pt, which is fine).

**Still not checked:** iPad landscape and the Macs sidebar (OR-04/05; the
simulator's windowing returns on rotation), widgets and Control Center
(VQ-070…079, OR-14/15), transfers (OR-13), dark mode, iPad mini, Duo.


## Build 24 queued (2026-11-25): build 23 QA fixes and the final QA pass

Build 24 is build 23 plus `LANE-qa23-fixes.md`, merged at `d1aaa06`. It
addresses the 4 failed and 15 new IDs from `VISUAL-QA-build23.md`:

- VQ-083 (P1): the deck header keep-out in edit mode.
- VQ-058: auto-reconnect.
- VQ-095: the pointer acceleration is capped and clamped to the display.
- VQ-060, VQ-061, VQ-084…097. VQ-034 and VQ-088 are partly done: wider
  fades.

There is no protocol, `project.yml`, plist or Loom change.

Linux: Core **1058 / 1058 pass** (190 suites); `linux-typecheck/run.sh`
passes; the UI test braces balance.

**New walk settings** (see `MAC-BUILD.md`):
- `TEST_RUNNER_PH_QA_MAC_NAME=<this Mac's name>`, so `connect()` never taps
  another Mac. "AH's Mac mini" is on the network.
- `TEST_RUNNER_PH_QA_FULLSCREEN=1` on the iPad, for real landscape and the
  Macs sidebar (VQ-092).

**Mac should do:**
1. The build and all tests. Loom isn't changed, so its full run is
   optional.
2. Install on the Mac and the iPad.
3. With the owner's OK to use the Mac, run `caffeinate -dimsu`, put a
   scratch TextEdit document in front, and run the walks on the iPad Pro
   11", the iPhone 17 Pro, AX3 and the free plan.
4. **Final QA pass:** re-check each ID in `LANE-qa23-fixes.md`'s table,
   and the items build 23 couldn't reach:
   - iPad landscape and the Macs sidebar (OR-04, OR-05);
   - widgets, the Lock Screen and Control Center (VQ-070…079, OR-14/15);
   - Transfers (OR-13);
   - dark mode;
   - iPad mini.

   Update `VISUAL-QA-build23.md`'s statuses in a new
   `VISUAL-QA-build24.md` (pass, fail or not checked; new findings from
   VQ-098), with the gallery.

## Mac build results (build 24) — 2026-11-26

Built from `b0212de` (build 24) on Xcode 27.2, Release, team `DD5AWPLT2V`,
in the shared `pixelhand-build` worktree.

**Build**
- Mac app: builds first time.
- iOS app: builds after 1 fix, `7b205ca`: `MirrorOverlay` passed the
  mirror tile's `stepsAsideWhenCrowded` before `belowAccessoryHeight`, but
  the memberwise init declares them the other way round (the VQ-083 change).

**Tests**
- `swift test --package-path DeckHand/Core`: **1058 / 1058 pass** (190 suites).
- `swift test --scratch-path .build-local`: **480 / 480 pass**.
- `DeckHandTests`: **8 / 8 pass**.

**Install**
- Mac: `/Applications/Pixel Hand.app` replaced and launched with `open`.
- iPad Air 11" (M3): **not installed**. CoreDevice error 4016 ("not able to
  fulfill the requested usage assertion"): the iPad isn't reachable over
  Wi-Fi. It needs a USB cable or Xcode › Devices › "Connect via network".

**Final QA pass** (owner gave the Mac; scratch TextEdit in front).
Report: `DeckHand/Integration/VISUAL-QA-build24.md`. Gallery (private):
https://claude.ai/artifact/GqAPQEFb6QVVixc8KkaufT
- `PixelHandUITests`, all passed:
  - iPad Pro 11": 17 / 17, with `PH_QA_FULLSCREEN=1` (real landscape).
  - iPhone 17 Pro: 17 / 17.
  - AX3: iPhone 5, iPad 3. Dark mode: iPad 5.
  - iPad mini: 4 (Mac-free set).
  - `PH_QA_MAC_NAME` kept every walk on the MacBook.
- **qa23 fix lane: 20 / 20 IDs pass** (VQ-058, 060, 061, 034, 088,
  083…097). OR-16's flick now moves ~630 pt (was ~3,250) and stops at the
  display edge.
- **Totals:** VQ-001…097 74 pass · 1 fail · 22 not checked;
  OR-01…16 12 pass · 4 not checked.
- **Newly checked:** iPad landscape and the Macs sidebar (OR-04 pass),
  Home Screen widgets (VQ-070…073 pass), dark mode (clean).

**Open bugs**
1. **VQ-100 (P2):** the pairing sheet's unlabelled Mac chooser defaults to
   the first Mac in the list. On the iPad mini it read "AH's Mac mini" under
   "Type the code showing on your Mac". On iPhone the footer runs under the
   keypad.
2. **VQ-098 (P2):** the mirror tile covers the empty deck's "No keys yet" at
   AX3, and most of the card at AX5 (outside edit mode).
3. **VQ-099 (P2):** iPad AX3 landscape: the Macs sidebar cards cut names
   mid-word.
4. **VQ-066 (still failing):** iPhone AX3 free plan: Show screen is cut by
   its card's bottom edge.

P3: VQ-101 (no "Connecting…" during a slow reconnect), VQ-102 (AX5 picker
text slides under the header buttons), VQ-103 (iPad mini simulator isn't
paired, so its connect walks wait and put an Allow prompt on the Mac).

**Notes**
- **Front app changed mid-run.** The Mac's front app became Universal
  Control, then Chrome, partway through the iPhone run. Only `test04`
  types, and it ran while TextEdit was in front.
- **Not checked:** Lock Screen and Control Center (VQ-074…079), transfers
  (OR-13, needs the real iPad), the sidebar's hidden state (OR-05), Duo.

Status: BUILT (build 24) — 4 bugs

## Owner testing (build 24) — 2026-11-26

From the owner on the real iPad (screen recording reviewed by the primary
session; landscape, Pro unlocked):

- **OT-1 Dock icons (P2):** app icons in the bottom dock sit on a square
  white/black container in light and dark mode. They should look like the
  macOS Dock: the real icon shape, no tile behind it. Cause found: the Mac
  sends icons as 64×64 **JPEG** (`DeckHandMac/InstalledAppScanner.swift`
  ~L175–195), which has no alpha.
- **OT-2 Keyboard open/close loop (P1):** tapping the dock's keyboard
  button in iPad landscape makes the keyboard open and close repeatedly
  until rotating to portrait or tapping the button again. In the recording
  the shell switches to a compact arrangement when the keyboard appears,
  then back, each cycle. Likely cause: the keyboard shrinks the layout
  (no `.ignoresSafeArea(.keyboard)` anywhere in `DeckHandiOS`), the
  arrangement changes, the view holding the first responder is rebuilt,
  the keyboard drops, the layout reverts.
- **OT-3 Typing UX (P2, owner open to ideas):** the keyboard input bar
  doesn't follow the rebrand, typing into a Mac text field isn't easy,
  and there's no number keypad.
- **OT-4 Right column handle (P2):** the collapsed right column's edge
  handle is hardly visible; it matches the background.
- **OT-5 Ask gets stuck after one use (P1):** after running a plan, the
  column ends in a state that only offers a Name field (rename and save);
  there's no way back, no new request and no other actions.

Fix lane: `claude/pixelhand-lane-owner24` (primary session). All five
fixed there, with Core tests and two UI walks (`test18`, `test19`); see
`LANE-owner24.md` for the iPad checks to run on the next build.

## Build 25 queued (2026-11-26): build 24 QA fixes + owner fixes OT-1…OT-5

- **qa24-fixes** (`LANE-qa24-fixes.md`): VQ-098 (mirror tile off the empty
  deck), VQ-099 (sidebar cards stack at AX sizes), VQ-100 (pairing chooser
  defaults to the Mac that asked), VQ-066 (free-plan card buttons pinned),
  VQ-101 Connecting… during reconnect, VQ-102 picker top-bar backdrop,
  VQ-103 walks pair or skip unpaired simulators.
- **owner24** (`LANE-owner24.md`): OT-1 transparent app icons (PNG/HEIC
  with alpha) and a macOS-style dock with an accent dot; OT-2 the keyboard
  no longer changes the arrangement (fixes the open/close loop); OT-3 the
  new Type panel (Live and Compose, keys row, fn keys, sticky modifiers,
  numpad, hardware-keyboard mode; `RemoteKeyboardPanel` deleted); OT-4 a
  high-contrast right-column handle; OT-5 Ask's `AskFlow` (New request,
  Run again, Save as key with Cancel, Edit).

Mac should check: build all targets (compile risks in both handoffs);
Core, Loom and app tests; the UI walks including the new landscape
keyboard walk and the Ask loop walk; install on the Mac and the iPad (if
the iPad is unreachable, say so plainly); then the final QA pass on the
iPad Pro 11" simulator in landscape. The owner re-checks OT-1…OT-5 on the
real iPad.

Status: READY FOR MAC BUILD (build 25)
## Mac build results (build 25) — 2026-11-26

Built from `c9b87da` (build 25) on Xcode 27.2, Release, team `DD5AWPLT2V`.

**Build:** Mac app and iOS app both build first time, with no fixes.

**Tests**
- `swift test --package-path DeckHand/Core`: **1133 / 1133 pass** (205 suites).
- `swift test --scratch-path .build-local`: **480 / 480 pass**.
- `DeckHandTests`: **8 / 8 pass**.

**Install**
- Mac: replaced and launched with `open`.
- iPad Air 11" (M3): **installed and launched**; the iPad was reachable this
  time. The owner can re-check OT-1…OT-5 on it.

**Walks** (owner gave the Mac; scratch TextEdit in front at the start)
- iPad Pro 11", full screen: **18 / 19 pass**. `test18_KeyboardStaysOpenInLandscape`
  fails: "The close button didn't close the panel" (bug 1).
- AX3: iPad `test13` and `test14`, iPhone `test03`, `test12` and `test14`;
  all pass.
- `test19_AskAgainAfterRun` passes and opened Mission Control on the Mac.

**Re-checks**
- **owner24:**
  - OT-1: dock icons are transparent on iPad and iPhone.
  - OT-2: in landscape, the keyboard stays open and the arrangement doesn't
    change.
  - OT-3: the Type panel has Live, Compose, the keys row, fn and numpad, and
    names the target app ("Typing into …").
  - OT-4: the collapsed column handle is an outlined, visible tab.
  - OT-5: after a run Ask offers New request, Run again, Save as key (with
    Cancel) and Edit.
  - All pass in the simulator, except the portrait Type panel (bug 1).
- **qa24-fixes:**
  - VQ-066: Show screen now sits inside its card at iPhone AX3.
  - VQ-098: the mirror tile stays off the empty deck.
  - VQ-099: iPad AX3 sidebar cards stack with whole words.
  - All three pass.
  - Not checked: VQ-100 ("AH's Mac mini" was no longer on the network, so
    the two-Mac chooser couldn't be reproduced), VQ-101 (cold boot),
    VQ-102 (AX5), VQ-103 (iPad mini).

**Open bugs**
1. **Type panel hidden in portrait (P1, OT-2/OT-3):** after `test18`
   rotates back to portrait with the keyboard up, the Type panel is behind
   the keyboard. Its close button isn't hittable, so the panel can't be
   closed (`test18` capture `11-not-hittable-ph.type.close`).
2. **Ask keeps the old request (P3, OT-5):** after Save as key › Cancel,
   the field still holds "Take a screenshot", so the next request is
   appended ("nowTake a screenshot") and Ask can't understand it.

**Tooling and an incident**
- The Mac's front app changed from TextEdit to Claude during the run, so
  `test18`'s Live step typed "hello" (no Return) into the Claude app on
  the Mac. Nothing was sent; the owner was told.
- The walks put the scratch document in front only at the start. They
  should check the front app before every step that types into the Mac.


## Owner testing (build 25) — 2026-11-26

The owner says build 25 is much better (layout and overall). Refinements,
from two iPad landscape screenshots (dark mode):

- **OT-6 Type panel can't move or resize (P1 usability):** it's a wide
  fixed card over the middle of the screen, so it hides where you're
  typing on the Mac. It should be **draggable** (put it anywhere, remembered)
  and **resizable** down to a sensible minimum width.
- **OT-7 Type panel and numpad too big (P2):** everything sits in one long
  row (field, then a full-width keys row: ⌘ ⌥ ⌃ ⇧ esc tab ⌫ ⏎ ← ↓ ↑ → home
  end pg fn). Use the space better: a shorter field (about 30% narrower)
  with an **inverted-T arrow cluster** beside it (↑ above ← ↓ →), keys in
  two compact rows instead of one stretched row. The numpad is also too
  large and should be compact, ideally docking beside the type keys
  instead of adding another tall block.
- **OT-8 Ask plan with a typed step can't be saved as a key (P2):** Ask
  plan "Open Safari · Type “youtube” · Press ⏎" ran fine, but Save as key
  shows "Keys can't type text yet. Remove the Type step to save this plan
  as a key." Deck keys should support typed-text steps (with the same
  "asks first" Return guard), so any plan Ask can run can be saved.

Fix lane: `claude/pixelhand-lane-owner25` (primary session).

Lane written: `LANE-owner25.md` (Type panel moves, resizes and folds; compact
two-row keys, inverted-T arrows, docked 5 × 4 numpad; keys that type, protocol
15). Needs an iPad re-check.

## Build 26 queued (2026-11-26): owner refinements and the final QA pass

Build 26 is build 25 plus lane owner25 (`LANE-owner25.md`), merged at
`45e9e7d`, plus the walk guard (`58d9204`). It contains:

- **OT-6:** the Type panel is draggable and resizable, and remembers where
  it was.
- **OT-7:** a compact Type panel: a shorter field, an inverted-T arrow
  cluster, two key rows, and a docked numpad.
- **OT-8:** deck keys can type text, with the same Return guard, so any
  plan Ask runs can be saved as a key. **Protocol 15: the Mac and the
  iPad must both run build 26.**
- **Build 25 bug 1 (P1):** the Type panel always stays above the keyboard,
  in every orientation and during rotation.
- **Build 25 bug 2 (P3):** Ask selects the old request when the field is
  focused, so typing replaces it.
- **Walks:** before typing on the Mac, they check the Mac's front app
  (`PH_QA_SCRATCH_APP`, default TextEdit). New walks: `test20` and `test21`.
  `test21` types into Safari only with `PH_QA_TYPE_IN_SAFARI=1`.

Linux: Core **1180 / 1180 pass** (215 suites); `linux-typecheck/run.sh`
passes; the UI tests parse and their braces balance.

**Mac should do:**
1. The build and all tests.
2. Install on the Mac and the iPad.
3. With the owner's OK to use the Mac and a scratch TextEdit document in
   front, run every walk:
   - iPad Pro 11" full screen and the iPhone 17 Pro, plus AX3;
   - `test18` (keyboard) in **both** orientations;
   - `test19`, `test20` and `test21`.
4. **Final QA pass:**
   - Re-check the `LANE-owner25.md` IDs and OT-1…8.
   - Re-check the open P3s: VQ-100 (if a second Mac is around), VQ-101,
     VQ-102 and VQ-103.
   - Record pass, fail or not checked in `VISUAL-QA-build26.md` (new
     findings from VQ-104), with the gallery.
   - If there are no P1 or P2 findings, the coordinator publishes the
     owner's review page.

Status: READY FOR MAC BUILD (build 26)

## Owner testing (build 26) — 2026-11-26

From the owner on the real iPad (portrait, dark), five screenshots, with
orange annotations marking wasted space:

- **OT-9 Send sheet off-theme (P2):** the Send/Inbox sheet doesn't follow
  the design system: stock segmented control and text field, oversized
  "Send to" cards (an offline Mac shown as a big dim card), labels not
  aligned under the cards, the lone blue clipboard circle, lots of empty
  space. Redesign it in the pixel identity with proper sizing and
  alignment.
- **OT-10 Capture preview in portrait (P2):** the full-screen capture shows a
  small image at the top, the action bar (Save, Copy, Share, Annotate,
  Read text) under it, and half the screen empty. Fit the image to the
  available space, actions anchored at the bottom, in both orientations.
- **OT-11 Type panel wastes space (P2):** the row beside the arrows under
  the text field is empty; the area under the arrow cluster is empty; the
  arrow keys stay one size whatever the panel's width and height. Make
  every block size to the panel. **In numpad mode show only the arrows and
  the numpad** (drop the modifier and special-key rows). When the panel is
  minimal, put the arrows in **one row** to save height. "Typing into
  Claude" appears twice (header label and field placeholder): keep one,
  ideally just the app icon in the header.
- **OT-12 Zoom to the input (idea from the owner):** a button on the Type
  panel that shows the Mac's focused text field up close, so you can see
  what you type without hunting for it on the mirror.
- **OT-13 Question:** can Live mode surface the Mac app's inline
  suggestions (e.g. Claude's ghost text accepted with Tab)?
- Also seen: with a hardware/minimised keyboard, the iPadOS keyboard bar
  (EN US · Paste from Screenshots · mic) sits over the app dock; the panel
  and dock should respect that frame.

Fix lane: `claude/pixelhand-lane-owner26` (primary session).

Lane written: `LANE-owner26.md` (Type panel fills its width × height, numpad
only with arrows, one-row arrows, target once, dock over the keyboard bar;
zoom-to-input loupe, protocol 16; Accept ⇥ and OT-13 findings; Send sheet
and capture preview redrawn). Needs an iPad and Mac re-check.

## Mac build results (build 26) — 2026-11-26

Built from `38c4a97` (build 26) on Xcode 27.2, Release, team `DD5AWPLT2V`.

**Build:** the Mac app and the iOS app build. The UI test target didn't
compile (`test20` passed an `XCUICoordinate` where `press(forDuration:thenDragTo:)`
wants an element): fixed in `a2f4adf`, which drags from the grip's and the
handle's coordinates.

**Tests**
- `swift test --package-path DeckHand/Core`: **1180 / 1180 pass**.
- `swift test --scratch-path .build-local`: **480 / 480 pass**.
- `DeckHandTests`: **8 / 8 pass**.

**Install:** Mac replaced and launched with `open`; iPad Air 11" (M3)
installed and launched (protocol 15 on both).

**Walks** (owner gave the Mac; scratch TextEdit in front)
- iPad Pro 11", full screen: **20 / 21 pass**. `test21` fails: Save as
  key's Save button is under the keyboard (VQ-104).
- iPhone 17 Pro: **20 / 21 pass**. `test21` saves the typed plan as a
  key and the key asks first, then fails tapping a Cancel the iPhone
  popover doesn't have (VQ-106, walk only).
- AX3 (iPhone 17 Pro): `test01`, `test09`, `test12`, `test14` pass. In
  `test09` and `test12` the launch reconnect never finished, so Settings
  and the paywall at AX3 weren't reached (see VQ-107).
- iPad mini (unpaired): `test04` is skipped as unpaired and sends the Mac
  no request (VQ-103 pass).
- The front-app guard worked: the Mac's front app changed to Claude
  (iPad run) and FlutterFlow Studio (iPhone run); the iPad's typing steps
  were skipped, and TextEdit was put back before the iPhone's. Only
  TextEdit received “hello”; `test19` ran Show Mission Control.

**Final QA pass:** `VISUAL-QA-build26.md`, gallery https://claude.ai/artifact/Y56FqdNycRXGqXwQ4ugK1N
- Owner testing OT-1…8: **7 pass, 1 fail** (OT-8 on iPad portrait,
  VQ-104). Build 25 bug 1 (`test18`, both orientations) and bug 2
  (`test19`): **pass**.
- Open P3s: VQ-101 **pass** (Connecting… with Cancel shows, but breaks
  at AX3: VQ-107); VQ-103 **pass**; VQ-100 and VQ-102 **not checked** (no
  second Mac on the network, no AX5 run).
- New findings: **VQ-104 (P2)**, VQ-105 (P3), VQ-106 (P3 tooling),
  **VQ-107 (P2)**, VQ-108 (P3).

**Open bugs**
1. **VQ-104, Save as key hidden under the keyboard (P2, OT-8):** iPad
   portrait, three-step plan: the name field is the last visible row and
   Save and Cancel are scrolled out of view. Return still saves.
2. **VQ-105, no keyboard button on the iPhone in landscape (P3):** the
   Screen tab in landscape has neither `ph.dock.keyboard` nor
   `ph.trackpad.keyboard`, so `test18` and `test20` stop early on iPhone.
3. **VQ-107, Connecting… breaks at AX3 (P2):** on the iPhone picker the
   reconnect state is squeezed to “Con- / necti…”, its Cancel draws over
   Pair, and twice the reconnect gave up.
4. **VQ-108, number pad over the pair sheet's title (P3):** iPad mini.

There are two P2s, so this isn't the clean pass that unlocks the owner
review page. Build 27 (queued below) changes the Type panel and Send areas, so
VQ-104 and VQ-105 can be checked again on it; VQ-107 and VQ-108 need a fix round.

Status: BUILT (build 26) — 4 bugs

## Build 27 queued (2026-11-26, primary session): owner round 26

Build 26 plus **owner26** (`LANE-owner26.md`, protocol 16):
- **OT-11** Type panel sizes every block to the panel: arrows scale, field
  can take two lines, numpad mode shows only arrows + numpad, arrows in
  one row at the minimal size, target shown once (app icon in the header),
  panel and dock avoid the iPadOS keyboard bar.
- **OT-12** Zoom to the input: the Mac reads the focused field and caret
  through Accessibility; a live loupe on the Type panel follows it (Pro);
  falls back to the area around the pointer.
- **OT-13** Accept ⇥ (Tab) in Live mode; native fields' text shown in the
  loupe. Ghost text from web/Electron apps (Claude) isn't readable as text;
  the loupe shows it as pixels.
- **OT-9** Send sheet redesigned in the design system; **OT-10** capture
  preview fits the screen in portrait.

Owner decision taken by the primary session: the Send sheet's Clipboard
chip should use the system `PasteButton` (no "Allow Paste" prompt), in
line with the S10 decision (UIPasteControl, no paste prompts). If the
lane's custom chip shipped, switch it in the next fix round.

Mac should check: build all targets (compile risks in the handoff), Core,
Loom and app tests, the walks (Type panel bands, loupe, Send sheet,
capture), the "Mac checks (protocol 16)" list, install on Mac and iPad.

Also in build 27: **paste-control** (`LANE-paste-control.md`), the Send
sheet's Clipboard chip uses the system paste control (no "Allow Paste").

Status: READY FOR MAC BUILD (build 27)

## Mac build results (build 27) — 2026-11-26

Built from `576f234` (build 27 is `a1550fb` plus the build 26 report) on
Xcode 27.2, Release, team `DD5AWPLT2V`.

**Build:** the Mac app, the iOS app and the UI test target all build first
time, with no fixes (none of the handoff's compile risks hit).

**Tests**
- `swift test --package-path DeckHand/Core`: **1265 / 1265 pass** (224 suites).
- `swift test --scratch-path .build-local`: **480 / 480 pass**. The first
  run, while the simulators were busy (load ~90), had one timing failure,
  “Realtime display queue shapes drains into bounded bursts”
  (`LoomOrderedUnreliableSendQueueTests.swift:407`), and then hung in the
  next test binary for 29 minutes. Rerun at normal load: all pass. Looks
  load-sensitive, not new.
- `DeckHandTests` (macOS): **8 / 8 pass**.

**Install:** Mac replaced and launched with `open`; iPad Air 11" (M3)
installed and launched (protocol 16 on both).

**Walks: only those that send nothing to the Mac.** The owner was using
the Mac (Slack and FlutterFlow Studio in front), so the walks that type or
click on the Mac (`test04`, `05`, `16`, `18`, `19`, `20`, `21`) and the
hands-on "Mac checks (protocol 16)" (loupe in TextEdit, Safari, Notes,
Mail; password field; Claude or Slack AX; lock; disconnect; OT-13 with
Accessibility Inspector) wait for the owner.
- iPad Pro 11", full screen: 01, 02, 03, 07, 09, 10, 11, 12, 13, 14, 17
  pass; **`test22`, `test23`, `test24` fail**.
- iPhone 17 Pro: 01, 03, 07, 09, 11, 12, 14, 23 pass (`test23` skipped
  itself: no `ph.transfer.send` on iPhone); **`test22`, `test24` fail**.

**Open bugs**
1. **Loupe covers the Type panel for hit-testing (P2, OT-12):**
   `FocusLoupeView` combines its children into one accessibility element,
   and the child is the whole mirror frame scaled up and offset, so the
   loupe's frame is about 4536 pt wide on iPad (`.clipped()` doesn't trim
   it). With the loupe open in portrait the panel's target chip and close
   aren't hittable (`test22` captures `06-not-hittable-ph-type-target`,
   `07-not-hittable-ph-type-close`); VoiceOver over the panel lands on the
   loupe. Fix: `.accessibilityHidden(true)` and `.allowsHitTesting(false)`
   on the picture, and `.contentShape(Rectangle())` on the loupe.
2. **Arrows don't grow with the panel (P2, OT-11):** `test22` drags the
   trailing resize corner down and the arrows stay 44 pt (wants > 48), on
   iPad (panel sitting on the keyboard) and iPhone (docked). Either the
   drag has no room to grow into with the keyboard up or the panel's height
   doesn't reach the arrows; the lane should check which.
3. **Send sheet chips (P3, OT-9):** iPad `test23`: the source chips are
   43 pt tall (wants 44) and 174.5 / 175 / 173.5 pt wide (wants equal).
4. **Capture preview off centre (P3, OT-10):** `test24`: the picture is
   8–9 pt nearer the header than the dock (246 / 255 pt iPad portrait,
   199 / 207 iPhone portrait, 12 / 20 landscape). On iPad the dock's
   measured frame ends 1169 pt below the window, probably an identifier on
   an oversized container (the same pattern as bug 1).
5. **iPhone landscape (P3):** `test22` finds no `ph.dock.keyboard` (as
   VQ-105) and then the panel's header has no target.

**Next:** with the owner's OK and a scratch TextEdit document in front,
run the Mac walks and the protocol 16 checks, and record them here.

Status: BUILT (build 27) — 5 bugs

## Owner testing (build 27) — 2026-11-27

From the owner on the iPad (landscape, dark), four screenshots:

- **OT-14 Badge behind its button (P2):** after sending from the
  clipboard, the Send button's indicator dot draws behind/under the glass
  circle (cut off). Same class as the earlier free-plan Pro badge drawn
  behind buttons. Fix the badge overlay for every glass button (draw above,
  never clipped), not just this one.
- **OT-15 Inbox uneven on iPad (P2):** the Send/Inbox sheet in Inbox is
  misaligned: the sheet sits off-centre over the canvas and right column,
  the empty state isn't centred in it, header spacing uneven.
- **OT-16 Send to names truncated (P2):** "Mu…Pro" in the device card;
  show the full Mac name (wrap to two lines, size cards to the name). The
  offline row "AH's Mac mini …" should match the card style.
- **OT-17 Paste chip looks different (P3):** Photos and Files match, Paste
  (system paste control) is styled differently (accent text). Make the
  three source chips look the same.
- **OT-18 Header Ask field (owner question):** the wide "Tell <Mac>…" field
  in the header has alignment issues and only opens the Ask column. Primary
  session's recommendation: replace it with a compact ⌘K button now (frees
  the header, fixes alignment; still opens Ask), and later turn ⌘K into a
  universal command palette (apps, deck keys, menu commands, Macs, then
  Ask) if the owner wants it.

Fix lane: `claude/pixelhand-lane-owner27` (primary session).

## Build 28 queued (2026-11-27, primary session)

Build 27 plus **build27-fixes** (`LANE-build27-fixes.md`): loupe no longer
swallows the Type panel's taps, arrows grow with the panel, Save as key
stays above the keyboard (VQ-104), Connecting… at AX3 (VQ-107), iPhone
landscape keyboard button (VQ-105), number pad clear of the pair sheet
title (VQ-108), Send chips 44 pt equal width, capture preview centred.

Mac should check: build all targets, tests, the walks including `test22`,
`test23`, `test24`; the Mac walks and protocol 16 checks need the owner's
Mac free with a scratch TextEdit document in front.

Also in build 28: **owner27** (`LANE-owner27.md`): badges and dots drawn
above glass buttons everywhere (OT-14), Send/Inbox sheet centred with an
even header and stable size (OT-15), full Mac names in Send to (OT-16),
matching Photos/Files/Paste chips (OT-17), header Ask field replaced by a
compact ⌘K button (OT-18).

Status: READY FOR MAC BUILD (build 28)

## Mac build results (build 28) — 2026-11-27

Built from `d307d54` on Xcode 27.2, Release, team `DD5AWPLT2V`. **This is build 28 without owner27:** owner27 was folded in (`7fc7d2f`) while this ran. A rebuild of the full build 28 follows; read these results as the build27-fixes check only.

**Build:** the Mac app, the iOS app and the UI test target build first
time, with no fixes.

**Tests**
- `swift test --package-path DeckHand/Core`: **1283 / 1283 pass** (233 suites).
- `swift test --scratch-path .build-local`: **480 / 480 pass** (run on its
  own, with no simulators busy).
- `DeckHandTests` (macOS): **8 / 8 pass**.

**Install:** Mac replaced and launched with `open`; iPad Air 11" (M3)
installed and launched.

**Walks: only those that send nothing to the Mac** (the owner said
"later" for the Mac walks and the protocol 16 checks).
- iPad Pro 11", full screen: 01, 02, 03, 07, 09, 10, 11, 12, 13, 14, 17,
  23 pass; **`test22`, `test24` fail** (one assertion each, below).
- iPhone 17 Pro: 01, 07, 09, 11, 12, 14, 23, 24 pass; **`test03`,
  `test22` fail**.
- iPhone 17 Pro AX3: 01, 09, 12 pass. The launch reconnect now finishes
  at AX3 (build 26 had two walks stuck), and the picker at rest shows
  Pair, Settings and the whole “Paired · Nearby” line.

**build27-fixes re-checks**
- Loupe taps (build 27 bug 1): **pass**. With the loupe open the panel's
  target chip and close are hittable again. The walk's frame check
  ("The loupe covers the panel") still fails on iPad (bug 3).
- Arrows grow (bug 2): **pass** on iPad: the tall drag grows the panel and
  its arrows (`test22` 03 vs 02).
- Send chips (bug 3): **pass** (`test23`, iPad and iPhone).
- Capture centring (bug 4): **pass** on both; the iPad dock frame check
  still fails (bug 4).
- VQ-107 (AX3 connect): **pass** for the reconnect; the Connecting… pill
  itself wasn't caught on screen.
- VQ-104, VQ-105, VQ-108: **not checked**. VQ-104 is in `test21` (types
  on the Mac); on iPhone landscape `test22` still snaps
  `missing-ph-dock-keyboard` before finding the panel (VQ-105); the iPad
  mini wasn't run (VQ-108).

**Open bugs**
1. **iPhone Live has no Accept (Tab) (P2, OT-13):** `test22` portrait and
   landscape: no `ph.type.accept` in Live on iPhone (iPad has it; build
   27's iPhone panel showed ⇥ ACCEPT).
2. **iPhone panel and keyboard (P3):** `test22`: "The taller panel went
   under the keyboard" by 374 pt, yet the captures show the panel above
   the dock with no system keyboard on screen. Either the keyboard didn't
   come up on iPhone or the walk reads a hidden keyboard's frame.
3. **Loupe frame overlaps the panel (P3):** iPad `test22`: taps work now,
   but the loupe's frame still intersects the panel's.
4. **Capture dock frame (P3):** iPad `test24`: the dock's measured frame
   ends 1177 pt (portrait) / 801 pt (landscape) below the window, though
   it looks right; likely the identifier sits on an oversized container.
5. **iPhone picker (P3):** `test03` fails: no `ph.connect.settings` on
   the picker (the walk used to snap it as missing and go on).

**Still waiting for the owner:** the Mac walks (`test04`, `05`, `16`, `18`,
`19`, `20`, `21`) and the protocol 16 checks.

Status: READY FOR MAC BUILD (build 28)

## Mac build results (build 28 with owner27) — 2026-11-27

Rebuilt from `839d62a` (build 28 with owner27 folded in) on Xcode 27.2,
Release, team `DD5AWPLT2V`. This replaces the build 28 section above
(which ran before owner27 was folded in) except where it says otherwise.

**Build:** the Mac app builds; the iOS app didn't compile:
`DeckHandiOS/Transfer/TransferSheet.swift:1081`, a `? :` between a `Color`
and a `RadialGradient` in the Send to tile's fill. Fixed in `5348ee6`
(both sides wrapped in `AnyShapeStyle`). The iOS app and the UI tests
then build.

**Tests**
- `swift test --package-path DeckHand/Core`: **1305 / 1305 pass** (238 suites).
- `swift test --scratch-path .build-local`: **480 / 480 pass**.
- `DeckHandTests` (macOS): **8 / 8 pass**.

**Install:** Mac replaced and launched with `open`; iPad Air 11" (M3)
installed and launched.

**Walks: only those that send nothing to the Mac** (the owner said
"later" for the Mac walks and the protocol 16 checks).
- iPad Pro 11", full screen: 01, 02, 03, 07, 09, 10, 11, 12, 13, 14, 17,
  25, 26 pass; **`test22`, `test23`, `test24` fail**.
- iPhone 17 Pro: 01, 03, 07, 09, 11, 12, 14, 23, 24, 25, 26 pass
  (`test26` skips itself: no header Ask button on iPhone); **`test22`
  fails**.
- iPhone 17 Pro AX3: 01, 09, 12 pass (the reconnect finishes, VQ-107).

**Re-checks**
- owner27: OT-14 badges above glass (`test25`, iPad and iPhone): **pass**.
  OT-18 header ⌘K Ask button (`test26`, iPad): **pass**, opens Ask with
  Recent. OT-15 and OT-16: the Send sheet is centred with an even header
  and shows “Muhammad’s / MacBook Pro” in full. OT-17: see bug 3.
- build27-fixes: as in the section above. Loupe taps, arrows grow, Send
  chips at 44 pt and capture centring **pass**.

**Open bugs**
1. **iPhone Live has no Accept (Tab) (P2, OT-13):** `test22`, still: no
   `ph.type.accept` in Live on iPhone. The iPad has it.
2. **iPhone landscape keyboard button not hittable (P2, VQ-105):** the
   rail now has a keyboard button (`ph.rail.keyboard`, visible in the
   capture) but XCTest says it isn't hittable, so `test22` can't open the
   Type panel in landscape (`06-not-hittable-ph-rail-keyboard`). Needs a
   check by hand.
3. **Send sheet (P3, OT-15…17):** iPad `test23`:
   - The device card is 90.5 pt tall (the walk wants ≤ 84). The full
     two-line name (OT-16) makes it taller, so the walk's limit and OT-16
     disagree.
   - The Paste chip's fill differs from Photos and Files by 23 (≤ 12
     wanted). It's the system `PasteButton`, per the owner's decision.
   - "Sheet centred" compares against a window frame the walk reads as
     zero, so that check is the walk's own bug.
4. **Loupe frame overlaps the panel (P3):** iPad `test22`: taps work; the
   frame check still fails.
5. **Capture dock frame (P3):** iPad `test24`: the dock's measured frame
   ends 1177 / 801 pt below the window, though it looks right.

**Still waiting for the owner:** the Mac walks (`test04`, `05`, `16`, `18`,
`19`, `20`, `21`, which also covers VQ-104) and the protocol 16 checks.

Status: BUILT (build 28) — 5 bugs
