//
//  MyMacsPlaceholderSheet.swift
//  DeckHandiOS – Shell
//
//  What the Mac pill opens until My Macs ships (UX-008 now, UX-030 in 1.3):
//  the connected Mac as a card (navy 16:10 tile, live pixel, name, front
//  app), the other paired Macs dimmed, a note that switching arrives in
//  1.3, and Disconnect. Board: `v2Macs` (`.mcard`).
//

import SwiftUI

struct MyMacsPlaceholderSheet: View {
    let currentMacName: String
    let currentSubtitle: String
    let isLive: Bool
    let onDisconnect: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var otherMacs: [PairedDevice] {
        PairedMacsStore.shared.macs.filter { $0.kind == .mac && $0.name != currentMacName }
    }

    private var columns: [GridItem] {
        let count = typeSize.typeBand >= .large ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: PixelHandTheme.Space.md, alignment: .top), count: count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PixelHandTheme.Space.xl) {
                    LazyVGrid(columns: columns, spacing: PixelHandTheme.Space.md) {
                        MacCardPlaceholder(name: currentMacName, subtitle: currentSubtitle, isLive: isLive, isFocused: true)
                        ForEach(otherMacs) { mac in
                            MacCardPlaceholder(name: mac.name, subtitle: "Paired", isLive: false, isFocused: false)
                        }
                    }

                    HStack(alignment: .top, spacing: PixelHandTheme.Space.md) {
                        PHGlyph(glyph: PixelGlyphs.mac, pitch: PixelPitch.chip)
                            .foregroundStyle(PixelHandTheme.accent)
                        Text("Switching between Macs from here, and swiping the Mac pill to the next one, arrive in Pixel Hand 1.3.")
                            .font(.subheadline)
                            .foregroundStyle(PixelHandTheme.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button("Disconnect from \(currentMacName)", role: .destructive, action: onDisconnect)
                        .buttonStyle(.ph(.destructive, size: .regular, fullWidth: true))
                }
                .padding(.horizontal, PixelHandTheme.Space.lg)
                .padding(.vertical, PixelHandTheme.Space.sm)
            }
            .background(PixelHandTheme.elevated)
            .navigationTitle("My Macs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// A Mac card at the placeholder's level: a navy 16:10 tile with the Mac
/// glyph, the live pixel and a 2 pt cobalt ring on the focused Mac.
private struct MacCardPlaceholder: View {
    let name: String
    let subtitle: String
    let isLive: Bool
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                    .fill(PixelHandTheme.Brand.screenSurface)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .overlay(
                        PHGlyph(glyph: PixelGlyphs.mac, pitch: 4, accent: PixelHandTheme.Brand.glow)
                            .foregroundStyle(isLive ? PixelHandTheme.Brand.phosphor : PixelHandTheme.Brand.dotOff)
                    )
                    .pixelOnNavy()
                Group {
                    if isLive {
                        LivePixel(color: PixelHandTheme.Brand.mint, size: 8)
                    } else {
                        StatusPixel(state: .off, size: 8)
                    }
                }
                .padding(PixelHandTheme.Space.sm)
            }
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip + 4, style: .continuous)
                        .strokeBorder(PixelHandTheme.accent, lineWidth: PixelHandTheme.Stroke.selection)
                        .padding(-4)
                }
            }
            VStack(alignment: .leading, spacing: PixelHandTheme.Space.xs) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PixelHandTheme.ink)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PixelHandTheme.ink2)
                    .lineLimit(2)
            }
            .padding(.horizontal, PixelHandTheme.Space.xs)
        }
        .opacity(isLive || isFocused ? 1 : 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([name, isFocused ? "connected" : nil, subtitle].compactMap { $0 }.joined(separator: ", "))
    }
}
