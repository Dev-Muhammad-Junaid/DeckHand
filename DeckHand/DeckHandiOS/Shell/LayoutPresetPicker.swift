//
//  LayoutPresetPicker.swift
//  DeckHandiOS – Shell
//
//  The iPad layout presets (UX-007): Split, Screen and Pointer as one glass
//  capsule of 44 pt glyph segments, in the header where the tab bar would
//  be. The lit segment carries the 4 pt selection dot like the tab bar. At
//  AX1+ labels never show (they don't at standard either: the glyphs are
//  the board's); long-press shows the Large Content Viewer.
//  Board: `padLand` toolbar (`.tabs` with layers / screen / pointer).
//

import SwiftUI

struct LayoutPresetPicker: View {
    @Binding var selection: LayoutPreset

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionSpace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LayoutPreset.allCases, id: \.self) { preset in
                segment(preset)
            }
        }
        .padding(2)
        .frame(height: PixelHandTheme.ControlHeight.standard)
        .phGlass(in: Capsule(), interactive: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Layout")
    }

    private func segment(_ preset: LayoutPreset) -> some View {
        let isOn = selection == preset
        return Button {
            guard !isOn else { return }
            GestureHaptic.selection.trigger()
            withAnimation(PixelHandMotion.reduced(PixelHandMotion.spring, reduceMotion: reduceMotion)) {
                selection = preset
            }
        } label: {
            PHGlyph(glyph: preset.glyph, pitch: PixelPitch.chip)
                .foregroundStyle(isOn ? PixelHandTheme.accent : PixelHandTheme.ink)
                .frame(width: 48, height: 40)
                .background {
                    if isOn {
                        Capsule()
                            .fill(PixelHandTheme.fill2)
                            .matchedGeometryEffect(id: "preset", in: selectionSpace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .phosphorFocusable(cornerRadius: 20)
        .accessibilityLabel(preset.spokenTitle)
        .accessibilityIdentifier("ph.header.layout")
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
        .accessibilityShowsLargeContentViewer {
            Label { Text(preset.title) } icon: { PHGlyph(glyph: preset.glyph, pitch: PixelPitch.chip) }
        }
        .help(preset.title)
    }
}

extension LayoutPreset {
    var glyph: GlyphBitmap {
        switch self {
        case .split: PixelGlyphs.layoutSplit
        case .screen: PixelGlyphs.screen
        case .pointer: PixelGlyphs.pointer
        }
    }
}

/// The handle between two panes: a 36 × 4 capsule in a 44 pt tall strip,
/// dragged vertically. VoiceOver adjusts it in 10 % steps.
struct PaneDragHandle: View {
    /// Called with the drag's vertical translation since the last call.
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void
    /// VoiceOver increment / decrement (taller top pane / shorter).
    let onAdjust: (_ grow: Bool) -> Void
    var label = "Resize panes"

    @State private var lastTranslation: CGFloat = 0
    @State private var isDragging = false

    var body: some View {
        Capsule()
            .fill(isDragging ? PixelHandTheme.accent : PixelHandTheme.ink3)
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: PixelHandTheme.Space.md)
            .contentShape(Rectangle().inset(by: -16))
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            GestureHaptic.light.trigger()
                        }
                        onDrag(value.translation.height - lastTranslation)
                        lastTranslation = value.translation.height
                    }
                    .onEnded { _ in
                        isDragging = false
                        lastTranslation = 0
                        onEnd()
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onAdjust(true)
                case .decrement: onAdjust(false)
                @unknown default: break
                }
            }
    }
}
