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

import PixelHandCore
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .padding(.leading, windowControlsInset)
            .frame(height: CGFloat(SidebarTogglePlacement.rowHeight))
            .background { WindowControlsInset(inset: $windowControlsInset) }

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

/// A Mac in the narrow sidebar (OR-04): a 16:10 tile 44 pt wide with the
/// Mac glyph (the lock glyph while locked) and the live pixel, then the name
/// and one status line, each on one line. At the Huge band the tile sits
/// on top and the name and status wrap in whole words under it (VQ-099). The focused Mac gets the cobalt
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

    /// The name and status sizes at the current Dynamic Type size.
    @ScaledMetric(relativeTo: .subheadline) private var nameSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var statusSize: CGFloat = 12

    private var band: TypeBand { typeSize.typeBand }

    var body: some View {
        // VQ-099: at AX3 the row left ~96 pt beside the tile and cut names
        // mid-word ("Muh / am…"). At the Huge band the card stacks and the
        // text gets the card's whole width (`SidebarCardPlan`).
        let layout = SidebarCardPlan.arrangement(band: band) == .stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PixelHandTheme.Space.xs))
            : AnyLayout(HStackLayout(spacing: PixelHandTheme.Space.sm))
        layout {
            tile
            texts
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
        .accessibilityShowsLargeContentViewer {
            Text("\(listing.name)\n\(statusLine)")
        }
    }

    /// The name and the status line. From AX1 each is laid out in whole
    /// words (`WholeWordName`), shrinking before it would cut one.
    @ViewBuilder
    private var texts: some View {
        let statusColor = isLocked && listing.isActive ? PixelHandTheme.warning : PixelHandTheme.ink2
        if SidebarCardPlan.usesWholeWords(band: band) {
            VStack(alignment: .leading, spacing: 2) {
                WholeWordName(name: listing.name, lines: SidebarCardPlan.nameLines(band: band), size: nameSize)
                WholeWordName(name: statusLine, lines: SidebarCardPlan.statusLines(band: band), size: statusSize, weight: .regular, color: statusColor)
                    .contentTransition(.opacity)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(listing.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PixelHandTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
            }
        }
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
            // On the tile's bottom-trailing corner, above it (OT-14).
            .controlBadge(isFreeLocked ? .proLockSmall : nil, style: .init(shape: .roundedRect(radius: 8), corner: .bottomTrailing, anchor: .rim))
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

/// The header's compact ⌘K button on wide windows (owner testing, build
/// 27, OT-18; it replaces the wide "Tell <Mac>…" field): a 44 pt glass
/// capsule with the Ask glyph and the chord, tooltip "Ask (⌘K)". It opens
/// Ask exactly as the field did (the shell's `openAsk`: the right column,
/// expanded, else the sheet), and ⌘K still works from a hardware keyboard.
/// While Ask shows in the column it reads as open; while Ask's field has
/// focus it is lit (`HeaderAskButton.State`). A command palette would plug
/// in at `HeaderAskButton.Command` (see there).
struct AskShortcutButton: View {
    let macName: String
    var state: HeaderAskButton.State = .idle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PixelHandTheme.Space.sm) {
                PHGlyph(glyph: PixelGlyphs.ask, pitch: PixelPitch.header)
                Text(HeaderAskButton.chord)
                    .font(.phChord)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            .foregroundStyle(state.isLit ? PixelHandTheme.accent : PixelHandTheme.ink)
            .padding(.horizontal, PixelHandTheme.Space.md)
            .frame(minWidth: CGFloat(HeaderAskButton.width), minHeight: PixelHandTheme.ControlHeight.standard)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .phGlass(in: Capsule(), interactive: true)
        .overlay {
            // Open in the column: the 2 pt accent ring, like a focused card.
            if state != .idle {
                Capsule()
                    .strokeBorder(PixelHandTheme.accent.opacity(state.isLit ? 1 : 0.5), lineWidth: PixelHandTheme.Stroke.selection)
                    .allowsHitTesting(false)
            }
        }
        .fixedSize()
        .keyboardShortcut(KeyEquivalent(HeaderAskButton.key), modifiers: .command)
        .help(HeaderAskButton.tooltip)
        .phosphorFocusable(cornerRadius: PixelHandTheme.ControlHeight.standard / 2)
        .accessibilityLabel("Ask")
        .accessibilityValue(state.spokenValue)
        .accessibilityHint("Type what you want \(macName) to do. Command K.")
        .accessibilityAddTraits(state.isSelected ? .isSelected : [])
        .accessibilityIdentifier("ph.ask")
        .accessibilityShowsLargeContentViewer {
            Label { Text(HeaderAskButton.tooltip) } icon: { PHGlyph(glyph: PixelGlyphs.ask, pitch: PixelPitch.tabBar) }
        }
        .animation(PixelHandMotion.quick, value: state)
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
