# App Store Connect status: Pixel Hand

Snapshot from 2026-11-20, created with the `asc` CLI on the owner's Mac.
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
| Subscription group | "Pixel Hand Pro" | `22597533` |
| Subscription, level 1 | `com.widgetsflow.pixelhand.pro.yearly` | `6836997343` |
| Subscription, level 2 | `com.widgetsflow.pixelhand.pro.monthly` | `6836997313` |

- Both bundle IDs have **iCloud with CloudKit support** on, with
  `iCloud.com.widgetsflow.pixelhand` assigned (and nothing else). Apple adds In-App
  Purchase to every App ID by default; nothing else is enabled. Apple lists
  both as platform "Universal", as it does for every App ID.
- No tests bundle ID was registered (not needed).
- No Mac App Store record: the Mac app ships as a Developer ID download.

App record, version 1.0 (Prepare for Submission):

- **Price: Free**, available in all 175 territories and new ones.
- Categories: Utilities (primary), Productivity (secondary).
- Age rating: every answer None / No (4+).
- Apple silicon Mac availability: off. Vision Pro availability left on.
- Subtitle and keywords as in `StoreListing.md`. Promotional text and
  description as in `Subscription.md` §2 (description = `StoreListing.md`
  with the subscription section before "Requires the free Pixel Hand app for
  Mac").
- URLs: support `https://pixelhand.app/support`, marketing
  `https://pixelhand.app`, privacy policy `https://pixelhand.app/privacy`.
- App Privacy: Crash Data, Performance Data, Other Diagnostic Data, each
  App Functionality, not linked to the user, no tracking. Published.

Pixel Hand Pro (per `Subscription.md` §1):

- Yearly $19.99 and monthly $2.99 (US), other storefronts from Apple's
  equalisation, available in all 175 territories and new ones.
- Family Sharing on for both (permanent).
- English (U.S.) display names "Pixel Hand Pro (Yearly)" / "(Monthly)" and
  descriptions; group display name "Pixel Hand Pro".
- Introductory offer on both: free trial, 2 weeks, all 175 territories.
- Billing grace period: on, 16 days, all renewals, production and sandbox.
- State: **Missing Metadata** until the paywall review screenshot is added.

## Still manual

1. **Review screenshot** for each subscription (the paywall, see
   `Subscription.md` §4), then submit both subscriptions with the first build
   that contains the paywall.
2. **App Review notes**: Mac download link and demo video still placeholders.
3. **Paid Applications agreement**: must be active before subscriptions can
   be sold or sandbox-tested end to end.
4. ~~Sentry projects~~ done: DSNs are in `DeckHand/project.yml`.
5. **CloudKit schema**: run Debug builds of both apps signed into iCloud,
   then deploy the schema of `iCloud.com.widgetsflow.pixelhand` to
   Production before release (see `AppStoreConnectSetup.md` §6).
