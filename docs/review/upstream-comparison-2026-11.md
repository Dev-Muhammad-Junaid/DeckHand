# Deck Hand × upstream Loom × Sill — November 2026 comparison

Date: 16 November 2026. Supersedes the review run on the owner's Mac on 17 October 2026.

Inputs:

| Codebase | Revision reviewed |
| --- | --- |
| Deck Hand | `main` at `b920181` (17 Oct 2026). `main` has not moved since. |
| Upstream Loom | `main` at `3e005c0` = tag **2.2.16** (1 Aug 2026) |
| Sill | `main` at `4e00c80` = **v0.6.2** (16 Nov 2026) |

Trial-merge branch: `scratch/trial-merge-loom-2.2.16`. It is pushed for the Mac build and is not meant for `main` as it stands.

> **How far to trust each conclusion.** This review ran in a Linux container. Apple-platform Swift (Network.framework, SwiftUI, ScreenCaptureKit, the Xcode app targets) cannot be compiled there. Every claim below is tagged:
>
> - **[read]**: verified by reading code or git history.
> - **[linux]**: checked with Swift 6.2.3 on Linux. In practice this covers only SwiftPM package resolution. A Linux compile of the merged `Loom` target is not possible, because Deck Hand's own fork files import `CryptoKit` and `Security` without `#if canImport` guards. So **no merge resolution has been compiled yet.**
> - **[mac]**: not verified. It needs the Mac commands in §3.6.
>
> Sill numbers come from Sill's own docs, measured on its developer's hardware.

---

## 1. Summary

1. **Upstream Loom has not changed since 2.2.16.** The 17 October merge analysis still applies, with the corrections in §2. Upstream has had no commits for 3½ months; its only other branch was merged in July.
2. **Merging upstream Loom is still the right Loom move, and it should happen before launch.** That merge is the one thing on the list that breaks the wire protocol (Loom v2→v3). Every Sill-inspired feature, HEVC included, can ship later as an additive, capability-gated change.
3. **The pairing break is smaller than the October review said.** It is a single policy flip in Loom, and a ~40-line Mac-side trust provider fixes it with today's Allow/Deny unchanged. That provider is already on the scratch branch. A new trust system is not required.
4. **HEVC does not depend on the Loom merge.** Sill runs video, input and audio over **one TCP+TLS connection**, with app-level backpressure. Deck Hand can do the same on a dedicated Loom stream on either fork.
5. **There is a cheap latency win nobody had flagged.** Deck Hand leaves Loom's `enablePeerToPeer` at its default of `true`, which turns on AWDL. Sill measured AWDL taking p90 latency from ~4 ms to 48–67 ms, and switched it off by default.
6. **Recommendation: Option C** (§5). Merge Loom now. Add the cheap Sill wins and release plumbing. Ship 1.0 in about 3 weeks, then ship HEVC as 1.1 without a second protocol break.

---

## 2. What changed, and what the October review got wrong

### 2.1 Upstream Loom

- Deck Hand forked at **1.6.11** (`92e176f`, 30 Mar 2026). Since then upstream has 83 commits and Deck Hand's fork has 80.
- Upstream since 2.2.16: **0 commits** **[read]**. `codex/pyrowave-tcp-receive-pump` (`9af254a`, "Remove TCP media throughput bottleneck") is already in `main`.

What upstream changed between 1.6.11 and 2.2.16, grouped:

