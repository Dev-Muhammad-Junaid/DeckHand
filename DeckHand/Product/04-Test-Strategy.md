# Pixel Hand test strategy

Today the only automated app tests are 12 wire-format contract tests
(`DeckHandTests/ControlMessageContractTests.swift`). There are no iOS tests and
no Mac host tests. The Loom package has its own suite (460 tests after the
merge). This plan adds coverage in the order the backlog needs it.

All new tests use **Swift Testing** (`import Testing`, `@Test("…")`,
`#expect`), never XCTest, matching `AGENTS.md`. Suites are named after the
type they cover (`ActionCodecTests`, `PairingCodeTests`).

## 1. Make most of it testable without a Mac

Cloud sessions run in Linux containers and cannot build the Xcode targets.
Ticket **PH-004** extracts a SwiftPM package, `PixelHandCore`, in
`DeckHand/Core/` (its own `Package.swift`, not the Loom package, so Loom stays
product-agnostic as `Architecture.md` requires). It holds only
Foundation-level code:

- the protocol (`ControlMessage` split by domain, framing, `hello`, receipts);
- `Action`, `KeyChord` and key-name tables;
- the deck model (`DeckDocument`, pages, migration, validation);
- context-deck resolution (which page shows for which front app);
- pairing code generation/verification (Damm), trust-record logic;
- share manifests (size limits, filename sanitising);
- AI output validation (`DeckProposal` → known IDs only);
- version compatibility rules.

No `import Loom`, SwiftUI, AppKit, UIKit or CryptoKit there. Both apps depend
on it via `project.yml`. Then `swift test --package-path DeckHand/Core` runs
on Linux and in CI's cheapest runner, and every lane can run it before
pushing.

## 2. Unit tests by area

| Area | Where | What to cover |
| --- | --- | --- |
| **Protocol** | Core | Round-trip of every case; **golden JSON fixtures** in `Core/Tests/Fixtures/protocol/*.json` (one per case, a test fails if a case has no fixture); decode rejects: nested `tracked`/`run`, unknown type, oversize strings (> 64 KB), oversize arrays (> 5,000 items); binary mirror frame header encode/decode, truncated frames, wrong magic/version. |
| **Version handshake** | Core | `hello` compatibility matrix: same, older remote, older Mac, missing fields; TXT record `ph-proto` parsing. |
| **Input** | Core + Mac | Key-name → keycode table complete for every name the remote can send (fn, F1–F20, arrows, media); `KeyChord` normalisation; scroll phase state machine (begin/changed/end always balanced, even when calls arrive out of order); `typeText` chunking. Mac: `CGEvent` construction without posting (flags, keycodes), coordinate mapping across displays of different scale. |
| **Trust / pairing** | Core + Mac | Damm check catches single-digit errors and adjacent swaps; code window expiry (5 min), single-use, 5-try lockout; trust record add/forget; handshake trust provider returns `.trusted` only for authenticated identity whose key ID matches (`DeckHandHandshakeTrustProvider`); per-capability grants enforced by the host dispatcher (a device without "See the screen" gets `refused` for capture). |
| **Context** | Mac | `ContextObserver` snapshot diffing and ID stability, with a fake `AXElementSource` protocol feeding canned trees (Save dialog, sheet, alert, nothing); stale ID → `refused`. Context-deck resolution in Core. |
| **Menu discovery** | Mac | `MenuShortcutDiscovery` against fixture menu trees: modifiers glyph parsing, submenus, separators, disabled items, item cap, per-element timeout path (fake returns `.cannotComplete`). |
| **Symbolic hot keys** | Mac | Reader returns user's bindings when SPI present, defaults when symbol lookup fails. |
| **Deck** | Core | JSON round-trip and migration v1→v2; validation (max keys, max macro steps, no `contextButton` persisted); reflow is order-preserving; per-Mac overrides. |
| **Sharing** | Core | Clipboard size limit and rate limit; filename sanitising (`../`, NUL, reserved names, 255-byte cap); approval policy table (auto-accept from trusted device under size limit, ask above 2 GB). Loom transfer resume is Loom's suite. |
| **AI** | Core | `DeckProposal` validation drops unknown IDs and caps size; NL plan → `[ActionRun]` validation (destructive set requires confirm; multi-Mac requires confirm). Model quality is evaluated separately (§6). |
| **iOS view models** | iOS test target (new, simulator) | `ControlSessionModel` message handling with a fake connection: auth state transitions, heartbeat timeout, receipt timeouts, mirror renegotiation, capture stale-token drop. |

