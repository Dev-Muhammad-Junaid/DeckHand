# Lane: Store (StoreKit 2 subscription and free-tier gating)

Branch `claude/pixelhand-lane-store`, cut from integration at `cfa4b0f` and
merged with `origin/claude/pixelhand-integration` at `a05e0a7` (build 6,
single-window mirroring) right before hand-off, so the gates cover the
newest views. **No protocol change** (still version 9). The Mac app is
untouched and stays free and ungated.

Written in a Linux container. Core was built and tested here (Swift 6.2);
`SubscriptionStore.swift` was type-checked against StoreKit stubs. The
SwiftUI files (paywall, modifiers, Settings section) were **not** compiled.
The owner's Mac build must run §4 and §5.

## 1. What changed

As decided (`DECISIONS.md` 2026-11-17): group "Pixel Hand Pro",
`com.widgetsflow.pixelhand.pro.monthly` ($2.99) and `.yearly` ($19.99), a
2-week free trial as the introductory offer, Family Sharing on, iOS only,
no server.

### Core: `Core/Sources/PixelHandCore/Store/` (31 new tests)

| File | What |
| --- | --- |
| `ProFeature.swift` | Feature → tier. Free: `trackpad`, `keyboard`, `mediaKeys`. Pro: `decks` (chips, dialog chips, app launcher, decks), `mirror` (all codecs, window mirror), `capture` (incl. OCR), `multipleMacs`, `sharing` (clipboard), `ai`. |
| `SubscriptionPlan.swift` | Product IDs, group name, trial length, USD fallback prices, yearly savings (44%, rounded down). |
| `Entitlement.swift` | `Entitlement.resolve(entitlements:statuses:hadSubscription:now:)` from plain facts copied out of StoreKit. Statuses: `unknown`, `cached`, `notSubscribed`, `trial`, `active`, `gracePeriod`, `billingRetry`, `expired`, `revoked`. Pro = trial, active, grace, billing retry (owner decision), or an unexpired cache. Revoked and upgraded transactions never entitle; your own plan beats a family-shared one; paid beats trial. |
| `EntitlementCache.swift` | The last Pro answer, stored until its end date (3 days when StoreKit gave none) so subscribers don't see locks flash at launch. Only ever unlocks; StoreKit's answer replaces it. |
| `FreeMacPolicy.swift` | The one-Mac rule (below). |
| `SubscriptionCopy.swift` | Every user-facing string: feature names, headlines, plan captions, the guideline 3.1.2 disclosure, the Settings status row, one-Mac lines, Terms of Use (Apple standard EULA) and privacy (`https://pixelhand.app/privacy`) URLs. |

### The one-Mac rule

- The **first Mac** this device connects to becomes the free Mac (by Loom
  device ID, which the picker has before dialling).
- **While Pro is on** (trial included) any Mac connects, and the free Mac
  follows the Mac used last, so when Pro ends the free Mac is the one the
  person was using.
- **Without Pro**, picking another Mac doesn't dial; it opens the paywall
  ("The free plan works with one Mac, *Studio*") with **"Use *Laptop* as my
  free Mac"**. The first change after an automatic pick works at once;
  after a change you make yourself, the next waits **7 days** (the paywall
  says until when). Setting the clock back doesn't help. After buying Pro
  or switching, the refused Mac is dialled automatically.
- Other Macs show a small lock on their picker card.
- Stored per device in `UserDefaults` (`store.freeMac`); a reinstall
  forgets it (accepted: low stakes).

### iOS: `DeckHandiOS/Store/` and Settings

