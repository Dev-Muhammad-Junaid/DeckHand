//
//  MacPill.swift
//  DeckHandiOS – Design system
//
//  The header's Mac pill: a navy tile with the Mac glyph and its live pixel,
//  the Mac's name and the front app (or approval state), on glass, 44 pt.
//  Offline shows a grey pixel; locked shows the lock glyph. At AX1+ the
//  second line drops before the name truncates.
//  Spec: `02-Design-System.md` §7, board `.macpill`.
//

import SwiftUI

struct MacPill: View {
    enum Status { case online, offline, locked }

    let name: String
    var subtitle: String?
    var status: Status = .online
    var action: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
                    .phosphorFocusable(cornerRadius: PixelHandTheme.ControlHeight.hit / 2)
            } else {
                content
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(action == nil ? [] : .isButton)
    }

    private var content: some View {
        HStack(spacing: PixelHandTheme.Space.sm) {
            tile
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(PixelHandTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle, typeSize.typeBand == .standard {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(PixelHandTheme.ink2)
                        .lineLimit(1)
                }
            }
            if action != nil {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(PixelHandTheme.ink2)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, PixelHandTheme.Space.sm)
        .padding(.trailing, PixelHandTheme.Space.md)
        .frame(minHeight: PixelHandTheme.ControlHeight.standard)
        .phGlass(in: Capsule(), interactive: action != nil)
        .contentShape(Capsule())
    }

    private var tile: some View {
        PHGlyph(glyph: status == .locked ? PixelGlyphs.lock : PixelGlyphs.mac, pitch: 1.8, accent: PixelHandTheme.Brand.glow)
            .foregroundStyle(Color(red: 0.81, green: 0.88, blue: 1))
            .frame(width: 28, height: 28)
            .background(PixelHandTheme.Brand.screenGradient, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PixelHandTheme.Radius.kbd, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: PixelHandTheme.Stroke.hairline)
            )
            .overlay(alignment: .topTrailing) {
                Group {
                    if status == .online {
                        LivePixel(color: PixelHandTheme.Brand.mint, size: 8)
                    } else {
                        StatusPixel(state: .off, size: 8)
                    }
                }
                .padding(2)
                .background(PixelHandTheme.canvas, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                .offset(x: 4, y: -4)
            }
    }

    private var accessibilityText: String {
        var parts = [name]
        switch status {
        case .online: break
        case .offline: parts.append("offline")
        case .locked: parts.append("locked")
        }
        if let subtitle { parts.append(subtitle) }
        return parts.joined(separator: ", ")
    }
}

#Preview("Mac pill") {
    VStack(alignment: .leading, spacing: 12) {
        MacPill(name: "Studio", subtitle: "Xcode", action: {})
        MacPill(name: "Mac mini", subtitle: "Locked", status: .locked)
        MacPill(name: "Office iMac", subtitle: "Offline", status: .offline)
    }
    .padding(16)
    .background(.phCanvas)
}
