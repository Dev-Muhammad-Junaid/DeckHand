//
//  MacPill.swift
//  DeckHandiOS – Design system
//
//  The header's Mac pill: a navy tile with the Mac glyph and its live pixel,
//  the Mac's name and the front app (or approval state), on glass, 44 pt.
//  Offline shows a grey pixel; locked shows the lock glyph. At AX1+ the
//  second line drops before the name truncates; at AX3+ the name gets two
//  lines, broken between words, never hyphenated, and the first word
//  shrinks rather than cut (build 22). Names truncate at the tail.
//  Spec: `02-Design-System.md` §7, board `.macpill`.
//

import SwiftUI

struct MacPill: View {
    enum Status { case online, offline, locked }

    let name: String
    var subtitle: String?
    var status: Status = .online
    /// 2 at the Huge type band: the name wraps rather than collapsing to
    /// "…" (`ShellHeaderPlan.pillNameLines`, VQ-065).
    var nameLines = 1
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
                nameText
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

    /// The name, breaking only between words (build 19: at AX3 a wrapped
    /// `Text` hyphenated it, "Muham- / mad’s Mac…"). Each line is its own
    /// one-line `Text`, which never hyphenates; `ViewThatFits` picks the
    /// first whole-word layout that fits (`ShellHeaderPlan.pillNameLayout`):
    /// the word splits, then the tail ones ("Muhammad’s / MacBook…").
    /// Build 22: when none fits, the fallback still has two lines, and its
    /// first word shrinks before it truncates, so the pill never reads
    /// "Muhamma…" on one line.
    @ViewBuilder
    private var nameText: some View {
        let layout = ShellHeaderPlan.pillNameLayout(name, lines: nameLines)
        if layout.candidates.count == 1, layout.fallback == layout.candidates[0] {
            nameLine(layout.fallback.first ?? name)
        } else {
            ViewThatFits(in: .horizontal) {
                ForEach(layout.candidates.indices, id: \.self) { index in
                    nameStack(layout.candidates[index])
                }
                nameStack(layout.fallback, minimumScale: ShellHeaderPlan.pillNameMinimumScale)
            }
        }
    }

    private func nameStack(_ lines: [String], minimumScale: Double = 1) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines.indices, id: \.self) { line in
                nameLine(lines[line])
                    .minimumScaleFactor(CGFloat(minimumScale))
            }
        }
        // Its full height, even in a tight header (build 22: the second
        // line was lost and the first cut).
        .fixedSize(horizontal: false, vertical: true)
    }

    private func nameLine(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(PixelHandTheme.ink)
            .lineLimit(1)
            .truncationMode(.tail)
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
        case .online: parts = ["\(name) focused"]
        case .offline: parts.append("offline")
        case .locked: parts.append("locked")
        }
        if let subtitle, subtitle.lowercased() != parts.last?.lowercased() { parts.append(subtitle) }
        return parts.joined(separator: ", ")
    }
}

#Preview("Mac pill") {
    VStack(alignment: .leading, spacing: 12) {
        MacPill(name: "Studio", subtitle: "Xcode", action: {})
        MacPill(name: "Mac mini", subtitle: "Locked", status: .locked)
        MacPill(name: "Office iMac", subtitle: "Offline", status: .offline)
        MacPill(name: "Muhammad’s MacBook Pro", nameLines: 2, action: {})
            .frame(width: 180, alignment: .leading)
    }
    .padding(16)
    .background(.phCanvas)
}
