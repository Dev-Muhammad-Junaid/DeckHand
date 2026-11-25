//
//  MacsSidebar.swift
//  DeckHandiOS – Shell
//
//  The Macs sidebar on wide windows (UX-007 built the list; UX-030 makes it
//  the switcher): "Macs" in Geist, a glyph button that collapses the
//  sidebar, then every Mac as a card with its live glance (`MacCard`), in
//  the same order as My Macs and ⌘1–⌘4. Tap a Mac to switch to it; the
//  canvas slides. 232 pt including its 24 pt leading margin
//  (`07-Polish-Spec.md` §1). Board: `v2PadLand` `.side`.
//

import SwiftUI

struct MacsSidebar: View {
    let currentMacName: String
    let currentSubtitle: String
    let isLive: Bool
    let onCollapse: () -> Void
    let onOpenMacs: () -> Void

    private let switcher = MacSwitcher.shared
    /// Stage Manager's window controls, so the title row starts after them
    /// like the header does (OR-05, VQ-080).
    @State private var windowControlsInset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.md) {
            // OR-05: the hide button leads the row, in the spot the header's
            // show button takes while the sidebar is hidden.
            HStack(spacing: PixelHandTheme.Space.sm) {
                SidebarToggleButton(sidebarShown: true, action: onCollapse)
                Text("Macs")
                    .font(.phDisplay())
                    .foregroundStyle(PixelHandTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .padding(.leading, windowControlsInset)
            .frame(height: CGFloat(SidebarTogglePlacement.rowHeight))
            .background { WindowControlsInset(inset: $windowControlsInset) }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: PixelHandTheme.Space.md) {
                    ForEach(switcher.listings) { listing in
                        Button {
                            pick(listing)
                        } label: {
                            MacCard(listing: listing, activeSubtitle: currentSubtitle)
                                .padding(4)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.card + 4)
                        .accessibilityIdentifier("ph.sidebar.mac")
                        .accessibilityHint(listing.isActive ? "Shows My Macs." : "Switches to \(listing.name).")
                    }

                    if let notice = switcher.notice {
                        Text(notice)
                            .font(.caption)
                            .foregroundStyle(PixelHandTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, PixelHandTheme.Space.xs)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.22), value: switcher.notice)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.leading, CGFloat(SidebarTogglePlacement.sidebarLeadingPadding))
        .padding(.bottom, PixelHandTheme.Space.lg)
        .frame(width: CGFloat(LayoutMetrics.sidebarWidth), alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Macs")
    }

    private func pick(_ listing: MacListing) {
        if listing.isActive {
            onOpenMacs()
        } else {
            GestureHaptic.selection.trigger()
            switcher.request(listing.deviceID)
        }
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
        .phosphorFocusable(cornerRadius: PixelHandTheme.ControlHeight.standard / 2)
        .accessibilityLabel("Ask")
        .accessibilityHint("Type what you want \(macName) to do")
        .accessibilityIdentifier("ph.ask")
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
        .phosphorFocusable(cornerRadius: size / 2)
        .accessibilityLabel("Ask")
        .accessibilityHint("Type what you want your Mac to do")
        .accessibilityIdentifier("ph.ask")
        .accessibilityShowsLargeContentViewer {
            Label { Text("Ask") } icon: { PHGlyph(glyph: PixelGlyphs.ask, pitch: PixelPitch.tabBar) }
        }
    }
}
