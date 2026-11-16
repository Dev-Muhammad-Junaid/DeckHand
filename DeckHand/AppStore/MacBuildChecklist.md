# Mac build session checklist (branch `claude/app-store-prep`)

None of this branch has been compiled: it was written in a Linux container with
no Xcode. Expect to fix small compile errors, most likely in
`Shared/DeckHandDiagnostics.swift` (new Sentry code under Swift 6).

## 0. Before building

- [ ] Xcode → Settings → **Accounts**: the Mega Creations LLC team signs in
      without errors. (This was the blocker in `AppleOS27-Support.md`.)
- [ ] Portal steps 1–3 in `AppStoreConnectSetup.md` are done (container and
      both bundle IDs, with the container assigned). If they aren't, automatic
      signing will try to register the IDs itself on the first build.
- [ ] Optional, for crash reports: DSNs pasted into `project.yml`
      (`AppStore/Sentry.md`). With them empty everything builds and reporting
      is just off.

## 1. Pull and generate

```bash
git fetch origin claude/app-store-prep
git checkout claude/app-store-prep
cd DeckHand
xcodegen generate          # first build also downloads sentry-cocoa 9.34+
open DeckHand.xcodeproj
```

## 2. Build

```bash
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandTests -destination 'platform=macOS' test
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandMac -destination 'platform=macOS' -allowProvisioningUpdates build
xcodebuild -project DeckHand.xcodeproj -scheme DeckHandiOS -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

- [ ] 12/12 contract tests pass.
- [ ] Both apps build with no new warnings from Deck Hand's own sources.
- [ ] Signing shows profiles for `com.widgetsflow.deckhand.mac` and
      `com.widgetsflow.deckhand` with the iCloud container
      `iCloud.com.widgetsflow.deckhand`.

## 3. Install. Read this first for the Mac

The new Mac bundle ID is clean. Keep it that way
(`MenuBarStatusItems-macOS26.md`):

- [ ] In Xcode, DeckHandMac scheme → Run → Info → Launch: **"Wait for the
      executable to be launched"** *before* the first ⌘R.
- [ ] Launch it with `open` or from Finder, never by running the executable.

Then:

- [ ] Quit and delete the **old** Mac app (`com.deckhand.mac`) and the **old**
      iPad/iPhone app. The new IDs install *beside* the old ones, so otherwise
      you'll have two "Deck Hand" icons and two menu-bar items.
- [ ] Install the new iOS app on the iPad (Xcode Run, or Devices window).

## 4. Permissions to grant again (new Mac bundle ID = new identity to macOS)

On the Mac, System Settings → Privacy & Security:

- [ ] **Accessibility**: remove the old "Deck Hand" entry (`−`), then grant
      the new one from the menu-bar panel's **Fix…**.
- [ ] **Screen & System Audio Recording**: same, remove old, grant new.
- [ ] **Automation**: approve Deck Hand → System Events the first time
      Mission Control / App Exposé is used.
- [ ] **Notifications**: allow when asked (connection approval alerts).
- [ ] **Local Network** (macOS 15+): allow when asked.

On the iPad:

- [ ] **Local Network**: allow on first launch.
- [ ] **Photos**: allow on first save.

Expected resets, all from the new bundle ID: settings back to defaults, the
welcome tour shows again, hidden and pinned apps are gone, and each device has
a new Loom identity, so the Mac asks to approve the iPad again.

## 5. Verify the app

- [ ] iPad finds the Mac; approving on the Mac connects.
- [ ] Trackpad, scrolling, mirror pinch, a capture and shortcut chips work.
- [ ] Both devices on the same iCloud account: the Mac shows a **My Mac** badge
      on the iPad (CloudKit with the new container). If not, check that the
      container exists and is assigned to both IDs.
- [ ] iPad **Settings → Privacy → Share crash reports** is there, on by
      default.
- [ ] Mac menu-bar panel footer has a **Share crash reports** checkbox, ticked,
      and the panel layout still fits at 270 pt.
- [ ] Settings → Connection still says "Recognize my own devices — Not
      available" even though CloudKit is on. That copy predates this branch;
      decide whether to update it before release.

## 6. Verify Sentry (only if DSNs are filled in)

Follow "Checking it works" in `Sentry.md`. In short:

- [ ] Force one crash per app *without the debugger attached*, relaunch, and
      see it in `deckhand-ios` / `deckhand-mac` under environment
      `development`.
- [ ] The event shows device model and OS, **no device name**, User with only
      an `id`, **no attachments**.
- [ ] Turn the switch off, crash again: nothing arrives.
- [ ] Remove the test crash button.
- [ ] After a **Release** archive with `sentry-cli` logged in, Sentry →
      Project Settings → Debug Files lists the dSYMs.

## 7. Store checks

- [ ] Product → Archive (DeckHandiOS). In Organizer, right-click the archive →
      **Generate Privacy Report**: it should list Crash Data, Performance Data
      and Other Diagnostic Data, all not linked and not tracking, plus
      Sentry's own manifest.
- [ ] Upload to App Store Connect (needs the app record). App Store Connect
      should **not** ask export-compliance questions, because of
      `ITSAppUsesNonExemptEncryption = NO`. If it does, answer per
      `ExportCompliance.md`.
- [ ] Archive DeckHandMac → Distribute → **Developer ID** → Upload (notarize).
      Check `spctl -a -vv "Deck Hand.app"` says "Notarized Developer ID".
