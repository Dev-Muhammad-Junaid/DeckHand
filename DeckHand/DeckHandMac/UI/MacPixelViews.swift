//
//  MacPixelViews.swift
//  DeckHandMac – UI
//
//  The pixel identity for the Mac panel and the "Pair a device" window
//  (UX-012): 9 × 9 glyphs, dot-matrix type, the dot beam and the glyph
//  tile, drawn from Core's data (`GlyphBitmap`, `DotMatrixFont`,
//  `DotGeometry`) with the same dot as the iOS design system.
//  Spec: `Product/Design/06-Pixel-Identity.md` §1, §2, §6.
//

import SwiftUI

// MARK: - Glyph

/// A 9 × 9 pixel glyph at a whole pitch. The accent dot takes `accent`;
/// every other dot the foreground style.
struct MacGlyph: View {
    let glyph: GlyphBitmap
    var pitch: CGFloat = 2
    var accent: Color = PixelHandTheme.accent

    var body: some View {
        let glyph = self.glyph
        let pitch = self.pitch
        let accent = self.accent
        let geometry = DotGeometry.glyph
        let side = CGFloat(PixelPitch.glyphSide(Double(pitch)))
        Canvas { context, _ in
            for point in glyph.litPoints {
                let f = geometry.frame(x: point.x, y: point.y, pitch: Double(pitch))
                let path = Path(
                    roundedRect: CGRect(x: f.x, y: f.y, width: f.side, height: f.side),
                    cornerRadius: geometry.cornerRadius(pitch: Double(pitch))
                )
                context.fill(path, with: glyph.isAccent(point.x, point.y) ? .color(accent) : .foreground)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

// MARK: - Dot-matrix type

/// 5 × 7 dot-matrix text for status words, counters and codes. Never for
/// sentences or buttons. Always carries a spoken label.
struct MacDotText: View {
    let text: String
    var pitch: CGFloat = 1.6
    var label: String?
    /// Unlit cells at 14 %: the "LED panel" look.
    var showsUnlit = false
    var glows = false

    init(_ text: String, pitch: CGFloat = 1.6, label: String? = nil, showsUnlit: Bool = false, glows: Bool = false) {
        self.text = text
        self.pitch = pitch
        self.label = label
        self.showsUnlit = showsUnlit
        self.glows = glows
    }

    var body: some View {
        let pitch = self.pitch
        let lit = DotMatrixFont.litCells(text)
        let unlit = showsUnlit ? DotMatrixFont.unlitCells(text) : []
        let geometry = DotGeometry.type
        Canvas { context, _ in
            func dot(_ point: GlyphPoint) -> Path {
                let f = geometry.frame(x: point.x, y: point.y, pitch: Double(pitch))
                return Path(
                    roundedRect: CGRect(x: f.x, y: f.y, width: f.side, height: f.side),
                    cornerRadius: geometry.cornerRadius(pitch: Double(pitch))
                )
            }
            if !unlit.isEmpty {
                var off = context
                off.opacity = 0.14
                for point in unlit { off.fill(dot(point), with: .foreground) }
            }
            for point in lit { context.fill(dot(point), with: .foreground) }
        }
        .frame(
            width: CGFloat(DotMatrixFont.widthInCells(text)) * pitch,
            height: CGFloat(DotMatrixFont.rows) * pitch
        )
        .shadow(color: glows ? PixelHandTheme.Brand.glow.opacity(0.7) : .clear, radius: glows ? 2 : 0)
        .accessibilityElement()
        // Spoken in sentence case, never as the uppercase dot string.
        .accessibilityLabel(label ?? (text.prefix(1).uppercased() + text.dropFirst().lowercased()))
    }
}

// MARK: - Dot beam

/// The long-wait indicator: a row of square dots, `lit` of them on.
struct MacDotBeam: View {
    let lit: Int
    var total: Int = PairingCodeDisplay.beamCells
    var dot: CGFloat = 6
    var gap: CGFloat = 4
    var color: Color = PixelHandTheme.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: dot * 0.3, style: .continuous)
                    .fill(index < lit ? AnyShapeStyle(color) : AnyShapeStyle(PixelHandTheme.fill2))
                    .frame(width: dot, height: dot)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: lit)
        .accessibilityHidden(true)
    }
}

// MARK: - Glyph tile

/// A glyph on a rounded navy tile (rows, the panel header, the QR centre).
/// Dots are phosphor on navy, with the accent in `glow`.
struct MacGlyphTile: View {
    let glyph: GlyphBitmap
    var size: CGFloat = 28
    var pitch: CGFloat = 2
    var isLit = true

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(PixelHandTheme.Brand.screenGradient)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(PixelHandTheme.Brand.tileStroke, lineWidth: 0.5)
            )
            .overlay(
                MacGlyph(glyph: glyph, pitch: pitch, accent: isLit ? PixelHandTheme.Brand.glow : PixelHandTheme.Brand.phosphor)
                    .foregroundStyle(isLit ? PixelHandTheme.Brand.phosphor : PixelHandTheme.Brand.stripDim)
                    // Centre the lit dots, not the 9 × 9 canvas: the pointer's
                    // dots fill only its left six columns (OR-10).
                    .offset(x: inkOffset.x, y: inkOffset.y)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var inkOffset: CGPoint {
        guard let box = GlyphInkCentring.box(glyph: glyph) else { return .zero }
        let offset = GlyphInkCentring.offset(box: box, columns: GlyphBitmap.size, rows: GlyphBitmap.size, pitch: Double(pitch))
        return CGPoint(x: offset.x, y: offset.y)
    }
}

/// The icon's tile with its dot hand: the panel header and the pairing
/// window use the same object as the app icon and the menu bar.
struct MacHandTile: View {
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(PixelHandTheme.Brand.tileGradient)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.25 - 3, style: .continuous)
                    .fill(PixelHandTheme.Brand.screenSurface)
                    .padding(3)
            )
            .overlay(
                // The glyph's frame is its 17 × 18 canvas; its lit dots are
                // 16 × 18, so it moves half a pitch right to sit on the
                // tile's centre (OR-10). The pitch is a whole half point.
                PixelGlyph(bitmap: PixelArt.hand, pitch: handPitch, palette: .brand, glows: false)
                    .offset(x: handOffset.x, y: handOffset.y)
            )
            .overlay(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(PixelHandTheme.Brand.mint)
                    .frame(width: 3, height: 3)
                    .padding(6)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private static let handBox = GlyphInkCentring.box(rows: MenuBarHand.handRows)

    /// Fits the hand's lit dots inside the tile's screen (3 pt in from each
    /// edge) with a point to spare.
    private var handPitch: CGFloat {
        guard let box = Self.handBox else { return (size - 10) / 18 }
        return CGFloat(GlyphInkCentring.pitch(fitting: box, in: Double(size - 6), margin: 1))
    }

    private var handOffset: CGPoint {
        guard let box = Self.handBox else { return .zero }
        let offset = GlyphInkCentring.offset(
            box: box,
            columns: PixelArt.hand.width,
            rows: PixelArt.hand.height,
            pitch: Double(handPitch)
        )
        return CGPoint(x: offset.x, y: offset.y)
    }
}

