# Releasing Pixel Hand for Mac

The Mac app is a **free download from the website**. It is signed with
Developer ID, notarized by Apple, and updates itself with **Sparkle 2**. It is
not on the Mac App Store. The paid product is the iPhone/iPad app on the App
Store; both apps carry the same version number and ship together.

```
project.yml ──► archive.sh ──► notarize.sh app ──► make-dmg.sh ──► notarize.sh dmg
   (version)     (Developer ID     (zip → notary,       (DMG + Applications   (notary, staple,
                  export)           staple the .app)      link, signed)         Gatekeeper check)
                                                                                    │
website ◄── git push ◄── publish.sh ◄── update-appcast.sh ◄── sign-update.sh ◄──────┘
(Pages: appcast,          (DMG → R2,      (website/public/       (Sparkle EdDSA
 /download/mac)            _redirects)     mac/appcast.xml)        signature)
```

`DeckHand/Scripts/release/release.sh` runs everything from `archive.sh` to
`update-appcast.sh`. `publish.sh` is separate, so you can test the DMG before
anyone else sees it.

> **Status:** written in a Linux container with no Xcode. None of the
> scripts, the Sparkle code or the workflow has been run yet. Everything
> marked **[Mac-verify]** needs checking on the first real release; §5 is the
> list.

| Thing | Value |
| --- | --- |
| Bundle ID | `com.widgetsflow.pixelhand.mac` |
| Team | `DD5AWPLT2V` (Mega Creations LLC) |
| Scheme | `DeckHandMac`, product `Pixel Hand.app` |
| Appcast | `website/public/mac/appcast.xml` → `SPARKLE_FEED_URL` in `project.yml` |
| DMGs | Cloudflare R2 bucket `pixelhand-downloads`, key `mac/PixelHand-<version>.dmg` |
| Download link | `/download/mac` on the website, a redirect kept in `website/public/_redirects` |
| Settings | `DeckHand/Scripts/release/config.sh` (every value can be overridden from the environment) |

---

## 1. One-time setup

Do these once, on the Mac you release from. Steps 1.1–1.3 are about 20
minutes; the Cloudflare part depends on whether the domain is on Cloudflare
yet.

### 1.0 Tools

```bash
xcode-select -p                   # Xcode 26+ selected
brew install xcodegen create-dmg node
```

`create-dmg` is optional: without it `make-dmg.sh` uses plain `hdiutil` (no
window layout). `node` provides `npx wrangler` for the R2 upload.

### 1.1 Developer ID Application certificate

Only the **Account Holder** of the Apple Developer team can create one.

1. Xcode → **Settings → Accounts** → select the team → **Manage
   Certificates…** → **+** → **Developer ID Application**.
   (Or developer.apple.com → Certificates → **+** → Developer ID Application,
   G2 Sub-CA, with a CSR from Keychain Access.)
