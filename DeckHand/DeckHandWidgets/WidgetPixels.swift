//
//  WidgetPixels.swift
//  DeckHandWidgets
//
//  The pixel identity in the widget extension, drawn from Core only (the
//  app's design-system views aren't compiled here): navy surfaces, 9 × 9
//  dot glyphs with the accent dot, dot-matrix text (`06-Pixel-Identity.md`
//  §3: widgets use the status strip at pitch 2).
//

import PixelHandCore
import SwiftUI
import WidgetKit

enum WidgetPalette {
    static func color(_ rgb: RGBColor) -> Color {
        Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    static let screen = color(PaletteTokens.Brand.screen)
    static let screenRaised = color(PaletteTokens.Brand.screenRaised)
    static let screenHigh = color(PaletteTokens.Brand.screenHigh)
    static let screenLift = color(PaletteTokens.Brand.screenLift)
    static let phosphor = color(PaletteTokens.Brand.phosphor)
    static let glow = color(PaletteTokens.Brand.glow)
    static let mint = color(PaletteTokens.Brand.mint)
    static let cobalt = color(PaletteTokens.Brand.cobalt)
    static let violet = color(PaletteTokens.Brand.pixelViolet)
    static let stripDim = color(PaletteTokens.Brand.stripDim)
    static let dotOff = color(PaletteTokens.Brand.dotOff.color).opacity(PaletteTokens.Brand.dotOff.opacity)

    /// A key's tint token (`KeyAppearance.tint`, the same tokens as the
    /// app's `DeckKeyTint`), as the glyph colour on a navy key.
    static func glyphColor(tint: String?) -> Color {
        switch tint {
        case "mint": mint
        case "violet": violet
        case "glow": glow
        default: phosphor
        }
    }

    /// The navy surface every widget sits on: `screen` with the lift at
    /// the top.
    static var surface: some View {
        ZStack {
            screen
            RadialGradient(colors: [screenLift, screen], center: .top, startRadius: 0, endRadius: 220)
        }
    }
}

/// A dot-matrix line (`DotMatrixFont`).
struct WidgetDotText: View {
    let text: String
    var pitch: CGFloat = 2

    init(_ text: String, pitch: CGFloat = 2) {
        self.text = text
        self.pitch = pitch
    }

    var body: some View {
        let cells = DotMatrixFont.litCells(text)
        let geometry = DotGeometry.type
        Canvas { context, _ in
            var path = Path()
            for cell in cells {
                let f = geometry.frame(x: cell.x, y: cell.y, pitch: Double(pitch))
                path.addRoundedRect(
                    in: CGRect(x: f.x, y: f.y, width: f.side, height: f.side),
                    cornerSize: CGSize(width: geometry.cornerRadius(pitch: Double(pitch)), height: geometry.cornerRadius(pitch: Double(pitch)))
                )
            }
            context.fill(path, with: .foreground)
        }
        .frame(width: CGFloat(DotMatrixFont.widthInCells(text)) * pitch, height: CGFloat(DotMatrixFont.rows) * pitch)
        .accessibilityLabel(text)
    }
}

/// A key's glyph: a 9 × 9 (or 8 × 8) dot bitmap, an SF Symbol, or a
/// dot-matrix monogram.
struct WidgetGlyphView: View {
    let glyph: WidgetGlyph
    /// The side of the glyph box.
    var side: CGFloat = 27
    /// The accent dot's colour; `nil` draws it like the others
    /// (lock-screen widgets are monochrome).
    var accent: Color? = WidgetPalette.glow

    var body: some View {
        switch glyph {
        case let .pixel(name):
            if let bitmap = PixelGlyphs.named(name) {
                DotBitmap(size: GlyphBitmap.size, side: side, accentDot: bitmap.accent.map { ($0.x, $0.y) }, accent: accent) { x, y in
                    bitmap.isOn(x, y)
                }
            } else {
                Image(systemName: "square.grid.3x3").font(.system(size: side * 0.7))
            }
        case let .bitmap(data):
            DotBitmap(size: data.size, side: side, accentDot: data.accent.map { ($0.x, $0.y) }, accent: accent) { x, y in
                data.isOn(x: x, y: y)
            }
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: side * 0.72, weight: .medium))
                .frame(width: side, height: side)
        case let .monogram(letters):
            WidgetDotText(letters, pitch: max(1, side / 11))
                .frame(width: side, height: side)
        }
    }
}

private struct DotBitmap: View {
    let size: Int
    let side: CGFloat
    let accentDot: (Int, Int)?
    let accent: Color?
    let isOn: (Int, Int) -> Bool

    var body: some View {
        let pitch = side / CGFloat(size)
        let geometry = DotGeometry.glyph
        Canvas { context, _ in
            var lit = Path()
            var accentPath = Path()
            for y in 0..<size {
                for x in 0..<size where isOn(x, y) {
                    let f = geometry.frame(x: x, y: y, pitch: Double(pitch))
                    let rect = CGRect(x: f.x, y: f.y, width: f.side, height: f.side)
                    let corner = geometry.cornerRadius(pitch: Double(pitch))
                    if let accentDot, accent != nil, accentDot == (x, y) {
                        accentPath.addRoundedRect(in: rect, cornerSize: CGSize(width: corner, height: corner))
                    } else {
                        lit.addRoundedRect(in: rect, cornerSize: CGSize(width: corner, height: corner))
                    }
                }
            }
            context.fill(lit, with: .foreground)
            if let accent { context.fill(accentPath, with: .color(accent)) }
        }
        .frame(width: side, height: side)
    }
}
