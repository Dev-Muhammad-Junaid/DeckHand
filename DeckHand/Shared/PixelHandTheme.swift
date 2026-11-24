//
//  PixelHandTheme.swift
//  Pixel Hand – Shared
//
//  The Pixel Hand design tokens (UX-001): colour, type with Dynamic Type,
//  space, radii and control heights. Values come from
//  `PixelHandCore.PaletteTokens`, so the contrast tests run on Linux and the
//  app, the Mac panel and the tests read one table.
//  Spec: `Product/Design/02-Design-System.md`, `07-Polish-Spec.md`.
//
//  Rule zero: each colour has one job.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

#if canImport(CoreText)
import CoreText
#endif

enum PixelHandTheme {

    // MARK: Brand (fixed; the same in both appearances)

    /// Fixed brand colours. Dot art and always-navy surfaces only; controls
    /// use the semantic colours below.
    enum Brand {
        /// The action colour on light surfaces.
        static let cobalt = Color(PaletteTokens.Brand.cobalt)
        /// The action colour on dark; gradient tops.
        static let cobaltHigh = Color(PaletteTokens.Brand.cobaltHigh)
        /// Cobalt as text on tints.
        static let cobaltInk = Color(PaletteTokens.Brand.cobaltInk)
        /// Tile gradient top, links on navy.
        static let sky = Color(PaletteTokens.Brand.sky)
        /// Always-dark surfaces: trackpad, mirror frame, brand screens.
        static let screen = Color(PaletteTokens.Brand.screen)
        /// Cards on `screen`.
        static let screenRaised = Color(PaletteTokens.Brand.screenRaised)
        /// The lit centre of the glass.
        static let screenHigh = Color(PaletteTokens.Brand.screenHigh)
        /// The radial lift at the top of navy surfaces.
        static let screenLift = Color(PaletteTokens.Brand.screenLift)
        /// Solid chrome when Reduce Transparency is on.
        static let navBar = Color(PaletteTokens.Brand.navBar)
        /// A lit dot.
        static let phosphor = Color(PaletteTokens.Brand.phosphor)
        /// Live activity right now. **On navy only.**
        static let glow = Color(PaletteTokens.Brand.glow)
        /// Tap rays, stats text on navy.
        static let ray = Color(PaletteTokens.Brand.ray)
        /// Connected / delivered on dark.
        static let mint = Color(PaletteTokens.Brand.mint)
        /// The hand's fill. Dot art only, never a control.
        static let pixelViolet = Color(PaletteTokens.Brand.pixelViolet)
        /// An unlit dot. Decorative, never carries meaning.
        static let dotOff = Color(PaletteTokens.Brand.dotOff)
        /// Status-strip text in its dim state.
        static let stripDim = Color(PaletteTokens.Brand.stripDim)
        /// Hairline stroke on cards sitting on `screen`.
        static let tileStroke = Color.white.opacity(0.09)

        /// The icon's tile.
        static var tileGradient: LinearGradient {
            LinearGradient(colors: [sky, cobaltHigh], startPoint: .topLeading, endPoint: .bottomTrailing)
        }

        /// Primary buttons: both stops keep white text above 4.4:1.
        static var actionGradient: LinearGradient {
            LinearGradient(colors: [cobaltHigh, cobalt], startPoint: .top, endPoint: .bottom)
        }

        /// Cards and tiles on the brand background.
        static var screenGradient: LinearGradient {
            LinearGradient(colors: [screenRaised, screen], startPoint: .topLeading, endPoint: .bottomTrailing)
        }

        /// Every navy surface: `#111A55 → screen`, lit toward the top.
        static var screenSurface: RadialGradient {
            RadialGradient(
                colors: [screenLift, screen],
                center: UnitPoint(x: 0.5, y: 0.15),
                startRadius: 0,
                endRadius: 720
            )
        }
    }

    // MARK: Semantic colours (adapt to light / dark / Increase Contrast)