2. Check it's in the login keychain:
   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   # → "Developer ID Application: Mega Creations LLC (DD5AWPLT2V)"
   ```
   If the name differs, set `DEVELOPER_ID_IDENTITY` in `config.sh`.
3. **Back it up**: Keychain Access → the certificate with its private key →
   Export → `.p12` with a strong password, kept in your password manager.
   Apple allows only a few Developer ID certificates; losing the key means
   revoking it, which breaks nothing already notarized but is a hassle.

**Provisioning profile.** The Mac app uses iCloud (CloudKit) and a keychain
access group, so the Developer ID build needs a *Developer ID* provisioning
profile for `com.widgetsflow.pixelhand.mac` with the iCloud capability.
`archive.sh` passes `-allowProvisioningUpdates`, so Xcode creates it on the
first export. **[Mac-verify]** If the export fails with a profile error,
create it by hand: developer.apple.com → Profiles → **+** → *Developer ID*
→ App ID `com.widgetsflow.pixelhand.mac` → the Developer ID certificate. Also
make sure the CloudKit container `iCloud.com.widgetsflow.pixelhand` is in
the **Production** environment schema before release (CloudKit Console →
Deploy Schema Changes), because Developer ID builds use production.

### 1.2 notarytool keychain profile

The scripts call `xcrun notarytool … --keychain-profile pixelhand-notary`.
Store the credentials once; they live in your login keychain, never in a
file in the repository.

**Option A: Apple ID + app-specific password** (simplest)

1. appleid.apple.com → Sign-In and Security → **App-Specific Passwords** →
   generate one named "notarytool".
2. ```bash
   xcrun notarytool store-credentials pixelhand-notary \
       --apple-id "<your Apple ID email>" --team-id DD5AWPLT2V
   # paste the app-specific password when asked
   ```

**Option B: App Store Connect API key** (also what CI uses, §4)

1. App Store Connect → **Users and Access → Integrations → App Store Connect
   API** → **Team Keys** → **+**, name "Pixel Hand release", access
   **Developer** for notarization only, or **Admin** if CI should also manage
   signing (§4). Download `AuthKey_<KEYID>.p8` (only once!) and note the
   Key ID and Issuer ID.
2. ```bash
   xcrun notarytool store-credentials pixelhand-notary \
       --key ~/Keys/AuthKey_<KEYID>.p8 --key-id <KEYID> --issuer <ISSUER-UUID>
   ```

Check it: `xcrun notarytool history --keychain-profile pixelhand-notary`.

### 1.3 Sparkle EdDSA keys

Sparkle checks every update against an Ed25519 public key baked into the
app. The private key signs updates and must never be committed.

1. Fetch Sparkle's tools by resolving packages once (any `archive.sh` run
   does this; or just this):
   ```bash
   cd DeckHand && xcodegen generate
   xcodebuild -resolvePackageDependencies -project DeckHand.xcodeproj \
       -clonedSourcePackagesDirPath build/release/SourcePackages
   ls build/release/SourcePackages/artifacts/sparkle/Sparkle/bin
   # generate_appcast  generate_keys  sign_update  BinaryDelta …
   ```
2. Generate the key pair. The private key goes into your login keychain
   (item "Private key for signing Sparkle updates"):
   ```bash
   build/release/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
   # prints: <key>SUPublicEDKey</key><string>BASE64…</string>
   ```
   Running it again later just prints the existing public key (`-p`).
3. Put the public key in `DeckHand/project.yml`, Mac target:
   ```yaml
   SPARKLE_PUBLIC_ED_KEY: "BASE64…"
   ```
   Commit that. It's public by design.
4. **Back up the private key** to your password manager:
   ```bash
   build/release/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/Desktop/sparkle-private-key.txt
   # copy the file's contents into the password manager, then delete the file
   ```
   If the private key is lost, installed copies can never be updated
   automatically again; users would have to download a new build by hand.
   (Sparkle supports key rotation only while you still have the old key.)

Until `SPARKLE_PUBLIC_ED_KEY` is set, the app doesn't start Sparkle at all and
"Check for Updates…" is greyed out (`AppUpdater.isConfigured`), and
`archive.sh` refuses to export.

### 1.4 Cloudflare

The website already deploys from this repository through Cloudflare Pages
(`website/README.md`). Two additions:

**Why R2 for the DMG.** Cloudflare Pages caps a single file at **25 MiB**
(developers.cloudflare.com/pages/platform/limits). The DMG holds Sparkle,
Sentry and the Loom/NIO stack as a universal binary and may well be close to
or above that. More importantly, Pages builds from git, and committing a DMG
per release would bloat the repository forever. So: appcast and release notes
on Pages (small text, versioned in git), DMGs in R2.

1. **R2 bucket.** Dashboard → R2 → **Create bucket** `pixelhand-downloads`
   (location: Automatic).
2. **Public access through a custom domain** (needs the domain's DNS on
   Cloudflare): bucket → Settings → **Custom Domains → Connect Domain** →
   e.g. `downloads.<your-domain>`. Then set in `config.sh`:
   ```bash
   DOWNLOAD_BASE_URL="https://downloads.<your-domain>/mac"
   ```
   (The placeholder `downloads.pixelhand.app` is a guess; nothing is
   registered.) The `r2.dev` public URL also works for testing, but Cloudflare
   rate-limits it and says not to use it in production.
3. **Feed URL.** If the site has a custom domain, change both:
   - `SPARKLE_FEED_URL` in `project.yml` → `https://<your-domain>/mac/appcast.xml`
   - `SITE_BASE_URL` in `config.sh` → `https://<your-domain>`

   The placeholder `https://pixelhand.pages.dev` assumes the Pages project is
   called `pixelhand`; check the real `*.pages.dev` name. **Decide this
   before the first public release**: the feed URL is compiled into every
   copy, and changing it later only reaches users who update through the old
   URL first. (A Pages redirect from the old path keeps working if you must
   move.)
