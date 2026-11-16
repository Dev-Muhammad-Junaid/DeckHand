# Apple Developer and App Store Connect setup

Everything here is **permanent**: a bundle ID can't be renamed, an iCloud
container can never be deleted, and an app record's bundle ID and SKU can't
change. Check each value twice before clicking **Register** or **Create**.

Team: **Mega Creations LLC (`DD5AWPLT2V`)**.

| What | Value |
| --- | --- |
| iOS/iPadOS bundle ID | `com.widgetsflow.pixelhand` (description: `Pixel Hand iOS`) |
| Mac bundle ID | `com.widgetsflow.pixelhand.mac` (description: `Pixel Hand Mac`) |
| Test bundle ID | `com.widgetsflow.pixelhand.tests` — **don't register**; unit tests don't need a portal ID |
| iCloud container | `iCloud.com.widgetsflow.pixelhand` (description: `Pixel Hand`) |
| App record name | `Pixel Hand: Remote for Mac` (see `StoreListing.md`) |
| App record SKU | `pixelhand-ios` (private, never shown) |
| Primary language | English (U.S.) |

## What can be automated

| Step | App Store Connect API | Notes |
| --- | --- | --- |
| Register bundle IDs | Yes (`POST /v1/bundleIds`) | |
| Turn on iCloud capability | Yes (`POST /v1/bundleIdCapabilities`, type `ICLOUD`) | |
| Create the iCloud container | **No** | Developer portal, or Xcode automatic signing |
| Assign the container to the bundle IDs | **No** | Developer portal, or Xcode automatic signing |
| Create the app record | **No** | Apple: "Don't use this API to create new apps"; `POST /v1/apps` returns "does not allow CREATE" |

Because the container and app record need the website anyway, the portal is
the simplest path for all of it. It takes about ten minutes.

## 1. iCloud container

developer.apple.com → Account → **Certificates, Identifiers & Profiles** →
**Identifiers** → **+** → **iCloud Containers** → Continue.

- Description: `Pixel Hand`
- Identifier: `iCloud.com.widgetsflow.pixelhand`
- Continue → **Register**.

## 2. iOS bundle ID

Identifiers → **+** → **App IDs** → Continue → **App** → Continue.

- Description: `Pixel Hand iOS`
- Bundle ID: **Explicit**, `com.widgetsflow.pixelhand`
- Capabilities: tick **iCloud** → choose **Include CloudKit support**.
  Leave everything else off (no Push, no App Groups, no Sign in with Apple).
- Continue → **Register**.
- Open the new ID → next to iCloud click **Edit** (or **Configure**) → tick
  `iCloud.com.widgetsflow.pixelhand` → Continue → **Save**.

## 3. Mac bundle ID

Same as step 2, with:

- Description: `Pixel Hand Mac`
- Bundle ID: **Explicit**, `com.widgetsflow.pixelhand.mac`
- Capabilities: **iCloud** with CloudKit, assigned the same container.
- Leave **App Sandbox** alone: the Mac app is a Developer ID build and isn't
  sandboxed.

(The platform list at the top says "iOS, iPadOS, macOS, tvOS, watchOS,
visionOS". That's fine for both; an App ID isn't tied to one platform.)

## 4. Developer ID certificate (Mac distribution)

If you've never notarized anything for this team: Certificates → **+** →
**Developer ID Application** → follow the CSR steps (Xcode → Settings →
Accounts → Manage Certificates → **+** → Developer ID Application does the
same in one click). Only the Account Holder can create it.

## 5. App record (iPhone + iPad)

appstoreconnect.apple.com → **Apps** → **+** → **New App**.

- Platforms: tick **iOS** only. (iPad support comes from the build, not this
  box. Don't tick macOS: the Mac app isn't going to the Mac App Store.)
- Name: `Pixel Hand: Remote for Mac`. If it's taken, App Store Connect says so
  here; fall back to `Pixel Hand – Mac Remote`.
- Primary Language: English (U.S.)
- Bundle ID: pick `com.widgetsflow.pixelhand` from the list (it appears once
  step 2 is done).
- SKU: `pixelhand-ios`
- User Access: Full Access.
- **Create**.

Then, still in App Store Connect:

- **Pricing and Availability** → set the price.
- **App Privacy** → answers in `AppPrivacy.md`.
- **App Information** → categories, age rating, privacy policy URL from
  `StoreListing.md`. Under "Apple silicon Mac" availability, untick it.
- **Agreements, Tax, and Banking** (Business section): the **Paid
  Applications** agreement must be active, with bank and tax forms done, or a
  paid app can't go on sale. Do this early; it can take days to clear.

## 6. CloudKit schema (before release)

The container starts empty. Loom creates its record types the first time a
**development** build runs and publishes a device. Before shipping:

1. Run a Debug build of both apps signed into iCloud, so each publishes once.
2. icloud.developer.apple.com → CloudKit Database → container
   `iCloud.com.widgetsflow.pixelhand` → **Deploy Schema Changes…** → deploy
   to Production.

Without step 2, TestFlight and App Store builds (which use the Production
environment) can't see each other through iCloud. Bonjour discovery still
works either way.

The old `iCloud.com.deckhand.shared` container stays in the portal forever
(containers can't be deleted). It's harmless; just leave it. The same goes for
anything already registered under the earlier `com.widgetsflow.deckhand*`
identifiers before the rename to Pixel Hand: leave it, and register the
`pixelhand` values above.

## If you'd rather script steps 2–3

The owner's existing App Store Connect CLI lives on the Mac, not in the cloud
container. If you want a cloud session to run it, add the API key as
environment secrets (cloud environment menu in the session's title bar → Edit
→ Network secrets / environment variables) as `ASC_KEY_ID`, `ASC_ISSUER_ID` and
`ASC_PRIVATE_KEY` (the `.p8` contents), then start a new session. Never paste
the key into chat. Steps 1, 5 and the container assignment still need the
website.
