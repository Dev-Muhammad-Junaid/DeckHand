//
//  PixelSurface.swift
//  DeckHandiOS – Design system
//
//  The navy pane every screen-like surface sits on: the trackpad, the mirror
//  well, brand plates. `screen` with the radial lift and the resting dot grid
//  (2.4 pt dots on a 15 pt pitch, `dotOff`). Unlit dots never carry meaning.
//  Spec: `Product/Design/02-Design-System.md` §2 and §6.
//

import SwiftUI

struct PixelSurface<Content: View>: View {
    var cornerRadius: CGFloat = PixelHandTheme.Radius.pane
    /// Draws the resting grid. Off where a picture covers the pane.
    var showsGrid = true
    @ViewBuilder var content: Content

    init(cornerRadius: CGFloat = PixelHandTheme.Radius.pane, showsGrid: Bool = true, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.showsGrid = showsGrid
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    PixelHandTheme.Brand.screenSurface
                    if showsGrid { DotGrid() }
                }
                .clipShape(shape)
            }
            .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: PixelHandTheme.Stroke.hairline))
            .pixelOnNavy()
    }
}

extension PixelSurface where Content == EmptyView {
    init(cornerRadius: CGFloat = PixelHandTheme.Radius.pane, showsGrid: Bool = true) {
        self.init(cornerRadius: cornerRadius, showsGrid: showsGrid) { EmptyView() }
    }
}

/// The resting dot grid: 2.4 pt dots on a 15 pt pitch, centred so the
/// margins are equal on both axes.
struct DotGrid: View {
    var pitch: CGFloat = 15
    var dot: CGFloat = 2.4
    var color: Color = PixelHandTheme.Brand.dotOff

    var body: some View {
        let pitch = self.pitch, dot = self.dot, color = self.color
        Canvas { context, size in
            let columns = Int(size.width / pitch)
            let rows = Int(size.height / pitch)
            let x0 = (size.width - CGFloat(columns - 1) * pitch) / 2
            let y0 = (size.height - CGFloat(rows - 1) * pitch) / 2
            var path = Path()
            for row in 0..<max(rows, 0) {
                for column in 0..<max(columns, 0) {
                    let cx = (x0 + CGFloat(column) * pitch).rounded()
                    let cy = (y0 + CGFloat(row) * pitch).rounded()
                    path.addRoundedRect(
                        in: CGRect(x: cx - dot / 2, y: cy - dot / 2, width: dot, height: dot),
                        cornerSize: CGSize(width: dot * 0.32, height: dot * 0.32)
                    )
                }
            }
            context.fill(path, with: .color(color))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Pixel surface") {
    PixelSurface {
        DotMatrixText("2 FINGERS · SCROLL", pitch: 1.3)
            .foregroundStyle(PixelHandTheme.Brand.phosphor)
    }
    .frame(height: 420)
    .padding(16)
    .background(.phCanvas)
}
