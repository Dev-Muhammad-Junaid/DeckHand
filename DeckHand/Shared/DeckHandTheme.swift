//
//  DeckHandTheme.swift
//  Deck Hand – Shared
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

// MARK: - Deck Hand design tokens

/// Every brand color comes from a part of the app icon: a cobalt tile, a
/// navy screen, and a pointing hand drawn in lit dots. The roles are fixed so
/// a color always means the same thing:
///
/// - **Cobalt** (`accent`) is the one action color: buttons, selection, tint.
/// - **Glow** (cyan) is live activity with the Mac: searching, connecting,
///   touches on the trackpad, the cursor locator.
/// - **Mint** (`success`) is connected and approved.
/// - **Pixel violet** is the hand's fill and appears only inside dot art.
///
/// The master artwork is `website/brand/concept-b2-ipad.svg`; the website's
/// `styles.css` uses the same values.
enum DeckHandTheme {

    // MARK: Accent and status

    /// The action color. Matches `AccentColor` in both asset catalogs; use
    /// this where a view needs the brand cobalt explicitly (fills behind white
    /// text, selection rings). Light: 6.0:1 against white. Dark: lifted to
    /// about 4.4:1 both as text on the dark canvas and behind white text,
    /// the most one color can manage both ways.
    static let accent = Color(light: "3A4CF2", dark: "5466FF")

    /// The icon's mint pixel in dark mode, a deep teal in light mode so it
    /// still reads on white.
    static let mint = Color(light: "0B7A6C", dark: "3DE0B0")

    /// Connected / live / approved status — use everywhere instead of `Color.green`.
    static let success = mint
    /// Cautionary / pending status — use instead of bare `Color.orange`
    /// (host-disconnected overlay, missing permissions, requests waiting on
    /// the Mac).
    static let warning = Color(light: "A35F00", dark: "FFB547")
    /// Negative / blocked status — use instead of bare `Color.red`
    /// (denied overlay, disconnect and remove buttons, destructive accents).
    static let danger = Color(light: "D92D3F", dark: "FF4D5E")

    // MARK: Brand surface (sampled from the app icon)

    /// Fixed colors from the icon itself. These don't adapt to appearance:
    /// they're used on surfaces that are always dark (first run, the picker,
    /// the trackpad) and in the mark's artwork.
    enum Brand {
        /// The icon's tile: the action color at full strength.
        static let cobalt = Color(hex: "3A4CF2")
        /// Cobalt lifted for hover, dark backgrounds and gradient tops.
        static let cobaltHigh = Color(hex: "5466FF")
        /// The pale top of the icon's tile gradient.
        static let sky = Color(hex: "86B4FF")

        /// Base canvas — the icon's screen glass, navy rather than neutral black.
        static let screen = Color(hex: "060A2A")
        /// The lit center of the screen glass.
        static let screenHigh = Color(hex: "1C2C80")
        /// Cards and tiles sitting on `screen`.
        static let screenRaised = Color(hex: "0E1540")

        /// A lit dot.
        static let phosphor = Color(hex: "EFFFFC")
        /// The cyan bloom around lit dots. Live activity with the Mac.
        static let glow = Color(hex: "3DE0E0")
        /// The tap rays above the fingertip.
        static let ray = Color(hex: "9FF6FF")
        /// The hand's fill. Dot art only, never a control.
        static let pixelViolet = Color(hex: "8E70FF")
        /// The mint pixel in the top-right of the screen.
        static let mint = Color(hex: "3DE0B0")
        /// An unlit dot.
        static let dotOff = Color(hex: "2B3C99").opacity(0.5)

        /// Hairline stroke on cards sitting on `screen`.
        static let tileStroke = Color.white.opacity(0.09)

