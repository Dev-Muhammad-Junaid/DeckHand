# App Store Connect: App Privacy answers (draft)

For the iPhone/iPad app `com.widgetsflow.deckhand`. Enter these under
App Store Connect → the app → **App Privacy**. They must match
`DeckHandiOS/PrivacyInfo.xcprivacy` and `website/public/privacy.html`. If one
changes, change all three.

**Privacy Policy URL:** `https://<site domain>/privacy` (the site isn't on its
final domain yet; until then use the `*.pages.dev` URL).

## Data collection

**Do you or your third-party partners collect data from this app?** → **Yes**

Select exactly these three types, all under **Diagnostics**:

| Data type | Used for | Linked to the user? | Used for tracking? |
| --- | --- | --- | --- |
| Crash Data | App Functionality | No | No |
| Performance Data | App Functionality | No | No |
| Other Diagnostic Data | App Functionality | No | No |

Why **App Functionality** and not **Analytics**: Apple's definition of App
Functionality explicitly includes "minimize app crashes, improve scalability
and performance". The reports aren't used to study how people use features.
If you later add product analytics (e.g. which screens get used), that's a new
data type ("Product Interaction") with purpose Analytics, and these answers
have to change.

Why **not linked**: `sendDefaultPii` is off, the IP isn't stored, there is no
account, and device names are scrubbed (see
`Shared/DeckHandDiagnostics.swift`).

Why **no tracking**: nothing is combined with other companies' data or shared
with data brokers, and there are no ads.

## Things that are *not* collected, and why

| Thing | Why it isn't "collected" in Apple's sense |
| --- | --- |
| Screen mirror, captures, pointer/keyboard input, app lists | Travel device-to-device over the local network; never reach us or a third party |
| iCloud device records (CloudKit) | Stored in the user's *private* CloudKit database, which the developer can't read |
| Photos | Only written to the user's library on device; nothing is read or sent |
| Settings | `UserDefaults` on device |
| Waitlist email | Website only, not the app; covered by the privacy policy, not this form |

## The one judgment call: Sentry's install ID

Sentry tags each report with a random ID generated for that app install (kept
so it can count "affected installs"). It isn't the advertising ID or any
hardware ID, it resets on reinstall, and it isn't tied to a person. Sentry's
own guidance is to declare only the three Diagnostics types above, and this
draft follows it.

If you'd rather be maximally conservative, also add **Identifiers → Device
ID** (App Functionality, not linked, no tracking). It costs nothing except a
slightly longer label on the store page. Either answer is defensible; just
keep it consistent with the privacy manifest (which would then also need
`NSPrivacyCollectedDataTypeDeviceID`).

## Resulting label on the App Store

- **Data Not Linked to You:** Diagnostics
- No "Data Used to Track You", no "Data Linked to You".
