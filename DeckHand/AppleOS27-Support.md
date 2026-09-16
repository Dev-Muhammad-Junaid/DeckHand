# Deck Hand on iOS 27, iPadOS 27, and macOS 27

Status: research and plan. Nothing in this document has been implemented.

iOS 27, iPadOS 27, and macOS 27 "Golden Gate" shipped on 14 September 2026. This
document covers two separate questions that are easy to conflate:

1. **Support** — what Deck Hand must do to keep working, and to build and ship
   against the 27 SDKs. Mostly small, and less than expected.
2. **Adoption** — which new capabilities are worth taking, in what order, and
   what each one actually costs. This is where the interesting work is.

Everything marked *verified* was checked on this machine. Everything marked
*unverified* is from Apple's release notes or session material and still needs a
real test, because release notes describe intent and hardware behaves how it
behaves.

---

## Baseline, verified on this machine

| Thing | Value |
| --- | --- |
| Host OS | macOS 27.0, build 26A428 |
| Toolchain | Xcode 27.0 (27A266a), Swift 6.4 |
| macOS SDK in use | `MacOSX27.0.sdk` |
| Deck Hand deployment targets | macOS 14.0, iOS 17.4 |
| Loom package platforms | macOS 14, iOS 17.4, visionOS 2 |

**Deck Hand already compiles cleanly against the macOS 27 SDK under Swift 6.4.**
A full `DeckHandMac` build with signing disabled succeeds with zero errors and
zero warnings from Deck Hand's own sources. The only Swift warning in the entire
build comes from the vendored Loom package:

```
Sources/LoomCloudKit/Public/CloudKit/LoomCloudKitShareManager.swift:375:29:
warning: result of call to 'accept' is unused
```

This is the single most important finding here. The 27 SDK is not a porting
project for us. It is a config-and-opportunity project.

### Two environment problems that look like code problems

A normal `xcodebuild` of either target currently fails, and neither failure is
Deck Hand's fault. Both are worth writing down because both will waste an
afternoon otherwise.

**Signing.** Both targets fail with `No profiles for 'com.deckhand.mac' were
found ... Automatic signing is disabled and unable to generate a profile`. The
targets are set to automatic signing, but `xcodebuild` will not talk to the
developer portal unless you pass `-allowProvisioningUpdates`. Xcode's Run button
does this for you, which is why this only shows up from the command line.

**This Xcode install is half-upgraded.** Two symptoms:

```
CoreSimulator is out of date. Current version (1051.55.0) is older than
build version (1171.7.0). Simulator device support disabled.

No locator class for device extension 'Xcode.Device.CoreDevice' ...
dlopen(.../DVTCoreDeviceCore): Symbol not found
```

Simulator support and physical-device support are both broken in this install.
Any "it does not build on 27" report should rule this out first. Fix the install
before drawing conclusions, and re-run the build to confirm.

---

## Part 1 — What supporting the 27 releases requires

### 1.1 Nothing about the deployment floor has to move

Building against the 27 SDK does not require raising the deployment target.
Deck Hand can keep macOS 14 / iOS 17.4 and gate every new API behind
`if #available`. Adopting anything in Part 2 needs availability checks, not a
floor bump, unless we decide otherwise deliberately.

### 1.2 The hard requirements when linking against the 27 SDK — audited

Apple gates roughly a dozen behavior changes on "built with the 27.0 SDK." I
audited Deck Hand against each one that could plausibly apply. Verified by
grep across `DeckHand/`:

| Requirement | Deck Hand today | Action |
| --- | --- | --- |
| Scene-based life cycle is **mandatory** — apps built with the iOS 27 SDK that use the old app life cycle **fail to launch** | Already scene-based; SwiftUI `App` + `WindowGroup` | None |
| Launch screen key **required** or the App Store rejects the build | `DeckHandiOS/Info.plist` already has one | None |
| `UIScreen.main` misreports in resizable environments | Not used | None |
| `userInterfaceIdiom` no longer meaningful for layout | Not used | None |
| Interface-orientation checks ignored when resizable | Not used | None |
| `canOpenURL:` deprecated | Not used | None |
| Multipeer Connectivity **deprecated wholesale in Xcode 27** | Not used; Loom is Network.framework | None |
| `PreviewProvider` deprecated in favor of `#Preview` | Not used | None |
| `FileDocument` / `ReferenceFileDocument` deprecated | Not used | None |
| `-ld_classic` ignored, `-ld64` now fails to link | No custom `OTHER_LDFLAGS` | None |