    /// Behind everything. Dark is navy-biased.
    static let canvas = Color(token: PaletteTokens.canvas)
    /// Keys, chips, cards, list rows.
    static let raised = Color(token: PaletteTokens.raised)
    /// Sheets, popovers, menus.
    static let elevated = Color(token: PaletteTokens.elevated)
    /// Primary text.
    static let ink = Color(token: PaletteTokens.ink)
    /// Secondary text.
    static let ink2 = Color(token: PaletteTokens.ink2)
    /// Tertiary text, chords, placeholders.
    static let ink3 = Color(token: PaletteTokens.ink3)
    /// Strokes and dividers.
    static let hairline = Color(token: PaletteTokens.hairline)
    /// Wells, idle buttons, unlit status dots.
    static let fill = Color(token: PaletteTokens.fill)
    static let fill2 = Color(token: PaletteTokens.fill2)
    /// Primary buttons, selection, the default dialog chip, edit outlines.
    static let accent = Color(token: PaletteTokens.accent)
    /// Accent text on `accentTint`.
    static let accentInk = Color(token: PaletteTokens.accentInk)
    /// Selected fills, AI suggestion panels.
    static let accentTint = Color(token: PaletteTokens.accentTint)
    /// Connected, delivered, toggles on.
    static let success = Color(token: PaletteTokens.success)
    static let successTint = Color(token: PaletteTokens.successTint)
    /// Needs a fix, pending, dialog waiting.
    static let warning = Color(token: PaletteTokens.warning)
    static let warningTint = Color(token: PaletteTokens.warningTint)
    /// Refused, failed, destructive.
    static let danger = Color(token: PaletteTokens.danger)
    static let dangerTint = Color(token: PaletteTokens.dangerTint)
    /// Behind sheets.
    static let scrim = Color(token: PaletteTokens.scrim)

    /// A token resolved for one appearance, for views that draw with a
    /// forced scheme (and the `DeckHandTheme` shim's `(_ scheme:)` calls).
    static func color(_ token: ColorToken, for scheme: ColorScheme) -> Color {
        let swatch = token.swatch(dark: scheme == .dark)
        return Color(swatch.color).opacity(swatch.opacity)
    }

    // MARK: Space, size and shape

    /// The spacing scale: `4 · 8 · 12 · 16 · 24 · 32 · 48`. Nothing else
    /// between siblings or as padding (`07-Polish-Spec.md` §2).
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    /// The radius scale, concentric: `8 · 14 · 18 · 24 · 30 · 36 · capsule`.
    /// Inner = outer − inset (pane 30 − 12 = key 18, sheet 36 − 12 = card 24,
    /// card 24 − 10 = chip 14, chip 14 − 6 = kbd 8).
    enum Radius {
        static let kbd: CGFloat = 8
        static let chip: CGFloat = 14
        static let key: CGFloat = 18
        static let card: CGFloat = 24
        static let pane: CGFloat = 30
        static let sheet: CGFloat = 36
        /// Badges and the status strip sit on pictures: 6.
        static let badge: CGFloat = 6
    }

    /// Control heights (`07-Polish-Spec.md` §4). Every target is ≥ 44 × 44
    /// even when the visual is smaller.
    enum ControlHeight {
        static let badge: CGFloat = 20
        static let strip: CGFloat = 24
        static let secondary: CGFloat = 36
        static let standard: CGFloat = 44
        static let primary: CGFloat = 52
        static let dock: CGFloat = 56
        /// The minimum hit target.
        static let hit: CGFloat = 44
    }

    /// Line widths.
    enum Stroke {
        static let hairline: CGFloat = 0.5
        static let selection: CGFloat = 2
    }
}

// MARK: - Type

extension PixelHandTheme {
    /// Font roles (`02-Design-System.md` §3). Geist for display moments, SF
    /// Pro for everything people read and tap, SF Mono for chords and
    /// numbers. Every role scales with Dynamic Type; there are no fixed sizes
    /// outside glyph art and dot-matrix text.
    enum TextRole: CaseIterable {
        case displayLarge, display, displaySmall
        case title, headline, body, chipLabel, keyLabel, caption, chord, numerals