| Area | Notable commits | Effect on Deck Hand |
| --- | --- | --- |
| Trust / handshake | `20783ef` "Fail closed when trust requires manual approval" (2 Apr); `be1702b`, `91128cd` security hardening; `5c2a77b` AES-GCM | **Breaks first-time pairing** (§3.3). |
| Wire protocol | `Loom.protocolVersion` 2 → **3** (`d7a9d21`, 22 May); UDP handshake isolation and flags | Old and new builds cannot connect (§3.4). |
| Media / realtime | priority input lane (`b439e4e`, `2b4ce58`), queued realtime and audio media profiles (`140bed9`, `92432b6`), batched TCP receives, removal of the TCP media throughput bottleneck | Useful for HEVC and input, but not required. |
| Discovery | AWDL/proximity preference, Bonjour off the main thread, TXT-monitor races, local-network-denied reporting | Several fixes for bugs Deck Hand has worked around. |
| Transfers | offer and completion deadlines, pending data-stream expiry, explicit failure on a bad resume offset | Very likely fixes `invalidResumeOffsetIsRejected` **[mac]**. |
| Platform | portable `LoomNetworking` / `LoomNetworkingNIO` backends, Windows support, QUIC added and then **removed** (`0116430`), floors back to iOS 17.4 / macOS 14, visionOS 26 | Core `Loom` now links swift-crypto (pinned `exact: 4.5.1`) and NIOSSH. |
| Identity | keychain-storage backends, an in-memory identity manager | The fork's keychain upsert fix had to be re-applied (§3.2). |

### 2.2 Sill

Sill has had 856 commits since 15 October and three releases: **v0.6.0** (2 Nov), **v0.6.1** (11 Nov) and **v0.6.2** (16 Nov). New since mid-October:

- **Audio** from the Mac, encoded as AAC-ELD. It is labelled beta and is on by default.
- **Clipboard** sync in both directions, text only, up to 256 KB.
- **Locked Mac:** a locked Mac streams only its lock screen and withholds windows, menus, sound and the clipboard.
- **Display wake** when the user interacts.
- **Picture in Picture**, **Full Screen**, and a **multi-monitor Desktop** button.
- **Hardware keyboard:** key repeat, CJK input methods, dictation.
- **Remote access:** "away" detection for Tailscale and SSH tunnels. Sill still has no relay server.
- **Self-updater:** custom, not Sparkle. It checks the GitHub Releases API, verifies Developer ID and notarization, and requires an Ed25519-signed manifest.
- **Releases:** a nightly channel and universal Mac builds.

**Corrections to the October Sill conclusions [read]:**

| October claim | Now |
| --- | --- |
| Sill lacks "shortcut chips from real menus" | **Overstated.** Sill has mirrored the Mac's real menus since **v0.5.1** (Sept): an Accessibility menu reader, the iPadOS 26 menu bar, and tap-to-press with a pressed/refused answer. It has no one-tap chips and no favourites; its shortcuts are display-only. Deck Hand's edge is speed and context (chips, dialog buttons), not access to menu commands. |
| Sill lacks delivery receipts | **Partly.** Menu presses and settings changes are acknowledged. Input, keys and window commands are not. |
| Keychain + Secure Enclave keys | **Wrong on Secure Enclave.** The device key is a software keychain P-256 key. Secure Enclave exists only behind a DEBUG flag (`iOSClient/DeviceIdentity.swift:13-23`). |
| Raw trackpad gestures use private API | **Wrong.** Gestures are recognised on the device and sent as the Mac's own keyboard shortcuts. The only private piece is *reading* the user's shortcut bindings (`CGSGetSymbolicHotKeyValue` via `dlsym`). |
| 44 test suites with mutation testing | Now **74** check folders, 73 of them with mutants (~7,000 `check(` sites). These are not XCTest or Swift Testing; each check compiles real sources with `swiftc` alongside a `main.swift`. |
| ~3% CPU | Not found anywhere in Sill's repo. Treat it as unverified. |
| HEVC requires a datagram or unordered lane (implied) | **Wrong.** Sill uses one TCP connection: TLS 1.3, `noDelay`, `serviceClass = .interactiveVideo`. It drops delta frames when more than 2 sends are un-acked and then asks for a keyframe (`StreamServer.swift:1648-1667`). |

Still true: hardware HEVC (~58 fps at 3024×1898, 8–10 ms frame age; glass-to-glass estimated at 40–60 ms), the newest-frame mailbox, software fallback, keyframe recovery (now with a device request), `AVSampleBufferDisplayLayer`, the local cursor, USB detection, opt-in Direct Wireless, VPN remote access, 12-digit Damm-check pairing codes with a 5-minute window, Pencil hover, the iPhone portrait layout, SHA-pinned CI actions, TestFlight and notarized-DMG workflows, and the stats HUD.

