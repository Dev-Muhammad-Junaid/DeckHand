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