## 3. Contract tests between the apps

- The golden fixtures are the contract. Both apps compile the same Core
  sources, so drift is impossible at build time, but the fixtures catch
  accidental *format* changes (renamed keys, changed enum raw values) that
  would break a Mac and a remote on different versions.
- Rule: changing a fixture requires bumping `PixelHandProtocol.version` and
  a line in `Core/CHANGELOG-protocol.md`. A test asserts the fixture hash list
  matches the version recorded in that file.
- A **fake host** (`Core/Tests/Support/FakeHost.swift`) and **fake remote**
  speak the protocol over an in-memory pipe, so request/response flows (auth,
  `run` → `receipt`, capture request → data, pairing) are tested without Loom.

## 4. What one Mac + the iOS Simulator can verify

The Simulator shares the Mac's network, so Bonjour discovery and a Loom session
to the host app on the same Mac work. Use this for daily end-to-end checks.

| Verifiable on one Mac + Simulator | Needs real devices |
| --- | --- |
| Discovery, version gate ("Please update"), Allow/Deny, pairing code entry | Local Network permission prompt behaviour and denial recovery |
| Shortcut chips, dialog chips, receipts (mint/red) | Multi-touch beyond 2 fingers (3/4-finger gestures), Pencil hover and pressure |
| App launcher, running apps, menu import | Haptics |
| Capture (full/region/window), OCR, annotation export | ProMotion 120 Hz input rate feel |
| Mirror (JPEG) on its own stream, cursor overlay | HEVC hardware decode performance, thermal behaviour |
| Text typing, clipboard sync | Hardware keyboard on iPad (partially in Simulator), key repeat feel |
| Deck editing, context-deck switching | Wi-Fi latency, AWDL off effect, keep-alive under radio doze |
| Layouts: every Simulator size, rotation, Split View, Stage Manager (iPad simulators) | Display wake on a real sleeping display; locked-Mac behaviour with a second account |
| Dynamic Type, VoiceOver basics (Accessibility Inspector) | Full VoiceOver pass |
| App Intents via the Shortcuts app in the Simulator | Siri voice, Control Center, Lock Screen widgets on device |
| Foundation Models if the Mac has Apple Intelligence on (Simulator uses the host model; **unverified**, check once) | Foundation Models on iPhone, performance |
| Multi-Mac: second "Mac" needs a second machine or a second host instance on another port (add a debug launch arg `-PHServiceSuffix 2`) | Real two-Mac switching and broadcast |
| – | Sparkle update from a notarized build, TestFlight install, Mac Gatekeeper first launch |

**UI tests (XCUITest, Simulator).** Add a `PixelHandUITests` target that
launches the remote with `-PHFakeHost`, which connects to an in-process fake
host instead of Loom. This tests navigation, layouts and receipts with no Mac
permissions. Keep to ~10 smoke flows; they cost CI minutes.

**CI budget.** macOS minutes are scarce (~200/month). CI runs: Core tests on
Linux on every PR (cheap); Loom tests on macOS only for PRs touching
`Sources/`, `Tests/`, `Package.*`; the app build + contract tests on macOS
only for PRs labelled `mac-ci` and on release branches. Everything else runs
on the owner's Mac.

## 5. Manual E2E checklist

Run on: iPhone (portrait + landscape), iPad (full screen, ½ Split View, Stage
Manager window), Mac on macOS 14 and on 27. Tick each for both themes where
it has visuals. "Fresh" means both apps deleted and permissions reset
(`tccutil reset All <bundle id>` on the Mac).

### A. Install, onboarding, permissions
- [ ] Mac fresh launch from the DMG: Gatekeeper accepts (notarized), first-run window shows, each permission row updates live when granted.
- [ ] Menu-bar icon appears (launched via `open`, see `MenuBarStatusItems-macOS26.md`), shows ready/request/connected states.
- [ ] Sparkle: "Check for Updates" finds a newer test build and installs it; connected remotes reconnect afterwards.
- [ ] iOS fresh install: onboarding pages, Local Network prompt, denial shows the fix; tour replay from Settings.

