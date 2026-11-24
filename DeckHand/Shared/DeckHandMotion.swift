//
//  DeckHandMotion.swift
//  Pixel Hand – Shared
//
//  The four timings Pixel Hand animates with. They match the website's
//  motion (`website/public/styles.css`: 160 ms hovers, `--ease-spring` at
//  400 ms, `--ease-hero` at 800 ms), so the app and the site move alike.
//

import SwiftUI

enum DeckHandMotion {
    /// 160 ms. Highlights, opacity changes, press-in.
    static let tap = Animation.snappy(duration: 0.16)
    /// 400 ms with a slight overshoot. Buttons, toggles, sheets, snapping
    /// into place.
    static let spring = Animation.spring(duration: 0.4, bounce: 0.12)
    /// 800 ms ease-out. First run, the mark's entrance, approval results.
    static let reveal = Animation.smooth(duration: 0.8)
    /// A 2.4 s breathing loop for live indicators. At most one per screen.
    static let ambient = Animation.easeInOut(duration: 2.4).repeatForever(autoreverses: true)

    /// `animation`, or `nil` when Reduce Motion is on. For `withAnimation`
    /// call sites, which can't read the environment themselves:
    ///
    ///     withAnimation(DeckHandMotion.resolved(.spring, reduceMotion: reduceMotion)) { … }
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

extension View {
    /// `.animation(_:value:)` that turns itself off under Reduce Motion.
    func deckHandAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ReducedMotionAnimation(animation: animation, value: value))
    }
}

private struct ReducedMotionAnimation<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

// MARK: - Pixel Hand motion tokens (UX-001)

/// The motion tokens of the design system (`02-Design-System.md` §5) and
/// the pixel transitions' timings (`06-Pixel-Identity.md` §7), which come
/// from `PixelTransitionPlan` in Core so tests pin them. Every
/// animation reads Reduce Motion: movement becomes a 160 ms cross-fade and dot
/// effects freeze (`reduced`).
enum PixelHandMotion {
    /// 160 ms ease-out. Press states, dot changes.
    static let quick = Animation.easeOut(duration: 0.16)
    /// 240 ms. Show/hide chips, strip changes.
    static let standard = Animation.smooth(duration: 0.24)
    /// 0.4 s, bounce 0.15. Arrangement changes, docks, sheets.
    static let spring = Animation.spring(duration: 0.4, bounce: 0.15)
    /// 0.8 s, no bounce. Onboarding, pairing success.
    static let hero = Animation.spring(duration: 0.8, bounce: 0)
    /// What every movement becomes under Reduce Motion.
    static let reducedFade = Animation.easeInOut(duration: PixelTransitionPlan.reducedFadeDuration)

    /// Pixel dissolve between surfaces or Macs.
    static let dissolveDuration: Double = PixelTransitionPlan.dissolveDuration
    /// Cell size of the dissolve: 8 pt, 6 pt on compact widths.
    static let dissolveCell = CGFloat(PixelTransitionPlan.dissolveCell)
    static let dissolveCellCompact = CGFloat(PixelTransitionPlan.dissolveCellCompact)
    /// Scanline sweep when the mirror connects or changes display.
    static let scanlineDuration: Double = PixelTransitionPlan.scanlineDuration
    /// Power-on: launch, pairing success, Pro unlocked.
    static let powerOnDuration: Double = PixelTransitionPlan.powerOnDuration
    /// Delivery strip: stagger per dot, hold, hold when refused.
    static let deliveryStagger: Double = 0.045
    static let deliveryHold: Double = 0.9
    static let deliveryHoldRefused: Double = 1.4
    /// Loading dot wave period.
    static let wavePeriod: Double = 1.2
    /// Press flash of a key's or chip's glyph dots.
    static let pressFlash: Double = 0.12
    /// Empty-state accent breathing.
    static let breathe: Double = 2.4

    /// `animation`, or the 160 ms cross-fade under Reduce Motion.
    static func reduced(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedFade : animation
    }
}
