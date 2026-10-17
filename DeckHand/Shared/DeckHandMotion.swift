//
//  DeckHandMotion.swift
//  Deck Hand – Shared
//
//  The four timings Deck Hand animates with. They match the website's
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