Deck Hand is unusually clean here, mostly because it is a young SwiftUI codebase.

Two that need a real look rather than a grep:

- **Menu item images are hidden by default** on macOS 27 and iPadOS 27. Apps
  linked on the macOS 27 SDK lose *non-symbol* images too, and the automatic
  protection for icon-only menu items goes away — an icon-only item renders as
  nothing. The override differs per framework, which is the trap: AppKit and
  UIKit use `preferredImageVisibility` (`.automatic` / `.visible` / `.hidden`),
  **SwiftUI does not have that property** and uses `labelStyle(.titleAndIcon)`
  instead. Deck Hand's menu bar UI is a SwiftUI popover rather than an `NSMenu`,
  so this may not bite at all, but `MacMenuBarView` uses `Label(_:systemImage:)`
  and needs a visual check on 27. *Unverified.*
- **`@State` is now a Swift macro** in Xcode 27, back-deployed to iOS 17. Largely
  source-compatible, with real exceptions: assigning a `@State` property in an
  initializer when it already has a declaration-site value may no longer compile,
  and the synthesized private memberwise initializer is disabled. Our build is
  clean, so we are not hitting these today, but it is the likeliest source of a
  surprise when someone adds an initializer to a view. *Verified clean; the rule
  is worth knowing.*

### 1.3 macOS 27 is Apple Silicon only

Golden Gate drops Intel. This does not break Deck Hand — our host still targets
macOS 14 and runs on Intel — but it changes who can be on 27. Any feature we gate
behind macOS 27 is implicitly Apple Silicon only, which conveniently is also what
Core AI and the on-device models require.

### 1.4 Config changes to make

- `DeckHand/project.yml` pins `xcodeVersion: "16.0"`. Bump to `"27.0"`.
- `SWIFT_VERSION` is `6.0`; the toolchain is Swift 6.4. Leave it unless we want
  6.4 language features, but decide deliberately rather than by omission.
- Add a documented `-allowProvisioningUpdates` command-line build recipe, or an
  unsigned recipe for CI, so this failure stops being rediscovered. The README's
  build section should get whichever we pick.
- Verify the Loom package still resolves and tests under Swift 6.4, and fix the
  one `LoomCloudKitShareManager` warning while we are in there.

### 1.5 Two OS-level changes that reach every binary

These apply on a 27 device regardless of which SDK we built with:

- **Stricter TLS** for MDM, enrollment, and software-update traffic. Deck Hand
  does none of these, so this is almost certainly irrelevant — noted so it is not
  mistaken for a Loom transport issue.
- **A Neural Engine background restriction with an associated entitlement.**
  This matters only if we later run models while backgrounded. Relevant to Part 2
  and needs checking before we design around background inference. *Unverified.*

---

## Part 2 — What the 27 releases offer Deck Hand

Ordered by value to this specific app, not by how much Apple talked about them.

### 2.1 Expose Deck Hand's own actions as App Intents — highest value, lowest risk

App Intents is the single framework that feeds Shortcuts, Spotlight, Widgets,
Siri, and now Siri AI. One set of intents lights up all of them.

For Deck Hand this means things like "connect to my Mac", "capture my Mac's
screen", "start the mirror", "run this shortcut on the Mac", "lock my Mac" become
available from Spotlight, the iPad menu bar, a widget, a Control Center control,
or by voice — without opening the app and driving the trackpad.

Concretely worth adopting:

- `AppIntent` conformances for the top actions, grouped in an
  `AppShortcutsProvider` so they work the moment the app is installed.
- `AppEntity` for the things Deck Hand already models — a paired Mac, a running
  app, a window, a capture.
- **Widgets are customizable through App Intents** in the 27 releases, which is
  the cheapest way to ship a home-screen "capture my Mac" button.
- The **App Intents Testing framework** now validates an integration including UI
  automation, so this is testable rather than hope-driven.

Cost: moderate and incremental — one intent is a useful shippable unit. No new
permissions. Deployment floor unaffected for the intents themselves; some of the
Siri AI surfaces require 27.

### 2.2 Onscreen awareness — the interesting one for a remote

iPadOS 27 and iOS 27 add annotation APIs that connect what is visible on screen
to structured entities the system understands, so Siri can resolve "this" and
"that" and act on it. UIKit, AppKit, and SwiftUI all support them:

- `NSUserActivity` for a screen with one primary item.
- `.appEntityIdentifier` view annotation for one entity among many.
- `.appEntityIdentifier(forSelectionType:)` for lists and collections, which also
  lets Siri see entities that were selected and then scrolled off screen.
