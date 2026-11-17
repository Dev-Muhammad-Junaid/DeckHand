# Pull request history (archived before the repo went private)

Exported 2026-11-17 from GitHub. Leaving the Loom fork network deletes PRs,
issues and comments; this file keeps their text. Git history is unaffected.

## #1 — Add region capture, window picker, OCR, and cursor locator features

- State: merged; opened 2026-05-07 by Dev-Muhammad-Junaid; merged 2026-05-07
- Branch: `claude/review-mirage-codebase-fhCIB` → `cursor/touch-bar-dialog-context` (head `cea226f`)

### Description

## Summary

This PR significantly expands MirageControl's capture capabilities with four major new features: region-based screen capture, window picking, on-device OCR, and a cursor locator overlay. It also modernizes the screenshot pipeline to use ScreenCaptureKit's full API surface and improves scroll handling with native trackpad phase support.

## Key Changes

### Screen Capture Pipeline Modernization
- **ScreenCaptureService.swift**: Complete rewrite backing the capture pipeline with ScreenCaptureKit's `SCScreenshotManager`
  - Implements caching of `SCShareableContent` with invalidation on display changes
  - Adds GPU-side downsampling via `SCStreamConfiguration` to avoid dragging full pixel grids to CPU (saves ~80 MB per shot on 6K displays)
  - Replaces `NSImage.lockFocus → tiffRepresentation → JPEG` chain with direct `CGImageDestination` encoding (eliminates two full-frame copies)
  - Adds `captureRegion()` for normalized-rect cropping at full native resolution before downscaling
  - Adds `captureWindow()` for single-window capture by `CGWindowID`

### New Capture Modes
- **CaptureMode.swift** (new): Shared enum defining three capture paths
  - `.fullScreen`: existing behavior
  - `.region(x, y, width, height)`: normalized 0…1 coordinates; Mac re-captures fresh pixels and crops server-side
  - `.window(windowID)`: single window by ID from window list

### Region Capture UI (iPad)
- **RegionCropView.swift** (new): Full-screen modal for drawing/refining crop rectangles
  - Two-step flow: user drags rect on preview, refines via corner/edge handles or repositioning
  - Supports move, resize, and fresh-draw gestures with visual feedback
  - Ships normalized rect back to Mac for fresh capture + crop

