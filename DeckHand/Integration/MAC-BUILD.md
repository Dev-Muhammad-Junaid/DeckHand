# Mac build, test and install — instructions for the Mac session

Cloud sessions write code but can't compile Xcode projects; the owner's Mac
is the build and verification gate. The owner has given full permission to
run commands on the Mac.

## Setup
1. `git fetch origin claude/pixelhand-integration` (head `291924a` or later).
   Work in a separate clean worktree on that branch. Leave other working
   copies (`~/Developer/DeckHand-build`, `~/Developer/DeckHand-review`) alone.
2. Read `DeckHand/Integration/STATUS.md`, `DeckHand/Integration/M0-FIXES.md`,
   `DeckHand/AppStore/MacBuildChecklist.md`,
   `DeckHand/AppStore/AppStoreConnectStatus.md`,
   `DeckHand/Release/RELEASING.md` §5 and
   `DeckHand/MenuBarStatusItems-macOS26.md`.

## What's on the branch (none of it compiled yet)
- Upstream Loom 2.2.16 merge with `DeckHandHandshakeTrustProvider` (keeps the
  Mac's Allow/Deny prompt), swift-nio-ssh ≥ 0.14.1, LoomHost thread-blocking
  fix.
- Rename to Pixel Hand: `com.widgetsflow.pixelhand` (iOS),
  `com.widgetsflow.pixelhand.mac`, container
  `iCloud.com.widgetsflow.pixelhand`, Bonjour `_pixelhand._tcp`. All
  registered in the developer portal, container assigned to both IDs.
- Sentry (`SENTRY_DSN` build setting, may be empty), privacy manifests, iPad
  `try!` fix, "Please update" protocol check.
- M0 fixes: remote-input validation (scroll crash), Show Desktop, Launchpad,
  duplicate-bundle-ID crash, mirror start race, pre-approval input gate.
- Sparkle 2 in the Mac app (inert while `SPARKLE_PUBLIC_ED_KEY` is empty;
  feed `https://pixelhand.app/mac/appcast.xml`).
- Website and support page for pixelhand.app.
- Two previously skipped Loom tests un-skipped.

## Build and test
1. Check Xcode → Settings → Accounts signs in for team `DD5AWPLT2V`
   (Mega Creations LLC).
2. `xcodegen generate` in `DeckHand/`; build the Mac app and the iOS app.
3. Fix compile errors with minimal, behaviour-preserving changes. Likely
   spots: the Loom merge, `DeckHandDiagnostics` (Sentry, Swift 6),
   `AppUpdater`, `PeerCompatibility`, and the Sendable notes at the end of
   `M0-FIXES.md`. One commit per fix; pull first; push to
   `claude/pixelhand-integration`.
4. `swift test --scratch-path .build-local` at the repo root with no
   `--skip`, then the app test target. Report counts; for any failure or hang
   say whether it's new or pre-existing, and fix it if the cause is clear.
5. Check whether the iOS Simulator boots now (earlier, CoreSimulator was too
   old for Xcode). If it does, do a first end-to-end pass against the Mac
   host on this machine.

## Install
Never use ⌘R in Xcode and never run the Mac executable directly: on
macOS 26+ that permanently breaks the menu-bar item.
- Mac: signed build, launch with `open "…/Pixel Hand.app"`. Ask the owner
  before moving the old `/Applications/Deck Hand.app` aside.
- iPad: `xcrun devicectl list devices`, build with
  `-allowProvisioningUpdates`, `xcrun devicectl device install app`, launch.
  Ask before removing the old Deck Hand app.
- New bundle IDs mean permissions must be granted again: Accessibility,
  Screen Recording, Automation, Notifications, Local Network; on iPad Local
  Network and Photos. Guide the owner.

## End-to-end check with the owner
You can't see the screens: ask the owner to confirm each item and record
pass / fail / not tested.
- Discovery; Allow/Deny prompt (Deny, 45 s timeout, prompt again after
  relaunch); taps made before approval are dropped.
- Trackpad, keyboard, scroll (including a fast flick), media keys.
- Show Desktop and Launchpad.
- Shortcut chips from real menus, dialog-button chips, delivery-receipt dots.
- Mirror, including two remotes at once.
- Region capture, OCR, annotation.
- Multi-display switching and Spaces.
- Menu-bar dot-hand icon; "Check for Updates…" (inert without a key is fine).
- Light and dark mode; iPhone and iPad layouts in both orientations.
- Sentry toggle.

## Report
Append a dated "Mac build results" section to
`DeckHand/Integration/STATUS.md`: build status, test counts, fixes pushed,
end-to-end results, open bugs. Push, then give the owner a short summary.
The coordinating cloud session ("Deckhand project status review") reads that
section and routes bugs to cloud fix sessions.

## One build worktree (owner request, 2026-11-24: Mac storage)

All editing happens in cloud sessions; the Mac only builds and installs, so
it needs exactly **one** worktree. Every Mac build session and loop uses:

    ~/Developer/DeckHand-build/.claude/worktrees/pixelhand-build

- If it exists, reuse it: `git -C <it> fetch origin claude/pixelhand-integration && git -C <it> checkout -B pixelhand-build FETCH_HEAD`.
- If it doesn't, create it once:
  `git -C ~/Developer/DeckHand-build worktree add ~/Developer/DeckHand-build/.claude/worktrees/pixelhand-build origin/claude/pixelhand-integration`.
- Don't create other worktrees for builds. If a session was started in its
  own worktree, `cd` to the one above for the build.
- Build with `-derivedDataPath ~/Developer/DeckHand-build/.derived` so all
  builds share one DerivedData folder instead of one per worktree.
- Keep at most one previous app copy for comparison; delete older ones.

## Build loop (run with `/loop 1h …` in the Mac build session)

Every tick:

1. `git fetch origin claude/pixelhand-integration`, then read the last line of
   `DeckHand/Integration/STATUS.md` on that branch.
2. If it isn't `Status: READY FOR MAC BUILD (build N)`, or that commit is
   already built, reply "no new build" and stop.
3. Otherwise check out the head in your clean worktree, then:
   - `xcodegen generate`, then build both apps;
   - fix compile errors minimally (one commit each, pull first);
   - run `swift test --scratch-path .build-local` with nothing skipped, the
     PixelHandCore tests if `DeckHand/Core` exists, and `DeckHandTests`;
   - install signed builds (Mac via `open`, iPad via `xcrun devicectl` if
     unlocked);
   - run the checks the "Build N queued" section asks for that you can do
     yourself or from the simulator, and list hands-on checks for the owner
     without blocking.
4. Append "Mac build results (build N)" to `STATUS.md`: build, test counts,
   fixes pushed, checks, open bugs. Set the last line to
   `Status: BUILT (build N) — green` or `— N bugs`, and push.

Never commit the apps' pins into the repo-root `Package.resolved`.