| File | What |
| --- | --- |
| `Store/SubscriptionStore.swift` | `@MainActor @Observable`, `.shared`. Listens to `Transaction.updates` (started first), finishes `Transaction.unfinished`, loads products, reads `Transaction.currentEntitlements` + `subscription.status` (+ `Transaction.all` to tell "expired" from "never"), `isEligibleForIntroOffer`. Purchase via SwiftUI `PurchaseAction`; handles verified / unverified / pending (Ask to Buy) / cancelled. Restore = `AppStore.sync()`. Free Mac storage and `admitMac`. |
| `Store/RequiresPro.swift` | `EnvironmentValues.entitlements` (Core `Entitlement`) and `.requiresPro(_ feature:)`: unlocked → unchanged; locked → dimmed, disabled, lock badge, tap opens the paywall (presented by the modifier itself, so it works in toolbars and sheets). |
| `Store/SubscriptionRoot.swift` | `.subscriptionStore()` for the app root: starts the store, publishes `\.entitlements`, refreshes on return to foreground, hosts the one-Mac paywall, and turns **Share clipboard** off once StoreKit settles on no Pro (also catches Pro that ended while the app was closed). |
| `Store/PaywallView.swift` | Headline for the locked feature, Pro feature list (AI hidden until it ships), yearly/monthly plans with the billed price most prominent, "Start your free 2 weeks"/"Subscribe", pending/error lines, the full disclosure, Restore Purchases, Terms of Use and Privacy Policy links. Closes itself when Pro turns on. |
| `Store/FreeMacBadge.swift` | `.freeMacBadge(deviceID:)`: the picker card's lock. Display only. |
| `Store/PixelHand.storekit` | Local StoreKit configuration matching App Store Connect (§7). |
| `Settings/SettingsSubscriptionSection.swift` | Status row (plan, trial end, renewal date, family-shared, payment problem), "Update payment method" in grace/billing retry, "Try Pixel Hand Pro free for 2 weeks"/"See Pixel Hand Pro" or "Manage subscription" (`manageSubscriptionsSheet`), Restore Purchases, the free plan's Mac. |

Docs: new `AppStore/Subscription.md` (App Store Connect setup, product page
copy with the required disclosure, review screenshot, review notes);
`AppStore/StoreListing.md` price line and App Review notes updated (they
said "no purchases or subscriptions").

Type check: `Scripts/linux-typecheck/StoreKitStubs.swift` (iOS 17 SDK
signatures) and `run.sh` now strips `import StoreKit` and checks
`DeckHandiOS/Store/SubscriptionStore.swift` by default.

## 2. Out-of-lane edits (all one line, marked `// Store lane`)

| File | Owner | Line |
| --- | --- | --- |
| `DeckHandiOS/DeckHandApp.swift` | Integration | `.subscriptionStore()` on the root `Group`, **inside** `.environmentObject(settings)` (it reads the settings) |
| `DeckHandiOS/SettingsView.swift` | Integration | `SettingsSubscriptionSection()` after `SettingsPairingSection()` |
| `DeckHandiOS/Control/ControlToolbar.swift` | Integration | `.requiresPro(.mirror)` on the mirror toggle (window mirroring starts from inside the running mirror, so this gates it too) |
| `DeckHandiOS/Control/ControlToolbar.swift` | Integration | `.requiresPro(.capture)` on `CaptureCapsule` (full screen, region, window, OCR) |
| `DeckHandiOS/QuickActionsBar.swift` | Integration | `.requiresPro(.decks)` on `shortcutChipsSegment` (app shortcut chips). Text-edit and numpad chips stay free (keyboard). |
| `DeckHandiOS/QuickActionsBar.swift` | Integration | `.requiresPro(.decks)` on the dialog-button chips |
| `DeckHandiOS/StreamDeckGridView.swift` | Integration | `.requiresPro(.decks)` on `AppButton` (app launcher tiles) |
| `DeckHandiOS/Clipboard/PasteToMacControl.swift` | iOS interaction | `.requiresPro(.sharing)` on `ClipboardRow` |
| `DeckHandiOS/Settings/SettingsPointerSection.swift` | iOS interaction | `.requiresPro(.sharing)` on the "Share clipboard" toggle |
| `DeckHandiOS/PeerPickerView.swift` | Pairing | `.freeMacBadge(deviceID:)` on `PeerCard` |
| `DeckHandiOS/PeerPickerView.swift` | Pairing | `guard SubscriptionStore.shared.admitMac(…) else { return }` at the top of `connectTo` (covers taps and the QR path) |
| `Scripts/linux-typecheck/run.sh` | shared tooling | copy `StoreKitStubs.swift`, strip `import StoreKit`, add `SubscriptionStore.swift` |

Left free on purpose: trackpad and gestures, the keyboard panel and live
typing, text-edit/numpad chips, media keys, the Mission Control /
Launchpad / Show Desktop buttons and the running-app switcher (both are
things the keyboard and trackpad do anyway). Mirror and capture settings
stay editable; they do nothing without the features.

