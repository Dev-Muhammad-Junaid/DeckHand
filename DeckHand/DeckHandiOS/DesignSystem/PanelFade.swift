//
//  PanelFade.swift
//  DeckHandiOS – Design system
//
//  How panels and status rows come and go under the owner's glyph rule:
//  a 180 ms ease-out fade, never a slide in from the bottom, and an instant
//  change under Reduce Motion. Timing from `ChromeRule.panelFade` in Core,
//  where tests pin it.
//

import SwiftUI

extension PixelHandMotion {
    /// The panel and status-row fade; `nil` (no animation) under Reduce
    /// Motion.
    static func panelFade(reduceMotion: Bool) -> Animation? {
        let timing = ChromeRule.panelFade(reduceMotion: reduceMotion)
        guard timing.effect != .instant else { return nil }
        return .easeOut(duration: timing.duration)
    }
}

extension View {
    /// Fades this panel or status row in and out with the rule's timing
    /// when `value` changes. Pair it with `.transition(.opacity)` on the
    /// view that appears.
    func phPanelFade<V: Equatable>(value: V) -> some View {
        modifier(PanelFadeModifier(value: value))
    }
}

private struct PanelFadeModifier<V: Equatable>: ViewModifier {
    let value: V

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(PixelHandMotion.panelFade(reduceMotion: reduceMotion), value: value)
    }
}
