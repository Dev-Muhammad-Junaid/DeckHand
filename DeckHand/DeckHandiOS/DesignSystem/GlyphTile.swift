//
//  GlyphTile.swift
//  DeckHandiOS – Design system
//
//  The navy glyph tile (onboarding bullets, the Mac picker, pairing, the
//  paywall) and the square page dots. Promoted from onboarding (UX-017).
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

#Preview("Glyph tile and page dots") {
    VStack(spacing: 16) {
        GlyphTile(glyph: PixelGlyphs.mac, side: 44, pitch: 3)
        PageDots(count: 5, current: 1)
    }
    .padding(24)
    .background(PixelHandTheme.Brand.screen)
}
