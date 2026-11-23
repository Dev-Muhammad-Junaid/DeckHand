//
//  AnnotationView.swift
//  DeckHandiOS
//
//  The capture sheet's annotate step (UX-009): draw on the capture with a
//  pen, then bake the marks into the capture at its own resolution.
//
//  - `AnnotationCanvas`: the picture in its well with the marks over it.
//    Marks are stored in the capture's own coordinates (Core
//    `CaptureGeometry`), so rotating or resizing the window keeps them on
//    the right spot, and drawing is clipped to the picture.
//  - `AnnotationToolbar`: pen widths, Undo and Clear (Clear asks) on one
//    row, inks on a second row that scrolls, so the tools fit 320 pt and
//    work at AX5.
//  - `AnnotationRenderer`: composites the marks onto the capture at its
//    native size and scale (the old export was screen-sized and kept the
//    letterbox bars).
//
//  The host (`ScreenshotPreviewView`) owns the marks and the header, so
//  annotate is a state inside the one capture sheet, not a sheet of its own.
//

import SwiftUI
import UIKit

// MARK: - Model

/// One pen stroke, in the capture's own points (top-left origin).
struct AnnotationStroke: Identifiable, Equatable {
    let id = UUID()
    var points: [CGPoint]
    var ink: CaptureSheetChrome.Ink
    /// Width in the capture's points; drawn on screen scaled to fit.
    var width: CGFloat
}

// MARK: - Canvas

struct AnnotationCanvas: View {
    let image: UIImage
    @Binding var strokes: [AnnotationStroke]
    let ink: CaptureSheetChrome.Ink
    /// Pen width in screen points (`CaptureSheetChrome.penWidths`).
    let penWidth: CGFloat

    @State private var live: AnnotationStroke?

    var body: some View {
        GeometryReader { proxy in
            let fitted = CaptureGeometry.fitted(image, in: proxy.size)
            let toImage = image.size.width / max(fitted.width, 1)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .accessibilityLabel("Capture being annotated")

                Canvas { context, _ in
                    context.clip(to: Path(fitted))
                    for stroke in strokes { draw(stroke, fitted: fitted, in: &context) }
                    if let live { draw(live, fitted: fitted, in: &context) }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let point = imagePoint(value.location, fitted: fitted)
                        if live == nil {
                            live = AnnotationStroke(points: [], ink: ink, width: penWidth * toImage)
                        }
                        live?.points.append(point)
                    }
                    .onEnded { _ in
                        if let finished = live, !finished.points.isEmpty {
                            strokes.append(finished)
                            GestureHaptic.selection.trigger()
                        }
                        live = nil
                    }
            )
        }
    }

    private func imagePoint(_ location: CGPoint, fitted: CGRect) -> CGPoint {
        let p = CaptureGeometry.imagePoint(
            x: Double(location.x), y: Double(location.y),
            fitted: MirrorRect(fitted),
            imageWidth: Double(image.size.width), imageHeight: Double(image.size.height)
        )
        return CGPoint(x: p.x, y: p.y)
    }

    /// Draws a stroke stored in image points into the on-screen fit.
    private func draw(_ stroke: AnnotationStroke, fitted: CGRect, in context: inout GraphicsContext) {
        let scale = fitted.width / max(image.size.width, 1)
        let points = stroke.points.map { CGPoint(x: fitted.minX + $0.x * scale, y: fitted.minY + $0.y * scale) }
        let width = stroke.width * scale
        let color = stroke.ink.color
        guard points.count > 1 else {
            if let p = points.first {
                context.fill(Path(ellipseIn: CGRect(x: p.x - width / 2, y: p.y - width / 2, width: width, height: width)), with: .color(color))
            }
            return
        }
        context.stroke(
            AnnotationRenderer.smoothPath(points),
            with: .color(color),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        )
    }
}

// MARK: - Toolbar

/// Row 1: pen widths · Undo · Clear. Row 2: inks, scrolling when the row is
/// wider than the dock. Every target is 44 pt.
struct AnnotationToolbar: View {
    @Binding var ink: CaptureSheetChrome.Ink
    @Binding var penWidth: CGFloat
    let canUndo: Bool
    let onUndo: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: PixelHandTheme.Space.xs) {
            HStack(spacing: 0) {
                ForEach(CaptureSheetChrome.penWidths, id: \.self) { width in
                    widthButton(CGFloat(width))
                }
                Spacer(minLength: PixelHandTheme.Space.sm)
                CaptureIconButton(glyph: CaptureGlyphs.undo, label: "Undo", isEnabled: canUndo, action: onUndo)
                CaptureIconButton(glyph: CaptureGlyphs.clear, label: "Clear all marks", isEnabled: canUndo, action: onClear)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(CaptureSheetChrome.Ink.allCases, id: \.self) { option in
                        inkButton(option)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }

    private func widthButton(_ width: CGFloat) -> some View {
        let selected = penWidth == width
        return Button {
            GestureHaptic.selection.trigger()
            penWidth = width
        } label: {
            Circle()
                .fill(ink.color)
                .frame(width: min(width * 1.6 + 4, 26), height: min(width * 1.6 + 4, 26))
                .frame(width: 36, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
                        .strokeBorder(selected ? PixelHandTheme.Brand.phosphor : Color.clear, lineWidth: PixelHandTheme.Stroke.selection)
                )
                .frame(width: PixelHandTheme.ControlHeight.hit, height: PixelHandTheme.ControlHeight.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pen width \(Int(width))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func inkButton(_ option: CaptureSheetChrome.Ink) -> some View {
        let selected = ink == option
        return Button {
            GestureHaptic.selection.trigger()
            ink = option
        } label: {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(option.color)
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: PixelHandTheme.Stroke.hairline)
                )
                .padding(3)
                .overlay(
                    RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd + 1, style: .continuous)
                        .strokeBorder(selected ? PixelHandTheme.Brand.phosphor : Color.clear, lineWidth: PixelHandTheme.Stroke.selection)
                )
                .shadow(color: selected ? PixelHandTheme.Brand.glow.opacity(0.6) : .clear, radius: 4)
                .frame(width: PixelHandTheme.ControlHeight.hit, height: PixelHandTheme.ControlHeight.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Export

enum AnnotationRenderer {
    /// The capture with every stroke baked in, at the capture's own size and
    /// scale. Strokes are already in the capture's points.
    static func render(_ image: UIImage, strokes: [AnnotationStroke]) -> UIImage {
        guard !strokes.isEmpty, image.size.width > 0, image.size.height > 0 else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for stroke in strokes {
                guard let first = stroke.points.first else { continue }
                stroke.ink.uiColor.setStroke()
                stroke.ink.uiColor.setFill()
                if stroke.points.count == 1 {
                    let r = stroke.width / 2
                    UIBezierPath(ovalIn: CGRect(x: first.x - r, y: first.y - r, width: stroke.width, height: stroke.width)).fill()
                } else {
                    let path = UIBezierPath(cgPath: smoothPath(stroke.points).cgPath)
                    path.lineWidth = stroke.width
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }
            }
        }
    }

    /// Quadratic smoothing through the midpoints, the same on screen and in
    /// the export.
    static func smoothPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for i in 1..<points.count {
            let prev = points[i - 1]
            let curr = points[i]
            path.addQuadCurve(to: CGPoint(x: (prev.x + curr.x) / 2, y: (prev.y + curr.y) / 2), control: prev)
        }
        if let last = points.last { path.addLine(to: last) }
        return path
    }
}
