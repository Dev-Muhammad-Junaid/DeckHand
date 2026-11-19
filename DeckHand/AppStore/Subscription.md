# Pixel Hand Pro: subscription setup and copy

For the iPhone/iPad app `com.widgetsflow.pixelhand` (Apple ID 6835622962).
Decided 2026-11-17 (`Integration/DECISIONS.md`). The Mac app stays free and is
not sold anywhere.

## 1. App Store Connect setup (owner)

Needs the **Paid Applications agreement** to be active (bank and tax were
submitted 2026-11-17; products can be created before it's approved, but
sandbox purchases and review need it).

**Monetization → Subscriptions → Subscription Groups → +**

| Field | Value |
| --- | --- |
| Reference name | `Pixel Hand Pro` |
| Group display name (localization, English (U.S.)) | `Pixel Hand Pro` |
| App name display | Use app name |

**Two subscriptions in that group:**

| | Yearly | Monthly |
| --- | --- | --- |
| Reference name | `Pixel Hand Pro Yearly` | `Pixel Hand Pro Monthly` |
| Product ID | `com.widgetsflow.pixelhand.pro.yearly` | `com.widgetsflow.pixelhand.pro.monthly` |
| Duration | 1 year | 1 month |
| Level (rank in group) | **1** | **2** |
| Price (US) | $19.99 | $2.99 |
| Other storefronts | Apple's automatic equalisation | same |
| Family Sharing | **On** (can't be turned off later) | **On** |
| Display name | `Pixel Hand Pro (Yearly)` | `Pixel Hand Pro (Monthly)` |
| Description (55 max) | `Every Pro feature, billed once a year.` | `Every Pro feature, billed monthly.` |
| Introductory offer | Free, 2 weeks, all countries, new subscribers | same |
| Review screenshot | the paywall (§4) | the paywall |
| Review notes | see §5 | see §5 |

Why yearly is level 1: moving monthly → yearly is then an upgrade that
starts at once (Apple refunds the unused month pro rata); yearly → monthly
waits for the year to end. Both plans unlock the same features.

Other settings:

- **App Information → License Agreement:** leave Apple's standard EULA.
  The paywall links to it as "Terms of Use".
- **App Information → Privacy Policy URL:** `https://pixelhand.app/privacy`.
- **Billing grace period** (Subscriptions page, group settings): **On, 16
  days**, all renewals, production and sandbox. The app treats grace and
  billing retry as Pro.
- **App Store Server Notifications:** not needed (no server).
- Submit both subscriptions **with the first app version that includes
  the paywall**: first-time subscriptions must be reviewed together with
  a binary.

## 2. Product page copy

**Subtitle** stays "Trackpad, mirror & shortcuts".

**Promotional text** (170):

> Free: trackpad, keyboard and media keys for your Mac. Pixel Hand Pro adds
> the live mirror, shortcut chips, capture and all your Macs. Try it free.

**Description: replace the last section ("Requires the free Pixel Hand app
for Mac") with these two, keeping it last:**

> **Free, with Pixel Hand Pro when you want more**
> The trackpad, keyboard and media keys are free with one Mac. Pixel Hand
> Pro adds shortcut chips and decks, the live mirror (whole display or one
> window), capture and text recognition, clipboard sharing, and every Mac
> you own. New subscribers get a 2-week free trial.
>
> Pixel Hand Pro is an auto-renewable subscription: $2.99 per month or
> $19.99 per year (prices in your currency are shown in the app). Payment is
> charged to your Apple Account when you confirm the purchase, or when the
> free trial ends. It renews automatically unless cancelled at least 24
> hours before the end of the current period, and your account is charged
> for the renewal within the 24 hours before the period ends. Manage or
> cancel it in your Apple Account settings. Family Sharing is supported.
>
> Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
> Privacy policy: https://pixelhand.app/privacy
>
> **Requires the free Pixel Hand app for Mac**
> Download it from https://pixelhand.app. Needs macOS 14 or later. Your
> iPhone or iPad and Mac need to be on the same network.

The Terms of Use link must be in the description (or the EULA field), as
guideline 3.1.2 requires for subscriptions.

## 3. In-app copy

All strings live in `Core/Sources/PixelHandCore/Store/SubscriptionCopy.swift`
and are tested. The paywall shows, before purchase: the plan name, each
plan's billed price and period (most prominent), the trial and when billing
starts, auto-renewal and the 24-hour rule, how to cancel, Restore
Purchases, and links to the Terms of Use and privacy policy.

## 4. Review screenshot

Take it on an iPad with the `.storekit` configuration (or sandbox): open
Settings › Subscription › "Try Pixel Hand Pro free for 2 weeks". Show the
plans, the button and the disclosure in one shot.

## 5. App Review notes (already in `StoreListing.md`)

> The iPhone/iPad app is free with an optional auto-renewable subscription,
> Pixel Hand Pro (monthly or yearly, 2-week free trial). The trackpad,
> keyboard and media keys work for free with one Mac. Pro unlocks shortcut
> chips, the app launcher, the live mirror, capture/OCR, clipboard sharing
> and more than one Mac; locked controls show a lock and open the paywall.
> The paywall is also in Settings › Subscription, with Restore Purchases.
> The Mac app is free and has no purchases. No account or login is needed.
