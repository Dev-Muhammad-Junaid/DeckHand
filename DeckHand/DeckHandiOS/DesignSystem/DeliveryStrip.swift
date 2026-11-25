//
//  DeliveryStrip.swift
//  DeckHandiOS – Design system
//
//  The receipt of a chip or key once the Mac answers. Under the owner's
//  glyph rule (OR-02) there is no dot row any more: running a chip or key
//  gives the press state and a haptic only. A refusal is the one thing that
//  leaves a mark, and it is colour alone: the control's outline turns
//  danger for `DeliveryState.hold`, a warning haptic plays and VoiceOver
//  hears why (`DeliveryTracker.run`). Rule: `ChromeRule.pressFeedback`.
//

import SwiftUI

extension View {
    /// Tints this chip's or key's outline danger while `state` is
    /// `.failed`. Nothing shows for sending, sent or delivered.
    func deliveryReceipt(_ state: DeliveryState, cornerRadius: CGFloat, onAccent: Bool = false) -> some View {
        modifier(DeliveryReceiptModifier(state: state, cornerRadius: cornerRadius, onAccent: onAccent))
    }
}

private struct DeliveryReceiptModifier: ViewModifier {
    let state: DeliveryState
    let cornerRadius: CGFloat
    let onAccent: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var feedback: PressFeedback {
        ChromeRule.pressFeedback(delivered: state != .failed)
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if feedback == .pressHapticAndFailureTint {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(onAccent ? Color.white : PixelHandTheme.danger, lineWidth: 2)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(PixelHandMotion.panelFade(reduceMotion: reduceMotion), value: state)
            .onChange(of: state) { _, new in
                if new == .failed { GestureHaptic.heavy.trigger() }
            }
    }
}