**Deck Hand differentiators at Sill's head:**

| Feature | In Sill? |
| --- | --- |
| Dialog-button chips | No |
| OCR + annotation | No |
| Media-key UI | No |
| Per-shortcut confirmation | No |
| One-tap shortcut chips | No |

### 2.3 Deck Hand

- **`main`: no commits since 17 October.** The rebrand (cobalt and phosphor, dot-matrix art, menu-bar dot hand) and shortcut delivery receipts (`hostFeatures(commandReceipts:)`, `tracked`, `commandReceipt`) landed that day in PRs #7 and #8, together with `3917c1b`, a fix so a dropped dialog press is not confirmed.
- **Unmerged work on `origin`:**
  - `claude/affectionate-euler-0yuyqm`, 2 commits ahead:
    - `eb916ad` **moves LoomHost's blocking `accept()` and `read()` onto dispatch queues.** This fixes the "LoomHost blocks Swift's shared threads" defect and adds a test.
    - `08ccca3` contains the CI path filters and test timeout.
  - `claude/happy-lovelace-jso3t1` (today): CI runs on PRs only, the DocC Pages workflow is dropped, and `actions/checkout` is pinned.
- **Why October saw 17 conflicts and this run sees 16:** the October merge ran on top of `eb916ad`, which adds a conflict in `LoomHostSocketConnection.swift`. Merge `affectionate-euler` first and the count is 17 again. That conflict is a small mechanical one.

### 2.4 The October "known defects", re-checked

| Defect | Status |
| --- | --- |
| swift-nio-ssh GHSA-998x-vgvp-xwpc / CVE-2026-43798 (fixed in 0.14.1) | **Still open on `main`:** the committed `Package.resolved` pins **0.12.0** **[read]**. Upstream 2.2.16 pins **0.14.0**, also vulnerable. The scratch branch raises the floor to `from: "0.14.1"`, and SwiftPM then resolves **0.15.1** **[linux]**. Exposure is probably low because Deck Hand doesn't use the SSH bootstrap paths, but the fix is a one-line `Package.swift` change plus a re-resolve, worth doing on `main` now. |
| `invalidResumeOffsetIsRejected` (a failed transfer never reports failure) | Upstream rewrote the accept path. The sender now yields `.failed` and sends `cancel` on an invalid offset, and both directions have completion deadlines; upstream's test expects `.cancelled` **[read]**. Likely fixed by the merge **[mac]**. |
| `liveSamePeerConnectionOutsideWindowIsDropped` hangs on a 3-core runner | Deck Hand-only test, unchanged. Plausibly the same thread-starvation family as `eb916ad` **[mac]**. |
| LoomHost `send`/`connect` block the cooperative pool | Fixed on the unmerged `affectionate-euler` branch. |
| Mirror frames are base64 JPEG inside JSON on the input stream | **Still true** **[read]**. `ControlMessage.mirrorFrame(seq:data:)` goes through `LoomConnectionHandle.send(_ message: ControlMessage)` (`Shared/LoomConnectionHandle+ControlMessage.swift:38`) at JPEG quality 0.5, capped at 30 fps and 1920 px. `showsCursor = true`, so the cursor is baked into the frame. |

New findings:

- **AWDL is on.** `LoomContainerConfiguration(enablePeerToPeer:)` defaults to `true` and neither app overrides it **[read]**.
- **Spaces use `osascript`.** Spaces switching shells out to `osascript` (`ControlReceiver.swift:392`), which adds an Automation permission prompt and process-spawn latency.
- **One doc needs updating after the merge.** `DeckHand/AppleOS27-Support.md` cites `LoomCloudKitShareManager.swift`, which upstream renamed to `LoomCloudKitPeerManager.swift`.

---

## 3. Trial merge of upstream Loom 2.2.16