- Custom canvas annotations for non-standard views.
- Menus in iOS 27 automatically show an **Ask Siri** button when there is
  content relevant to Siri.

For Deck Hand this is unusually well matched: the remote is a grid of Mac apps, a
list of Mac windows, and a live mirror. Annotate the app grid and the window
picker and "close that window" or "switch to that one" becomes tractable through
the system rather than through our own command parsing.

Cost: moderate. Requires persistent entity identifiers — `TransientAppEntity`
cannot be annotated, so our entity model has to carry stable IDs, which the
bundle-ID-keyed model mostly already does.

### 2.3 Driving Mac apps by intent instead of by synthetic keystroke — read the limits first

This is the most attractive idea in this document and the one most likely to
disappoint, so the constraint goes first.

**There is no public API for one app to invoke another app's App Intents.** App
Intents are exposed to Siri, Spotlight, Shortcuts, and Widgets — not to arbitrary
third-party callers. Everything that appears to do this in the wild goes through
private WorkflowKit classes, `DYLD_INSERT_LIBRARIES` injection into
`/usr/bin/shortcuts`, or requires SIP and AMFI disabled. None of that is
shippable, and it should not go in Deck Hand.

What *is* sanctioned, and genuinely useful:

| Path | Shape | Notes |
| --- | --- | --- |
| `shortcuts run "Name"` | CLI, exit codes, stdout | Needs a logged-in GUI session. Fine for us: the host is a logged-in menu bar app. |
| `Shortcuts Events` | AppleScript / ScriptingBridge | Runs headlessly and returns results to the caller. |
| `shortcuts://run-shortcut?name=…` | URL scheme, `x-callback-url` | Apple's stated use is exactly ours: integrating from another app. |

So the realistic feature is: **the iPad browses and runs the Mac's Shortcuts.**
Any app that ships App Intents contributes Shortcuts actions automatically, which
means the user's existing shortcuts become a structured, discoverable, reliable
remote command surface — far better than sending Cmd-key sequences and hoping the
right app is frontmost.

This is a strong feature on its own terms. It is not "invoke any app's intents
directly", and the spec should not promise that.

Caveats to design around: a shortcut that prompts will hang forever, so every
invocation needs a timeout (macOS ships no `timeout(1)`); permission prompts must
be pre-authorized interactively before unattended use; and a shortcut written for
a foreground user breaks silently when run with nobody watching.

Also noted and explicitly speculative: third parties report native MCP support
being built into App Intents, spotted in a macOS 26.1 beta. If that lands
publicly it changes this section completely. Do not plan around it yet.

### 2.4 Foundation Models — natural-language control and better text handling

The 27 release of Foundation Models is substantial, and several pieces map onto
things Deck Hand already does badly or not at all:

- **`OCRTool`**, a Vision-backed built-in tool. Deck Hand already runs Vision OCR
  on captures in `OCRResultView`. Routing that through a model session upgrades
  it from "here is the text" to "answer questions about what is on my Mac's
  screen."
- **Multimodal prompting** — the on-device model now accepts images directly.
  Given that we already stream and capture the Mac's screen, this is the shortest
  path to "what is this dialog asking me?" Larger images cost more tokens and
  latency, so the mirror's existing resolution tiers become the natural knob.
- **Tool calling with `@Generable` guided generation.** This is the right shape
  for a natural-language command bar: the model emits a *typed* Swift value, and
  our `ControlMessage` enum is already that typed vocabulary. "Open Safari and
  full-screen it" becomes structured output rather than string parsing.
- **`PrivateCloudComputeLanguageModel`** — 32K context, reasoning levels, no
  account, no API key, no billing. Worth it for the occasional hard request.
- **A Spotlight-backed search tool** for fully local RAG over the Mac's index.
- **Dynamic Profiles** for swapping instructions and tools by mode, which fits an
  app with distinct trackpad / capture / mirror contexts.
- **The `fm` CLI on macOS 27**, useful for prototyping prompts before writing
  Swift.

Cost: real. Requires Apple Intelligence-capable hardware, a 27 floor for the new
pieces, prompt evaluation work, and honest UI for when the model is wrong. This
is where "make it a really powerful app" actually lives, and also where it is
easiest to ship something unreliable. The `@Generable` typed-output approach is
what keeps it honest: an unparseable response becomes a clean failure instead of
a wrong click.