4. **wrangler login** for uploads: `npx wrangler login` (browser), once.
5. Nothing to configure for headers: `website/public/_headers` serves
   `/mac/*` with a 5-minute cache, and the R2 upload sets
   `Cache-Control: immutable` on each DMG (the file name has the version in it,
   so it never changes).

### 1.5 Dry run (recommended)

Before the real 1.0, do §2 once with a throwaway version like `0.9` / build
`1` and run the update test in §3 with `0.9.1` / build `2`. That flushes out
signing, notarization and appcast problems while no one is watching. Delete
the test DMGs from R2 and the test items from `appcast.xml` afterwards (or
keep them on the `beta` channel).

---

## 2. Each release

### 2.1 Version bump (both apps)

```bash
./DeckHand/Scripts/release/bump-version.sh 1.1          # build number +1
git commit -am "Bump version to 1.1 (5)"
```

It sets `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` on every target in
`project.yml`, so the iOS build uploaded to App Store Connect and the Mac
DMG match. **Sparkle compares the build number** (`CFBundleVersion`), so it
must go up every time, betas included; the script refuses to lower it.

### 2.2 Build, notarize, sign

```bash
./DeckHand/Scripts/release/release.sh                 # stable
CHANNEL=beta ./DeckHand/Scripts/release/release.sh    # beta testers only
```

Output in `DeckHand/build/release/<version>-<build>/` (gitignored):

| File | |
| --- | --- |
| `DeckHandMac.xcarchive` | keep it: it has the dSYMs (Sentry also gets them) |
| `export/Pixel Hand.app` | Developer ID–signed, notarized, stapled |
| `PixelHand-<version>.dmg` | signed, notarized, stapled: the download and the Sparkle update |
| `sparkle-signature.txt` | `sparkle:edSignature="…" length="…"` |
| `notary-*.json` | Apple's notarization results |

It stops at the first failure. Re-run the failed step alone:

| Step | Script | Typical failure |
| --- | --- | --- |
| Archive + export | `archive.sh` | Signing/profile (§1.1); `SUPublicEDKey` empty (§1.3) |
| Notarize the app | `notarize.sh app` | Apple's log is printed: usually an unsigned nested binary or a missing hardened runtime |
| DMG | `make-dmg.sh` | `create-dmg` window layout times out without a GUI session (harmless, it falls back) |
| Notarize the DMG | `notarize.sh dmg` | as above |
| Sparkle signature | `sign-update.sh` | keychain key ≠ `SPARKLE_PUBLIC_ED_KEY` in `project.yml` |
| Appcast | `update-appcast.sh` | — |

Why notarize twice: the app is stapled before it goes in the DMG, so a copy
dragged to Applications opens offline; the DMG is stapled so the download
itself passes Gatekeeper.

### 2.3 Release notes

Before `update-appcast.sh` (or re-run it after), write
`website/public/mac/notes/<version>.html` from `notes/_template.html`.
Sparkle shows it in the update window. Without it, the update alert has no
notes (the script warns).

### 2.4 Test the DMG

At least: open the DMG on another Mac (or a fresh user account), drag to
Applications, open. No Gatekeeper warning should appear. For a release that
changes anything about updating, also run §3.

### 2.5 Publish

```bash
./DeckHand/Scripts/release/publish.sh
```

It uploads the DMG to R2, checks the public URL returns the same size, and
(stable only) points `/download/mac` at the new DMG in
`website/public/_redirects`. Then deploy the website:

```bash
git add website/public/mac website/public/_redirects
git commit -m "Release Pixel Hand for Mac 1.1 (5)"
git push        # to the Pages production branch (main)
```