### 3.1 Mechanics

The merge was rerun on 16 November: `origin/main` (`b920181`) merged with `upstream/main` (`3e005c0`) on the branch `scratch/trial-merge-loom-2.2.16`.

- **16 files conflicted, 38 hunks** **[read]**.
- Auto-merged without conflict:
  - All **15 Deck Hand-only package files** survived: 14 sources and tests plus `ci.yml`.
  - Upstream's renames came in cleanly: `LoomCloudKitShareManager` → `LoomCloudKitPeerManager`, and `LoomRemoteCandidateTransportTests` → `LoomRemoteCandidateTests`.
  - Upstream's deletion of five tests came in cleanly. These were the LoomKit, LoomHost and bootstrap smoke tests and the transport-parameters tests.
- **Test count:** the fork has 194 `@Test`, upstream 428, the merge **460**.

### 3.2 Conflicts and how each was resolved

| File | Hunks | Resolution |
| --- | --- | --- |
| `Package.swift` | 1 | Took upstream's `.visionOS("26.0")`. The apps don't ship visionOS. Also raised `swift-nio-ssh` to `from: "0.14.1"`. |
| `Sources/Loom/Internal/Logging/Logger.swift` | 1 | Kept the fork's `LoomLogger.configure(subsystem:)` and its `LoggerStorage` cache. Dropped upstream's static per-category cache, which would freeze the subsystem at first use. |
| `.../Network/BonjourBrowser.swift` | 1 | Upstream's state tracking (`isBrowserReady`, `setLocalNetworkAccessDenied`) plus the fork's WID-333 guidance logging. |
| `.../Network/BonjourEntitlementCheck.swift` | 2 | Kept the fork's `isRunningInTestContext`, which is also used outside `DEBUG`. Added upstream's swift-testing argument checks. |
| `.../Utilities/LoomAsyncBroadcaster.swift` | 2 | **Combined:** upstream's `bufferingPolicy` and `Bool`-returning `yield`, plus the fork's `retainsHistory` replay. Both are init parameters. |
| `.../Sessions/LoomAuthenticatedSession.swift` | 2 | Took upstream's broadcasters and upstream's deadline-bounded trust resolution. Re-applied the fork's B1 fix: incoming-stream observers are created with `retainsHistory: true`. Removed the fork's now-unused 45 s approval timeout. **Kept upstream's fail-closed trust mapping** (§3.3). |
| `.../Sessions/LoomSessionProtocol.swift` | 1 | Kept both requirements: the fork's `makePathObserver()` (used by `LoomConnectionHandle`) and upstream's `makeBootstrapProgressObserver()`. |
| `.../Identity/LoomIdentityManager.swift` | 1 | Took upstream's storage-backend refactor. Re-applied the fork's `kSecAttrSynchronizableAny` upsert fix inside upstream's `LoomKeychainIdentityKeyStorage.swift`. |
| `.../Transfers/LoomTransferEngine.swift` | 4 | Took upstream's deadline and pending-stream machinery. Kept the fork's incoming-stream observer task and **WID-342 resume rehash**, now inside upstream's `do` block with the hasher written back to stored state. Verification now runs whenever a full running hash exists, not only for `resumeOffset == 0`. |
| `.../Types/LoomConnectionFailure.swift` | 1 | Upstream's finer DNS and TLS classification. |
| `LoomCloudKit/.../LoomCloudKitManager.swift` | 1 | Kept the fork's caches and account-change observer, which are still referenced. |
| `LoomHost/Internal/LoomVirtualAppSession.swift` | 2 | `package private(set) var state` (fork) plus `bootstrapProgress` (upstream), and both observer functions. |
| `Tests/LoomTests/LoomTransferEngineTests.swift` | 1 | Upstream's new test sources. `MemoryTransferSink` keeps the fork's `LoomReadableTransferSink` conformance. |
| `README.md` | 4 | Deck Hand's README. |
| `AGENTS.md` | 1 | Deck Hand's text plus upstream's "Repository Isolation" rule, which fits `AGENTS.md`'s product-agnostic rule. |
| `Architecture.md` | 3 | Upstream's product list. The fork's descriptions where upstream's still mention QUIC, which upstream later removed. |