        /// The icon's tile, for symbols and accents on dark brand surfaces.
        static var tileGradient: LinearGradient {
            LinearGradient(
                colors: [sky, cobaltHigh],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        /// Primary buttons on dark brand surfaces. Both stops keep white
        /// text above 4.4:1.
        static var actionGradient: LinearGradient {
            LinearGradient(
                colors: [cobaltHigh, cobalt],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        /// Cards and tiles on the brand background.
        static var screenGradient: LinearGradient {
            LinearGradient(
                colors: [screenRaised, screen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// Full-bleed brand background: the icon's navy screen with its two light
    /// sources — a cobalt bloom just above center and the mint pixel's cast
    /// in the top-right corner.
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

    enum Radius {
        static let sm: CGFloat = 12
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let hero: CGFloat = 28
    }

    // MARK: Surfaces (iOS shell + shared semantics)

    static func canvasBackground(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark:
            return Color(hex: "0A0A0F")
        case .light:
            #if os(iOS)
            return Color(UIColor.systemGroupedBackground)
            #elseif os(macOS)
            return Color(nsColor: .windowBackgroundColor)
            #else
            return Color(white: 0.95)
            #endif
        @unknown default:
            return Color(hex: "0A0A0F")
        }
    }

    static func cardFill(_ scheme: ColorScheme, pressed: Bool = false) -> Color {
        switch scheme {
        case .dark:
            return .white.opacity(pressed ? 0.12 : 0.07)
        case .light:
            #if os(iOS)
            return Color(UIColor.systemBackground).opacity(pressed ? 0.9 : 1.0)
            #elseif os(macOS)
            return Color(nsColor: .controlBackgroundColor)
            #else
            return Color(white: 1)
            #endif
        @unknown default:
            return .white.opacity(0.07)
        }
    }

    static func cardBorder(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark: return .white.opacity(0.1)
        case .light: return Color.primary.opacity(0.08)
        @unknown default: return .white.opacity(0.1)
        }
    }

    static func navDivider(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark: return .white.opacity(0.07)
        case .light: return Color.primary.opacity(0.08)
        @unknown default: return .white.opacity(0.07)
        }
    }

    static func tabContainerFill(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark: return .white.opacity(0.06)
        case .light:
            #if os(iOS)
            return Color(UIColor.systemFill)
            #elseif os(macOS)
            return Color(nsColor: .controlBackgroundColor).opacity(0.65)
            #else
            return Color(white: 0.9)
            #endif
        @unknown default:
            return .white.opacity(0.06)
        }
    }

    static func tabContainerBorder(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark: return .white.opacity(0.09)
        case .light: return Color.primary.opacity(0.06)
        @unknown default: return .white.opacity(0.09)
        }
    }

    /// Search field on the Apps grid — same fill as the control tab strip container.
    static func searchFieldFill(_ scheme: ColorScheme) -> Color {
        tabContainerFill(scheme)
    }

    static func tabPillSelectedFill(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark: return .white.opacity(0.14)
        case .light:
            #if os(iOS)
            return Color(UIColor.systemBackground)
            #elseif os(macOS)
            return Color(nsColor: .controlBackgroundColor)
            #else
            return Color(white: 1)
            #endif
        @unknown default:
            return .white.opacity(0.14)
        }
    }

    /// The trackpad is the icon's screen in both appearances: a dark slab
    /// that reads as a device, lit a little toward the top like the icon's
    /// glass. Content on it is drawn with a forced dark color scheme.
    static var trackpadSurface: RadialGradient {
        RadialGradient(
            colors: [Color(hex: "111A55"), Brand.screen],
            center: UnitPoint(x: 0.5, y: 0.15),
            startRadius: 0,
            endRadius: 720
        )
    }

    static func subtleWellFill(_ scheme: ColorScheme) -> Color {
        Color.primary.opacity(0.07)
    }

    // MARK: Authorization overlay

    /// Backdrop scrim behind the auth dialog. Card chrome and button chrome
    /// come from native materials / button styles — only the scrim opacity
    /// is opinionated.
    static func authScrim(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .dark: return .black.opacity(0.45)
        case .light: return .black.opacity(0.22)
        @unknown default: return .black.opacity(0.45)
        }
    }

    // MARK: Error banner

    static func errorBannerFill(_ scheme: ColorScheme) -> Color {
        danger.opacity(scheme == .dark ? 0.38 : 0.14)
    }

    static func errorBannerLabel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .white : danger
    }

    // MARK: Mac menu bar

    static var headerGradientColors: [Color] {
        [Brand.cobaltHigh, Brand.cobalt]
    }

    /// Shadow color for floating dialog cards (auth overlay, modal sheets).
    static func dialogCardShadow(_ scheme: ColorScheme) -> Color {
        .black.opacity(scheme == .dark ? 0.35 : 0.12)
    }

    // MARK: Floating Action Buttons (Apps page keyboard / numeric toggles)

    /// Design tokens for the circular floating-action toggle buttons that
    /// surface the keyboard / numeric edit rows on the Apps page. Geometry,
    /// shadow, and animation come from the native `Button` styles
    /// (`.glass` / `.glassProminent` on iOS 26+, `.bordered` /
    /// `.borderedProminent` on iOS 17). Only the active tint is opinionated.
    enum FAB {
        /// Keyboard FAB uses the accent.
        static let keyboardTint: Color = DeckHandTheme.accent
        /// Numeric FAB uses a deep teal so the two toggles read distinctly
        /// against the same surface. Dark enough to keep a white glyph legible.
        static let numericTint:  Color = Color(hex: "0B7A6C")
    }

    // MARK: Typography (rounded matches picker / control chrome)

    enum TypeStyle {
        static let titleRounded = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let bodyRounded = Font.system(size: 15, weight: .regular, design: .rounded)
        static let captionRounded = Font.system(size: 13, weight: .regular, design: .rounded)
        static let buttonRounded = Font.system(size: 15, weight: .semibold, design: .rounded)
        /// Progress / empty-state titles (peer search, initializing, apps loading).
        static let loadingTitle = Font.system(size: 15, weight: .medium, design: .rounded)
    }
}