When Pages has deployed (1–2 minutes):

```bash
curl -s https://<site>/mac/appcast.xml | head -20         # new item on top
curl -sI https://<site>/download/mac | grep -i location   # new DMG
```

Installed copies find it on their next scheduled check (Sparkle's default is
once a day) or immediately with **Check for Updates…**.

### 2.6 Same day: the iOS app

The iOS build of the same version goes through App Store Connect as before
(`AppStore/AppStoreConnectSetup.md`). Release the iOS version and push the
appcast together, so a Mac update never asks for an iPhone/iPad version
that isn't out yet (and vice versa). Because the Bonjour protocol check
("Please update Pixel Hand on your …") compares Loom protocol versions,
mismatched app versions only matter when the Loom protocol changes.

### 2.7 If something's wrong after publishing

- **Bad build:** remove its `<item>` from `appcast.xml`, push. Machines that
  already updated stay on it, so publish a fixed build with a *higher* build
  number; Sparkle never downgrades.
- **Wrong signature in the appcast:** Sparkle refuses the update (nothing
  is installed). Re-run `sign-update.sh` and `update-appcast.sh`, push.

---

## 3. Testing an update (older build → newer build)

Do this on the dry run (§1.5) and whenever updating changes: the Sparkle
version, the feed URL, the key, signing or the DMG layout.

1. **Build N.** Release (§2.2) version `0.9`, build `1`, and publish it (§2.5). Install it from the DMG into
   `/Applications`, open it, grant Accessibility and Screen Recording.
2. **Build N+1.** `bump-version.sh 0.9.1` → build `2`, change something
   visible (e.g. a line in the menu-bar panel) so you can tell them apart,
   run `release.sh`, write `notes/0.9.1.html`, `publish.sh`, push the
   website.
3. **Manual check.** In build N's menu-bar panel: **Check for Updates…**.
   Expect Sparkle's window with version 0.9.1 and its notes. Click **Install
   Update**, then **Install and Relaunch**. The app quits, is replaced, and
   reopens as 0.9.1. Confirm with Finder → Get Info, or
   `defaults read "/Applications/Pixel Hand.app/Contents/Info" CFBundleVersion`.
4. **With a device connected.** Repeat with an iPhone/iPad connected:
   on Install and Relaunch, Pixel Hand asks "Updating disconnects your
   devices". **Later** keeps the update for the next quit; **Update Now**
   installs.
5. **Scheduled check.** On a build-N install, force the next check:
   ```bash
   defaults delete com.widgetsflow.pixelhand.mac SULastCheckTime
   ```
   and relaunch; the update alert should appear within a minute or so
   **[Mac-verify: Sparkle may wait for its first-launch grace period]**.
6. **Permissions survive.** After updating, Accessibility and Screen Recording
   should still be granted. They're tied to the Developer ID signature and
   bundle ID, which don't change. If macOS asks again, the designated
   requirement changed; check `codesign -d -r- "/Applications/Pixel Hand.app"`
   is the same for both builds.
7. **Tampered update is refused.** Edit the item's `sparkle:edSignature` in
   a *test* appcast (one character), push or serve it, check for updates:
   Sparkle must report the update as improperly signed and install nothing.

**Testing without bothering real users:** publish build N+1 on the **beta
channel** (`CHANNEL=beta ./release.sh`, then `CHANNEL=beta ./publish.sh`,
which leaves `/download/mac` alone). Only installs that opted in see beta
items:

```bash
defaults write com.widgetsflow.pixelhand.mac PixelHandBetaUpdates -bool YES
# … test …
defaults delete com.widgetsflow.pixelhand.mac PixelHandBetaUpdates
```

(`AppUpdater.allowedChannels(for:)` reads that flag.) Sparkle 2 doesn't take a
feed URL override from user defaults, so a channel is the way to test against
the real feed.

---

## 4. Optional: releasing from GitHub Actions

`.github/workflows/release-mac.yml` runs `release.sh` (and optionally
`publish.sh`) on a GitHub macOS runner. It is **manual only**
(Actions → *Release Mac app* → Run workflow; choose channel, and whether to
upload to R2). It never runs on push or PR, because macOS minutes count 10x.
It doesn't commit: download the `pixelhand-mac-release` artifact and commit
its `appcast.xml` and `_redirects` (or run `update-appcast.sh` locally).

