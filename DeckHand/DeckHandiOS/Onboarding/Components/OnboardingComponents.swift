//
//  OnboardingComponents.swift
//  DeckHandiOS – Onboarding
//
//  Onboarding's own pieces: the bullet row and the page text transition.
//  `PageDots` and `GlyphTile` live in `DesignSystem/GlyphTile.swift`, the
//  pixel dissolve in `DesignSystem/PixelTransitions.swift`.
//

import SwiftUI

/// One onboarding bullet: glyph tile and a short line.
struct OnboardingBulletRow: View {
    let bullet: OnboardingPage.Bullet

    var body: some View {
        HStack(spacing: 12) {
            GlyphTile(glyph: bullet.glyph)
            Text(bullet.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Page text transition

/// Swaps a page's text with an 8 pt slide and a fade in the direction of
/// travel. Reduce Motion: a cross-fade. The ZStack keeps the outgoing and
/// incoming text overlapping instead of stacking.
struct PageTextTransition: ViewModifier {
    let page: Int
    let direction: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        ZStack {
            content
                .id(page)
                .transition(transition)
        }
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .offset(x: CGFloat(8 * direction)).combined(with: .opacity),
            removal: .opacity
        )
    }
}

#Preview("Bullets and dots") {
    VStack(alignment: .leading, spacing: 16) {
        OnboardingBulletRow(bullet: .init(glyph: PixelGlyphs.click, text: "Two fingers to scroll"))
        OnboardingBulletRow(bullet: .init(glyph: PixelGlyphs.missionControl, text: "Three fingers to switch desktops"))
        PageDots(count: 5, current: 1)
    }
    .padding(24)
    .background(PixelHandTheme.brandBackground())
}
