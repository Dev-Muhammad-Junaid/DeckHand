//
//  DotMatrixText.swift
//  DeckHandiOS – Design system
//
//  5 × 7 dot-matrix type for status words, counters, stats and codes. Never
//  for sentences, buttons, prices or anything a person must read to decide.
//  Doesn't follow Dynamic Type; at AX1+ the pitch steps up one size.
//  Spec: `Product/Design/06-Pixel-Identity.md` §2.
//

import SwiftUI

struct DotMatrixText: View {
    let text: String
    /// Dot pitch: 1.3–1.4 badges, 1.6 counters, 2 status strips, 3 large
    /// counters, 5 the PRO mark.
    var pitch: CGFloat = 2
    /// The plain-language label VoiceOver reads ("Page 1 of 3"). Every
    /// dot-matrix string needs one; defaults to the text itself.
    var label: String?
    /// The "LED panel" look: unlit cells at 14 %. Only for the PRO mark, the
    /// specimen and a strip's dim state.
    var showsUnlit = false
    /// Glow behind the dots. Defaults to on when drawn on navy.
    var glows: Bool?
    /// Steps up one pitch at AX1+.
    var stepsWithType = true

    @Environment(\.pixelOnNavy) private var onNavy
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ text: String, pitch: CGFloat = 2, label: String? = nil, showsUnlit: Bool = false, glows: Bool? = nil, stepsWithType: Bool = true) {
        self.text = text
        self.pitch = pitch
        self.label = label
        self.showsUnlit = showsUnlit
        self.glows = glows
        self.stepsWithType = stepsWithType
    }

    var body: some View {
        let pitch = stepsWithType
            ? CGFloat(PixelPitch.stepped(Double(self.pitch), for: typeSize.typeBand))
            : self.pitch
        let lit = DotMatrixFont.litCells(text)
        let unlit = showsUnlit ? DotMatrixFont.unlitCells(text) : []
        let geometry = DotGeometry.type
        let width = CGFloat(DotMatrixFont.widthInCells(text)) * pitch
        let height = CGFloat(DotMatrixFont.rows) * pitch
        let glows = self.glows ?? onNavy

        Canvas { context, _ in
            func dot(_ point: GlyphPoint) -> Path {
                let f = geometry.frame(x: point.x, y: point.y, pitch: Double(pitch))
                return Path(
                    roundedRect: CGRect(x: f.x, y: f.y, width: f.side, height: f.side),
                    cornerRadius: geometry.cornerRadius(pitch: Double(pitch))
                )
            }
            if !unlit.isEmpty {
                var off = context
                off.opacity = 0.14
                for point in unlit { off.fill(dot(point), with: .foreground) }
            }
            for point in lit { context.fill(dot(point), with: .foreground) }
        }
        .frame(width: width, height: height)
        .shadow(color: glows ? PixelHandTheme.Brand.glow.opacity(0.75) : .clear, radius: glows ? 2 : 0)
        .contentTransition(.identity)
        .accessibilityElement()
        .accessibilityLabel(label ?? text)
    }
}

/// The dot-matrix page counter: `01/03`, pitch 1.6, spoken "Page 1 of 3".
struct PageCounter: View {
    let current: Int
    let total: Int

    var body: some View {
        DotMatrixText(
            String(format: "%02d/%02d", current, total),
            pitch: 1.6,
            label: "Page \(current) of \(total)"
        )
        .foregroundStyle(.phInk2)
    }
}

#Preview("Dot-matrix type") {
    VStack(alignment: .leading, spacing: 16) {
        DotMatrixText("ABCDEFGHIJKLM", pitch: 2.2, showsUnlit: true)
        DotMatrixText("NOPQRSTUVWXYZ", pitch: 2.2, showsUnlit: true)
        DotMatrixText("0123456789 · : / % - + < >", pitch: 2.2, showsUnlit: true)
        DotMatrixText("60 FPS", pitch: 3)
        DotMatrixText("4.1/9.4 MB", pitch: 2)
    }
    .foregroundStyle(PixelHandTheme.Brand.phosphor)
    .padding(24)
    .background(PixelHandTheme.Brand.screen)
    .pixelOnNavy()
}