On the branch, outside the merge commit:

- **`DeckHand/DeckHandMac/DeckHandHandshakeTrustProvider.swift`** (new) is wired in `MacHostApp.swift` through `LoomContainerConfiguration(trustProvider:)`.
- **`Package.resolved`** re-resolved: swift-nio-ssh 0.15.1, swift-nio 2.95.0, swift-crypto 4.5.1.

### 3.3 Pairing and trust: what breaks and why

This was verified by reading code **[read]**.

| | Fork (today) | Upstream 2.2.16 |
| --- | --- | --- |
| Map the provider's decision to the handshake | `evaluation.decision == .denied ? .denied : .trusted`, so **`.requiresApproval` → trusted** (`LoomAuthenticatedSession.swift:666`) | `evaluation.decision == .trusted ? .trusted : .denied`, so **`.requiresApproval` → denied** (commit `20783ef`) |
| How long trust may take | 45 s, its own task group | Inside the **handshake deadline: `authenticatedSessionHandshakeTimeout`, default 10 s**. LoomKit does not expose it. |
| Who evaluates | Host (receiver) only | Host (receiver) only |

Deck Hand passes no `trustProvider`, so LoomKit installs `LoomLocalTrustProvider`. That provider returns `.requiresApproval` for any device not in its store, which is every device, because Deck Hand never persists trust. Today that passes the handshake and `DeviceAuthorizationManager` shows Allow/Deny. After the merge the handshake denies the device first, so **no first-time connection can succeed**.

There are two ways to fix it:

1. **Keep today's model (done on the scratch branch).**
   - `DeckHandHandshakeTrustProvider` returns `.trusted` only when the peer proved its identity key: `isIdentityAuthenticated`, and the key ID matches the public key. Otherwise it returns `.denied`.
   - Allow/Deny still gates everything, because `ControlReceiver` only observes handles that `DeviceAuthorizationManager` authorized.
   - This is exactly today's security model. It touches no Loom code, needs nothing on iOS, and is about half a day with a test.
2. **Approve inside the handshake.** The provider would suspend until the user answers. That needs the handshake timeout raised to ≥45 s on both ends, which means a product-agnostic `handshakeTimeout` knob added to `LoomContainerConfiguration`. It gains little until trust is persisted. Revisit when persistent pairing (Sill item S4) lands.

### 3.4 Wire protocol v2 → v3

- **Hard break:** Loom's hello validation requires an equal `protocolVersion`, so a v2 and a v3 build cannot form a session **[read]**. Deck Hand's `hostFeatures` runs inside the encrypted session, so it cannot negotiate this, as October said.
- **What October missed:** both forks already put `protocolVersion` in the Bonjour TXT record and surface it as `LoomPeer.advertisement.protocolVersion` **[read]**.
  - So **a new remote can see an old Mac before dialling** and show "Update Deck Hand on your Mac".
  - An old remote that finds a new Mac fails generically, because it is old code. The App Store and Sparkle make that window short.
- **Version tag to add (app layer, not Loom):**
  - Advertise `deckhand-proto=1` via `LoomContainerConfiguration(advertisementMetadata:)` and gate the picker on both that and `advertisement.protocolVersion == Loom.protocolVersion`.
  - Have the Mac send a `hostFeatures`-style app version on connect.
  - Future `ControlMessage` breaks then get the same friendly path.
- Because Mac and iPad ship together before launch, **taking the v3 break now costs nothing**. Taking it after launch strands every user whose two devices update on different days.

### 3.5 Other merge risks