## 3. `project.yml` (integration applies)

Keeps the `.storekit` file in the navigator but out of Copy Bundle
Resources, and runs the iOS scheme against it. In the `DeckHandiOS`
target, replace its `sources` and `scheme: {}`:

```yaml
    sources:
      - path: DeckHandiOS
        type: group
        excludes:
          - Store/PixelHand.storekit
      - path: DeckHandiOS/Store/PixelHand.storekit
        buildPhase: none
      - path: Shared
        type: group
```

```yaml
    scheme:
      storeKitConfiguration: DeckHandiOS/Store/PixelHand.storekit
```

No new package, target, entitlement or Info.plist key: StoreKit 2 needs no
capability on iOS ("In-App Purchase" is on for every App ID). Release
builds ignore the scheme's StoreKit configuration, so TestFlight and the
App Store use the sandbox / production store. Archive builds are
unaffected.

## 4. iPad checks (owner's Mac build)

Run from Xcode with the `DeckHandiOS` scheme (it uses `PixelHand.storekit`).
Open **Debug → StoreKit → Manage Transactions** to watch and edit
transactions. Delete the app first for a clean start.

| Check | Expected |
| --- | --- |
| Fresh install, no purchase | Settings › Subscription: "Free plan", "Try Pixel Hand Pro free for 2 weeks". Mirror toggle and capture capsule dimmed with a lock; app chips, dialog chips, app tiles, Paste to Mac row and "Share clipboard" locked. Trackpad, keyboard panel, live typing, text-edit/numpad chips, media keys, Mission Control buttons work. |
| Tap a locked control | Paywall opens with that feature's headline ("Live mirror is part of Pixel Hand Pro"), yearly preselected, "$19.99 / year" and "$2.99 / month" largest, captions "2 weeks free, then … · save 44%", disclosure, Restore Purchases, Terms of Use and Privacy Policy open in Safari. |
| Start trial (yearly) | StoreKit sheet shows the free trial; after confirming, the paywall closes, every lock disappears at once, Settings: "Pixel Hand Pro free trial — Free until <date>, then $19.99/year." |
| Trial with a second Mac | Any Mac connects; no lock on picker cards. |
| Trial ends | In Manage Transactions, **Expire** the subscription (or speed time up in the `.storekit` editor; turn off auto-renew first to test lapsing). Locks return, Settings: "Free plan — Pro ended …", "Share clipboard" turns off. |
| Not eligible for trial again | After the trial, the paywall button reads "Subscribe", captions drop "2 weeks free", disclosure drops the trial lines. |
| Purchase monthly | Settings: "Pixel Hand Pro, monthly — Renews <date> at $2.99/month."; "Manage subscription" opens Apple's sheet. |
| Upgrade to yearly in Manage subscription | Plan becomes yearly at once (level 1). |
| Restore | Delete and reinstall with an active transaction in Manage Transactions, tap Restore Purchases: Pro returns. With no transactions: "No Pixel Hand Pro subscription was found…". |
| Refund | **Refund** the transaction in Manage Transactions: locks return, Settings "…was refunded…". |
| Grace / billing retry | In the `.storekit` editor enable **Billing Grace Period**, then in Manage Transactions turn on **Billing retry** / fail renewal: Pro stays on, Settings shows the payment problem in orange with "Update payment method". |
| Ask to Buy | Enable **Ask to Buy** in the `.storekit` editor, purchase: "Your purchase is waiting for approval…"; approve in Manage Transactions: Pro turns on and the paywall closes. |
| Launch as subscriber | Quit and relaunch with Pro: no lock flashes (cache). |
| One Mac, free | No purchase. Connect to Mac A (it becomes the free Mac; Settings › Subscription › "Free plan's Mac: A"). Back in the picker, Mac B shows a lock. Tap B: paywall "Control all your Macs" + "The free plan works with one Mac, A" + "Use B as my free Mac". Tap it: the paywall closes and B dials. Picker now locks A; tap A: the paywall says you can change again on <today + 7 days>. Buy Pro from that paywall: it closes and A dials. |
| One Mac via QR | Free, free Mac A, scan B's pairing QR: the one-Mac paywall instead of dialling. |
| VoiceOver | A locked control reads "<feature>, Pixel Hand Pro", hint "Opens Pixel Hand Pro". |

