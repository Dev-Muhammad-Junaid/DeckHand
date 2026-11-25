//
//  ChromeRule.swift
//  PixelHandCore – Design
//
//  The owner's rule for glyphs, dots and loaders (owner review of the build
//  18 visual QA), as data the apps read and tests pin:
//
//  - Selection shows by colour and fill only: no dot under a selected tab,
//    chip or row.
//  - The dot-matrix loader is only for real waiting (`LoaderOccasion`).
//    Running a shortcut or chip, switching tabs or opening an app gets the
//    press highlight and a haptic, nothing else.
//  - Buttons say what they do with no trailing "…" or dots
//    (`buttonTitle(_:)`). Status text such as "Connecting…" keeps its
//    ellipsis.
//  - Panels and status rows fade in and out over 180 ms, ease-out, and
//    never slide in from the bottom. Reduce Motion changes at once
//    (`panelFade(reduceMotion:)`).
//

import Foundation

/// Why something might show the dot-matrix loader.
public enum LoaderOccasion: String, CaseIterable, Sendable {
    // Real waiting: the loader belongs here.
    /// An Ask plan running several steps.
    case askPlanRunning
    /// Waiting on the Mac to answer (a list, a capture, menus).
    case waitingOnMac
    /// A step that is stuck or slow.
    case slowStep
    /// Connecting, reconnecting or looking for Macs.
    case connecting
    /// Waiting for the camera or another system resource.
    case systemResource

    // Instant actions: press state and haptic only.
    /// Running a shortcut, a deck key or a strip chip.
    case runShortcut
    /// Switching surface tabs.
    case switchTab
    /// Opening or switching to an app on the Mac.
    case openApp
}

/// What an instant action shows when it runs.
public enum PressFeedback: Equatable, Sendable {
    /// The press highlight and a haptic; nothing stays on screen.
    case pressAndHaptic
    /// The press highlight and a haptic, then the control's outline turns
    /// danger for a moment (colour only, no dots) and VoiceOver hears why.
    case pressHapticAndFailureTint
}

public enum ChromeRule {
    /// Panel and status-row fade: 180 ms, inside the owner's 150–200 ms.
    public static let panelFadeDuration = 0.18

    /// How a panel or status row appears and disappears: a fade, never a
    /// slide. Reduce Motion is instant.
    public static func panelFade(reduceMotion: Bool) -> PixelTransitionTiming {
        reduceMotion
            ? PixelTransitionTiming(effect: .instant, duration: 0, curve: .easeOut)
            : PixelTransitionTiming(effect: .fade, duration: panelFadeDuration, curve: .easeOut)
    }

    /// Whether `occasion` may show the dot-matrix loader.
    public static func showsLoader(for occasion: LoaderOccasion) -> Bool {
        switch occasion {
        case .askPlanRunning, .waitingOnMac, .slowStep, .connecting, .systemResource:
            true
        case .runShortcut, .switchTab, .openApp:
            false
        }
    }

    /// What running a shortcut or chip shows once the Mac has answered.
    /// Only a refusal leaves a mark, and that mark is colour alone.
    public static func pressFeedback(delivered: Bool) -> PressFeedback {
        delivered ? .pressAndHaptic : .pressHapticAndFailureTint
    }

    /// `title` without a trailing "…" or "...": buttons say what they do.
    public static func buttonTitle(_ title: String) -> String {
        var result = title.trimmingCharacters(in: .whitespaces)
        while true {
            if result.hasSuffix("…") {
                result.removeLast()
            } else if result.hasSuffix("...") {
                result.removeLast(3)
            } else {
                break
            }
            result = result.trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    /// Whether `title` already follows the button rule.
    public static func isCleanButtonTitle(_ title: String) -> Bool {
        buttonTitle(title) == title
    }
}
