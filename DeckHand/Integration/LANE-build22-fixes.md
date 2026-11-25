# Lane: build 22 fixes

Branch `claude/pixelhand-lane-build22-fixes`, from `claude/pixelhand-integration`
at `7c7bf58`. It fixes the 3 bugs in "Mac build results (build 22)" in
`STATUS.md`.

| ID | Status | Note | Files |
|---|---|---|---|
| Bug 1: Try again during a slow first start (P2) | Fixed | Starts are single-flight on both sides. Try again joins a start in flight, or refreshes discovery once running. Loom now advertises and browses before the CloudKit account check. | Core `Network/NetworkStartGate.swift`, `ContentRootView.swift`, `PeerPickerView.swift`, Loom `LoomStore.swift`, `LoomContext.swift` (doc), `AdoptLoomKitInSwiftUI.md`, `Tests/LoomKitTests/LoomStoreStartTests.swift` |
| Bug 2: AX3 Mac pill cuts the name (P2, VQ-065) | Fixed (needs a Mac re-check) | The name always gets two lines at AX3. Tail candidates such as "Muhammad’s / MacBook…" are tried before the fallback. In the fallback, the first word shrinks (to 70 %) before it truncates. The header now always takes its full height. | Core `Design/ShellChromePlan.swift` (`pillNameLayout`), `DesignSystem/MacPill.swift`, `Shell/ShellHeader.swift` (one modifier) |
| Bug 3: AX3 lock banner overflows into the header (P2) | Fixed (needs a Mac re-check) | At the Large and Huge bands, and in narrow windows, the Keyboard button moves under the message, so the message gets the full width and breaks at words. The banner takes its full height (`fixedSize` vertical), so it grows downward and can't ride up over the header. | Core `Design/ShellChromePlan.swift` (`StatusBannerPlan`), `DesignSystem/Feedback.swift` (`StatusPill`) |
| `PixelHandUITests.swift` structure | Checked | Every `func` is closed and the class brace balances (brace-depth scan, final depth 0). | `PixelHandUITests/PixelHandUITests.swift` |

## Bug 1 in detail

**Cause.**
- `ContentRootView` ran the start in `.task(id: loomStartAttempt)`. Try again bumped the id, which cancelled attempt 1 mid-start (`CancellationError`) and began attempt 2 beside it.
- Inside Loom, `LoomStore.start()` is an actor method that awaits. Attempt 2 got in while attempt 1 waited about 45 s on `CKContainer.accountStatus()`, and failed with "Already advertising service". Attempt 1's failure path then called `stop()`, which tore everything down.
- Advertising and browsing only began after that CloudKit check.

**App side.**
- Core `NetworkStartGate`: `idle → starting(n) → running | failed`.
  - `request()` returns `.start(n)` from idle or failed, `.join(n)` while starting, and `.refresh` once running.
  - `finished(attempt:error:)` ignores stale or duplicate results.
- `ContentRootView.requestLoomStart()` runs the start in its own `Task`, so nothing cancels it. Launch (`.task`) and both Try again buttons go through it.
- The picker's 10 s timer for the "Can’t find your Mac?" card restarts after Try again (`checksRound`), so the card comes back if there is still no Mac.

**Loom side (product-agnostic).**
- `LoomStore.start()` is single-flight. Callers join a stored start task, so cancelling one caller doesn't cancel the start.
- `cloudKitManager.initialize()` and `peerManager.setup()` now run after advertising, discovery and the overlay directory start, right before the cloud peer refresh and publish. `LoomContext.start()` itself still returns only after the CloudKit step.
- I updated the DocC for `LoomContext/start()` and the "Adopt LoomKit in SwiftUI" article.
- The new Loom tests (Swift Testing, `LoomStoreStartTests`) cover:
  - 4 concurrent starts all succeed;
  - a cancelled first caller doesn't fail a later one;
  - start, stop, then start again.

**Core tests** (`NetworkStartGateTests`, 8 tests): the build 22 sequence, refresh once running, failure then retry, stale results, idle, and stop. A sweep over every 6-event sequence checks that there are never two starts in flight.

## Linux results