Sandbox (TestFlight or a device build with the scheme's configuration set
to None) once the products exist in App Store Connect: repeat purchase,
trial and restore with a sandbox tester (Settings › Developer › Sandbox
Apple Account); sandbox renews monthly every 5 minutes.

## 5. Compile risks (most likely first)

1. **`.requiresPro` inside `ToolbarItem`** (`ControlToolbar`): an overlay
   button and a `.sheet` on a toolbar button. If the toolbar rejects it or
   the sheet doesn't present, move the modifier onto the
   `ToolbarItem`'s content wrapper (e.g. wrap the button in a `Group`), or
   on iOS 26 check the glass toolbar's hit testing.
2. **`if/else` in `RequiresProModifier.body`** with `.disabled`/`.overlay`
   chains: should infer `_ConditionalContent`; if the type checker is slow,
   mark `body` `@ViewBuilder` explicitly.
3. **StoreKit API names** (type-checked against stubs only):
   `transaction.offer?.type == .introductory`, `offer?.paymentMode ==
   .freeTrial` (iOS 17.2+), `Product.SubscriptionInfo.RenewalState` matched
   with `case .subscribed:`, `renewalInfo.autoRenewPreference`,
   `subscription.isEligibleForIntroOffer` (async property),
   `catch StoreKitError.userCancelled`.
4. **`@Environment(\.purchase)`** (`PurchaseAction`, iOS 17) is
   `@MainActor`; `SubscriptionStore.purchase(_:using:)` is too.
5. **`@Bindable private var store = SubscriptionStore.shared`** in a
   `ViewModifier` (for `$store.macPaywall`). If Xcode objects, use
   `@State private var store = SubscriptionStore.shared` and
   `Bindable(store).macPaywall`.
6. **`retry: { connectTo(peer) }`** in `PeerPickerView` is passed as
   `@MainActor () -> Void`; fine with the iOS 18+ SDK (`View` is
   `@MainActor`).
7. `Task.detached { [weak self] in for await … in Transaction.updates }`
   under Swift 6: `SubscriptionStore` is `@MainActor`, so `self` is
   Sendable; the loop hops with `await self?.handle(result)`.
8. `DeckHandTheme.Brand.cobalt/mint`, `DeckHandTheme.mint/warning`,
   `Radius.md`, `brandBackground()` and `DeckHandMark(size:)` are used as
   they exist on integration today.

## 6. Behaviour notes and limits

- UI gating only. A mirror already running when a trial expires runs until
  closed; it can't be restarted. The Mac answers everything it's sent.
- `.unknown` (outside `.subscriptionStore()`, e.g. previews) locks Pro
  features. Wrap previews in `.environment(\.entitlements, …)` to see them
  unlocked.
- Billing retry counts as Pro for as long as Apple retries (up to 60 days),
  per the owner's decision.
- No App Store Server Notifications, no receipt validation server:
  StoreKit 2's on-device JWS verification only.
- `AppPrivacy.md` needs no change: purchases go through Apple and nothing
  about them leaves the device to us.
- AI isn't listed on the paywall until it ships (guideline 2.3); the
  `.ai` feature is already Pro for when it does.

## 7. Needs the owner in App Store Connect

Everything is in `AppStore/Subscription.md` §1:

1. Paid Applications agreement active (under Apple review since
   2026-11-17).
2. Create group "Pixel Hand Pro" and the two subscriptions with the exact
   product IDs, prices, levels (yearly 1, monthly 2), Family Sharing on,
   2-week free introductory offer, localizations, review screenshot.
3. Turn on the billing grace period (16 days).
4. Submit both subscriptions with the next app version (first
   subscriptions are reviewed with a binary).
5. Update the product page description and App Review notes (copy in
   `Subscription.md` §2 and `StoreListing.md`).
6. Create a sandbox tester for the sandbox checks in §4.

## 8. Linux verification

```sh
swift test --package-path DeckHand/Core     # 420 tests in 72 suites, green
DeckHand/Scripts/linux-typecheck/run.sh     # Build complete, no errors
```

Lane: READY TO MERGE