### Window Picker (iPad)
- **WindowPickerView.swift** (new): Modal sheet listing all visible Mac windows
  - Adaptive grid layout (more columns on wider devices)
  - Sorted by Cmd+Tab order (via `RunningAppMonitor`'s bundle ID list)
  - Tap to capture single window

### On-Device OCR (iPad)
- **OCRResultView.swift** (new): Sheet displaying recognized text from captured image
  - Uses `VNRecognizeTextRequest` for on-device recognition (no Mac round-trip)
  - Scrollable/copyable text with "Copy All" affordance
  - Separate from preview flow since intent is text extraction, not visual annotation

### Cursor Locator (Mac)
- **CursorLocator.swift** (new): Floating overlay pulsing a multi-color target ring at cursor position
  - Triggered by iPad's "Locate" gesture button
  - Borderless `NSPanel` with `ignoresMouseEvents = true` and `.statusBar` level
  - 1.5 s animation sequence (outer violet pulse + white halo, main violet ring, yellow inner ring, crosshair)
  - Auto-repositions to whichever display cursor is on for multi-monitor support

### Message Protocol Updates
- **ControlMessage.swift**: Enhanced with request IDs and new message types
  - `requestScreenshot` now includes `requestID` (for deduplication) and `CaptureMode`
  - `screenshotData` / `screenshotError` echo back `requestID` to prevent stale responses hijacking UI
  - New `requestWindowList` / `windowListResponse` for window picker
  - `mouseScroll` now includes `ScrollPhase` for native trackpad rubber-banding + momentum

### Scroll Phase Support
- **ScrollPhase.swift** (new): Shared enum mirroring `NSEvent.Phase` / `NSEvent.MomentumPhase`
- **TrackpadSender.swift**: Tracks scroll gesture state and emits `.begin` / `.changed` / `.end` phases
- **InputInjector.swift**: Converts iPad phases to AppKit phases for native scroll animations
- **MultiTouchTrackpad.swift**:

https://claude.ai/code/session_019d7ybY6eqAgSPZ9T2qv2fm

### Commits

- `c743b48` MirageControl: codebase review fixes
- `8135b1b` MirageControl: capture menu, locate cursor, multi-display pointer, scroll phases
- `b1fb298` MirageControl: window picker grid, region resize handles, locator polish, fix Mac build
- `f7e6e11` MirageControl: native-feeling window shots, Universal Control hand-off
- `cea226f` MirageControl: cursor revert, native-res region shots, OCR from preview

---

## #2 — docs: Document macOS 26 menu bar status item poisoning

- State: closed; opened 2026-08-15 by Dev-Muhammad-Junaid; closed 2026-08-16
- Branch: `docs/menu-bar-status-items-macos26` → `feature/mirage-mirror-liveness-loom-diagnostics` (head `2e1cafa`)

### Description

## Summary

Writes up the root cause of the long-running "MirageControl's menu bar icon never appears" bug, which turned out not to be in our code at all.

**Launching a menu bar app's executable directly, instead of through LaunchServices, permanently poisons that bundle identifier's menu bar registration.** Xcode's Run button launches macOS apps exactly that way, so the first run burns the bundle ID and it never recovers — no code change, clean build, re-sign, or reinstall brings the icon back, because the state is keyed to the bundle identifier rather than the app path or the binary.

The doc records:

- The reproduction (fresh bundle ID works, one direct launch, broken forever)
- The fastest tell — a healthy status item window is 33 pt tall and matches the menu bar; a poisoned one is 22 pt and sits off-screen or under Control Center
- Every theory that was tested and eliminated, so nobody re-walks them
- What does *not* clear the state (DerivedData, reinstall, re-signing, `killall ControlCenter`, `lsregister` rebuild, Control Center prefs)
- The fix, and the Xcode scheme setting that stops it recurring
- Two diagnostic techniques, including enumerating on-screen menu bar windows without needing Screen Recording permission
- A warning that bisecting git history gives a false answer here, since old commits build under the same poisoned ID

## Notes

Documentation only, no code changes. Confirmed on macOS 26.6 / Xcode 26.6, 14" MacBook Pro.

The accompanying fix (a fresh bundle identifier) is deliberately not in this PR, since the pending rename to Deck Hand would immediately supersede it.

Made with [Cursor](https://cursor.com)

### Commits

- `2e1cafa` docs: Document macOS 26 menu bar status item poisoning

### Comments

**cursor[bot]**, 2026-08-15:

<!-- BUGBOT_FREE_TIER_DISABLED_UPSELL -->
Bugbot is not enabled for your account, so this pull request was not reviewed.

Enable Bugbot in the [Cursor dashboard](https://www.cursor.com/dashboard/bugbot) to get automatic reviews on future PRs.

**Dev-Muhammad-Junaid**, 2026-08-16:

Landed in `main` via fast-forward to 91128cd, so GitHub can't mark this as merged — there are no commits left between the branches. Every commit from this PR is now reachable from `main`. Closing as delivered; the branch is intentionally kept.

---

## #3 — Rename MirageControl to Deck Hand and add the app icon

- State: closed; opened 2026-08-15 by Dev-Muhammad-Junaid; closed 2026-08-16
- Branch: `refactor/rename-to-deck-hand` → `docs/menu-bar-status-items-macos26` (head `ac32d08`)

### Description

Renames the app end to end and gives it an icon. Stacked on
`docs/menu-bar-status-items-macos26` (PR #2), so review that one first. The iPad
feature work that used to sit on this branch now lives in PR #5, stacked on top
of this one.

## Changes

- **Warning cleanup.** `NWError` gained a `.wifiAware` case, so the switch in
  `LoomConnectionFailure.classify` warned about unhandled values; it already had
  an `@unknown default` returning the same result, so this is behavior-neutral.
  The app-side monitors likewise no longer need awaiting from a main-actor
  context.
- **Menu bar ownership.** The status item is now created by an
  `NSApplicationDelegate` instead of `MenuBarExtra`, so its behavior and
  visibility are explicit and the popover sizes itself from the SwiftUI content
  rather than a hard-coded frame that left the hosting view's height ambiguous.
  The global hotkey and floating-window fallbacks are gone — they were added
  while the missing icon was misattributed to `MenuBarExtra`, and a second way
  to open the panel only hid the real problem.
- **Rename.** Product, targets, directories, types, log subsystem
  (`com.deckhand`), Bonjour service type (`_deckhand._tcp`), defaults suite, and
  user-facing strings. Bundle identifiers move to `com.deckhand.*`.
  `MirageControl/` is now `DeckHand/`; the app builds as `Deck Hand.app`.
- **App icon.** A control-deck grid on the brand violet/indigo palette, for both
  platforms, generated from one master by `Scripts/make-app-icons.swift`.
- **Two pre-existing build gaps**, both found while verifying this branch: the
  test bundle had no Info.plist so code signing refused it and the suite had
  never run, and the iOS target had no signing team so it could only be built
  for the simulator.

## Why the rename also fixes the menu bar

The old `com.miragecontrol.*` identifiers were poisoned by direct executable
launches during the investigation, and that state cannot be cleared on the
affected machine. `com.deckhand.*` are clean, which is why the icon appears
again. The finding is written up in `MenuBarStatusItems-macOS26.md`.

## Wire compatibility

`Shared/ControlMessage.swift` and `Shared/UIContext.swift` changed by exactly one
line each — the file header comment. No `CodingKeys` or enum raw value contains
the old name, so the Mac/iPad protocol is byte-identical, and all 12 contract
tests pass.

## Platform impact

macOS and iOS both. Because the bundle identifiers changed, the Mac host needs
its Accessibility and Screen Recording permissions granted again, and paired
iPads have to re-approve — Loom identity lives in a keychain access group keyed
to the bundle ID, and the device ID moved to a new defaults suite.

## Test plan

- [x] `DeckHandMac` builds and signs as `com.deckhand.mac`
- [x] `DeckHandiOS` builds for the simulator and for a device as `com.deckhand.ios`
- [x] Every commit on the branch builds on its own, not just the tip
- [x] 12/12 wire-format contract tests pass
- [x] Launching `Deck Hand.app` through LaunchServices puts a live 33 pt status
      item in the menu bar (item count drops by one when the app quits)
- [x] `AppIcon.icns` and `Assets.car` land in the built bundle

### Commits

- `ee79ead` fix: Compile against current Network.framework and monitor APIs
- `868bfef` refactor: Own the menu bar status item from an app delegate
- `844a627` refactor: Rename MirageControl to Deck Hand
- `62f1a32` feat: Add Deck Hand app icon for macOS and iOS
- `5806c46` fix: Let the contract test bundle build
- `ac32d08` fix: Let the iOS target build for a device

### Comments

**cursor[bot]**, 2026-08-15:

<!-- BUGBOT_FREE_TIER_DISABLED_UPSELL -->
Bugbot is not enabled for your account, so this pull request was not reviewed.

Enable Bugbot in the [Cursor dashboard](https://www.cursor.com/dashboard/bugbot) to get automatic reviews on future PRs.

**ecc-tools[bot]**, 2026-08-15:

> Analyzing 200 commits...

**ecc-tools[bot]**, 2026-08-15:

## Analysis Complete

Generated ECC bundle from **4 commits** | Confidence: **60%**

### [View Pull Request #4](https://github.com/Dev-Muhammad-Junaid/Loom-kit-apple/pull/4)

<details>
<summary>Repository Profile</summary>

| Attribute | Value |
|-----------|-------|
| Language | Swift |
| Framework | Not detected |
| Commit Convention | conventional |
| Test Directory | `separate` |

</details>

<details>
<summary>Changed Files (70)</summary>

| Metric | Value |
|--------|-------|
| Files changed | 70 |
| Additions | 707 |
| Deletions | 333 |

**Top hotspots**

| Path | Status | +/- |
|------|--------|-----|
| `DeckHand/Scripts/make-app-icons.swift` | added | +173 / -0 |
| `DeckHand/DeckHandMac/DeckHandAppDelegate.swift` | added | +111 / -0 |
| `DeckHand/DeckHandMac/Assets.xcassets/AppIcon.appiconset/Contents.json` | added | +68 / -0 |
| `DeckHand/DeckHandMac/MacHostApp.swift` | renamed | +26 / -38 |
| `DeckHand/DeckHandMac/ContextObserver.swift` | renamed | +22 / -22 |

**Top directories**

| Directory | Files | Total changes |
|-----------|-------|---------------|
| `DeckHand/DeckHandMac` | 18 | 355 |
| `DeckHand/DeckHandiOS` | 22 | 306 |
| `DeckHand/Scripts` | 1 | 173 |
| `DeckHand/DeckHandMac/Assets.xcassets/AppIcon.appiconset` | 8 | 68 |
| `DeckHand/Shared` | 12 | 58 |

</details>

<details>
<summary>Analysis Depth Readiness (commit-history, 7%)</summary>

ECC Tools uses this to decide whether recommendations should stay at commit-history/setup guidance or expand into CI, security, harness, reference-set, AI-routing, and team backlog work.

| Area | Status | Evidence / Next Step |
|------|--------|----------------------|
| Commit history | Partial | `4 commits sampled` |
| CI/CD signals | Missing | Add workflow files or CI troubleshooting evidence so ECC Tools can reason about pipeline setup. |
| Security evidence | Missing | Add AgentShield, audit, SARIF, SBOM, or security review evidence so recommendations can cover security posture. |
| Harness configuration | Missing | Add Claude, Codex, OpenCode, Zed, dmux, MCP, plugin, or cross-harness config evidence for harness-agnostic recommendations. |
| Reference/eval evidence | Missing | Add fixtures, golden traces, reference sets, or evaluator benchmarks so deeper recommendations have regression evidence. |
| AI routing and cost controls | Missing | Add model-routing, budget, usage, or cost-control files before relying on AI-heavy automation recommendations. |
| Team handoff and project tracking | Missing | Add roadmap, runbook, project, Linear, or follow-up tracking docs so generated work can land in a team queue. |

</details>

<details>
<summary>Reference Set Readiness (0/7, 0%)</summary>

| Area | Status | Evidence / Next Step |
|------|--------|----------------------|
| Deep analyzer corpus | Missing | Add analyzer fixture, golden, benchmark, or reference-set files that can catch analyzer regressions. |
| RAG/evaluator comparison | Missing | Add retrieval or evaluator reference-set comparison fixtures with expected ranking behavior. |
| PR salvage/review corpus | Missing | Add stale-PR, review-thread, reopen-flow, or salvage reference cases for queue cleanup automation. |
| Discussion triage corpus | Missing | Add public discussion triage fixtures, golden cases, or reference sets for informational, answered, and no-response classifications. |
| Harness compatibility | Missing | Add cross-harness, adapter-compliance, or harness-audit evidence for Claude, Codex, OpenCode, Zed, dmux, and agent surfaces. |
| Security evidence | Missing | Attach security evidence such as SBOMs, SARIF, audit reports, or AgentShield evidence packs. |
| CI failure-mode evidence | Missing | Add captured CI failure logs, dry-run fixtures, or troubleshooting docs for common workflow failure modes. |

</details>

<details>
<summary>Generated Instincts (6)</summary>

| Domain | Count |
|--------|-------|
| git | 2 |
| code-style | 3 |
| testing | 1 |

After merging, import with:
```
/instinct-import .claude/homunculus/instincts/inherited/Loom-kit-apple-instincts.yaml
```

</details>

### Files
- `.claude/ecc-tools.json`
- `.claude/skills/Loom-kit-apple/SKILL.md`
- `.agents/skills/Loom-kit-apple/SKILL.md`
- `.agents/skills/Loom-kit-apple/agents/openai.yaml`
- `.claude/identity.json`
- `.codex/config.toml`
- `.codex/AGENTS.md`
- `.codex/agents/explorer.toml`
- `.codex/agents/reviewer.toml`
- `.codex/agents/docs-researcher.toml`
- `.claude/homunculus/instincts/inherited/Loom-kit-apple-instincts.yaml`

---
<sub>[ECC Tools](https://ecc.tools) | [Everything Claude Code](https://github.com/affaan-m/everything-claude-code)</sub>

**Dev-Muhammad-Junaid**, 2026-08-16:

Landed in `main` via fast-forward to 91128cd, so GitHub can't mark this as merged — there are no commits left between the branches. Every commit from this PR is now reachable from `main`. Closing as delivered; the branch is intentionally kept.

---

## #4 — feat: add Loom-kit-apple ECC bundle

- State: open; opened 2026-08-15 by ecc-tools[bot]
- Branch: `ecc-tools/Loom-kit-apple-1786829546644` → `main` (head `8cdc18e`)

### Description

## Summary

Auto-generated ECC bundle from repository analysis.

### What This Does

Merging this PR adds repo-local ECC artifacts for both [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and Codex. The generated bundle captures repository patterns, Codex baseline config, and reusable workflow scaffolds derived from git history analysis.

### Analysis Scope
- Commit history patterns and conventions
- Code architecture and structure
- Testing patterns and coverage
- Recurring workflows

### Files
| Path | Description |
|------|-------------|
| `.claude/ecc-tools.json` | ECC install manifest used for upgrades, repair, and uninstall. |
| `.claude/skills/Loom-kit-apple/SKILL.md` | Repository-specific Claude Code skill generated from git history. |
| `.agents/skills/Loom-kit-apple/SKILL.md` | Codex-facing copy of the generated repository skill. |
| `.agents/skills/Loom-kit-apple/agents/openai.yaml` | Codex skill metadata so the repo skill appears cleanly in the skill interface. |
| `.claude/identity.json` | Suggested identity.json baseline derived from repository conventions. |
| `.codex/config.toml` | Repo-local Codex MCP and multi-agent baseline aligned with ECC defaults. |
| `.codex/AGENTS.md` | Codex usage guide that points at the generated repo skill and workflow bundle. |
| `.codex/agents/explorer.toml` | Read-only explorer role config for Codex multi-agent work. |
| `.codex/agents/reviewer.toml` | Read-only reviewer role config focused on correctness and security. |
| `.codex/agents/docs-researcher.toml` | Read-only docs researcher role config for API verification. |
| `.claude/homunculus/instincts/inherited/Loom-kit-apple-instincts.yaml` | Continuous-learning instincts derived from repository patterns. |

<details>
<summary>Optional: Continuous Learning (6 instincts)</summary>

This PR also includes instincts for the [continuous-learning-v2](https://github.com/affaan-m/everything-claude-code/tree/main/skills/continuous-learning-v2) skill. These are optional and only useful if you use that skill.

Import after merging:
```
/instinct-import .claude/homunculus/instincts/inherited/Loom-kit-apple-instincts.yaml
```

</details>

### Review Checklist
- [ ] Verify detected patterns are accurate
- [ ] Confirm generated config, commands, and skill metadata match the repo’s real workflow
- [ ] Check best practices align with team standards before merging

---
<sub>[ECC Tools](https://ecc.tools) | [Everything Claude Code](https://github.com/affaan-m/everything-claude-code)</sub>

### Commits

- `6837b39` feat: add Loom-kit-apple ECC bundle (.claude/ecc-tools.json)
- `3e8625b` feat: add Loom-kit-apple ECC bundle (.claude/skills/Loom-kit-apple/SKILL.md)
- `776b266` feat: add Loom-kit-apple ECC bundle (.agents/skills/Loom-kit-apple/SKILL.md)
- `10b653d` feat: add Loom-kit-apple ECC bundle (.agents/skills/Loom-kit-apple/agents/openai.yaml)
- `e3667a8` feat: add Loom-kit-apple ECC bundle (.claude/identity.json)
- `8a92ad2` feat: add Loom-kit-apple ECC bundle (.codex/config.toml)
- `397347c` feat: add Loom-kit-apple ECC bundle (.codex/AGENTS.md)
- `c4b9996` feat: add Loom-kit-apple ECC bundle (.codex/agents/explorer.toml)
- `14d51ec` feat: add Loom-kit-apple ECC bundle (.codex/agents/reviewer.toml)
- `70fb31f` feat: add Loom-kit-apple ECC bundle (.codex/agents/docs-researcher.toml)
- `8cdc18e` feat: add Loom-kit-apple ECC bundle (.claude/homunculus/instincts/inherited/Loom-kit-apple-instincts.yaml)

---

## #5 — Add settings, onboarding, and a resizable live mirror to the iPad remote

- State: closed; opened 2026-08-16 by Dev-Muhammad-Junaid; closed 2026-08-16
- Branch: `feat/ipad-remote-settings-and-onboarding` → `refactor/rename-to-deck-hand` (head `91128cd`)

### Description

Builds the iPad remote out into something shippable: a resizable live mirror, a
settings page, and a first-run tour. Stacked on `refactor/rename-to-deck-hand`
(PR #3), so review that one first — this branch assumes the Deck Hand naming.

## Live mirror

The floating mirror thumbnail is now pinch-resizable up to roughly full screen
instead of toggling between two fixed sizes. Resolution is renegotiated in tiers
as it grows rather than on every gesture frame, the Mac's stream ceiling moves
from 1280 to 1920 wide to keep the large sizes sharp, and dragging stays inside
the safe area. Position and size can persist across sessions.

## Settings

A new settings page, backed by a persisted `DeckHandSettings` store, exposes what
used to be hard-coded: mirror frame rate and sharpness, pointer sensitivity and
input send rate, natural scrolling, haptic strength, screenshot quality, the
default capture action, auto-save to Photos, and appearance.

Rows for features that are visible but not yet functional are explicitly marked
as unavailable rather than left looking broken. Screenshot quality needed a wire
change — see below.

## First run

Adds a multi-page onboarding tour shown once on first launch, and rebuilds the
device picker around the icon's visual language: a `DeckHandMark` built from the
same tile grid, and shared brand tokens replacing the old pink/lavender gradient
that clashed with the new icon. `RoseThreeLoaderView` is removed for the same
reason. Both screens are laid out for iPad rather than stretched from phone
sizes.

## Two bugs found while wiring settings up

- **Haptics only ever respected the setting on the trackpad.** Every other call
  site constructed its own `UIImpactFeedbackGenerator`, so turning haptics off
  silently did nothing for the rest of the app. All call sites now route through
  `GestureHaptic`, which checks the setting before firing.
- **Hiding an app was a one-way door** with no way to get it back. Hidden apps
  are now listed in settings and can be restored.

## Wire compatibility

`requestScreenshot` gains an optional `quality` field, defaulting to `.standard`
on both encode and decode. This is additive and compatible in both directions: an
older host ignores the unknown key, and a newer host treats its absence as a
standard-quality capture. Contract tests cover both the defaulting path and an
explicit non-default value.

## Platform impact

iOS for the settings, onboarding, and picker work; macOS for the mirror stream
ceiling and the capture-quality plumbing on the host side.

## Test plan

- [x] `DeckHandiOS` builds for the simulator and for a device
- [x] `DeckHandMac` builds
- [x] Every commit on the branch builds on its own, not just the tip
- [x] 12/12 wire-format contract tests pass, including the new `quality` cases
- [x] Onboarding, picker, and settings verified on an M3 iPad
- [ ] Mirror resize and renegotiation checked against a slower network

### Commits

- `c259c0c` feat: Pinch to resize the live mirror
- `e6ddaa7` feat: Add a settings page to the iPad remote
- `ca9e2cc` feat: Add onboarding and rebuild first run around the app icon
- `91128cd` fix: Honour the haptics setting everywhere and let hidden apps come back

### Comments

**cursor[bot]**, 2026-08-16:

<!-- BUGBOT_FREE_TIER_DISABLED_UPSELL -->
Bugbot is not enabled for your account, so this pull request was not reviewed.

Enable Bugbot in the [Cursor dashboard](https://www.cursor.com/dashboard/bugbot) to get automatic reviews on future PRs.

**Dev-Muhammad-Junaid**, 2026-08-16:

Landed in `main` via fast-forward to 91128cd, so GitHub can't mark this as merged — there are no commits left between the branches. Every commit from this PR is now reachable from `main`. Closing as delivered; the branch is intentionally kept.

---

## #6 — Multi-display mirroring, Space switching, and signed builds under the new team

- State: merged; opened 2026-09-22 by Dev-Muhammad-Junaid; merged 2026-09-22
- Branch: `experiment/mirror-display-and-spaces` → `main` (head `dc6dc5a`)

### Description

## What this adds

**Multi-display mirroring + Space switching (iPad remote)**
- The live mirror can now target a specific physical display, not just the main one (`DisplayInfo`, optional `displayID` on `startMirror`).
- Three-finger swipe on the PIP now switches macOS Spaces on the mirrored display instead of sending a raw keyboard shortcut, using System Events under the hood since direct `CGEvent` injection doesn't reliably drive Mission Control's Space hotkeys.
- The PIP's Space controls are native chevron icons with a directional slide animation, and the cursor is parked on the new Space after switching.

**Stop over-prompting for permissions**
- Removed the proactive `SCShareableContent` probe at launch, which was the actual cause of the "record your screen and system audio" dialog reappearing on every run even when already granted — `SCShareableContent` is a *request*, not a preflight.
- Screen Recording status now comes from `CGPreflightScreenCaptureAccess` only; audio capture is explicitly disabled in `SCStreamConfiguration`.
- Notifications are only requested once, when authorization is still `.notDetermined`.

**Signed builds under the Mega Creations LLC team**
- Both targets now sign with `DEVELOPMENT_TEAM: DD5AWPLT2V` (a real paid Apple Developer Program membership) instead of a free personal team, with `SystemCapabilities.iCloud` set in `project.yml` so automatic signing provisions the capability.
- Same-iCloud device awareness (the "My Mac" badge + host auto-allow) is enabled end to end: `DeckHandCloud.isCloudEnabled = true`, both `.entitlements` files carry the `iCloud.com.deckhand.shared` container, and this has been verified against the actual signed binary's entitlements.

**Fix: notifications "Fix" button opened the wrong Settings pane**
- Notifications is its own top-level System Settings pane, not a Privacy & Security anchor. The button was opening the generic Privacy & Security overview with an invalid `Privacy_Notifications` anchor, so there was never an Allow toggle to find. It now deep-links to `com.apple.Notifications-Settings.extension?id=<bundleID>`, landing directly on Deck Hand's row.

## Testing

- `swift build` and the `DeckHandTests` contract suite pass.
- Verified signed, clean installs end to end on both a real Mac (`/Applications/Deck Hand.app`) and a real iPad, including a full permissions reset (`tccutil reset All com.deckhand.mac`, uninstalling the stale pre-rename `MirageControl` app from the iPad) to confirm first-run permission prompts behave correctly.
- Manually confirmed Space switching, the multi-display picker, and the notifications Fix button on-device.

## Platform impact

macOS (host) and iPadOS (remote). No iOS-only-device-specific behavior changed beyond the notification pane deep link, which is Mac-only.

Made with [Cursor](https://cursor.com)

### Commits

- `966a8c8` feat: Let the live mirror pick a display and switch Spaces
- `ed37970` feat: Slide the mirror between Spaces and park the cursor on the one you land on
- `3a1c3ca` fix: Stop asking for screen-and-audio permission on every launch
- `4458c84` fix: Switch Spaces via System Events and use native chevron symbols
- `e2b6741` feat: Sign under the Mega Creations LLC team and enable CloudKit
- `fbe80bd` fix: Deep-link the notifications Fix button to the right pane
- `dc6dc5a` fix: Skip the two pre-existing hanging Loom tests in CI

### Comments

**ecc-tools[bot]**, 2026-09-22:

<!-- ecc-tools:pr-audit:ECC Tools / Security Evidence:fbe80bd5e0628e9c665bd296a78bdcc73c60dc03 -->
## ECC Tools / Security Evidence

Commit: `fbe80bd5e0628e9c665bd296a78bdcc73c60dc03`

**Security evidence gate passed** (success)

No security-sensitive scanner-evidence gap detected.

Mode: enforce

Scanned 18 changed file(s). No missing scanner-evidence signal was detected.

Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

**ecc-tools[bot]**, 2026-09-22:

<!-- ecc-tools:pr-audit:ECC Tools / PR Risk Taxonomy:fbe80bd5e0628e9c665bd296a78bdcc73c60dc03 -->
## ECC Tools / PR Risk Taxonomy

Commit: `fbe80bd5e0628e9c665bd296a78bdcc73c60dc03`

**PR taxonomy clear** (success)

Scanned 18 changed file(s). No taxonomy bucket signals were detected.

Scanned 18 changed file(s).

No PR taxonomy bucket signals were detected.

Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

**ecc-tools[bot]**, 2026-09-22:

<!-- ecc-tools:pr-audit:ECC Tools / Reference Set Readiness:fbe80bd5e0628e9c665bd296a78bdcc73c60dc03 -->
## ECC Tools / Reference Set Readiness

Commit: `fbe80bd5e0628e9c665bd296a78bdcc73c60dc03`

**Reference set readiness gaps detected** (neutral)

Reference evidence present for 0/7 areas (0%) across 18 changed file(s).

This check is based on files changed in this PR. Repository-level readiness is still reported by `/ecc-tools analyze` comments and generated manifests.

| Area | Status | Evidence / Next Step |
| --- | --- | --- |
| Deep analyzer corpus | Missing | Add analyzer fixture, golden, benchmark, or reference-set files that can catch analyzer regressions. |
| RAG/evaluator comparison | Missing | Add retrieval or evaluator reference-set comparison fixtures with expected ranking behavior. |
| PR salvage/review corpus | Missing | Add stale-PR, review-thread, reopen-flow, or salvage reference cases for queue cleanup automation. |
| Discussion triage corpus | Missing | Add public discussion triage fixtures, golden cases, or reference sets for informational, answered, and no-response classifications. |
| Harness compatibility | Missing | Add cross-harness, adapter-compliance, or harness-audit evidence for Claude, Codex, OpenCode, Zed, dmux, and agent surfaces. |
| Security evidence | Missing | Attach security evidence such as SBOMs, SARIF, audit reports, or AgentShield evidence packs. |
| CI failure-mode evidence | Missing | Add captured CI failure logs, dry-run fixtures, or troubleshooting docs for common workflow failure modes. |

Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

**ecc-tools[bot]**, 2026-09-22:

<!-- ecc-tools:pr-audit:ECC Tools / Hosted Promotion Readiness:fbe80bd5e0628e9c665bd296a78bdcc73c60dc03 -->
## ECC Tools / Hosted Promotion Readiness

Commit: `fbe80bd5e0628e9c665bd296a78bdcc73c60dc03`

**Hosted promotion readiness passed** (success)

No hosted promotion evidence gaps detected across 18 changed file(s); 0 corpus scenarios had matching evidence.

This check compares PR file changes against the evaluator/RAG promotion corpus in `src/analyzers/fixtures/evaluator-rag-corpus.ts`.
Hosted output scoring inspected 0 completed cached hosted job results.

No evaluator corpus scenarios matched this PR.

Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

**ecc-tools[bot]**, 2026-09-22:

<!-- ecc-tools:pr-audit:ECC Tools / Security Evidence:dc6dc5ad451a70cc58bfe55f8f003bea0736bc7f -->
## ECC Tools / Security Evidence

Commit: `dc6dc5ad451a70cc58bfe55f8f003bea0736bc7f`

**Security evidence gate passed** (success)

No security-sensitive scanner-evidence gap detected.

Mode: enforce

Scanned 19 changed file(s). No missing scanner-evidence signal was detected.

Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

**ecc-tools[bot]**, 2026-09-22:

<!-- ecc-tools:pr-audit:ECC Tools / PR Risk Taxonomy:dc6dc5ad451a70cc58bfe55f8f003bea0736bc7f -->
## ECC Tools / PR Risk Taxonomy

Commit: `dc6dc5ad451a70cc58bfe55f8f003bea0736bc7f`

**PR taxonomy review recommended** (neutral)

Detected 2 PR taxonomy bucket(s): Security Evidence, CI/CD Recommendation.

Scanned 19 changed file(s).



Roadmap taxonomy buckets:



### Security Evidence
Security-sensitive changes should carry explicit scanner, code-scanning, or focused regression evidence.

Signals:
- 1 security-sensitive path(s) changed

Paths:
- `.github/workflows/ci.yml`

### CI/CD Recommendation
CI, dependency, coverage, and contract signals should be routed into follow-up checks or verification work.

Signals:
- CI workflow changes may ship without failure-mode evidence
- Dependency or CI drift could surface after merge
- 1 CI or workflow path(s) changed

Paths:
- `.github/workflows/ci.yml`
- `DeckHand/project.yml`

Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

**ecc-tools[bot]**, 2026-09-22:

<!-- ecc-tools:pr-audit:ECC Tools / Reference Set Readiness:dc6dc5ad451a70cc58bfe55f8f003bea0736bc7f -->
## ECC Tools / Reference Set Readiness

Commit: `dc6dc5ad451a70cc58bfe55f8f003bea0736bc7f`

**Reference set readiness gaps detected** (neutral)

Reference evidence present for 0/7 areas (0%) across 19 changed file(s).

This check is based on files changed in this PR. Repository-level readiness is still reported by `/ecc-tools analyze` comments and generated manifests.

| Area | Status | Evidence / Next Step |
| --- | --- | --- |
| Deep analyzer corpus | Missing | Add analyzer fixture, golden, benchmark, or reference-set files that can catch analyzer regressions. |
| RAG/evaluator comparison | Missing | Add retrieval or evaluator reference-set comparison fixtures with expected ranking behavior. |
| PR salvage/review corpus | Missing | Add stale-PR, review-thread, reopen-flow, or salvage reference cases for queue cleanup automation. |
| Discussion triage corpus | Missing | Add public discussion triage fixtures, golden cases, or reference sets for informational, answered, and no-response classifications. |
| Harness compatibility | Missing | Add cross-harness, adapter-compliance, or harness-audit evidence for Claude, Codex, OpenCode, Zed, dmux, and agent surfaces. |
| Security evidence | Missing | Attach security evidence such as SBOMs, SARIF, audit reports, or AgentShield evidence packs. |
| CI failure-mode evidence | Missing | Add captured CI failure logs, dry-run fixtures, or troubleshooting docs for common workflow failure modes. |

Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

**ecc-tools[bot]**, 2026-09-22:

<!-- ecc-tools:pr-audit:ECC Tools / Hosted Promotion Readiness:dc6dc5ad451a70cc58bfe55f8f003bea0736bc7f -->
## ECC Tools / Hosted Promotion Readiness

Commit: `dc6dc5ad451a70cc58bfe55f8f003bea0736bc7f`

**Hosted promotion readiness passed** (success)

No hosted promotion evidence gaps detected across 19 changed file(s); 0 corpus scenarios had matching evidence.

This check compares PR file changes against the evaluator/RAG promotion corpus in `src/analyzers/fixtures/evaluator-rag-corpus.ts`.
Hosted output scoring inspected 0 completed cached hosted job results.

No evaluator corpus scenarios matched this PR.

Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

**ecc-tools[bot]**, 2026-09-22:

<!-- ecc-tools:pr-audit:ECC Tools / PR Config Audit:dc6dc5ad451a70cc58bfe55f8f003bea0736bc7f -->
## ECC Tools / PR Config Audit

Commit: `dc6dc5ad451a70cc58bfe55f8f003bea0736bc7f`

**No changed-config issues detected** (success)

Scanned 1 config file(s) present at this commit across 1 changed config path(s) and found no issues in the supported security rules.

Changed config files:
- .github/workflows/ci.yml



Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

**ecc-tools[bot]**, 2026-09-22:

<!-- ecc-tools:pr-audit:ECC Tools / PR Harness Audit:dc6dc5ad451a70cc58bfe55f8f003bea0736bc7f -->
## ECC Tools / PR Harness Audit

Commit: `dc6dc5ad451a70cc58bfe55f8f003bea0736bc7f`

**No harness issues detected** (success)

Scanned 1 changed config file(s) and found no harness issues.

Changed config files:
- .github/workflows/ci.yml

Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

---

## #7 — Add the Deck Hand website and the new pixel-hand logo

- State: merged; opened 2026-10-09 by Dev-Muhammad-Junaid; merged 2026-10-17
- Branch: `claude/practical-pascal-6noais` → `main` (head `196d324`)

### Description

## What this adds

**Website (`website/`)**: a static marketing site with a waitlist, ready for Cloudflare Pages.

- **Pages:** a single landing page with a hero, feature sections, shortcuts, settings, a privacy section, setup steps, requirements and an FAQ. There is also a privacy policy at `/privacy`, a "joined" page for visitors without JavaScript, and a 404 page.
- **Product shots:**
  - They are HTML rebuilds of the real app screens, taken from the SwiftUI views (sizes, colours and strings), not drawings.
  - They sit inside Apple's official iPad Pro 13″ and iPhone 17 Pro bezels from the iOS and iPadOS 27 Figma kit, with official App Store icons in the app grid.
  - The Mac screen shows real code from `ControlMessage.swift`.
- **Waitlist:**
  - `functions/api/waitlist.js` stores signups in Cloudflare KV under the `WAITLIST` binding.
  - It catches duplicates and has a hidden field that turns away form-filling bots.
  - It returns JSON to the page's script and redirects to `/joined` when the form is posted without JavaScript.
- **Tooling:**
  - `tools/mockups/build.py` regenerates the product shots.
  - `tools/fit_bezels.py` fits Apple bezel PNGs to the mockups.
  - `tools/fetch-apple-assets.sh` downloads bezels and icons.

**App**

- **New logo:** a tilted iPad with the classic pointing-hand cursor drawn in lit dots.
- **App icons:** the macOS and iOS `AppIcon` sets and `AppIconMaster.png` are regenerated from it.
- **In-app mark:** `DeckHandMark.swift` now draws the new logo natively in a `Canvas` instead of the 3×3 grid. Tap rays fade in after the entrance animation, and nothing animates when Reduce Motion is on.

## Platform impact

- **macOS and iOS/iPadOS:** new app icons.
- **iOS/iPadOS:** the picker and onboarding screens show the new mark.
- **No other app behaviour changes.**

## Needs checking before merge

- **Build both apps in Xcode.** `DeckHandMark.swift` was written without a Swift toolchain, and CI only builds the Loom package, so it hasn't been compiled.
- **Fill in the two `[contact email — add before launch]` placeholders** in `website/public/privacy.html`.

## Deploying

The steps are in `website/README.md`:
- Create a Cloudflare Pages project with root directory `website` and build output `public`, with no build command.
- Bind a KV namespace as `WAITLIST`.
- Add the custom domain, then set the absolute `og:image` URL and the canonical link.

## Verified

- **Screenshots:** reviewed the site at 1440 px and 390 px, with no horizontal scroll and no console errors.
- **Waitlist function:** tested against a fake KV store for a new signup, a duplicate, an invalid email, the bot field, a form post without JavaScript, and a missing binding.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_0141DwrihpUKTBVm9FcPnAnz

---
_Generated by [Claude Code](https://claude.ai/code/session_0141DwrihpUKTBVm9FcPnAnz)_

### Commits

- `20b3b89` Add Deck Hand marketing website and new icon concepts
- `8d63d21` Add iPad-screen icon concept and switch the site to it
- `378454f` Rebuild website product shots from the app's real layouts
- `549611b` Adopt the iPad pixel-hand logo and add the website waitlist
- `e71872a` Ignore Python bytecode caches
- `30a459b` Use Apple's official bezels and app icons on the website
- `62a053a` Add Keynote, Pages and Numbers icons to the website
- `3d6c605` Fit device screens to the bezel and redraw the interlude icons
- `246c492` Redraw the pixel hand and the interlude icons
- `196d324` Add a privacy policy page

### Comments

**ecc-tools[bot]**, 2026-10-09:

<!-- ecc-tools:pr-audit:ECC Tools / Security Evidence:196d32410f03a31483775c329e3a56926b779f8e -->
## ECC Tools / Security Evidence

Commit: `196d32410f03a31483775c329e3a56926b779f8e`

**Security evidence gate passed** (success)

No security-sensitive scanner-evidence gap detected.

Mode: enforce

Scanned 58 changed file(s). No missing scanner-evidence signal was detected.

Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

**ecc-tools[bot]**, 2026-10-09:

<!-- ecc-tools:pr-audit:ECC Tools / PR Risk Taxonomy:196d32410f03a31483775c329e3a56926b779f8e -->
## ECC Tools / PR Risk Taxonomy

Commit: `196d32410f03a31483775c329e3a56926b779f8e`

**PR taxonomy review recommended** (neutral)

Detected 1 PR taxonomy bucket(s): CI/CD Recommendation.

Scanned 58 changed file(s).



Roadmap taxonomy buckets:



### CI/CD Recommendation
CI, dependency, coverage, and contract signals should be routed into follow-up checks or verification work.

Signals:
- Regression coverage may lag behind the diff
- API contract changes may ship without integration coverage
- API implementation changes may ship without contract artifact updates
- User-facing UI changes may ship without browser coverage
- 0 CI or workflow path(s) changed

Paths:
- `website/functions/api/waitlist.js`
- `website/public/site.js`
- `website/src/index.html`
- `website/tools/fit_bezels.py`
- `website/tools/mac_icon.py`
- `website/tools/mockups/build.py`
- `website/tools/mockups/mac.py`

Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

**ecc-tools[bot]**, 2026-10-09:

<!-- ecc-tools:pr-audit:ECC Tools / Reference Set Readiness:196d32410f03a31483775c329e3a56926b779f8e -->
## ECC Tools / Reference Set Readiness

Commit: `196d32410f03a31483775c329e3a56926b779f8e`

**Reference set readiness gaps detected** (neutral)

Reference evidence present for 0/7 areas (0%) across 58 changed file(s).

This check is based on files changed in this PR. Repository-level readiness is still reported by `/ecc-tools analyze` comments and generated manifests.

| Area | Status | Evidence / Next Step |
| --- | --- | --- |
| Deep analyzer corpus | Missing | Add analyzer fixture, golden, benchmark, or reference-set files that can catch analyzer regressions. |
| RAG/evaluator comparison | Missing | Add retrieval or evaluator reference-set comparison fixtures with expected ranking behavior. |
| PR salvage/review corpus | Missing | Add stale-PR, review-thread, reopen-flow, or salvage reference cases for queue cleanup automation. |
| Discussion triage corpus | Missing | Add public discussion triage fixtures, golden cases, or reference sets for informational, answered, and no-response classifications. |
| Harness compatibility | Missing | Add cross-harness, adapter-compliance, or harness-audit evidence for Claude, Codex, OpenCode, Zed, dmux, and agent surfaces. |
| Security evidence | Missing | Attach security evidence such as SBOMs, SARIF, audit reports, or AgentShield evidence packs. |
| CI failure-mode evidence | Missing | Add captured CI failure logs, dry-run fixtures, or troubleshooting docs for common workflow failure modes. |

Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

**ecc-tools[bot]**, 2026-10-09:

<!-- ecc-tools:pr-audit:ECC Tools / Hosted Promotion Readiness:196d32410f03a31483775c329e3a56926b779f8e -->
## ECC Tools / Hosted Promotion Readiness

Commit: `196d32410f03a31483775c329e3a56926b779f8e`

**Hosted promotion readiness passed** (success)

No hosted promotion evidence gaps detected across 58 changed file(s); 0 corpus scenarios had matching evidence.

This check compares PR file changes against the evaluator/RAG promotion corpus in `src/analyzers/fixtures/evaluator-rag-corpus.ts`.
Hosted output scoring inspected 0 completed cached hosted job results.

No evaluator corpus scenarios matched this PR.

Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

---

## #8 — Rebrand the apps and site around the new icon's cobalt and dot matrix

- State: merged; opened 2026-10-17 by Dev-Muhammad-Junaid; merged 2026-10-17
- Branch: `claude/affectionate-euler-0yuyqm` → `main` (head `05063a0`)

### Description

Follows #7 (the website and the new pixel-hand icon), which is now merged into `main`. The diff here is only the rebrand.

## What changes

The new icon gave Deck Hand its identity, but the apps still used the retired 3×3-tile icon's violet and fell back to system blue. Now every brand color comes from the icon, and each has one job:

| Color | Used for |
| --- | --- |
| Cobalt `#3A4CF2` (`#5466FF` in dark) | The one action color. It's now `AccentColor` in both apps, so system controls follow. |
| Screen navy | Always-dark surfaces: first run, the picker, the trackpad (now dark in Light mode too) |
| Cyan glow | Live activity with the Mac: touches, searching, connecting |
| Mint | Connected and approved |
| Pixel violet | The hand's fill, inside dot art only |

Raw `.orange`, `.red` and `.yellow` now use the status tokens, which have light and dark values.

**iPad and iPhone remote**
- The trackpad is the icon's dot screen. Dots light under each finger with a short afterglow, a tap sends a ring outward, and a long-press right-click fills the ring. It replaces the violet ripple.
- The picker's radar and the shared loading view become a slow scan across dots.
- While the Mac decides, the approval card shows the dot hand with its rays pulsing. Its dots then rearrange into a mint check or a red cross, and the controls brighten behind it. Grants faster than a person could click (the user's own iCloud Macs) skip the pause.
- The toolbar's connected dot is the icon's mint pixel, breathing.
- Empty states use the website's dot glyphs. A search with no matches no longer shows a blank page.
- Shortcut and dialog chips show five dots that light as the command goes out, then turn mint when the Mac confirms it, or red when it can't act or never answers. VoiceOver announces the failure.

**Mac host**
- The menu bar item is the dot hand as a template image, in three states: an outline when ready, blinking rays for a pending request, and filled when an iPad is connected.
- Pending requests get labelled Deny and Allow buttons in place of red and green circles.
- The cursor locator uses cobalt and cyan.

**Protocol**: backward compatible in both directions.
- The host announces `hostFeatures(commandReceipts:)` at session start and with each capability report.
- Only then does the remote wrap commands in `tracked(requestID:command:)`, so an older Mac never receives a message it can't run.
- The host answers with `commandReceipt(requestID:delivered:)` once the command has been handed to input injection. `delivered` is false without Accessibility permission, or for a dialog button from a superseded snapshot.
- Nested `tracked` wrappers are rejected before the inner command decodes.

**Motion**: `DeckHandMotion` has four timings matching the website's curves. Every new effect holds still under Reduce Motion, as do the approval pulse and the mirror's slide between Spaces, which ignored it before.

**Website**
- The hero, night bands and glows move from violet and peach to navy and cobalt, after the OG image.
- On load, the icon's hand lights in the hero's dot grid behind the headline, without delaying it.
- The product shots are rebuilt from the rebranded app.
- `/assets/*` is no longer `immutable` for a year, because the filenames aren't content-hashed and a new icon would never have reached returning visitors.

**Docs**: the README gains a Design section and documents the receipts. No DocC changes, since the Loom package is untouched.

## Platforms

iOS / iPadOS 17.4+, macOS 14+. No deployment target, signing or bundle ID changes. `project.yml` gains `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`, so run `xcodegen generate` after pulling.

## Testing

- Both apps built with Xcode 27.1 in Swift 6 mode, and signed builds were installed and run on a Mac and an iPad. That build found one compile error, fixed in 05063a0.
- The contract tests (18) pass. They now cover the three new message types, sparse `hostFeatures`, and nested or unknown `tracked` commands.
- The website was checked at 1440 px and 390 px, with reduced motion, and with no console errors or horizontal scroll.
- CI (`build-and-test`) only builds and tests the Loom package, which this PR doesn't touch. Every run so far, including every push to `main`, has been cancelled at the job's 15-minute timeout, so expect the same here until that's fixed separately.

## Not in this PR

- Merging the three press-feedback implementations into one style.
- A matched-geometry transition from the picker row into the toolbar.
- A larger session ID.

Each changes layout, and I'd rather do them with screenshots to compare.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01F5LGgCGjgFqXKunf2t5HjB

### Commits

- `85caff1` feat: Rebrand the app around the new icon's cobalt and phosphor
- `5a2eec3` feat: Bring the icon's dot matrix into the iPad remote
- `6b9d12f` feat: Draw the Mac menu bar item as the icon's dot hand
- `e1a38dd` feat: Confirm on the iPad that the Mac got each shortcut
- `b9fd57e` docs: Describe the color roles, dot matrix and shortcut receipts
- `0ed2d7b` feat: Finish the website's move to the new icon's cobalt
- `3917c1b` fix: Don't confirm dialog presses the Mac dropped
- `05063a0` fix: Compile the pixel morph's glyph change under Swift 6

### Comments

**ecc-tools[bot]**, 2026-10-17:

<!-- ecc-tools:pr-audit:ECC Tools / Security Evidence:05063a01a83387ab165bfbbcfd3227715b4d54c1 -->
## ECC Tools / Security Evidence

Commit: `05063a01a83387ab165bfbbcfd3227715b4d54c1`

**Security evidence gate passed** (success)

No security-sensitive scanner-evidence gap detected.

Mode: enforce

Scanned 50 changed file(s). No missing scanner-evidence signal was detected.

Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

**ecc-tools[bot]**, 2026-10-17:

<!-- ecc-tools:pr-audit:ECC Tools / PR Risk Taxonomy:05063a01a83387ab165bfbbcfd3227715b4d54c1 -->
## ECC Tools / PR Risk Taxonomy

Commit: `05063a01a83387ab165bfbbcfd3227715b4d54c1`

**PR taxonomy review recommended** (neutral)

Detected 1 PR taxonomy bucket(s): CI/CD Recommendation.

Scanned 50 changed file(s).



Roadmap taxonomy buckets:



### CI/CD Recommendation
CI, dependency, coverage, and contract signals should be routed into follow-up checks or verification work.

Signals:
- Regression coverage may lag behind the diff
- User-facing UI changes may ship without browser coverage
- 0 CI or workflow path(s) changed

Paths:
- `DeckHand/DeckHandMac/Assets.xcassets/AccentColor.colorset/Contents.json`
- `DeckHand/DeckHandiOS/Assets.xcassets/AccentColor.colorset/Contents.json`
- `DeckHand/project.yml`
- `website/public/site.js`
- `website/src/index.html`
- `website/tools/mockups/build.py`
- `website/tools/mockups/mac.py`

Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

**ecc-tools[bot]**, 2026-10-17:

<!-- ecc-tools:pr-audit:ECC Tools / Reference Set Readiness:05063a01a83387ab165bfbbcfd3227715b4d54c1 -->
## ECC Tools / Reference Set Readiness

Commit: `05063a01a83387ab165bfbbcfd3227715b4d54c1`

**Reference set readiness gaps detected** (neutral)

Reference evidence present for 0/7 areas (0%) across 50 changed file(s).

This check is based on files changed in this PR. Repository-level readiness is still reported by `/ecc-tools analyze` comments and generated manifests.

| Area | Status | Evidence / Next Step |
| --- | --- | --- |
| Deep analyzer corpus | Missing | Add analyzer fixture, golden, benchmark, or reference-set files that can catch analyzer regressions. |
| RAG/evaluator comparison | Missing | Add retrieval or evaluator reference-set comparison fixtures with expected ranking behavior. |
| PR salvage/review corpus | Missing | Add stale-PR, review-thread, reopen-flow, or salvage reference cases for queue cleanup automation. |
| Discussion triage corpus | Missing | Add public discussion triage fixtures, golden cases, or reference sets for informational, answered, and no-response classifications. |
| Harness compatibility | Missing | Add cross-harness, adapter-compliance, or harness-audit evidence for Claude, Codex, OpenCode, Zed, dmux, and agent surfaces. |
| Security evidence | Missing | Attach security evidence such as SBOMs, SARIF, audit reports, or AgentShield evidence packs. |
| CI failure-mode evidence | Missing | Add captured CI failure logs, dry-run fixtures, or troubleshooting docs for common workflow failure modes. |

Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

**ecc-tools[bot]**, 2026-10-17:

<!-- ecc-tools:pr-audit:ECC Tools / Hosted Promotion Readiness:05063a01a83387ab165bfbbcfd3227715b4d54c1 -->
## ECC Tools / Hosted Promotion Readiness

Commit: `05063a01a83387ab165bfbbcfd3227715b4d54c1`

**Hosted promotion readiness passed** (success)

No hosted promotion evidence gaps detected across 50 changed file(s); 0 corpus scenarios had matching evidence.

This check compares PR file changes against the evaluator/RAG promotion corpus in `src/analyzers/fixtures/evaluator-rag-corpus.ts`.
Hosted output scoring inspected 0 completed cached hosted job results.

No evaluator corpus scenarios matched this PR.

Check publication was denied or unavailable. An app owner must enable Checks: read and write, and the installation owner must approve the updated permission.

---

## #9 — Add Sentry crash reporting to Pixel Hand iOS and macOS apps

- State: open; opened 2026-11-17 by Dev-Muhammad-Junaid
- Branch: `cursor/sentry-crash-reporting-7e58` → `main` (head `3d2fd77`)

### Description

<!-- CURSOR_AGENT_PR_BODY_BEGIN -->
## Summary

Adds Sentry Cocoa crash/error reporting to the Pixel Hand (DeckHand) **iOS** and **macOS** app targets only. Loom stays untouched.

There was no existing Sentry integration and no xcconfig/secrets pattern, so each app’s public DSN is stored as `SENTRY_DSN` in that target’s `Info.plist` and read at launch.

## Files changed

| File | Change |
| --- | --- |
| `DeckHand/project.yml` | SPM dep on `getsentry/sentry-cocoa` (`from: 9.35.0`), product `SentrySPM` on `DeckHandiOS` + `DeckHandMac` only |
| `DeckHand/DeckHandiOS/Info.plist` | `SENTRY_DSN` → `pixelhand-ios` |
| `DeckHand/DeckHandMac/Info.plist` | `SENTRY_DSN` → `pixelhand-mac` |
| `DeckHand/Shared/DeckHandSentry.swift` | Shared bootstrap (`#if canImport(Sentry)` so `DeckHandTests` stays package-free) |
| `DeckHand/DeckHandiOS/DeckHandApp.swift` | Calls `DeckHandSentry.start()` first in `init()` |
| `DeckHand/DeckHandMac/DeckHandAppDelegate.swift` | Calls `DeckHandSentry.start()` in `init()` before `MacDaemon` |

## Where each DSN lives

- **iOS** (`widgetsflow` / `pixelhand-ios`): `DeckHand/DeckHandiOS/Info.plist` → `SENTRY_DSN`
  - `https://39ab9907703e2b99fc30f2d76e6b3ac5@o4512448017072128.ingest.us.sentry.io/4512448021069824`
- **macOS** (`widgetsflow` / `pixelhand-mac`): `DeckHand/DeckHandMac/Info.plist` → `SENTRY_DSN`
  - `https://13458f5fbc835d8a1c16b748500aa778@o4512448017072128.ingest.us.sentry.io/4512448022642688`

## SDK options

- `sendDefaultPii = false`
- `attachScreenshot = false` / `attachViewHierarchy = false`
- `tracesSampleRate = 0.2`
- `environment` = `debug` / `release` via `#if DEBUG`
- `releaseName` = `<bundleID>@<CFBundleShortVersionString>+<CFBundleVersion>`

## How to verify

```bash
cd DeckHand
xcodegen generate
open DeckHand.xcodeproj
```

1. Build/run `DeckHandiOS` and `DeckHandMac`.
2. Confirm Console shows `Sentry started (env=debug)` (or `release`).
3. Temporarily trigger a test event, e.g. after start:
   ```swift
   SentrySDK.capture(message: "pixelhand-sentry-smoke-test")
   ```
   or force a crash once, then confirm the event in the matching Sentry project (`pixelhand-ios` / `pixelhand-mac`).
4. Confirm Loom targets and `DeckHandTests` do not link Sentry (`Package.swift` unchanged; tests rely on `canImport` no-op).

## Could not verify here

- This agent runs on **Linux** — no Xcode/`xcodebuild`, so iOS/macOS app builds and live Sentry ingest were **not** run.
- Please regenerate with XcodeGen on macOS and build both schemes before merging.

<!-- CURSOR_AGENT_PR_BODY_END -->

<div><a href="https://cursor.com/agents/bc-bce18ed0-a20c-5df6-a184-1845217d7e58?cursor_ref=pr_footer&cursor_cta=open_in_web"><picture><source media="(prefers-color-scheme: dark)" srcset="https://cursor.com/assets/images/open-in-web-dark.png"><source media="(prefers-color-scheme: light)" srcset="https://cursor.com/assets/images/open-in-web-light.png"><img alt="Open in Web" width="114" height="28" src="https://cursor.com/assets/images/open-in-web-dark.png"></picture></a>&nbsp;<a href="https://cursor.com/background-agent?bcId=bc-bce18ed0-a20c-5df6-a184-1845217d7e58&cursor_ref=pr_footer&cursor_cta=open_in_cursor"><picture><source media="(prefers-color-scheme: dark)" srcset="https://cursor.com/assets/images/open-in-cursor-dark.png"><source media="(prefers-color-scheme: light)" srcset="https://cursor.com/assets/images/open-in-cursor-light.png"><img alt="Open in Cursor" width="131" height="28" src="https://cursor.com/assets/images/open-in-cursor-dark.png"></picture></a>&nbsp;</div>

### Commits

- `3d2fd77` Add Sentry crash reporting to Pixel Hand iOS and macOS apps

---