| Risk | Detail | Verified? |
| --- | --- | --- |
| Larger dependency surface | Core `Loom` now links swift-crypto (pinned `exact: 4.5.1`), NIO and NIOSSH, so the iOS binary will grow. The `exact` pin can collide with other packages later. | **[read]** |
| visionOS floor 26 | Irrelevant to the apps. | **[read]** |
| `retryPolicy` and `messageRateLimitPolicy` | These are fork additions to `LoomContainerConfiguration`. They auto-merged next to upstream's `trustProvider` and `trust` parameters. | **[mac]** |
| Fork LoomKit additions on upstream internals | `LoomConnectionHealth`, `LoomRetryPolicy`, `LoomRateLimiter`, `LoomDiagnosticsView`, and +354 lines in `LoomStore`. They compiled in October's merge but should be re-run. | **[mac]** |
| AWDL | Upstream 2.x *prefers* AWDL / proximity paths when peer-to-peer is enabled. Set `enablePeerToPeer: false` in the same change (§4, S1). | **[read]** |

### 3.6 Commands for the Mac session

Run these on Xcode 27 / Swift 6.4, the toolchain `AppleOS27-Support.md` verified. Run them locally, not in CI: the free-plan macOS minutes won't cover the iteration.

```bash
git fetch origin scratch/trial-merge-loom-2.2.16
git switch scratch/trial-merge-loom-2.2.16

# 1. Package
swift package resolve            # expect swift-nio-ssh ≥ 0.14.1
swift build
swift test --scratch-path .build-local 2>&1 | tee /tmp/loom-merge-test.log
#    If it hangs, re-run with:  --skip liveSamePeerConnectionOutsideWindowIsDropped
#    Specifically confirm:      --filter invalidResumeOffsetIsRejected   (expected to pass now)
#                               --filter LoomAsyncBroadcasterReplayTests
#                               --filter LoomTransferEngineTests

# 2. Apps
cd DeckHand && xcodegen generate
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandMac   -destination 'platform=macOS' build
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandiOS   -destination 'generic/platform=iOS Simulator' build
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandTests -destination 'platform=macOS' test
```

Then do a manual check on hardware with two fresh installs:

1. **First-time pairing:** the iPad sees the Mac, the Mac shows Allow/Deny, and Allow connects.
2. Deny refuses.
3. A 45 s timeout expires the request.
4. Relaunching the Mac prompts again.
5. Shortcut receipts turn mint.
6. The mirror runs.
7. Pair a `main` build against a merge build and confirm they refuse each other. That proves the v3 break, so the "please update" path can be built.

If anything fails, the files to look at first are `LoomAsyncBroadcaster.swift`, `LoomTransferEngine.swift` around `acceptIncomingTransfer`, and `LoomSessionProtocol.swift` conformers.

---

## 4. Sill: what to adopt, ranked

Value ÷ effort, for a pre-launch Deck Hand.

