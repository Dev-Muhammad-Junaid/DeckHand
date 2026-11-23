//
//  PixelGlyphEditor.swift
//  DeckHandiOS – Deck
//
//  The key inspector's 8 × 8 pixel glyph editor (UX-020, D3; board "Deck
//  editor (1.2)"): the same rounded dots as every glyph, drawn big. Tap a
//  dot to toggle it, drag to paint (the first dot decides paint or erase),
//  the Accent tool marks the one lit dot that glows. Mirror, nudge, clear
//  and its own Undo. A live preview at the key's pitch, and design rule 1
//  ("strokes one dot wide") as a warning, never a block.
//  Spec: `06-Pixel-Identity.md` §1 "User glyphs".
//

import PixelHandCore
import SwiftUI

struct PixelGlyphEditor: View {
    @Binding var glyph: PixelGlyphData
    /// Side of the drawing grid in points.
    var side: CGFloat = 176

    @State private var history = DeckUndoHistory<PixelGlyphData>(limit: 40)
    @State private var isAccentTool = false
    @State private var paintValue: Bool?
    @State private var lastCell: GlyphDot?

    private var size: Int { glyph.size }
    private var gap: CGFloat { 3 }
    private var cell: CGFloat { (side - gap * CGFloat(size - 1)) / CGFloat(size) }

    var body: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.md) {
            HStack(alignment: .top, spacing: PixelHandTheme.Space.lg) {
                grid
                VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
                    Text("Preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PixelHandTheme.ink2)
                    PHGlyph(glyph: glyph.bitmap(), pitch: PixelPitch.key)
                        .foregroundStyle(PixelHandTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(PixelHandTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    DotMatrixText(String(format: "%02d", glyph.litCount), pitch: 1.6, label: "\(glyph.litCount) dots lit")
                        .foregroundStyle(PixelHandTheme.ink2)
                    Spacer(minLength: 0)
                    toolButton(isAccentTool ? "Accent" : "Draw", systemImage: isAccentTool ? "sparkle" : "pencil.tip", isOn: isAccentTool) {
                        isAccentTool.toggle()
                    }
                    .accessibilityHint("Switches between drawing dots and marking the accent dot")
                }
                .frame(height: side)
            }
            HStack(spacing: PixelHandTheme.Space.sm) {
                toolButton("Undo", systemImage: "arrow.uturn.backward") { undo() }
                    .disabled(!history.canUndo)
                toolButton("Mirror", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") { change { $0.mirrored } }
                Menu {
                    Button("Up", systemImage: "arrow.up") { change { $0.shifted(dx: 0, dy: -1) } }
                    Button("Down", systemImage: "arrow.down") { change { $0.shifted(dx: 0, dy: 1) } }
                    Button("Left", systemImage: "arrow.left") { change { $0.shifted(dx: -1, dy: 0) } }
                    Button("Right", systemImage: "arrow.right") { change { $0.shifted(dx: 1, dy: 0) } }
                } label: {
                    toolLabel("Move", systemImage: "arrow.up.and.down.and.arrow.left.and.right", isOn: false)
                }
                .accessibilityLabel("Move the drawing")
                Menu {
                    ForEach(PixelGlyphs.all) { set in
                        Button(set.label) { change { _ in PixelGlyphData(bitmap: set, size: 8) } }
                    }
                } label: {
                    toolLabel("Start from", systemImage: "square.grid.3x3", isOn: false)
                }
                .accessibilityLabel("Start from a glyph")
                toolButton("Clear", systemImage: "trash") { change { $0.cleared } }
                    .disabled(glyph.litCount == 0)
            }
            if glyph.hasThickStroke {
                Label("Strokes read best one dot wide.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(PixelHandTheme.warning)
            }
        }
    }

    // MARK: Grid

    private var grid: some View {
        let glyph = self.glyph
        return Canvas { context, _ in
            for y in 0..<glyph.size {
                for x in 0..<glyph.size {
                    let rect = CGRect(x: CGFloat(x) * (cell + gap), y: CGFloat(y) * (cell + gap), width: cell, height: cell)
                    let path = Path(roundedRect: rect, cornerRadius: cell * 0.3)
                    let color: Color
                    if glyph.accent == GlyphDot(x: x, y: y) {
                        color = PixelHandTheme.Brand.glow
                    } else if glyph.isOn(x: x, y: y) {
                        color = PixelHandTheme.accent
                    } else {
                        color = PixelHandTheme.fill2
                    }
                    context.fill(path, with: .color(color))
                }
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in paint(at: value.location) }
                .onEnded { _ in
                    paintValue = nil
                    lastCell = nil
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Glyph drawing, \(size) by \(size) dots")
        .accessibilityValue("\(glyph.litCount) dots lit")
        .accessibilityHint("Draw with one finger. VoiceOver users can start from a glyph instead.")
    }

    private func cellAt(_ point: CGPoint) -> GlyphDot? {
        let x = Int(point.x / (cell + gap))
        let y = Int(point.y / (cell + gap))
        guard (0..<size).contains(x), (0..<size).contains(y), point.x >= 0, point.y >= 0 else { return nil }
        return GlyphDot(x: x, y: y)
    }

    private func paint(at point: CGPoint) {
        guard let dot = cellAt(point), dot != lastCell else { return }
        let first = lastCell == nil
        lastCell = dot
        if first { history.record(glyph) }
        if isAccentTool {
            guard first else { return }
            glyph = glyph.togglingAccent(x: dot.x, y: dot.y)
            GestureHaptic.selection.trigger()
            return
        }
        if paintValue == nil { paintValue = !glyph.isOn(x: dot.x, y: dot.y) }
        guard let on = paintValue, glyph.isOn(x: dot.x, y: dot.y) != on else { return }
        var next = glyph.setting(x: dot.x, y: dot.y, on: on)
        if !on, next.accent == dot { next.accent = nil }
        glyph = next
        GestureHaptic.selection.trigger()
    }

    // MARK: Tools

    private func change(_ transform: (PixelGlyphData) -> PixelGlyphData) {
        let next = transform(glyph)
        guard next != glyph else { return }
        history.record(glyph)
        glyph = next
    }

    private func undo() {
        if let previous = history.undo(current: glyph) { glyph = previous }
    }

    private func toolButton(_ title: String, systemImage: String, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            toolLabel(title, systemImage: systemImage, isOn: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func toolLabel(_ title: String, systemImage: String, isOn: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isOn ? PixelHandTheme.accentInk : PixelHandTheme.ink)
            .frame(width: 40, height: 36)
            .background(isOn ? PixelHandTheme.accentTint : PixelHandTheme.fill2, in: Capsule())
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

private struct GlyphEditorPreview: View {
    @State private var glyph = PixelGlyphData(bitmap: PixelGlyphs.build)

    var body: some View {
        PixelGlyphEditor(glyph: $glyph)
            .padding()
            .background(PixelHandTheme.canvas)
    }
}

#Preview("Glyph editor") {
    GlyphEditorPreview()
}