        var font: Font {
            switch self {
            case .displayLarge: return PixelHandFonts.geist(.medium, size: 34, relativeTo: .largeTitle)
            case .display: return PixelHandFonts.geist(.medium, size: 22, relativeTo: .title2)
            case .displaySmall: return PixelHandFonts.geist(.semibold, size: 17, relativeTo: .headline)
            case .title: return .title3.weight(.semibold)
            case .headline: return .headline
            case .body: return .body
            case .chipLabel: return .subheadline.weight(.semibold)
            case .keyLabel: return .caption.weight(.semibold)
            case .caption: return .caption
            case .chord: return .system(.caption2, design: .monospaced).weight(.medium)
            case .numerals: return .system(.footnote, design: .monospaced).monospacedDigit()
            }
        }

        /// Tracking at the default size, in points.
        var tracking: CGFloat {
            switch self {
            case .displayLarge: return -0.9
            case .display: return -0.5
            case .displaySmall: return -0.2
            default: return 0
            }
        }
    }
}

extension Font {
    /// Geist display type that scales with `style`.
    static func phDisplay(_ style: Font.TextStyle = .title2) -> Font {
        switch style {
        case .largeTitle: return PixelHandTheme.TextRole.displayLarge.font
        case .headline: return PixelHandTheme.TextRole.displaySmall.font
        default: return PixelHandTheme.TextRole.display.font
        }
    }

    static var phChip: Font { PixelHandTheme.TextRole.chipLabel.font }
    static var phChord: Font { PixelHandTheme.TextRole.chord.font }
    static var phKeyLabel: Font { PixelHandTheme.TextRole.keyLabel.font }
    static var phNumerals: Font { PixelHandTheme.TextRole.numerals.font }
}

extension View {
    /// Applies a text role's font and tracking.
    func phText(_ role: PixelHandTheme.TextRole) -> some View {
        font(role.font).tracking(role.tracking)
    }
}

/// Registers the bundled Geist faces once, at first use, so no Info.plist
/// `UIAppFonts` entry is needed. When the files aren't in the bundle (the Mac
/// app, tests) the custom font falls back to the system font at the same size.
enum PixelHandFonts {
    enum Weight: String {
        case medium = "Geist-Medium"
        case semibold = "Geist-SemiBold"
    }

    static func geist(_ weight: Weight, size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        _ = registered
        return .custom(weight.rawValue, size: size, relativeTo: style)
    }

    private static let registered: Bool = {
        #if canImport(CoreText)
        for weight in [Weight.medium, .semibold] {
            guard let url = Bundle.main.url(forResource: weight.rawValue, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        #endif
        return true
    }()
}

// MARK: - Colour plumbing

extension Color {
    /// A fixed sRGB colour from a Core value.
    init(_ rgb: PixelHandCore.RGBColor) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    /// A fixed colour from a Core swatch (colour and opacity).
    init(_ swatch: Swatch) {
        self.init(.sRGB, red: swatch.color.red, green: swatch.color.green, blue: swatch.color.blue, opacity: swatch.opacity)
    }

    /// A colour that follows the appearance it is drawn in (including
    /// `.environment(\.colorScheme, …)` overrides) and Increase Contrast.
    init(token: ColorToken) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            let swatch = token.swatch(
                dark: traits.userInterfaceStyle == .dark,
                highContrast: traits.accessibilityContrast == .high
            )
            return UIColor(red: swatch.color.red, green: swatch.color.green, blue: swatch.color.blue, alpha: swatch.opacity)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ])
            let isDark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            let isHigh = match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
            let swatch = token.swatch(dark: isDark, highContrast: isHigh)
            return NSColor(srgbRed: swatch.color.red, green: swatch.color.green, blue: swatch.color.blue, alpha: swatch.opacity)
        })
        #else
        self.init(token.light)
        #endif
    }
}

extension ShapeStyle where Self == Color {
    static var phCanvas: Color { PixelHandTheme.canvas }
    static var phRaised: Color { PixelHandTheme.raised }
    static var phElevated: Color { PixelHandTheme.elevated }
    static var phInk: Color { PixelHandTheme.ink }
    static var phInk2: Color { PixelHandTheme.ink2 }
    static var phInk3: Color { PixelHandTheme.ink3 }
    static var phHairline: Color { PixelHandTheme.hairline }
    static var phFill: Color { PixelHandTheme.fill }
    static var phFill2: Color { PixelHandTheme.fill2 }
    static var phAccent: Color { PixelHandTheme.accent }
}
