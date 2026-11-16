# App Store listing (draft)

For the iPhone/iPad app `com.widgetsflow.pixelhand`. Limits are App Store
Connect's: name and subtitle 30 characters, keywords 100, promotional text 170,
description 4,000.

## Name: **Pixel Hand: Remote for Mac** (26)

Why this form:

- The app was called Deck Hand until November 2026. About ten US apps
  already used "Deckhand" (among them **DeckHand for CyberDeck**, also an
  iPad control surface), and the registered US mark **DECKHAND** (Reg.
  6629861, class 9) was close. The owner chose **Pixel Hand** instead: the App
  Store had no apps called Pixel Hand or Pixelhand when it was checked, and
  the name fits the icon's dot-matrix hand.
- "Remote for Mac" follows Apple's own guidance on its trademarks: say an app
  works *with* an Apple product ("for Mac") rather than making "Mac" part of
  the product's name. "Pixel Hand – Mac Remote" (23) reads more like a product
  called "Mac Remote" and is likelier to draw a guideline 5.2.5 question at
  review. If you still prefer it, it fits.
- A trademark search for "Pixel Hand" hasn't been done. A one-hour clearance
  opinion from a trademark attorney before launch is cheap insurance. This
  isn't legal advice.

Home-screen name stays **Pixel Hand** (`CFBundleDisplayName`); only the store
name carries the descriptor.

## Subtitle: **Trackpad, mirror & shortcuts** (28)

Alternative: "Trackpad and screen for Mac" (27).

## Keywords (99)

```
trackpad,mouse,keyboard,touchpad,mirror,screen,shortcuts,launcher,presenter,wireless,cursor,desktop
```

Notes: commas only, no spaces. Words already in the name or subtitle ("pixel",
"hand", "remote", "mac") are indexed already, so they aren't repeated. No
competitor names or trademarks (Apple's own included: no "MacBook", "iMac",
"Keynote"; and no "Stream Deck"). Once live, check search rankings after two
weeks in App Store Connect → Analytics and swap the weakest words.

## Promotional text (170 max, can change any time without review)

> Your iPad becomes a trackpad, a live view of your Mac's screen, and a row of
> shortcuts that follow whatever app is in front. Free Mac app included.

## Description

> Pixel Hand turns your iPhone or iPad into a control surface for your Mac.
>
> Sit back from your desk, present from across the room, or keep a second
> screen of controls beside your keyboard. Pixel Hand connects straight to your
> Mac over your local network, with no account and no cloud service in the
> middle.
>
> **A real trackpad**
> Multi-touch pointer control with adjustable sensitivity, clicks,
> double-clicks and two-finger scrolling with natural momentum, so your Mac
> scrolls the way it does with its own trackpad.
>
> **See your Mac's screen**
> A live mirror floats over the controls. Pinch it from a small tile to nearly
> full screen and it gets sharper as it grows.
>
> **Shortcuts that know the app you're in**
> Pixel Hand reads the menus of the app in front on your Mac and gives you its
> real shortcuts as one-tap chips. When a dialog opens, its buttons appear on
> your iPad too, so "Don't Save, Cancel, Save" is a tap away.
>
> **Capture, mark up, recognise text**
> Grab the full screen, a region or a single window. Annotate it, pull the
> text out of it, or save it to Photos.
>
> **Launch and switch apps**
> Browse your Mac's apps, open any of them, and see what's running in
> Command-Tab order. Media keys are there too.
>
> **Private by design**
> Your screen, keystrokes and captures go only between your own devices. Every
> new connection has to be approved on the Mac. Devices on the same iCloud
> account recognise each other.
>
> **Requires the free Pixel Hand app for Mac**
> Download it from <site URL> *[replace]*. Needs macOS 14
> or later. Your iPhone or iPad and Mac need to be on the same network.

Before submitting, replace the bracketed URL, and check the description
doesn't promise anything the build doesn't do (e.g. if CloudKit recognition is
switched off, drop the last sentence of "Private by design").

## Categories, age rating, pricing

- **Primary category:** Utilities. **Secondary:** Productivity.
- **Age rating:** 4+ (answer "None" to every content question; the app has no
  web browser, user-generated content or chat).
- **Price:** paid, owner's call. Remember the paid app is the *only* revenue:
  the Mac app is free.
- **Availability:** all territories is fine export-wise (see
  `ExportCompliance.md`).
- **Devices:** iPhone and iPad. Under "Apple silicon Mac availability" turn
  **off** "Make this app available" — running the remote *on* a Mac makes no
  sense and the build already sets `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO`.

## URLs

- **Support URL** (required): must be a web page, not a `mailto:` link. The
  site has none yet; add a small `/support` page with the support email.
- **Marketing URL:** the site's home page.
- **Privacy Policy URL:** `https://<domain>/privacy`.

## App Review notes

> Pixel Hand is a remote control for a Mac. The iPhone/iPad app does nothing on
> its own: it needs the free companion Mac app, Pixel Hand for Mac, running on
> a Mac on the same Wi-Fi network.
>
> The Mac app is distributed outside the Mac App Store as a free, notarized
> Developer ID download from https://<domain>/ *[replace]*, because it has to
> control the pointer and keyboard through macOS Accessibility, which the Mac
> App Store sandbox doesn't allow. It's free: there are no purchases,
> subscriptions or accounts anywhere, and the iOS app unlocks nothing outside
> the App Store.
>
> To test:
> 1. On a Mac with macOS 14 or later, download and open Pixel Hand for Mac. It
>    appears in the menu bar. Grant Accessibility and Screen Recording when
>    the menu-bar panel asks (System Settings → Privacy & Security).
> 2. Put the iPhone/iPad on the same Wi-Fi network, open Pixel Hand and allow
>    Local Network access.
> 3. Tap the Mac in the list, then click Allow on the Mac (every new device
>    must be approved there).
> 4. Use the trackpad, pinch the mirror tile, try a capture and the shortcut
>    chips.
>
> A video of the full flow on real devices: <link — unlisted video, replace>
>
> No login is required. Crash reporting can be turned off in Settings →
> Privacy.

Attach the video link; reviewers often can't set up a Mac, and a video is what
gets these approved first time.

## Screenshots needed

- iPhone 6.9" (1320 × 2868 or 2868 × 1320) — required.
- iPad 13" (2064 × 2752 or 2752 × 2064) — required since the app runs on iPad.
- Up to 10 each; the first three carry the listing. Suggested order: trackpad
  with mirror; shortcut chips for a real app; dialog buttons on the iPad; a
  capture with markup; the app launcher.
