//
//  SurfaceTabBar.swift
//  DeckHandiOS – Shell
//
//  The glass tab bar: Pointer / Screen / Deck with pixel glyphs at pitch 2.6,
//  plus the Ask circle in the search slot. The selected tab shows by colour
//  and fill only (accent tint on a `fill2` capsule); no dot under it (OR-01). Horizontal at the bottom, or a vertical rail on short, wide
//  windows (iPhone landscape). At AX1+ labels drop and long-press shows the
//  Large Content Viewer.
//
//  Drawn by hand rather than with `TabView` so the tabs carry the pixel
//  glyphs and the layout works the same on iOS 17.4 and 26 (Liquid Glass
//  via `phGlass`). Board: `.sdock`, `.tabs`, `.ask`.
//

import SwiftUI

struct SurfaceTabBar: View {
    @Binding var selection: ControlSurface
    var tabs: [ControlSurface] = ControlSurface.allCases
    var axis: Axis = .horizontal
    let onAsk: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsLabels: Bool { typeSize.typeBand == .standard && axis == .horizontal }

    var body: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: PixelHandTheme.Space.md))
            : AnyLayout(VStackLayout(spacing: PixelHandTheme.Space.md))
        layout {
            tabGroup
            askButton
        }
        .phGlassGroup(spacing: PixelHandTheme.Space.md)
    }

    private var tabGroup: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 2))
            : AnyLayout(VStackLayout(spacing: 2))
        return layout {
            ForEach(tabs) { surface in
                tabButton(surface)
            }
        }
        .padding(4)
        .frame(height: axis == .horizontal ? 62 : nil)
        .frame(width: axis == .vertical ? 62 : nil)
        .phGlass(in: Capsule(), interactive: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Surfaces")
    }

    private func tabButton(_ surface: ControlSurface) -> some View {
        let isOn = selection == surface
        return Button {
            // Colour and fill only: the selected capsule fades in place
            // (instant under Reduce Motion); no dot, no sliding marker.
            withAnimation(PixelHandMotion.panelFade(reduceMotion: reduceMotion)) {
                selection = surface
            }
        } label: {
            VStack(spacing: 4) {
                PHGlyph(glyph: surface.glyph, pitch: PixelPitch.tabBar)
                if showsLabels {
                    Text(surface.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isOn ? PixelHandTheme.accent : PixelHandTheme.ink)
            .frame(maxWidth: axis == .horizontal ? .infinity : nil)
            .frame(width: axis == .vertical ? 54 : nil, height: 54)
            .background {
                if isOn {
                    Capsule()
                        .fill(PixelHandTheme.fill2)
                        .transition(.opacity)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .phosphorFocusable(cornerRadius: 27)
        .accessibilityLabel(surface.title)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("ph.tab.\(surface.rawValue)")
        .accessibilityShowsLargeContentViewer {
            Label { Text(surface.title) } icon: { PHGlyph(glyph: surface.glyph, pitch: PixelPitch.tabBar) }
        }
    }

    private var askButton: some View {
        Button(action: onAsk) {
            PHGlyph(glyph: PixelGlyphs.ask, pitch: PixelPitch.tabBar)
                .foregroundStyle(PixelHandTheme.ink)
                .frame(width: 62, height: 62)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .phGlass(in: Circle(), interactive: true)
        .keyboardShortcut("k", modifiers: .command)
        .phosphorFocusable(cornerRadius: 31)
        .accessibilityLabel("Ask")
        .accessibilityIdentifier("ph.tab.ask")
        .accessibilityHint("Type what you want your Mac to do")
        .accessibilityShowsLargeContentViewer {
            Label { Text("Ask") } icon: { PHGlyph(glyph: PixelGlyphs.ask, pitch: PixelPitch.tabBar) }
        }
    }
}

private struct TabBarPreview: View {
    @State private var selection = ControlSurface.pointer

    var body: some View {
        VStack(spacing: 24) {
            SurfaceTabBar(selection: $selection) {}
            SurfaceTabBar(selection: $selection, axis: .vertical) {}
        }
        .padding(16)
        .background(.phCanvas)
    }
}

#Preview("Tab bar") {
    TabBarPreview()
}
