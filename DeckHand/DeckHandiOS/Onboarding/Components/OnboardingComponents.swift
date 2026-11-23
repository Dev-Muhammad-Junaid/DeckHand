//
//  OnboardingComponents.swift
//  DeckHandiOS – Onboarding
//
//  Small pieces shared by onboarding, the Mac picker and pairing: square
//  page dots, the 30 pt navy glyph tile used for bullets, the page text
//  transition and the pixel dissolve. Kept here rather than in
//  `DesignSystem/` because they belong to this lane; promote them later if
//  other surfaces need them.
//

import SwiftUI

// MARK: - Page dots

/// 6 pt square page dots; the current one phosphor with a glow. Decorative:
/// the dot-matrix counter carries the spoken step.
struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                    .fill(index == current ? PixelHandTheme.Brand.phosphor : Color.white.opacity(0.22))
                    .frame(width: 6, height: 6)
                    .shadow(color: index == current ? PixelHandTheme.Brand.glow.opacity(0.9) : .clear, radius: 3)
            }
        }
        .animation(PixelHandMotion.standard, value: current)
        .accessibilityHidden(true)
    }
}

// MARK: - Glyph tile

/// A navy tile with a pixel glyph: 30 pt for bullets, larger for header
/// buttons. The glyph's accent dot glows cyan.
struct GlyphTile: View {
    let glyph: GlyphBitmap
    var side: CGFloat = 30
    var pitch: CGFloat = 2
    var tint: Color = Color(red: 0.81, green: 0.88, blue: 1)

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At AX sizes the tile grows with the glyph's stepped pitch.
        let stepped = CGFloat(PixelPitch.stepped(Double(pitch), for: typeSize.typeBand))
        let side = max(self.side, CGFloat(PixelPitch.glyphSide(Double(stepped))) + 12)
        PHGlyph(glyph: glyph, pitch: stepped)
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
                    .fill(PixelHandTheme.Brand.screenRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
                    .strokeBorder(PixelHandTheme.Brand.tileStroke, lineWidth: 1)
            )
            .pixelOnNavy()
            .accessibilityHidden(true)
    }
}

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

// MARK: - Pixel dissolve

extension AnyTransition {
    /// The view appears and disappears cell by cell in a scattered order, on
    /// an 8 pt grid (`PixelHandMotion.dissolveCell`).
    static var pixelDissolve: AnyTransition {
        .modifier(
            active: PixelDissolveModifier(progress: 0),
            identity: PixelDissolveModifier(progress: 1)
        )
    }
}

/// Masks the view to the cells whose scattered rank is below `progress`.
struct PixelDissolveModifier: ViewModifier, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let progress = self.progress
        // Always masked (a full mask at 1) so the view keeps its identity
        // and its state when the transition ends.
        content.mask {
            Canvas { context, size in
                guard progress < 1 else {
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                    return
                }
                let cell = PixelHandMotion.dissolveCell
                let columns = Int((size.width / cell).rounded(.up))
                let rows = Int((size.height / cell).rounded(.up))
                var path = Path()
                for row in 0..<max(rows, 0) {
                    for column in 0..<max(columns, 0) where Self.rank(column, row) < progress {
                        path.addRect(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                    }
                }
                context.fill(path, with: .color(.black))
            }
        }
    }

    /// A stable pseudo-random rank in 0..<1 for a cell.
    nonisolated static func rank(_ x: Int, _ y: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: x &* 73_856_093 ^ y &* 19_349_663)
        h ^= h >> 13
        h = h &* 0x5bd1_e995
        h ^= h >> 15
        return Double(h % 10_000) / 10_000
    }
}

#Preview("Bullets and dots") {
    VStack(alignment: .leading, spacing: 16) {
        OnboardingBulletRow(bullet: .init(glyph: PixelGlyphs.click, text: "Two fingers to scroll"))
        OnboardingBulletRow(bullet: .init(glyph: PixelGlyphs.missionControl, text: "Three fingers to switch desktops"))
        PageDots(count: 5, current: 1)
    }
    .padding(24)
    .background(DeckHandTheme.brandBackground())
}