### B. Connect, trust, version
- [ ] Picker finds the Mac within 5 s; incompatible Mac shows "Update Pixel Hand on this Mac".
- [ ] Allow connects; Deny refuses; 45 s timeout expires; Mac relaunch prompts again (1.0).
- [ ] 1.1: pair with code, with QR; wrong code ×5 locks; Forget on each side.
- [ ] Kill the Mac app: remote returns to picker within 6 s. Kill the remote: Mac shows device gone.
- [ ] Background the remote 30 s and return: session resumes or reconnects cleanly, no false "disconnected".
- [ ] Lock the Mac: lock banner on remote, deck dimmed, password typing works, unlock restores.

### C. Trackpad and keyboard
- [ ] Move, click, double-click (exactly one double-click on the Mac), right-click (long-press), tap-hold-drag selects text and drags a window.
- [ ] Two-finger scroll with phases (rubber-band in Safari), natural scrolling toggle, sensitivity slider.
- [ ] Three-finger swipes: Spaces left/right, Mission Control, App Exposé, using the user's rebound shortcuts (change one in System Settings first).
- [ ] Type text with the on-screen keyboard (incl. emoji and an accented word); hardware keyboard on iPad with key repeat.
- [ ] Display wake: sleep the display, touch the trackpad, display wakes.

### D. Deck and context
- [ ] Shortcut chips follow the front app; tapping one turns mint; with Accessibility off it turns red and the banner appears.
- [ ] Dialog chips: unsaved TextEdit → ⌘W → Don't Save/Cancel/Save chips appear; each works; stale chip after the dialog closes is refused.
- [ ] Import menu shortcuts for a large app (Xcode, Photoshop); completes < 3 s; a hung app times out with a message.
- [ ] App launcher: launch, pin, hide, unhide; running apps in Cmd-Tab order.
- [ ] Media keys: play/pause, next, previous, volume.
- [ ] 1.2: create page, add keys from each library section, reorder, undo, per-app page auto-switch and pin, macro with delay, Mac Shortcut with timeout, "Ask before running".
- [ ] 1.2: Suggest a deck (on an AI device, and on a non-AI device with fallback).

### E. Mirror and capture
- [ ] Mirror tile: pinch to grow, sharpness tiers change, drag stays in safe area, position remembered across rotation.
- [ ] Cursor drawn on device follows the Mac pointer; shape changes over text fields.
- [ ] Display picker switches monitors; Space chevrons.
- [ ] Stats overlay values plausible (fps ≤ requested, RTT shown).
- [ ] Capture full / region / window; preview zoom; annotate and export at full resolution with correct colours; OCR; save to Photos; share.
- [ ] 1.1: HEVC tiers, keyframe recovery after Wi-Fi drop, software fallback.

### F. Sharing (1.1+)
- [ ] Mac copies text → appears on remote; Paste-on-Mac chip sends and receipts; password-manager copies are skipped.
- [ ] 1.3: send photo, file (1 GB, interrupt and resume), link; approval prompt; Inbox on iOS; `~/Downloads/Pixel Hand` on Mac; Share extension; drag onto a Mac card.

### G. Multi-Mac (1.3)
- [ ] Two Macs: switcher, overview thumbnails, per-Mac deck page, run on both with per-Mac receipts, one Mac going offline mid-run.

### H. System integration (1.2)
- [ ] Shortcuts app actions, Siri phrase, widget key, Control Center control, Spotlight result; each with Mac unreachable shows the clear error.

### I. Layout and accessibility
- [ ] Each arrangement in `03-UX-Guidelines.md` §1.2, rotating mid-session, Split View resize while the region crop is open.
- [ ] Dynamic Type xxxLarge and AX5 on the control screen, picker, settings.
- [ ] VoiceOver: connect, send a chip (outcome announced), trackpad custom actions, settings.
- [ ] Increase Contrast, Reduce Motion, Reduce Transparency, Differentiate Without Color.

### J. Privacy and diagnostics
- [ ] Sentry toggle off on both apps: no events sent (check Sentry project); on: a test crash arrives without device names.
- [ ] Export logs contains no screen content or typed text.

## 6. AI evaluation

Model behaviour is tested separately from unit tests: a fixture set of 30
apps' menu trees and 100 natural-language commands with expected
`ActionRun`s, run with the evaluation tooling on the owner's Mac against each
OS model version (Apple says to re-test prompts when the model changes).
Pass bar: ≥ 90 % exact plan match on the safe set, 100 % of destructive
commands flagged for confirmation.
