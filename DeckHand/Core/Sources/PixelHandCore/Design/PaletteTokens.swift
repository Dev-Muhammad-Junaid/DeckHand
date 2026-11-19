//
//  PaletteTokens.swift
//  PixelHandCore
//
//  Pixel Hand's colour tokens as numbers: the single source for the app's
//  `PixelHandTheme`, and what the WCAG contrast tests read on Linux.
//  Spec: `Product/Design/02-Design-System.md` §1. Rule zero: each colour has
//  one job.
//

import Foundation

/// An sRGB colour with components in 0…1.
public struct RGBColor: Sendable, Hashable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `0xRRGGBB`.
    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    public static let white = RGBColor(hex: 0xFFFFFF)
    public static let black = RGBColor(hex: 0x000000)

    /// This colour at `opacity`, composited over `background`.
    public func composited(opacity: Double, over background: RGBColor) -> RGBColor {
        let a = min(max(opacity, 0), 1)
        return RGBColor(
            red: red * a + background.red * (1 - a),
            green: green * a + background.green * (1 - a),
            blue: blue * a + background.blue * (1 - a)
        )
    }

    /// WCAG 2 relative luminance.
    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2 contrast ratio between two opaque colours (1…21).
    public static func contrast(_ a: RGBColor, _ b: RGBColor) -> Double {
        let la = a.relativeLuminance, lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

/// A colour with an opacity, as a token defines it ("ink @ 64 %").
public struct Swatch: Sendable, Hashable {
    public let color: RGBColor
    public let opacity: Double

    public init(_ hex: UInt32, opacity: Double = 1) {
        self.color = RGBColor(hex: hex)
        self.opacity = opacity
    }

    public init(_ color: RGBColor, opacity: Double = 1) {
        self.color = color
        self.opacity = opacity
    }

    /// The colour a viewer sees over an opaque `background`.
    public func resolved(over background: RGBColor) -> RGBColor {
        color.composited(opacity: opacity, over: background)
    }
}

/// A semantic token: one swatch per appearance, with optional Increase
/// Contrast variants.
public struct ColorToken: Sendable, Hashable {
    public let name: String
    public let light: Swatch
    public let dark: Swatch
    public let lightHighContrast: Swatch
    public let darkHighContrast: Swatch

    public init(_ name: String, light: Swatch, dark: Swatch, lightHighContrast: Swatch? = nil, darkHighContrast: Swatch? = nil) {
        self.name = name
        self.light = light
        self.dark = dark
        self.lightHighContrast = lightHighContrast ?? light
        self.darkHighContrast = darkHighContrast ?? dark
    }

    public func swatch(dark isDark: Bool, highContrast: Bool = false) -> Swatch {
        switch (isDark, highContrast) {
        case (false, false): return light
        case (true, false): return dark
        case (false, true): return lightHighContrast
        case (true, true): return darkHighContrast
        }
    }
}

public enum PaletteTokens {
    /// Fixed brand colours, the same in both appearances (§1.1).
    public enum Brand {
        public static let cobalt = RGBColor(hex: 0x3A4CF2)
        public static let cobaltHigh = RGBColor(hex: 0x5466FF)
        public static let cobaltInk = RGBColor(hex: 0x2A38C9)
        public static let sky = RGBColor(hex: 0x86B4FF)
        public static let screen = RGBColor(hex: 0x060A2A)
        public static let screenRaised = RGBColor(hex: 0x0E1540)
        public static let screenHigh = RGBColor(hex: 0x1C2C80)
        /// The radial lift at the top of every navy surface (`#111A55 → screen`).
        public static let screenLift = RGBColor(hex: 0x111A55)
        public static let navBar = RGBColor(hex: 0x11152F)
        public static let phosphor = RGBColor(hex: 0xEFFFFC)
        public static let glow = RGBColor(hex: 0x3DE0E0)
        public static let ray = RGBColor(hex: 0x9FF6FF)
        public static let mint = RGBColor(hex: 0x3DE0B0)
        public static let pixelViolet = RGBColor(hex: 0x8E70FF)
        /// An unlit dot: `#5064D2` at 22 %. Decorative only.
        public static let dotOff = Swatch(0x5064D2, opacity: 0.22)
        /// Status-strip text in its dim state (locked, offline).
        public static let stripDim = RGBColor(hex: 0x6D7BB8)
    }

    private static let inkLight: UInt32 = 0x121522
    private static let inkDark: UInt32 = 0xF4F6FF
    private static let warningLight: UInt32 = 0xA35F00
    private static let warningDark: UInt32 = 0xFFB547
    private static let dangerLight: UInt32 = 0xD92D3F
    private static let dangerDark: UInt32 = 0xFF4D5E

    // Semantic tokens (§1.2). Increase Contrast: hairline → 20 %, ink2 → 80 %.
    public static let canvas = ColorToken("canvas", light: Swatch(0xF3F4F9), dark: Swatch(0x070A1C))
    public static let raised = ColorToken("raised", light: Swatch(0xFFFFFF), dark: Swatch(0x0E1330))
    public static let elevated = ColorToken("elevated", light: Swatch(0xFFFFFF), dark: Swatch(0x161C40))
    public static let ink = ColorToken("ink", light: Swatch(inkLight), dark: Swatch(inkDark))
    public static let ink2 = ColorToken(
        "ink2",
        light: Swatch(inkLight, opacity: 0.64), dark: Swatch(inkDark, opacity: 0.64),
        lightHighContrast: Swatch(inkLight, opacity: 0.8), darkHighContrast: Swatch(inkDark, opacity: 0.8)
    )
    public static let ink3 = ColorToken("ink3", light: Swatch(inkLight, opacity: 0.4), dark: Swatch(inkDark, opacity: 0.38))
    public static let hairline = ColorToken(
        "hairline",
        light: Swatch(inkLight, opacity: 0.08), dark: Swatch(0xFFFFFF, opacity: 0.08),
        lightHighContrast: Swatch(inkLight, opacity: 0.2), darkHighContrast: Swatch(0xFFFFFF, opacity: 0.2)
    )
    public static let fill = ColorToken("fill", light: Swatch(inkLight, opacity: 0.06), dark: Swatch(0xFFFFFF, opacity: 0.07))
    public static let fill2 = ColorToken("fill2", light: Swatch(inkLight, opacity: 0.10), dark: Swatch(0xFFFFFF, opacity: 0.12))
    public static let accent = ColorToken("accent", light: Swatch(0x3A4CF2), dark: Swatch(0x5466FF))
    public static let accentInk = ColorToken("accentInk", light: Swatch(0x2A38C9), dark: Swatch(0x9FB0FF))
    public static let accentTint = ColorToken("accentTint", light: Swatch(0xE6EAFF), dark: Swatch(0x5466FF, opacity: 0.2))
    public static let success = ColorToken("success", light: Swatch(0x0B7A6C), dark: Swatch(0x3DE0B0))
    public static let successTint = ColorToken("successTint", light: Swatch(0xDCF6F1), dark: Swatch(0x3DE0B0, opacity: 0.14))
    public static let warning = ColorToken("warning", light: Swatch(warningLight), dark: Swatch(warningDark))
    public static let warningTint = ColorToken("warningTint", light: Swatch(0xFFF1DB), dark: Swatch(warningDark, opacity: 0.14))
    public static let danger = ColorToken("danger", light: Swatch(dangerLight), dark: Swatch(dangerDark))
    public static let dangerTint = ColorToken("dangerTint", light: Swatch(0xFDE7EA), dark: Swatch(dangerDark, opacity: 0.16))
    public static let scrim = ColorToken("scrim", light: Swatch(0x060A2A, opacity: 0.28), dark: Swatch(0x000000, opacity: 0.45))

    /// Every semantic token, for tests and previews.
    public static let all: [ColorToken] = [
        canvas, raised, elevated, ink, ink2, ink3, hairline, fill, fill2,
        accent, accentInk, accentTint, success, successTint, warning, warningTint,
        danger, dangerTint, scrim,
    ]
}
