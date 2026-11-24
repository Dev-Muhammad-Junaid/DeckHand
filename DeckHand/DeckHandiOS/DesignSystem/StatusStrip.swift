//
//  StatusStrip.swift
//  DeckHandiOS – Design system
//
//  The "now playing" LED panel: always navy (`screen` @ 84 %), a 0.5 pt rim,
//  a status pixel at the leading end and dot-matrix items joined by " · ".
//  Truncates at a separator by dropping trailing items, never mid-word.
//  Also the link badge and desktop dots that sit next to it.
//  Spec: `Product/Design/06-Pixel-Identity.md` §3–§4.
//

import SwiftUI

/// A 6 pt square status light: mint live, amber needs-you, grey offline.
/// Lit only while a Mac is talking.
struct StatusPixel: View {
    enum Kind { case live, needsYou, off }

    var state: Kind = .live
    var size: CGFloat = 6

    var body: some View {
        let color: Color = switch state {
        case .live: PixelHandTheme.Brand.mint
        case .needsYou: Color(red: 1, green: 0.71, blue: 0.28)
        case .off: Color(red: 0.29, green: 0.32, blue: 0.44)
        }
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: state == .off ? .clear : color.opacity(0.9), radius: size / 2)
            .accessibilityHidden(true)
    }
}

struct StatusStrip: View {
    enum Style {
        /// Phosphor text, mint pixel.
        case live
        /// Amber text and pixel: dialog waiting, permission missing.
        case needsYou
        /// `#6D7BB8` text, grey pixel, unlit cells shown: locked, offline.
        case dim
    }

    let items: [String]
    var style: Style = .live
    /// 1.3 Mac cards · 1.4 floating tile · 1.6–1.8 mirror · 2 widgets/stats.
    var pitch: CGFloat = 2
    /// Spoken instead of the dot text, e.g. "Studio, display 1 of 2, 60 frames per second".
    var accessibilityText: String?
    /// Fallbacks to try in turn, widest first (`MirrorPaneChrome
    /// .stripCandidates`: name shortened, then dropped, then trailing
    /// items). `nil` drops trailing items only.
    var candidates: [[String]]?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(fallbacks.enumerated()), id: \.offset) { _, shown in
                row(shown)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText ?? items.joined(separator: ", "))
    }

    private var fallbacks: [[String]] {
        if let candidates, !candidates.isEmpty { return candidates }
        return (1...max(items.count, 1)).reversed().map { Array(items.prefix($0)) }
    }

    private var height: CGFloat {
        switch pitch {
        case ..<1.35: 16
        case ..<1.5: 18
        case ..<1.9: 20
        default: 24
        }
    }

    private func row(_ shown: [String]) -> some View {
        HStack(spacing: pitch < 1.5 ? 5 : 8) {
            StatusPixel(state: pixelState, size: pitch < 1.5 ? 5 : 6)
            DotMatrixText(shown.joined(separator: " · "), pitch: pitch, showsUnlit: false, glows: style != .dim, stepsWithType: false)
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, pitch < 1.5 ? 6 : 8)
        .frame(height: height)
        .background(PixelHandTheme.Brand.screen.opacity(0.84), in: RoundedRectangle(cornerRadius: pitch < 1.5 ? 6 : 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: pitch < 1.5 ? 6 : 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: PixelHandTheme.Stroke.hairline)
        )
        .fixedSize()
        .pixelOnNavy()
    }

    private var pixelState: StatusPixel.Kind {
        switch style {
        case .live: .live
        case .needsYou: .needsYou
        case .dim: .off
        }
    }

    private var textColor: Color {
        switch style {
        case .live: PixelHandTheme.Brand.phosphor
        case .needsYou: Color(red: 1, green: 0.84, blue: 0.6)
        case .dim: PixelHandTheme.Brand.stripDim
        }
    }
}

/// Wired / VPN / Wi-Fi / Direct: a 20 pt badge with a glyph and a dot-matrix
/// label at pitch 1.4. Wired is mint, VPN cobalt tint, the others muted.
struct LinkBadge: View {
    enum Kind: CaseIterable {
        case wired, vpn, wifi, direct

