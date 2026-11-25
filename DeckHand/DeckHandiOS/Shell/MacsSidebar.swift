//
//  MacsSidebar.swift
//  DeckHandiOS – Shell
//
//  The Macs sidebar on wide windows (UX-007 built the list; UX-030 makes it
//  the switcher): "Macs" in Geist, a glyph button that collapses the
//  sidebar, then every Mac as a compact card (`CompactMacCard`: a small
//  tile with the live pixel, the name and one status line), in the same
//  order as My Macs and ⌘1–⌘4. Tap a Mac to switch to it. The sidebar only
//  switches Macs, so it is narrow: 176 pt including its 16 pt leading
//  margin (`LayoutMetrics.sidebarWidth`, OR-04), and the canvas gets the
//  room. My Macs keeps the full `MacCard`. Board: `v2PadLand` `.side`.
//

import SwiftUI

struct MacsSidebar: View {
    let currentMacName: String
    let currentSubtitle: String
    let isLive: Bool
    let onCollapse: () -> Void
    let onOpenMacs: () -> Void

    private let switcher = MacSwitcher.shared

    var body: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.md) {
            HStack(spacing: PixelHandTheme.Space.sm) {
                Text("Macs")
                    .font(.phDisplay())
                    .foregroundStyle(PixelHandTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
                VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
                    ForEach(switcher.listings) { listing in
                        Button {
                            pick(listing)
                        } label: {
                            CompactMacCard(listing: listing, activeSubtitle: currentSubtitle)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .phosphorFocusable(cornerRadius: PixelHandTheme.Radius.chip)
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
        .padding(.leading, CGFloat(LayoutMetrics.sidebarLeadingMargin))
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

/// A Mac in the narrow sidebar (OR-04): a 16:10 tile 44 pt wide with the
/// Mac glyph (the lock glyph while locked) and the live pixel, then the name
/// and one status line, each on one line. The focused Mac gets the cobalt
/// ring and a filled row; selection is colour and fill only. A Mac the free
/// plan doesn't cover shows the small Pro lock inside the tile's corner.
struct CompactMacCard: View {
    let listing: MacListing
    var activeSubtitle: String?

    @Environment(\.entitlements) private var entitlements
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isLocked: Bool { listing.glance?.isLocked ?? false }
    private var isFreeLocked: Bool {
        !entitlements.isPro && SubscriptionStore.shared.isLockedMac(deviceID: listing.deviceID)
    }

    var body: some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(listing.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PixelHandTheme.ink)
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .truncationMode(.tail)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(isLocked && listing.isActive ? PixelHandTheme.warning : PixelHandTheme.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(PixelHandTheme.Space.xs + 2)
        .background(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
                .fill(listing.isActive ? PixelHandTheme.accentTint : Color.clear)
        )
        .opacity(listing.isActive || listing.isConnecting || listing.isReachable ? 1 : 0.55)
        .animation(.easeOut(duration: 0.18), value: listing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isFreeLocked ? "Needs \(SubscriptionCopy.productName): the free plan works with one Mac" : "")
    }

    private var statusLine: String {
        if listing.isActive, let activeSubtitle, !isLocked { return activeSubtitle }
        return MacGlanceCopy.statusLine(for: listing, now: Date())
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(PixelHandTheme.Brand.screenSurface)
            .frame(width: 44, height: 28)
            .overlay {
                PHGlyph(glyph: isLocked ? PixelGlyphs.lock : PixelGlyphs.mac, pitch: 2, accent: PixelHandTheme.Brand.glow)
                    .foregroundStyle(listing.isActive ? PixelHandTheme.Brand.phosphor : PixelHandTheme.Brand.dotOff)
            }
            .overlay(alignment: .topTrailing) {
                Group {
                    if listing.isActive {
                        LivePixel(color: PixelHandTheme.Brand.mint, size: 4)
                    } else {
                        StatusPixel(state: listing.isReachable ? .live : .off, size: 4)
                            .opacity(listing.isReachable ? 0.7 : 1)
                    }
                }
                .padding(3)
            }
            .overlay {
                if listing.isActive {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(PixelHandTheme.accent, lineWidth: PixelHandTheme.Stroke.selection)
                        .padding(-2)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isFreeLocked {
                    ProLockBadge()
                        .scaleEffect(0.8)
                        .offset(x: 4, y: 4)
                }
            }
            .pixelOnNavy()
    }

    private var accessibilityText: String {
        var parts = [listing.name]
        if listing.isActive { parts.append("connected") }
        parts.append(statusLine)
        if let slot = listing.slot { parts.append("Command \(slot)") }
        return parts.joined(separator: ", ")
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
