# Pixel Hand product docs

Written 16 Nov 2026 for the 1.0 plan (Option C). Other sessions build from
these files; the coordinating session owns the ticket order.

| File | What it is |
| --- | --- |
| [01-Feature-Inventory.md](01-Feature-Inventory.md) | Every feature today, Mac and iOS: how it works (file:line), assessment, bugs, fixes; Sill comparison; rename hazards |
| [02-Product-Spec.md](02-Product-Spec.md) | The product for 1.0 → 1.4: deck, AI, multi-Mac, sharing, mirror and control, system integration, onboarding, settings; owner decisions |
| [03-UX-Guidelines.md](03-UX-Guidelines.md) | Layout rules per size, tokens, components, the dot-matrix identity in new screens, accessibility |
| [04-Test-Strategy.md](04-Test-Strategy.md) | Unit and contract tests, what one Mac + Simulator can verify, manual E2E checklist |
| [05-Backlog.md](05-Backlog.md) | Tickets by milestone, lanes, hot-spot rules, week-by-week plan |

## Top recommendations

1. **Fix the host crash first.** One scroll message with a huge or NaN value
   kills the Mac app (`InputInjector.swift:144-145`). PH-031.
2. **Add typing and drag to 1.0** (≈3 days). Today you can't type a word or
   drag a window from the remote, which defeats "no need to go to the Mac".
3. **Reset and split the protocol in week 1** (PH-003/004/005/010). There
   are no users, so drop all back-compat; split `ControlMessage`,
   `ControlReceiver`, `ControlView` and `QuickActionsBar` so five lanes can
   work in parallel in week 2.
4. **Extract `PixelHandCore`** as a Foundation-only package so protocol,
   deck and pairing logic is testable on Linux in cloud sessions.
5. **One `Action` model for everything.** Deck keys, chips, Siri, widgets, AI
   and multi-Mac runs all resolve to the same typed action and receipt, so new
   features combine safely.
6. **Deck 2 before multi-Mac and AI** (1.2 → 1.3 → 1.4): every later feature
   is "run an action somewhere", so the action/deck model comes first.
7. **AI on-device only**: Foundation Models on the iPhone/iPad, else on the
   paired Mac, else a deterministic fallback; no third-party cloud.

## Milestones

- **M0 Foundation** (week 1): branches + Loom 2.2.16 merge, protocol reset,
  Core package, file splits, version handshake ("Please update"), Sparkle,
  notarized DMG, AWDL off + keep-alive.
- **M1 Quick wins and must-fix** (week 2): mirror on its own binary stream,
  cursor on device, Mission Control via real shortcuts, hardened AX menu
  reading, display wake, locked-Mac check, typing, drag, layout and
  accessibility pass, crash fixes, safer approval, stats overlay.
- **M2 Beta and release** (week 3): fake-host UI tests, TestFlight + Sparkle
  beta, full E2E pass, store submission, both apps released together.
- **1.1** HEVC + tiers, persistent pairing and My Macs, clipboard text.
- **1.2** Deck 2, App Intents/widgets/Control Center, "Suggest a deck".
- **1.3** Multi-Mac sessions and overview, sharing files/photos/links.
- **1.4** Natural-language command bar, ask about the screen.

## Decisions for the owner

See `02-Product-Spec.md` §12. In short: release order after 1.1; persistent
pairing stays in 1.1; Private Cloud Compute opt-in or never; AI via the Mac's
model; iPhone↔iPad sharing; price/trial; store name "Pixel Hand: Remote for
Mac"; typing + drag in 1.0; change all identifiers in the rename now.
