# App Store Connect status: Pixel Hand

Snapshot from 2026-11-17, created with the `asc` CLI on the owner's Mac.
Team: **Mega Creations LLC (`DD5AWPLT2V`)**. These identifiers supersede the
`deckhand` ones in the other files in this folder.

The old `com.deckhand.ios`, `com.deckhand.mac` and
`iCloud.com.deckhand.shared` still exist and were left untouched.

## Created

| What | Identifier | Portal / ASC ID |
| --- | --- | --- |
| iOS/iPadOS bundle ID ("Pixel Hand iOS") | `com.widgetsflow.pixelhand` | `C3YKAM98MT` |
| Mac bundle ID ("Pixel Hand Mac") | `com.widgetsflow.pixelhand.mac` | `V8D37Q8822` |
| iCloud container ("Pixel Hand") | `iCloud.com.widgetsflow.pixelhand` | `7Q2HUZYS22` |
| iOS app record | "Pixel Hand: Remote for Mac", SKU `pixelhand-ios`, en-US | Apple ID `6835622962` |

- Both bundle IDs have **iCloud with CloudKit support** on, with
  `iCloud.com.widgetsflow.pixelhand` assigned (and nothing else). Apple adds In-App
  Purchase to every App ID by default; nothing else is enabled. Apple lists
  both as platform "Universal", as it does for every App ID.
- No tests bundle ID was registered (not needed).
- No Mac App Store record: the Mac app ships as a Developer ID download.

App record, version 1.0 (Prepare for Submission):

- Categories: Utilities (primary), Productivity (secondary).
- Age rating: every answer None / No (4+).
- Apple silicon Mac availability: off. Vision Pro availability left on.
- Subtitle, keywords and promotional text: as in `StoreListing.md`.
- App Privacy: Crash Data, Performance Data, Other Diagnostic Data, each
  App Functionality, not linked to the user, no tracking. **Saved, not
  published.**

## Still manual

1. **Support email**, and a `/support` page for the required Support URL.
2. **Site domain → Privacy Policy URL**, then publish App Privacy (App Store
   Connect → the app → App Privacy → Publish).
3. **Description and App Review notes**: left empty until `StoreListing.md`
   says "Pixel Hand" and the site URLs are final.
4. **Sentry projects** `pixelhand-ios` and `pixelhand-mac`.
5. **Pricing**, and the **Paid Applications agreement**: it shows "Pending
   User Info" (bank and tax details in App Store Connect → Business). A paid
   app can't go on sale until it's active.
6. **CloudKit schema**: run Debug builds of both apps signed into iCloud,
   then deploy the schema of `iCloud.com.widgetsflow.pixelhand` to
   Production before release (see `AppStoreConnectSetup.md` §6).