Note: the on-device model **changes** when a user updates to 27, and Apple
explicitly says to re-test prompts against it. Any prompt we ship needs a
version-pinned evaluation, which is what the new evaluations framework is for.

### 2.5 Core AI — bring-your-own-model

A new framework in the 27 releases for loading, specializing, and running our own
models entirely on-device, Apple Silicon only, with a type-safe Swift API and no
token costs. Interesting for a specialized small model — for example, mapping
utterances to `ControlMessage` values without a general LLM — but this is a
research bet, not a feature. Park it behind 2.4.

### 2.6 ScreenCaptureKit — 72 new APIs, no deprecations

Directly relevant to the mirror and capture paths:

- **`SCRecordingOutput`** writes screen and audio straight to a file. Deck Hand
  could record a Mac session from the iPad without us building an encoder — we
  currently ship JPEG frames and have no recording feature at all.
- **HDR capture** via `captureDynamicRange` (`hdrLocalDisplay` /
  `hdrCanonicalDisplay`) and matching presets, plus HDR screenshots through
  `SCScreenshotManager`. macOS 27 also brings **HDR to all system UI**, so an SDR
  mirror will increasingly look wrong next to the real screen.
- **`SCStreamConfiguration.Preset`** — replaces hand-tuned config for common
  cases.
- **Typed `SCStreamError` with a `Code` enum** including `insufficientStorage`,
  `notSupported`, and `missingBackgroundMode`. Our `MirrorStreamService` error
  handling can stop pattern-matching strings.
- **`SCFrameStatus` and `SCStreamFrameInfo`** — first-class frame metadata. We
  currently hand-roll monotonic sequence numbers in `mirrorFrame(seq:data:)` to
  drop stale frames; some of that may now come from the framework.
- **`SCContentSharingPicker`** with `isAvailable` and present entry points — the
  system picker for choosing what to share, which is a better and more trusted
  window picker than our own enumeration.
- ScreenCaptureKit now spans iOS and iPadOS too, not just macOS. The
  `missingBackgroundMode` error hints at background capture rules there.

This is the highest-leverage *incremental* work: it improves an existing feature
with framework code rather than new UI. Everything here needs availability
gating, and the HDR path needs a real look at what it does to our bandwidth
budget before it goes anywhere near the default.

### 2.7 macOS 27 external display modes

macOS 27 adds broader support for external display modes and HDR throughout the
system UI. Deck Hand already has multi-display pointer handling, and the mirror
picks a display. Worth re-testing capture and coordinate mapping against the new
display modes — coordinate translation across displays with different scales is
already the fiddliest part of input injection, and this is exactly the kind of
change that breaks it quietly.

### 2.8 Transport — Network.framework, QUIC, and the Wi-Fi Aware question

Loom uses Bonjour plus direct `Network.framework` sessions, so nothing here is
urgent. What is available:

- The **Swift-concurrency Network.framework API** — `NetworkConnection`,
  `NetworkListener`, `NetworkBrowser` (26+) — plus a built-in TLV framer and a
  genuinely cheap path to **QUIC**. For a screen-mirror stream, QUIC's stream
  multiplexing is a better fit than what we do now. Apple's throughput guidance:
  chunks of at least 64 KiB, 1 MiB on fast links.
- **Wi-Fi Aware** for high-bandwidth, low-latency, encrypted peer-to-peer Wi-Fi,
  with `WAPerformanceMode.realtime`, per-access-category latency reports, and
  `.bulk` for everything else. **Wi-Fi Aware and QUIC together require iOS 27**;
  it was unsupported before.
- **Multipeer Connectivity is deprecated in Xcode 27**, which confirms
  Network.framework as the only strategic direction. We are already there.

**The catch, and it is a big one:** Apple's Wi-Fi Aware documentation lists
iOS 26+, iPadOS 26+, and Mac Catalyst 26+ — **not native macOS**. If that is
accurate, Wi-Fi Aware cannot carry a Mac-host-to-iPad connection at all, and this
entire avenue is dead for Deck Hand's topology. It also requires the
`com.apple.developer.wifi-aware` entitlement, declared services in `Info.plist`,
and explicit pairing via `DeviceDiscoveryUI` or `AccessorySetupKit`.

**Verify native macOS availability before spending a single day here.** This is
the highest-risk item in the document and the easiest to check.

### 2.9 iPadOS 27 UI changes worth taking

