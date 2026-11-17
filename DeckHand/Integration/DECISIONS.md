# Owner decisions (source of truth for all Pixel Hand sessions)

Recorded by the coordinating session ("Deckhand project status review").
Newest first. If a doc elsewhere disagrees, this file wins.

## 2026-11-17 — Business model: subscription with a 2-week free trial
- iPhone/iPad app is **free to download**; access is an **auto-renewable
  subscription** with **monthly** and **yearly** plans, each with a
  **2-week free trial** (introductory offer).
- **Confirmed by the owner 2026-11-17:** $2.99/month and $19.99/year
  (USD tier; other storefronts follow Apple's equalisation); one
  subscription group "Pixel Hand Pro"; product IDs
  `com.widgetsflow.pixelhand.pro.monthly` and
  `com.widgetsflow.pixelhand.pro.yearly`; Family Sharing on.
- Proposed, pending owner confirmation: free tier = trackpad, keyboard and
  media keys with one Mac; Pro = decks and chips, mirror, capture/OCR,
  multiple Macs, sharing, AI. During the trial everything is unlocked.
- The Mac app stays a free Developer ID download; entitlement lives on the
  iOS side (StoreKit 2, `Transaction.currentEntitlements`), no server.
- Needed in the app: StoreKit 2 paywall and "Restore Purchases", a
  subscription status row in Settings, a local `.storekit` configuration for
  testing, and Apple's required subscription disclosures (price, period,
  auto-renewal, links to Terms of Use / standard EULA and the privacy
  policy) on the paywall and in the App Store description.
- This is a new M1 ticket. It touches iOS settings/onboarding, so it goes in
  after the hot-spot file splits (PH-003/005/010).

## 2026-11-16/17 — Earlier decisions
- Name **Pixel Hand**; store name "Pixel Hand: Remote for Mac"; IDs
  `com.widgetsflow.pixelhand` (iOS), `com.widgetsflow.pixelhand.mac`,
  container `iCloud.com.widgetsflow.pixelhand` (all registered; app record
  Apple ID 6835622962).
- Site **pixelhand.app**, support **support@pixelhand.app**; Sparkle feed
  `https://pixelhand.app/mac/appcast.xml`.
- Mac app: free notarized Developer ID download with Sparkle, not on the Mac
  App Store. Mac and iOS apps release together.
- Plan "Option C": ~3 weeks to 1.0 (M0 merge/refactor, M1 Sill quick wins +
  typing and drag, M2 beta and release), then 1.1 HEVC / persistent pairing /
  clipboard, 1.2 Deck 2 + App Intents, 1.3 multi-Mac + sharing between any
  paired devices, 1.4 AI commands.
- AI runs on-device (Foundation Models), else on the paired Mac, else a
  deterministic fallback; no third-party cloud. Private Cloud Compute: not
  used unless the owner asks.
- Clean break from old versions (no users yet). Re-implement Sill features
  from its behaviour; don't copy its code. Mac private APIs: Mission Control
  shortcut reading and locked-Mac check approved; virtual display on hold.
- Crash reporting: Sentry with a user toggle. CI: GitHub Free, PR-only.
