//
//  DeckHandTheme.swift
//  Pixel Hand – Shared
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Hex

/// sRGB components parsed from a hex string. Kept as plain values so the
/// dynamic-color providers below can capture them without touching UI types.
private struct HexRGBA: Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    /// Parses `#RGB`, `#RRGGBB`, or `#RRGGBBAA` (with or without `#`).
    init(_ hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var i: UInt64 = 0
        Scanner(string: h).scanHexInt64(&i)
        let a, r, g, b: UInt64
        switch h.count {
        case 3:  (a, r, g, b) = (255, (i >> 8) * 17, (i >> 4 & 0xF) * 17, (i & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, i >> 16, i >> 8 & 0xFF, i & 0xFF)
        case 8:  (a, r, g, b) = (i >> 24, i >> 16 & 0xFF, i >> 8 & 0xFF, i & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        red = Double(r) / 255
        green = Double(g) / 255
        blue = Double(b) / 255
        opacity = Double(a) / 255
    }
}

extension Color {
    /// Parses `#RGB`, `#RRGGBB`, or `#RRGGBBAA` (with or without `#`).
    init(hex: String) {
        let c = HexRGBA(hex)
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.opacity)
    }

    /// A color that resolves to `light` or `dark` with the appearance it is
    /// drawn in, including `.environment(\.colorScheme, …)` overrides.
    init(light: String, dark: String) {
        let l = HexRGBA(light)
        let d = HexRGBA(dark)
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? d : l
            return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: c.opacity)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? d : l
            return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.opacity)
        })
        #else
        self.init(.sRGB, red: l.red, green: l.green, blue: l.blue, opacity: l.opacity)
        #endif
    }
}

// MARK: - Legacy tokens (forwarding shim)

/// **Deprecated: use `PixelHandTheme`.** Kept as a forwarding shim (UX-001)
/// so existing views compile and pick up the new tokens until each lane
/// restyles its views; removed in UX-014. Every value here now comes from
/// `PixelHandTheme`, so the whole app already wears the new palette: the
/// navy-biased dark canvas, raised cards, hairlines and Dynamic Type roles.
enum DeckHandTheme {

    // MARK: Accent and status

    static var accent: Color { PixelHandTheme.accent }
    static var mint: Color { PixelHandTheme.success }
    static var success: Color { PixelHandTheme.success }
    static var warning: Color { PixelHandTheme.warning }
    static var danger: Color { PixelHandTheme.danger }

    // MARK: Brand surface

    typealias Brand = PixelHandTheme.Brand

    /// Full-bleed brand background: the icon's navy screen with a cobalt
    /// bloom just above centre and the mint pixel's cast top-trailing.
    static func brandBackground() -> some View {
        ZStack {
            Brand.screen
            RadialGradient(
                colors: [Brand.cobalt.opacity(0.34), Brand.cobalt.opacity(0.08), .clear],
                center: UnitPoint(x: 0.5, y: 0.34),
                startRadius: 8,
                endRadius: 420
            )
            RadialGradient(
                colors: [Brand.mint.opacity(0.12), .clear],
                center: UnitPoint(x: 0.92, y: 0.08),
                startRadius: 4,
                endRadius: 260
            )
        }
    }

    /// Old radius names mapped onto the concentric scale by role.
    enum Radius {
        static let sm: CGFloat = PixelHandTheme.Radius.kbd + 4
        static let md: CGFloat = PixelHandTheme.Radius.chip
        static let lg: CGFloat = PixelHandTheme.Radius.key
        static let xl: CGFloat = PixelHandTheme.Radius.key
        static let xxl: CGFloat = PixelHandTheme.Radius.card
        static let hero: CGFloat = PixelHandTheme.Radius.pane
    }

    // MARK: Surfaces

    static func canvasBackground(_ scheme: ColorScheme) -> Color {
        PixelHandTheme.color(PaletteTokens.canvas, for: scheme)
    }

    static func cardFill(_ scheme: ColorScheme, pressed: Bool = false) -> Color {
        PixelHandTheme.color(pressed ? PaletteTokens.fill2 : PaletteTokens.raised, for: scheme)
    }

    static func cardBorder(_ scheme: ColorScheme) -> Color {
        PixelHandTheme.color(PaletteTokens.hairline, for: scheme)
    }

    static func navDivider(_ scheme: ColorScheme) -> Color {
        PixelHandTheme.color(PaletteTokens.hairline, for: scheme)
    }

    static func tabContainerFill(_ scheme: ColorScheme) -> Color {
        PixelHandTheme.color(PaletteTokens.fill, for: scheme)
    }

    static func tabContainerBorder(_ scheme: ColorScheme) -> Color {
        PixelHandTheme.color(PaletteTokens.hairline, for: scheme)
    }

    static func searchFieldFill(_ scheme: ColorScheme) -> Color {
        tabContainerFill(scheme)
    }

    static func tabPillSelectedFill(_ scheme: ColorScheme) -> Color {
        PixelHandTheme.color(PaletteTokens.raised, for: scheme)
    }

    /// The trackpad is the icon's screen in both appearances.
    static var trackpadSurface: RadialGradient {
        PixelHandTheme.Brand.screenSurface
    }

    static func subtleWellFill(_ scheme: ColorScheme) -> Color {
        PixelHandTheme.color(PaletteTokens.fill, for: scheme)
    }

    // MARK: Authorization overlay

    static func authScrim(_ scheme: ColorScheme) -> Color {
        PixelHandTheme.color(PaletteTokens.scrim, for: scheme)
    }

    // MARK: Error banner

    static func errorBannerFill(_ scheme: ColorScheme) -> Color {
        PixelHandTheme.color(PaletteTokens.dangerTint, for: scheme)
    }

    static func errorBannerLabel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : danger
    }

    // MARK: Mac menu bar

    static var headerGradientColors: [Color] {
        [Brand.cobaltHigh, Brand.cobalt]
    }

    static func dialogCardShadow(_ scheme: ColorScheme) -> Color {
        .black.opacity(scheme == .dark ? 0.35 : 0.12)
    }

    // MARK: Floating Action Buttons (removed with the FABs in UX-005)

    enum FAB {
        static var keyboardTint: Color { PixelHandTheme.accent }
        static var numericTint: Color { PixelHandTheme.success }
    }

    // MARK: Typography

    /// Old fixed sizes, now text styles with the same default size so they
    /// follow Dynamic Type. SF Rounded is dropped (`02-Design-System.md` §3).
    enum TypeStyle {
        static var titleRounded: Font { .title3.weight(.semibold) }
        static var bodyRounded: Font { .subheadline }
        static var captionRounded: Font { .footnote }
        static var buttonRounded: Font { .subheadline.weight(.semibold) }
        static var loadingTitle: Font { .subheadline.weight(.medium) }
    }
}
