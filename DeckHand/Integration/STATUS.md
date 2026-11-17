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
