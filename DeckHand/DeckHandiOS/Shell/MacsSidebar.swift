//
//  MacsSidebar.swift
//  DeckHandiOS – Shell
//
//  The Macs sidebar on wide windows (UX-007; the list itself grows in
//  UX-030 / 1.3): "Macs" in Geist, a glyph button that collapses the
//  sidebar, then the connected Mac's card (ring, live pixel) and the other
//  paired Macs dimmed, from `PairedMacsStore`. Tapping another Mac opens My
//  Macs, which says switching arrives in 1.3. 232 pt including its 24 pt
//  leading margin (`07-Polish-Spec.md` §1). Board: `v2PadLand` `.side`.
//

import SwiftUI

struct MacsSidebar: View {
    let currentMacName: String
    let currentSubtitle: String
    let isLive: Bool
    let onCollapse: () -> Void
    let onOpenMacs: () -> Void

    private var otherMacs: [PairedDevice] {
        PairedMacsStore.shared.macs.filter { $0.kind == .mac && $0.name != currentMacName }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.md) {
            HStack(spacing: PixelHandTheme.Space.sm) {
                Text("Macs")
                    .font(.phDisplay())
                    .foregroundStyle(PixelHandTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                GlassCircleButton(
                    glyph: PixelGlyphs.sidebar,
                    label: "Hide the Macs sidebar",
                    size: PixelHandTheme.ControlHeight.secondary,
                    action: onCollapse
                )
            }
            .frame(height: PixelHandTheme.ControlHeight.standard)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: PixelHandTheme.Space.md) {
                    MacCardPlaceholder(name: currentMacName, subtitle: currentSubtitle, isLive: isLive, isFocused: true)
                        .padding(4)
                    ForEach(otherMacs) { mac in
                        Button(action: onOpenMacs) {
                            MacCardPlaceholder(name: mac.name, subtitle: "Paired", isLive: false, isFocused: false)
                                .padding(4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows My Macs.")
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.leading, PixelHandTheme.Space.xl)
        .padding(.bottom, PixelHandTheme.Space.lg)
        .frame(width: CGFloat(LayoutMetrics.sidebarWidth), alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Macs")
    }
}

/// Ask as a glass field on wide windows (`03-Layout-Strategy.md`: "Ask
/// field ⌘K"): the Ask glyph, "Tell <Mac>…" and the shortcut. Opens the Ask
/// sheet; ⌘K works from a hardware keyboard.
struct AskField: View {
    let macName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PixelHandTheme.Space.sm) {
                PHGlyph(glyph: PixelGlyphs.ask, pitch: PixelPitch.chip)
                    .foregroundStyle(PixelHandTheme.ink)
                Text("Tell \(macName)…")
                    .font(.subheadline)
                    .foregroundStyle(PixelHandTheme.ink3)
                    .lineLimit(1)
                Spacer(minLength: PixelHandTheme.Space.sm)
                Text("⌘K")
                    .font(.phChord)
                    .foregroundStyle(PixelHandTheme.ink3)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, PixelHandTheme.Space.lg)
            .frame(maxWidth: .infinity, minHeight: PixelHandTheme.ControlHeight.standard)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .phGlass(in: Capsule(), interactive: true)
        .keyboardShortcut("k", modifiers: .command)
        .accessibilityLabel("Ask")
        .accessibilityHint("Type what you want \(macName) to do")
    }
}

/// Ask as a glass circle: next to the dock on iPad portrait, and in the
/// wide header when the row has no room for the field.
struct AskCircleButton: View {
    var size: CGFloat = PixelHandTheme.ControlHeight.dock
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PHGlyph(glyph: PixelGlyphs.ask, pitch: size >= PixelHandTheme.ControlHeight.dock ? PixelPitch.tabBar : PixelPitch.header)
                .foregroundStyle(PixelHandTheme.ink)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .phGlass(in: Circle(), interactive: true)
        .keyboardShortcut("k", modifiers: .command)
        .accessibilityLabel("Ask")
        .accessibilityHint("Type what you want your Mac to do")
        .accessibilityShowsLargeContentViewer {
            Label { Text("Ask") } icon: { PHGlyph(glyph: PixelGlyphs.ask, pitch: PixelPitch.tabBar) }
        }
    }
}
