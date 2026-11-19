//
//  PHGlyph.swift
//  DeckHandiOS – Design system
//
//  A 9 × 9 pixel glyph drawn with a `Canvas` at a whole pitch: one rounded
//  square per lit cell (78 % of the pitch, radius 30 % of the dot). Never
//  scaled with a transform; a bigger glyph is drawn at the next pitch.
//  Spec: `Product/Design/06-Pixel-Identity.md` §1.
//

import SwiftUI

struct PHGlyph: View {
    let glyph: GlyphBitmap
    /// Distance between dot centres. Use a value from `PixelPitch.glyph`.
    var pitch: CGFloat = PixelPitch.chip
    /// Draws unlit cells at `dotOff` (empty states, the glyph sheet).
    var showsUnlit = false
    /// Steps the pitch up one size at AX1+ (dot-matrix rule). Off for glyphs
    /// whose container already switches layout.
    var stepsWithType = false
    /// Press flash: every dot phosphor for `PixelHandMotion.pressFlash`.
    var isFlashing = false
    /// Overrides the surface's accent colour (`glow` on navy, `accent` on light).
    var accent: Color?

    @Environment(\.pixelOnNavy) private var onNavy
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let pitch = stepsWithType
            ? CGFloat(PixelPitch.stepped(Double(self.pitch), for: typeSize.typeBand))
            : self.pitch
        let glyph = self.glyph
        let accent = self.accent ?? PixelHandTheme.pixelAccent(onNavy: onNavy)
        let flash = isFlashing
        let unlit = showsUnlit
        let geometry = DotGeometry.glyph
        let side = CGFloat(PixelPitch.glyphSide(Double(pitch)))

        Canvas { context, _ in
            func dot(_ x: Int, _ y: Int) -> Path {
                let f = geometry.frame(x: x, y: y, pitch: Double(pitch))
                return Path(
                    roundedRect: CGRect(x: f.x, y: f.y, width: f.side, height: f.side),
                    cornerRadius: geometry.cornerRadius(pitch: Double(pitch))
                )
            }
            if unlit {
                for y in 0..<GlyphBitmap.size {
                    for x in 0..<GlyphBitmap.size where !glyph.isOn(x, y) {
                        context.fill(dot(x, y), with: .color(PixelHandTheme.Brand.dotOff))
                    }
                }
            }
            for point in glyph.litPoints {
                let shading: GraphicsContext.Shading
                if flash {
                    shading = .color(PixelHandTheme.Brand.phosphor)
                } else if glyph.isAccent(point.x, point.y) {
                    shading = .color(accent)
                } else {
                    shading = .foreground
                }
                context.fill(dot(point.x, point.y), with: shading)
            }
        }
        .frame(width: side, height: side)
        .shadow(color: flash ? PixelHandTheme.Brand.glow.opacity(0.8) : .clear, radius: flash ? 3 : 0)
        .accessibilityHidden(true)
    }
}

#Preview("Glyph sheet") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 12) {
            ForEach(PixelGlyphs.all) { glyph in
                VStack(spacing: 8) {
                    PHGlyph(glyph: glyph, pitch: 4, showsUnlit: true)
                    Text(glyph.label).font(.caption2).foregroundStyle(.phInk2)
                }
            }
        }
        .padding(16)
    }
    .foregroundStyle(.phInk)
    .background(.phCanvas)
}

#Preview("Pitches on navy") {
    HStack(alignment: .bottom, spacing: 24) {
        ForEach([1.4, 2, 2.6, 3, 4, 6], id: \.self) { pitch in
            PHGlyph(glyph: PixelGlyphs.run, pitch: pitch)
        }
    }
    .foregroundStyle(PixelHandTheme.Brand.phosphor)
    .padding(24)
    .background(PixelHandTheme.Brand.screen)
    .pixelOnNavy()
}