// MARK: - Status pixel

/// The panel's status light (OR-09): it fades in over 180 ms, ease-out,
/// when the panel opens, and a live one then breathes. Both change only
/// the dot's opacity, in animations scoped to the dot, so it never moves
/// with the panel's layout (it used to flow in from the bottom). Under
/// Reduce Motion it is simply there, still.
struct MacStatusPixel: View {
    var color: Color = PixelHandTheme.success
    var size: CGFloat = 7
    /// Only one light per panel breathes: the header's.
    var breathes = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShown = false
    @State private var isDim = false

    var body: some View {
        let fade = MacPanelMotion.fade(reduceMotion: reduceMotion).map { Animation.easeOut(duration: $0) }
        let breath: Animation? = reduceMotion
            ? nil
            : .easeInOut(duration: MacPanelMotion.halfBreath).repeatForever(autoreverses: true)
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.45), radius: size * 0.6)
            .animation(breath) { $0.opacity(isDim ? MacPanelMotion.breathDim : 1) }
            .animation(fade) { $0.opacity(isShown ? 1 : 0) }
            .onAppear {
                isShown = true
                if breathes, !reduceMotion { isDim = true }
            }
            .onChange(of: reduceMotion) { _, reduced in
                isDim = breathes && !reduced
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Panel tabs

/// Devices | Transfers at the top of the panel (OR-13). Selection is
/// colour and fill only: no dot or bar under the chosen segment.
struct MacPanelTabs: View {
    enum Tab: Hashable { case devices, transfers }

    @Binding var selection: Tab
    /// The Transfers count; `nil` hides the badge.
    let transfersBadge: Int?

    var body: some View {
        HStack(spacing: 2) {
            segment(.devices, title: "Devices", badge: nil, id: "ph.mac.tabDevices")
            segment(.transfers, title: "Transfers", badge: transfersBadge, id: "ph.mac.tabTransfers")
        }
        .padding(2)
        .background(Capsule(style: .continuous).fill(PixelHandTheme.fill))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ph.mac.tabs")
    }

    private func segment(_ tab: Tab, title: String, badge: Int?, id: String) -> some View {
        let isOn = selection == tab
        return Button {
            selection = tab
        } label: {
            HStack(spacing: PixelHandTheme.Space.xs) {
                Text(title)
                    .font(.callout.weight(isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? PixelHandTheme.ink : PixelHandTheme.ink2)
                if let badge {
                    Text("\(badge)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(isOn ? Color.white : PixelHandTheme.ink2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule(style: .continuous).fill(isOn ? AnyShapeStyle(PixelHandTheme.accent) : AnyShapeStyle(PixelHandTheme.fill2)))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 22)
            .background(Capsule(style: .continuous).fill(isOn ? AnyShapeStyle(PixelHandTheme.elevated) : AnyShapeStyle(Color.clear)))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

// MARK: - Buttons

/// The panel's buttons (board "mbtn"): a small capsule with a real text
/// label, reachable from the keyboard, never shown only on hover.
struct MacPanelButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive, quiet }
    var kind: Kind = .secondary

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(kind == .quiet ? .regular : .medium))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .quiet ? 4 : 12)
            .padding(.vertical, 4)
            .frame(minHeight: 24)
            .background(Capsule(style: .continuous).fill(background))
            .contentShape(Capsule(style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
    }

    private var foreground: AnyShapeStyle {
        switch kind {
        case .primary: AnyShapeStyle(Color.white)
        case .secondary: AnyShapeStyle(PixelHandTheme.ink)
        case .destructive: AnyShapeStyle(PixelHandTheme.danger)
        case .quiet: AnyShapeStyle(PixelHandTheme.ink2)
        }
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .primary: AnyShapeStyle(PixelHandTheme.Brand.actionGradient)
        case .secondary: AnyShapeStyle(PixelHandTheme.fill)
        case .destructive: AnyShapeStyle(PixelHandTheme.dangerTint)
        case .quiet: AnyShapeStyle(Color.clear)
        }
    }
}

extension ButtonStyle where Self == MacPanelButtonStyle {
    static var macPrimary: MacPanelButtonStyle { MacPanelButtonStyle(kind: .primary) }
    static var macSecondary: MacPanelButtonStyle { MacPanelButtonStyle(kind: .secondary) }
    static var macDestructive: MacPanelButtonStyle { MacPanelButtonStyle(kind: .destructive) }
    static var macQuiet: MacPanelButtonStyle { MacPanelButtonStyle(kind: .quiet) }
}

// MARK: - Section label

/// A section's label: small caps in real text, so it follows the Mac's
/// text size (dot-matrix is for status words and codes only).
struct MacSectionLabel: View {
    let text: String
    var color: Color = PixelHandTheme.ink2

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(color)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isHeader)
    }
}