- **External display scenes changed shape.** `windowExternalDisplayNonInteractive`
  is no longer offered automatically; use
  `UIViewController.registerSceneAccessory(_:)` with
  `UISceneAccessory.externalNonInteractive`, or SwiftUI's `.sceneAccessory` with
  `ExternalNonInteractiveAccessory`. A genuine opportunity: put the Mac mirror on
  an external display while the trackpad stays on the iPad.
- `UISceneClosureConfirmation` — confirm before a scene goes away. Reasonable for
  an active remote session.
- Navigation bar minimization (`barMinimizeBehavior`) and
  `UIBarButtonItem.visibilityPriority` — more room for the mirror.
- Menu subtitles and `highlightStateUpdateHandler` for live previews, which suits
  the shortcut chips.
- `LabeledContent` inside a `Menu` now maps its value to the menu item subtitle.

---

## Suggested sequencing

Each phase is independently shippable and independently useful.

**Phase 0 — unblock the toolchain.** Repair the Xcode install so simulator and
device support work. Bump `xcodeVersion` in `project.yml`. Document the
`-allowProvisioningUpdates` build. Confirm both targets build *signed* on 27, run
the contract tests, and smoke-test the app on a 27 device. Fix the Loom warning.
Acceptance: signed builds and green tests on 27, no source changes required.

**Phase 1 — visual and behavioral audit on 27.** Menu images in the Mac menu bar
UI, capture and coordinate mapping against the new external display modes, mirror
appearance against HDR system UI, Liquid Glass opacity slider. Acceptance: a list
of concrete defects, or a written statement that there are none.

**Phase 2 — App Intents.** Ship three or four intents plus an
`AppShortcutsProvider`, and one widget. Acceptance: "capture my Mac" works from
Spotlight and from a widget without opening the app.

**Phase 3 — Shortcuts as the remote command surface.** Host enumerates the Mac's
shortcuts; the iPad browses and runs them with timeouts and clear failures.
Acceptance: running a real user shortcut from the iPad, including the
hang-prevention path.

**Phase 4 — ScreenCaptureKit modernization.** Typed errors, presets, frame
metadata, `SCContentSharingPicker` for the window picker; evaluate HDR and
`SCRecordingOutput` behind a setting. Acceptance: no regression in mirror latency,
plus at least one capability we did not have.

**Phase 5 — onscreen awareness and Foundation Models.** Annotate the app grid and
window picker. Prototype a natural-language command bar with `@Generable` output
into `ControlMessage`, evaluated before it ships. Acceptance: measured accuracy on
a fixed command set, and a clean failure path when the model is unsure.

Wi-Fi Aware is deliberately absent. It is gated on the macOS availability
question in 2.8; if the answer is "Mac Catalyst only", it never gets a phase.

---

## Open questions

Honest list of what I could not establish from available sources:

1. **Is Wi-Fi Aware available on native macOS?** Docs suggest iOS / iPadOS /
   Mac Catalyst only. Blocks 2.8 entirely.
2. **Did macOS 27 change the Accessibility API, `AXUIElement`, `CGEvent`
   injection, or the Accessibility and Screen Recording permission model?** I
   found no authoritative evidence either way. Given that input injection and AX
   menu reading are the foundation of this app, this is the most important
   unknown, and searching turned up only low-quality third-party material. It
   needs a direct read of the macOS 27 AppKit and Accessibility release notes,
   plus a functional test on 27.
3. **Does the bundle-identifier status-item poisoning from
   [MenuBarStatusItems-macOS26.md](MenuBarStatusItems-macOS26.md) still occur on
   27?** Same failure mode, new OS. Worth re-testing before anyone debugs a
   missing menu bar icon again.
4. **What exactly does the Neural Engine background restriction entitlement
   require?** Gates any background inference.
5. **Does the menu-image change actually affect a SwiftUI popover** rather than an
   `NSMenu`? Determines whether 1.2's second bullet is real work or a non-issue.

---

## Sources

Apple: Xcode 27, macOS 27, and iOS & iPadOS 27 release notes; What's new in
macOS 27 and iPadOS 27; ScreenCaptureKit, Foundation Models, App Intents, and
Wi-Fi Aware documentation; TN3213 (Multipeer Connectivity to Network framework),
TN3111 (iOS Wi-Fi API overview); WWDC26 sessions 240, 241, 278, 339, 343;
WWDC24 session 10088; WWDC25 sessions 228, 250.

Local verification: `sw_vers`, `xcodebuild -version`, `swift --version`, and full
builds of `DeckHandMac` and `DeckHandiOS` against `MacOSX27.0.sdk` on
16 September 2026.
