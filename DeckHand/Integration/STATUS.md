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