Add these under **Settings → Secrets and variables → Actions → New
repository secret**:

| Secret | What | How to make it |
| --- | --- | --- |
| `MAC_DEVELOPER_ID_P12_BASE64` | Developer ID Application certificate **and private key** (add your Apple Development certificate to the same .p12, see below) | Keychain Access → select both → Export → `.p12`; then `base64 -i signing.p12 \| pbcopy` |
| `MAC_DEVELOPER_ID_P12_PASSWORD` | the .p12's password | |
| `ASC_API_KEY_P8_BASE64` | App Store Connect API key, for notarization and for `-allowProvisioningUpdates` | §1.2 option B, role **Admin** (profiles); `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| `ASC_API_KEY_ID` | its Key ID | |
| `ASC_API_ISSUER_ID` | the Issuer ID on the same page | |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle private key (one base64 line) | the contents of the file from §1.3 step 4 |
| `CLOUDFLARE_API_TOKEN` | only if "publish" is used | Cloudflare → My Profile → API Tokens → Create → *Edit Cloudflare Workers* template, or custom with **Account → Workers R2 Storage → Edit** |
| `CLOUDFLARE_ACCOUNT_ID` | only if "publish" is used | Cloudflare dashboard → right sidebar of any zone / Workers & Pages overview |

Notes:

- **[Mac-verify, first CI run]** The project uses automatic signing. The
  archive step signs with a *development* identity before export re-signs
  with Developer ID, so the runner needs an Apple Development certificate
  too: either include it in the .p12, or rely on the Admin API key letting
  Xcode use a cloud-managed one. If the archive step complains about
  signing, include the Apple Development certificate in the .p12.
- Nothing secret is written to the repository or logs. The keychain and
  `.p8` live in `$RUNNER_TEMP` and are deleted at the end; the Sparkle key
  exists only as a temporary file during `sign-update.sh`.
- In CI, `sign-update.sh` can't compare the private key with
  `SPARKLE_PUBLIC_ED_KEY` (that check needs the login keychain). Make sure
  the secret is the same key as `project.yml`'s public key; the update test
  in §3 is the proof.
- Runner and Xcode: `macos-26` with Xcode 26.2, as in `ci.yml`. Update both
  workflows together.

---

## 5. What still needs verifying on a Mac

Nothing here has been compiled or run. In order:

1. **Build:** `xcodegen generate` then build `DeckHandMac`. Sparkle resolves
   (`from: 2.9.0`, latest 2.10.x). `AppUpdater.swift` compiles under Swift 6:
   the `nonisolated` delegate methods with `MainActor.assumeIsolated`, and the
   `publisher(for: \.canCheckForUpdates)` KVO observation.
2. **Panel:** "Check for Updates…" appears above the footer; greyed out
   while `SPARKLE_PUBLIC_ED_KEY` is empty; enabled once it's set.
3. **No sandbox:** the Mac app has no `com.apple.security.app-sandbox`
   entitlement, so Sparkle needs no installer XPC services. `archive.sh`
   warns if that ever changes.
4. **archive.sh:** Developer ID export with automatic signing and the
   iCloud entitlement (§1.1 profile note); Sparkle's `Autoupdate` and
   `Updater.app` re-signed with team `DD5AWPLT2V`; universal binary.
5. **notarize.sh / make-dmg.sh:** both notarizations accepted; `spctl`
   passes; the DMG opens with no warning on a second Mac.
6. **sign-update.sh:** `sign_update --verify` and `generate_keys -p` flags
   behave as used here in the Sparkle version that resolves.
7. **publish.sh:** `wrangler r2 object put … --remote` with the flags used;
   the custom domain serves the DMG with the right length.
8. **The update path:** §3 steps 3–7, including the "Updating disconnects
   your devices" prompt and what Sparkle does after **Later**.
9. **Workflow:** first manual run (§4).
10. **Export compliance:** the binary check in
    `AppStore/ExportCompliance.md` ("Confirm on the Mac").
