//
//  ContextChip.swift
//  DeckHandiOS – Design system
//
//  One action in the context strip: optional glyph, label, chord in mono and
//  a 3-dot delivery strip. Minimum 44 pt. Kinds: standard, dialog button,
//  the dialog's default button (cobalt with a 2 pt ring) and an AI proposal
//  (dashed outline, no strip). Spec: `02-Design-System.md` §7, board
//  "Components" (`.chip`).
//

import SwiftUI

struct ContextChip: View {
    enum Kind {
        case standard
        case dialog
        case defaultAction
        case suggestion
    }

    let title: String
    var glyph: GlyphBitmap?
    var chord: String?
    var kind: Kind = .standard
    var delivery: DeliveryState = .idle
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                label
                if kind != .suggestion {
                    DeliveryStrip(state: delivery, onAccent: kind == .defaultAction)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .frame(minHeight: PixelHandTheme.ControlHeight.standard)
            .background(background)
            .overlay(border)
            .contentShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous))
        }
        .buttonStyle(ChipPressStyle())
        .padding(kind == .defaultAction ? 4 : 0)
        .accessibilityLabel(title)
        .accessibilityHint(chord.map { "Shortcut \($0)" } ?? "")
    }

    @ViewBuilder
    private var label: some View {
        let stacked = typeSize.typeBand >= .large
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 6))
        layout {
            HStack(spacing: 6) {
                if let glyph {
                    PHGlyph(glyph: glyph, pitch: PixelPitch.chip, accent: kind == .defaultAction ? .white : nil)
                        .foregroundStyle(glyphColor)
                }
                Text(title)
                    .font(.phChip)
                    .foregroundStyle(textColor)
                    .lineLimit(stacked ? 2 : 1)
            }
            if let chord {
                Text(chord)
                    .font(.phChord)
                    .foregroundStyle(kind == .defaultAction ? Color.white.opacity(0.7) : PixelHandTheme.ink3)
            }
        }
    }

    private var textColor: Color {
        switch kind {
        case .defaultAction: .white
        case .suggestion: PixelHandTheme.accentInk
        default: PixelHandTheme.ink
        }
    }

    private var glyphColor: Color {
        switch kind {
        case .defaultAction: .white
        case .suggestion: PixelHandTheme.accentInk
        default: PixelHandTheme.accent
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .standard, .dialog:
            shape.fill(PixelHandTheme.raised)
                .shadow(color: scheme == .dark ? .clear : PixelHandTheme.Brand.screen.opacity(0.06), radius: 1, y: 1)
        case .defaultAction:
            shape.fill(PixelHandTheme.accent)
        case .suggestion:
            Color.clear
        }
    }

    @ViewBuilder
    private var border: some View {
        switch kind {
        case .standard, .dialog:
            shape.strokeBorder(PixelHandTheme.hairline, lineWidth: PixelHandTheme.Stroke.hairline)
        case .defaultAction:
            // 2 pt of canvas, then a 2 pt ring of accent at 55 %.
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip + 4, style: .continuous)
                .strokeBorder(PixelHandTheme.accent.opacity(0.55), lineWidth: 2)
                .padding(-4)
        case .suggestion:
            shape.strokeBorder(PixelHandTheme.accent.opacity(0.65), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
    }
}

/// Press feedback shared by chips and keys: a quick dim, no movement under
/// Reduce Motion.
struct ChipPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(PixelHandMotion.quick, value: configuration.isPressed)
    }
}

#Preview("Chips") {
    ScrollView(.horizontal) {
        HStack(spacing: 8) {
            ContextChip(title: "Save", chord: "↩", kind: .defaultAction) {}
            ContextChip(title: "Cancel", chord: "esc", kind: .dialog) {}
            ContextChip(title: "Build", glyph: PixelGlyphs.build, chord: "⌘B", delivery: .confirmed) {}
            ContextChip(title: "Run", glyph: PixelGlyphs.run, chord: "⌘R", delivery: .sending) {}
            ContextChip(title: "Quit", glyph: PixelGlyphs.close, chord: "⌘Q", delivery: .failed) {}
            ContextChip(title: "Suggest", glyph: PixelGlyphs.ask, kind: .suggestion) {}
        }
        .padding(16)
    }
    .background(.phCanvas)
}
