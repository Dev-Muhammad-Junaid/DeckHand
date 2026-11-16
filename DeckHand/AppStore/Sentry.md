# Crash reporting with Sentry

Both apps report crashes, hangs and a 10% sample of performance traces to
Sentry through `Shared/DeckHandDiagnostics.swift`. Users can turn it off: the
**Share crash reports** switch is under Settings → Privacy on iPhone and iPad,
and is a checkbox at the bottom of the Mac menu-bar panel. It defaults to on.

What is never sent: screenshots, view hierarchy, session replay, device or
computer names, IP address, name or email (`sendDefaultPii = false`, plus a
`beforeSend` scrub). The only identifier is Sentry's random per-install ID. Keep it that way. The privacy policy, both `PrivacyInfo.xcprivacy`
files and the App Store privacy answers all assume it.

## One-time setup (owner)

1. **Create the organization** at <https://sentry.io/signup/>. Use the slug
   `widgetsflow`. If you pick another slug, change `SENTRY_ORG` in
   `DeckHand/project.yml`.
2. **Create two projects** (Projects → Create Project):

   | Platform | Project name (slug) | For |
   | --- | --- | --- |
   | Apple → iOS | `pixelhand-ios` | the iPhone/iPad app |
   | Apple → macOS | `pixelhand-mac` | the Mac host |

   Separate projects keep the paid app's crash rate clean and let you set
   different alert rules. If you use different slugs, change `SENTRY_PROJECT`
   on the matching target in `project.yml`.
3. **Privacy settings.** In Organization Settings → Security & Privacy, turn on
   **Prevent Storing of IP Addresses** and leave **Data Scrubber** on. Do the
   same in each project's Security & Privacy if it isn't inherited.
4. **Copy the DSNs.** In each project: Settings → Client Keys (DSN) → copy the
   DSN (`https://<key>@o<number>.ingest.<region>.sentry.io/<number>`). Paste
   them into `DeckHand/project.yml`:

   ```yaml
   DeckHandMac:  ... SENTRY_DSN: "https://…"   # pixelhand-mac's DSN
   DeckHandiOS:  ... SENTRY_DSN: "https://…"   # pixelhand-ios's DSN
   ```

   A DSN only allows *sending* events, it's meant to ship inside the app, and
   it's fine to commit. Leave it empty and reporting is simply off.
5. **dSYM uploads**, so crashes show function names. On the Mac you archive on:

   ```bash
   brew install getsentry/tools/sentry-cli
   sentry-cli login        # stores an auth token in ~/.sentryclirc
   ```

   Create the token with the scopes `project:releases` and `org:read`
   (Settings → Auth Tokens, or let `sentry-cli login` make one). Never commit
   it. Release builds then upload their dSYMs automatically in the "Upload
   dSYMs to Sentry" build phase. Debug builds skip it, and a missing
   `sentry-cli` only produces a warning.
6. **Alerts (optional).** Each project → Alerts → Create Alert → "Issues" →
   "A new issue is created" → email. That's enough for launch.

## Checking it works

Run a **Debug** build with the DSN filled in, then in Sentry:

- **Issues**: nothing yet is fine. To force one, temporarily add
  `SentrySDK.crash()` behind a button, run *without the debugger attached*
  (crashes under the debugger aren't captured), relaunch, and the crash should
  arrive within a minute. Remove the button afterwards.
- **Environment** filter shows `development` for Debug and `production` for
  Release builds.
- Open an event and check **Device**: it shows the model and OS but **no
  name**. Check **User**: only an `id` (Sentry's random per-install ID), no IP, name or email. Check **Attachments**: none.
- Turn the switch off, crash again: nothing should arrive.