- `swift test --package-path DeckHand/Core`: **1031 / 1031 pass** (183 suites). It was 1018 before, so 13 tests are new.
- `DeckHand/Scripts/linux-typecheck/run.sh`: **Build complete**, no errors. No file was added to its list; the changed app files are SwiftUI.
- Loom (`swift test --scratch-path .build-local`) **can't run on Linux**. Please run it on the Mac, including the new `LoomKit Store Start` suite.

## Re-check steps

**On the Mac (iPhone 17 Pro simulator and Mac):**
1. **Bug 1.** Fresh iPad mini simulator, no iCloud account, Mac app open.
   - Launch, wait for "Can’t find your Mac?", tap **Try again** (twice if the card returns).
   - The Mac should be listed well before the 45 s check ends. The log should show "Try again: LoomContext start (attempt 1) is still running" and no "Already advertising service".
   - Or run `test17_TryAgainDuringSlowStart`: it captures `mac-listed`, or `stuck-searching` on failure.
2. **Bug 2.** iPhone 17 Pro at AX3, Mac named "Muhammad’s MacBook Pro".
   - The pill should read "Muhammad’s" / "MacBook Pro", or "Muhammad’s" / "MacBook…".
   - It should never read one line, never cut mid-word, and never show a hyphen.
   - Also check AX5, where the first word may shrink.
3. **Bug 3.** iPhone 17 Pro at AX3 with the Mac locked (`test04` at AX3, capture `01-pointer`).
   - The banner sits under the header with Keyboard on its own row, and the message breaks only between words.
   - `test04` now captures `lock-banner`, and `banner-overlaps-header` if the banner's top is above the pill's bottom.
4. Run the new Loom suite and the full Loom suite.

**On the iPad Pro 11" simulator:**
- Portrait and landscape at Standard: the lock banner still has Keyboard on the same row, and the pill shows one line.
- At AX3: the banner is stacked and the pill has two lines.
- Stage Manager window dragged down to iPhone width, Standard size:
  - The banner stacks once the message would be narrower than 160 pt.
  - The header and banner never overlap.
- The picker's Try again works the same on iPad.

## PixelHandUITests changes

- `test04_ConnectAndPointer` calls the new `checkBannerBelowHeader()` after the first capture. It does nothing unless the Mac is locked.
- New `test17_TryAgainDuringSlowStart`.
- New ID `ph.status.<kind>` (`ph.status.locked`, `ph.status.warning`, `ph.status.info`) on `StatusPill`.
- All existing `ph.<area>.<name>` IDs are unchanged.

## Compile risks (most likely first)

1. `MacPill.nameText`: `ViewThatFits` holding a `ForEach` plus one more child (the fallback), and `.minimumScaleFactor(CGFloat(...))` on each line.
2. `ContentRootView.requestLoomStart()`:
   - `withAnimation { startGate.request() }` returns a value, and `_ = withAnimation { startGate.finished(...) }`;
   - the `@State` struct is mutated from a `Task { @MainActor in }` inside a `View` method;
   - I added `import PixelHandCore`.
3. `LoomStore`:
   - `startTask: Task<Void, Error>?` stored on the actor;
   - the `Task { try await self.performStart() }` inherits the actor;
   - a `defer` clears it after the await.
4. `StatusPill`: `onGeometryChange` with an optional `CGFloat` state; `.fixedSize()` on the `Button`; `HStack(alignment: .top)`.
5. `LoomStoreStartTests`: `LoomNetworkConfiguration(serviceType:enablePeerToPeer:enabledDirectTransports:)` uses defaults for the other parameters.

## Behaviour notes

- While Loom's CloudKit step is still running at start, a hello sent to a Mac carries no iCloud user ID yet. Same-account auto-allow then falls back to the normal Allow prompt for that one connection. With iCloud signed in the check usually takes milliseconds.
- `StatusPill` stacks at the Large band too, wherever it has a fix button. That covers every `StatusPill` with a fix button, not only the lock banner.

## Out-of-lane edits

- `DeckHandiOS/ContentRootView.swift`: it owns the start task, so it is part of the start path.
- `DeckHandiOS/Shell/ShellHeader.swift`: one modifier, `.fixedSize(horizontal: false, vertical: true)`, so the header keeps its full height.
- Loom (`Sources/LoomKit`, `Tests/LoomKitTests`): the brief allows this when needed. It is product-agnostic, with no product names in code, comments, tests or commit messages.

Lane: READY TO MERGE