| # | Item | Value | Effort (days) | Risk | Private API | Needs Loom merge? |
| --- | --- | --- | --- | --- | --- | --- |
| S1 | **AWDL off by default + Wi-Fi keep-alive "tick"** | High | 0.5–1 | Low | none | No |
| S2 | **Sparkle + notarized DMG release script** (Sill's `release.sh` / `make-dmg.sh` as reference; not its 6k-LOC custom updater) | High (launch blocker) | 3–3.5 | Low | none | No |
| S3 | **Local cursor**: `showsCursor = false`, shape via `NSCursor.currentSystem`, sprite on iPad | High | 2–3 | Low | none | No |
| S4 | **Persistent pairing**: trust list keyed on the Loom identity key, Damm-check code / QR, 5-min single-device window, revoke UI | High | 4–5 | Medium (security) | none | No (uses Loom trust hooks; easier after the merge) |
| S5 | **HEVC pipeline**: VTCompressionSession + newest-frame mailbox + keyframe on request + delta-drop backpressure + binary framing on a dedicated `openStream("mirror")`, decoded into `AVSampleBufferDisplayLayer` | Very high | 8–12 MVP; 13–17 with software fallback, watchdog and slow-state handling | Medium | none | No (helps) |
| S6 | **Stats line + client stats HUD** (build with S5) | High with S5 | 1–1.5 | None | none | No |
| S7 | **Symbolic hot keys**: read the user's real Mission Control bindings and post `CGEvent` chords, replacing `osascript` | Medium–high | 1–1.5 | Low–medium | **Mac:** `CGSGetSymbolicHotKeyValue`, `CGSIsSymbolicHotKeyEnabled` (SkyLight via `dlsym`) | No |
| S8 | **Display wake** (public IOPM) + **locked-Mac input gate** | Medium–high | 1 (wake) + 2–3 (gate) | Low–medium | **Mac**, gate only: undocumented `CGSSession*` keys / notify name | No |
| S9 | **AX menu-read hardening**: per-element `AXUIElementSetMessagingTimeout`, item caps, off-main queue, for `MenuShortcutDiscovery` | Medium | 1 | Low | none | No |
| S10 | **Clipboard text sync**, with `UIPasteControl` on iOS (no paste prompts; App Store-safe) | Medium | 2–3 | Low | none | No |
| S11 | **Gestures**: 4-finger, pinch, toggle-back (pairs with S7) | Medium | 2–3 | Low | Mac via S7 | No |
| S12 | Pencil hover pointer (`UIHoverGestureRecognizer`) | Low–medium | 1 | Low | none | No |
| S13 | Link judge + USB-cable "Wired" detection (IOKit CDC-NCM ancestry) | Medium | 3.5 | Low–medium | none (public IOKit) | No; may need Loom to expose the scoped remote endpoint |
| S14 | Single-window streaming (Deck Hand already has the window picker) | Medium | 1–5 | Low | none | No |
| S15 | Remote access over VPN / Tailscale (pinned keys, "away" quality) | Medium, later | 5–8 | Medium | none | Helps; belongs in Loom's remote layer and needs S4 |
| S16 | Virtual display (`CGVirtualDisplay*`) | Low–medium | 4–6 | **High** | **Mac**: CoreGraphics SPI | No |
| S17 | Audio | Low for a remote | 6–10 | Medium–high | none | Helps |
| — | iPhone portrait layout | Low; Deck Hand's grid UI is different | n/a | — | none | — |

S1 details:

- Sill measured AWDL taking the radio off-channel for up to ~97 ms every 524 ms: p90 48–67 ms versus ~4 ms with it off (`docs/direct-wireless-plan.md`, `docs/DEVELOPMENT.md:2442`).
- Pass `enablePeerToPeer: false` in both apps.
- Send a tiny tick so the iPad radio doesn't doze; Sill saw a 5→300 ms RTT sawtooth without one. Deck Hand's 2 s ping is too sparse.

**Private API on the Mac.** The Mac app ships outside the Mac App Store, so App Store guideline 2.5.1 doesn't apply to it.

- **S7: adopt.** It is small, falls back to default bindings if the symbols vanish, and removes an Automation prompt.
- **S8's lock gate: adopt with a public-API fallback.**
- **S16: defer.** It is only worth it with single-window streaming, and it is the most likely to break on a macOS update.
- None of these touch the iOS app, which stays public-API only.

**License (Apache-2.0).** Sill has a LICENSE ("Copyright 2026 Noah Saffer"), **no NOTICE file**, and no per-file headers. It has no third-party dependencies.

If code is adapted rather than re-implemented:

- ship a copy of Sill's LICENSE, for example `ThirdPartyLicenses/Sill-LICENSE.txt`, and include it in both apps' acknowledgements;
- keep the copyright line;
- put a "Modified from Sill (Apache-2.0) by Deck Hand" note at the top of each adapted file.

There is no NOTICE text to carry over. Apache-2.0 is compatible with a paid App Store app and with Deck Hand's MIT-licensed Loom fork. Don't put Sill-derived code in the Loom targets: it isn't product-agnostic, and it would mix licenses inside the MIT package.

---

## 5. Options

Every option starts with the same day-one items, which are each under a day:

- the nio-ssh floor on `main`;
- merging `affectionate-euler`, which carries the LoomHost blocking-IO fix and the CI trims;
- the `happy-lovelace` CI change;
- S1 (AWDL off and the tick).

### Option A: merge Loom now, ship HEVC in 1.0

| Week | Work |
| --- | --- |
| 1 | Loom merge on the Mac (§3.6), trust provider, app version tag / "please update", S2 (Sparkle + DMG) |
| 2–4 | S5 + S6 (HEVC, MVP with software fallback), S3 local cursor |
| 5 | S7, S9, hardening, TestFlight, notarized beta |

- **1.0 in about 5 weeks.**
- **Pro:** launches with a mirror at Sill's level.
- **Con:** the longest path. The riskiest component lands last, and the launch date depends on VideoToolbox edge cases.

### Option B: ship 1.0 on the current fork, merge after

| Week | Work |
| --- | --- |
| 1 | Day-one items, S2, S3, S7, S9, version tag |
| 2 | Beta, ship 1.0 |
| later | Loom merge in 1.1 or later |

- **1.0 in about 2 weeks.**
- **Pro:** fastest.
- **Con:** the v3 break lands **after launch**. Every paying user then needs both apps updated together, and an iPad that updates before its Mac can't connect. It also keeps a 7-month-old Loom with known transfer and threading bugs.
- **Not recommended.** The owner's decision only accepts a break *before* launch.

### Option C (recommended): merge Loom now, cheap wins in 1.0, HEVC in 1.1

| Week | Work |
| --- | --- |
| 1 | Day-one items. Loom merge validated on the Mac (§3.6); fix whatever the Mac build finds. Trust provider (done) plus version tag and "please update" in the picker. S2 Sparkle + notarized DMG. |
| 2 | S3 local cursor. Move JPEG frames off the input stream onto a dedicated `openStream("mirror")` with binary payloads (no base64/JSON), offered through `hostFeatures`. S7 symbolic hot keys. S9 AX hardening. S8 display wake. |
| 3 | Beta on TestFlight and a notarized DMG, then **ship 1.0** (both apps together, Loom v3). |
| 4–6 | **1.1:** S5 + S6 HEVC behind a `hostFeatures(videoCodecs:)` capability, keeping JPEG as the fallback. This is additive, with no protocol break. Then S4 persistent pairing and S10 clipboard. |
| later | S13, S11, S12, S14; S15 remote access once S4 is in. |

- **1.0 in about 3 weeks**, with the one protocol break taken while nobody depends on it.
- The mirror improves at once: no base64, no head-of-line blocking of input behind frames, the local cursor, and no AWDL stalls.
- The biggest feature arrives two to three weeks after launch through the update channels the launch sets up (Sparkle and the App Store).
- Persistent pairing (S4) can move into 1.0 if per-launch Allow/Deny is judged too much friction for a paid app. It adds about 4–5 days.

**CI budget.** About 200 macOS minutes a month is roughly 13 runs of the current 15-minute job.

- Run §3.6 and all HEVC tuning on the owner's Mac.
- Keep CI to PRs that touch `Sources/`, `Tests/` or `Package.*`, as the pending branch does.
- Don't adopt Sill's mutation matrix in CI. It takes hours of macOS time; run it locally before releases.

---

## 6. Decisions for the owner

1. **Pick an option.** Recommended: **C**.
2. **Persistent pairing in 1.0 or 1.1?** The scratch branch keeps per-launch Allow/Deny.
3. **AWDL off by default?** Recommended: yes, with an opt-in "Direct Wireless" toggle later.
4. **Mac private API.** Approve S7 (symbolic hot keys) and S8's lock-gate keys; defer S16 (virtual display).
5. **Merge the two pending branches** (`affectionate-euler`, `happy-lovelace`) and the nio-ssh bump on `main` now?
6. **Updater.** Sparkle, as planned, rather than Sill's custom Ed25519/GitHub updater.
7. **Adapt or re-implement Sill code?** Re-implementing from Sill's docs avoids the per-file attribution. Adapting is faster for the pure parts: the pairing code and window, the encoder mailbox, and the AX menu limits.