        var glyph: GlyphBitmap {
            switch self {
            case .wired: PixelGlyphs.wired
            case .vpn: PixelGlyphs.vpn
            case .wifi, .direct: PixelGlyphs.wifi
            }
        }

        var text: String {
            switch self {
            case .wired: "WIRED"
            case .vpn: "VPN"
            case .wifi: "WI-FI"
            case .direct: "DIRECT"
            }
        }

        var spoken: String {
            switch self {
            case .wired: "Wired connection"
            case .vpn: "Connected over VPN"
            case .wifi: "Connected over Wi-Fi"
            case .direct: "Direct connection"
            }
        }
    }

    let kind: Kind
    @Environment(\.pixelOnNavy) private var onNavy

    var body: some View {
        HStack(spacing: 5) {
            PHGlyph(glyph: kind.glyph, pitch: PixelPitch.badge, accent: foreground)
            DotMatrixText(kind.text, pitch: 1.4, glows: false)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .frame(height: PixelHandTheme.ControlHeight.badge)
        .background(background, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.badge, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.spoken)
    }

    private var foreground: Color {
        switch kind {
        case .wired: onNavy ? PixelHandTheme.Brand.mint : PixelHandTheme.success
        case .vpn: PixelHandTheme.accentInk
        case .wifi, .direct: PixelHandTheme.ink2
        }
    }

    private var background: Color {
        switch kind {
        case .wired: onNavy ? PixelHandTheme.Brand.mint.opacity(0.16) : PixelHandTheme.successTint
        case .vpn: PixelHandTheme.accentTint
        case .wifi, .direct: PixelHandTheme.fill
        }
    }
}

/// 6 pt desktop dots, 5 pt apart: current phosphor with glow (accent on
/// light), others unlit, full-screen app desktops hollow.
struct DesktopDots: View {
    let count: Int
    let current: Int
    var fullScreen: Set<Int> = []

    @Environment(\.pixelOnNavy) private var onNavy

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(count, 0), id: \.self) { index in
                let shape = RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                Group {
                    if fullScreen.contains(index) && index != current {
                        shape.strokeBorder(onNavy ? Color(red: 0.53, green: 0.63, blue: 1).opacity(0.6) : PixelHandTheme.ink3, lineWidth: 1.2)
                    } else if index == current {
                        shape.fill(onNavy ? PixelHandTheme.Brand.phosphor : PixelHandTheme.accent)
                            .shadow(color: onNavy ? PixelHandTheme.Brand.glow : .clear, radius: 3)
                    } else {
                        shape.fill(onNavy ? Color(red: 0.53, green: 0.63, blue: 1).opacity(0.32) : PixelHandTheme.fill2)
                    }
                }
                .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Desktop \(current + 1) of \(count)")
    }
}

#Preview("Status strip and badges") {
    VStack(alignment: .leading, spacing: 12) {
        StatusStrip(items: ["STUDIO", "DISPLAY 1/2", "DESK 2/3", "60 FPS", "7 MS"])
        StatusStrip(items: ["MACBOOK AIR", "PAGES", "DIALOG WAITING"], style: .needsYou)
        StatusStrip(items: ["MAC MINI", "LOCKED"], style: .dim)
        StatusStrip(items: ["LIVE", "D1", "60"], pitch: 1.4)
        StatusStrip(items: ["STUDIO", "D1/2", "DESK 2/3", "60 FPS"], pitch: 1.6)
            .frame(width: 140, alignment: .leading)
        HStack(spacing: 8) {
            ForEach(LinkBadge.Kind.allCases, id: \.self) { LinkBadge(kind: $0) }
        }
        DesktopDots(count: 3, current: 1, fullScreen: [2]).pixelOnNavy()
            .padding(8).background(PixelHandTheme.Brand.screen)
    }
    .padding(16)
    .background(.phCanvas)
}
