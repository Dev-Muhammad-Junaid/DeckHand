//
//  MacCard.swift
//  DeckHandiOS – Macs
//
//  A Mac card with its glance tier (UX-030; board `v2Macs` `.mcard`): a
//  navy 16:10 tile with the Mac glyph (the lock glyph while locked), the
//  live pixel, the link badge and the ⌘ shortcut; then the name and one
//  status line (front app, "Locked", "Nearby · last in Safari", "Not found
//  · seen 2 h ago"). The focused Mac gets the 2 pt cobalt ring. A Mac the
//  free plan doesn't cover shows the Store lane's PRO badge. One component
//  for My Macs and the iPad sidebar (`07-Polish-Spec.md` §5.9).
//

import SwiftUI

struct MacCard: View {
    let listing: MacListing
    /// Replaces the focused Mac's status line (the approval state while
    /// the Mac hasn't allowed this device yet).
    var activeSubtitle: String?

    @Environment(\.dynamicTypeSize) private var typeSize

    private var isLocked: Bool { listing.glance?.isLocked ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: PixelHandTheme.Space.sm) {
            tile
                .overlay {
                    if listing.isActive {
                        RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip + 4, style: .continuous)
                            .strokeBorder(PixelHandTheme.accent, lineWidth: PixelHandTheme.Stroke.selection)
                            .padding(-4)
                    } else if listing.isConnecting {
                        RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip + 4, style: .continuous)
                            .strokeBorder(PixelHandTheme.Brand.phosphor.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 5]))
                            .padding(-4)
                    }
                }
                .freeMacBadge(deviceID: listing.deviceID) // Store lane: PRO on a Mac the free plan doesn't cover
            VStack(alignment: .leading, spacing: PixelHandTheme.Space.xs) {
                Text(listing.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PixelHandTheme.ink)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(isLocked && listing.isActive ? PixelHandTheme.warning : PixelHandTheme.ink2)
                    .lineLimit(2)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, PixelHandTheme.Space.xs)
        }
        .opacity(listing.isActive || listing.isConnecting || listing.isReachable ? 1 : 0.55)
        .animation(.easeOut(duration: 0.22), value: listing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var statusLine: String {
        if listing.isActive, let activeSubtitle, !isLocked { return activeSubtitle }
        return MacGlanceCopy.statusLine(for: listing, now: Date())
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: PixelHandTheme.Radius.chip, style: .continuous)
            .fill(PixelHandTheme.Brand.screenSurface)
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                if listing.isConnecting {
                    DotWave(pitch: 3, label: "Connecting to \(listing.name)")
                } else {
                    PHGlyph(glyph: isLocked ? PixelGlyphs.lock : PixelGlyphs.mac, pitch: 4, accent: PixelHandTheme.Brand.glow)
                        .foregroundStyle(listing.isActive ? PixelHandTheme.Brand.phosphor : PixelHandTheme.Brand.dotOff)
                }
            }
            .overlay(alignment: .topTrailing) {
                Group {
                    if listing.isActive {
                        LivePixel(color: PixelHandTheme.Brand.mint, size: 8)
                    } else {
                        StatusPixel(state: listing.isReachable ? .live : .off, size: 8)
                            .opacity(listing.isReachable ? 0.7 : 1)
                    }
                }
                .padding(PixelHandTheme.Space.sm)
            }
            .overlay(alignment: .bottomLeading) {
                if let link = linkBadge, typeSize.typeBand == .standard {
                    LinkBadge(kind: link)
                        .padding(PixelHandTheme.Space.xs + 2)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let slot = listing.slot, typeSize.typeBand == .standard {
                    Text(MacGlanceCopy.chord(slot: slot))
                        .font(.phChord)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(PixelHandTheme.Space.sm)
                        .accessibilityHidden(true)
                }
            }
            .pixelOnNavy()
    }

    /// Cable and VPN always; Wi-Fi only on the focused Mac, where it's known.
    private var linkBadge: LinkBadge.Kind? {
        let link: LinkKind? = listing.isActive ? listing.glance?.link : (listing.isReachable && !listing.isNearby ? .tunnel : nil)
        switch link {
        case .wired, .ethernet: return .wired
        case .tunnel: return .vpn
        case .wifi: return listing.isActive ? .wifi : nil
        case .peerToPeer: return listing.isActive ? .direct : nil
        default: return nil
        }
    }

    private var accessibilityText: String {
        var parts = [listing.name]
        if listing.isActive { parts.append("connected") }
        parts.append(statusLine)
        if let link = linkBadge { parts.append(link.spoken) }
        if let slot = listing.slot { parts.append("Command \(slot)") }
        return parts.joined(separator: ", ")
    }
}
