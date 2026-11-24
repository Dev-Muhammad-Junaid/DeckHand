//
//  DeckKey.swift
//  DeckHandiOS – Design system
//
//  A deck key: square at the grid's whole-point key size, glyph at pitch 3,
//  a two-line label, the chord and a 4-dot delivery strip. Kinds: standard,
//  system (navy), ghost (AI proposal, dashed, 75 % content) and editing
//  (dotted outline with a remove badge). Ask-first keys show a `?` corner.
//  At AX3+ the deck uses `DeckKeyRow` instead.
//  Spec: `02-Design-System.md` §7, board `.key` / `.gkey`, `07-Polish-Spec.md` §6.
//

import SwiftUI

struct DeckKey: View {
    enum Kind {
        case standard
        case system
        case ghost
        case editing
    }

    let title: String
    let glyph: GlyphBitmap
    var chord: String?
    /// Side in points, from `LayoutMetrics.deckGrid.keySize`.
    var size: CGFloat = 83
    var kind: Kind = .standard
    var asksFirst = false
    var delivery: DeliveryState = .idle
    /// A real app icon drawn instead of the glyph (launch keys). Deck UI lane.
    var icon: Image?
    /// The glyph's colour from the key's palette token; `nil` = accent.
    var tint: Color?
    var onRemove: (() -> Void)?
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            ZStack {
                background
                VStack(spacing: 4) {
                    if let icon {
                        icon.resizable().interpolation(.high).scaledToFit()
                            .frame(width: 30, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    } else {
                        PHGlyph(glyph: glyph, pitch: PixelPitch.key)
                            .foregroundStyle(kind == .system ? Color(red: 0.81, green: 0.88, blue: 1) : (tint ?? PixelHandTheme.accent))
                    }
                    Text(title)
                        .font(.phKeyLabel)
                        .foregroundStyle(kind == .system ? .white : PixelHandTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.9)
                    if let chord {
                        Text(chord)
                            .font(.system(.caption2, design: .monospaced).weight(.medium))
                            .foregroundStyle(kind == .system ? Color.white.opacity(0.55) : PixelHandTheme.ink3)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
                .opacity(kind == .ghost ? 0.75 : 1)

                DeliveryStrip(state: delivery, count: 4, dotSize: 3.5, spacing: 2.5)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 6)

                if asksFirst {
                    Text("?")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(PixelHandTheme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 6)
                        .padding(.trailing, 8)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: size, height: size)
            .contentShape(shape)
        }
        .buttonStyle(ChipPressStyle())
        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.key)
        .overlay(alignment: .topLeading) {
            if kind == .editing, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "minus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(PixelHandTheme.ink3, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: -18, y: -18)
                .accessibilityLabel("Remove \(title)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title + (asksFirst ? ", asks first" : ""))
        .accessibilityValue(chord ?? "")
        .accessibilityActions {
            if kind == .editing, let onRemove {
                Button("Remove \(title)", action: onRemove)
            }
        }
        .accessibilityIdentifier("ph.deck.key")
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PixelHandTheme.Radius.key, style: .continuous)
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .standard, .editing:
            shape.fill(PixelHandTheme.raised)
                .overlay(shape.strokeBorder(PixelHandTheme.hairline, lineWidth: PixelHandTheme.Stroke.hairline))
                .shadow(color: scheme == .dark ? .clear : PixelHandTheme.Brand.screen.opacity(0.06), radius: 1, y: 1)
                .overlay {
                    if kind == .editing {
                        shape.strokeBorder(PixelHandTheme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    }
                }
        case .system:
            shape.fill(PixelHandTheme.Brand.screenGradient)
        case .ghost:
            shape.strokeBorder(PixelHandTheme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
    }
}

/// The deck at AX3–AX5: a row with the glyph at pitch 3, the full label and
/// the chord trailing, at least 64 pt tall.
struct DeckKeyRow: View {
    let title: String
    let glyph: GlyphBitmap
    var chord: String?
    var delivery: DeliveryState = .idle
    /// A real app icon drawn instead of the glyph. Deck UI lane.
    var icon: Image?
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PixelHandTheme.Space.md) {
                if let icon {
                    icon.resizable().interpolation(.high).scaledToFit()
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    PHGlyph(glyph: glyph, pitch: PixelPitch.key)
                        .foregroundStyle(tint ?? PixelHandTheme.accent)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(PixelHandTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let chord {
                    Text(chord).font(.phChord).foregroundStyle(PixelHandTheme.ink3)
                }
                DeliveryStrip(state: delivery, count: 4, dotSize: 3.5, spacing: 2.5)
            }
            .padding(.horizontal, PixelHandTheme.Space.lg)
            .frame(minHeight: 64)
            .background(PixelHandTheme.raised, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.key, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.key, style: .continuous))
        }
        .buttonStyle(ChipPressStyle())
        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.key)
        .accessibilityLabel(title)
        .accessibilityValue(chord ?? "")
        .accessibilityIdentifier("ph.deck.key")
    }
}

#Preview("Keys") {
    let metrics = LayoutMetrics(width: 402, height: 874)
    let grid = metrics.deckGrid
    VStack(spacing: 12) {
        HStack(spacing: grid.gutter) {
            DeckKey(title: "Build", glyph: PixelGlyphs.build, chord: "⌘B", size: grid.keySize, delivery: .confirmed) {}
            DeckKey(title: "Run", glyph: PixelGlyphs.run, chord: "⌘R", size: grid.keySize, delivery: .sending) {}
            DeckKey(title: "Clean Build", glyph: PixelGlyphs.close, chord: "⇧⌘K", size: grid.keySize, asksFirst: true) {}
            DeckKey(title: "Mission Control", glyph: PixelGlyphs.missionControl, size: grid.keySize, kind: .system) {}
        }
        HStack(spacing: grid.gutter) {
            DeckKey(title: "Read Text", glyph: PixelGlyphs.readText, size: grid.keySize, kind: .ghost) {}
            DeckKey(title: "Space Left", glyph: PixelGlyphs.spaceLeft, chord: "⌃←", size: grid.keySize, kind: .editing, onRemove: {}) {}
        }
        DeckKeyRow(title: "Open Quickly", glyph: PixelGlyphs.find, chord: "⇧⌘O") {}
    }
    .padding(.leading, grid.leadingMargin)
    .padding(.trailing, grid.trailingMargin)
    .frame(width: 402)
    .background(.phCanvas)
}
