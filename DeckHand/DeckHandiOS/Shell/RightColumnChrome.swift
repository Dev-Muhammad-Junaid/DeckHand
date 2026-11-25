//
//  RightColumnChrome.swift
//  DeckHandiOS – Shell
//
//  The right column's own controls (OR-06): the Deck | Ask switch with the
//  collapse button beside it, and the slim edge handle the column leaves
//  when collapsed. The rules (which arrangements have the column, which can
//  collapse it, the per-arrangement memory) are `RightColumnPlan` and
//  `RightColumnMemory` in Core; the shell lays these out.
//
//  The switch shows its selection by colour and fill only: no dot, no bar
//  under the selected half, nothing that slides. Panels fade (180 ms
//  ease-out); under Reduce Motion they change at once.
//

import SwiftUI

/// Deck | Ask, then the collapse button where the arrangement allows it.
struct RightColumnSwitch: View {
    @Binding var mode: RightColumnMode
    let canCollapse: Bool
    let onCollapse: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            HStack(spacing: 2) {
                ForEach(RightColumnMode.allCases, id: \.self) { item in
                    segment(item)
                }
            }
            .padding(2)
            .background(PixelHandTheme.fill, in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)

            if canCollapse {
                GlassCircleButton(
                    glyph: PixelGlyphs.sidebar,
                    label: "Hide the column",
                    size: PixelHandTheme.ControlHeight.secondary,
                    action: onCollapse
                )
                .accessibilityIdentifier("ph.column.collapse")
            }
        }
        .frame(minHeight: PixelHandTheme.ControlHeight.secondary)
    }

    private func segment(_ item: RightColumnMode) -> some View {
        let isSelected = mode == item
        return Button {
            guard mode != item else { return }
            GestureHaptic.selection.trigger()
            mode = item
        } label: {
            HStack(spacing: PixelHandTheme.Space.xs) {
                PHGlyph(glyph: item == .deck ? PixelGlyphs.deck : PixelGlyphs.ask, pitch: PixelPitch.chip, stepsWithType: true)
                // VQ-087: glyphs only at AX3+ ("De… | Ask"); the Large
                // Content Viewer shows the word.
                if RightColumnMode.switchShowsTitles(band: typeSize.typeBand) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isSelected ? Color.white : PixelHandTheme.ink2)
            .padding(.horizontal, PixelHandTheme.Space.md)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(
                Capsule().fill(isSelected ? PixelHandTheme.accent : Color.clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .phosphorFocusable(cornerRadius: 16)
        .accessibilityShowsLargeContentViewer {
            Text(item.title)
        }
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(item == .deck ? "ph.column.deck" : "ph.column.ask")
    }
}

/// The collapsed column: a slim rounded bar on the trailing edge with a
/// 44 pt touch target. A tap brings the column back.
struct RightColumnHandle: View {
    let mode: RightColumnMode
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            Capsule()
                .fill(PixelHandTheme.raised)
                .overlay(Capsule().strokeBorder(PixelHandTheme.hairline, lineWidth: PixelHandTheme.Stroke.hairline))
                .frame(width: 6, height: 72)
                .frame(width: CGFloat(RightColumnPlan.handleWidth))
                .frame(maxHeight: .infinity)
                // The touch target reaches past the slim bar to 44 pt.
                .contentShape(Rectangle().inset(by: -CGFloat(RightColumnPlan.handleHitWidth - RightColumnPlan.handleWidth) / 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .ask ? "Show Ask" : "Show the deck")
        .accessibilityHint("Opens the column beside the canvas")
        .accessibilityIdentifier("ph.column.expand")
    }
}

extension Animation {
    /// Panels and status rows: a 180 ms ease-out fade, or no animation
    /// under Reduce Motion (the owner's motion rule).
    static func phPanelFade(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }
}
