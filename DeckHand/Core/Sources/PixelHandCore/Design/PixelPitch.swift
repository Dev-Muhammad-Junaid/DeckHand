//
//  PixelPitch.swift
//  PixelHandCore
//
//  The only pitches glyphs and dot-matrix text are drawn at, and how they
//  step with Dynamic Type. Glyphs never scale with a transform: they're
//  redrawn at the next pitch (`06-Pixel-Identity.md` §1–§2,
//  `07-Polish-Spec.md` §6).
//

/// The three Dynamic Type bands the layouts switch between.
public enum TypeBand: Int, Sendable, Hashable, Comparable, CaseIterable {
    /// xSmall – xxxLarge: as designed.
    case standard
    /// AX1 – AX2: strip wraps, chords move under labels, deck keeps 3 columns.
    case large
    /// AX3 – AX5: deck becomes rows, the strip collapses into one button.
    case huge

    /// The band for a Dynamic Type size, given as its position in Apple's
    /// list (0 = xSmall … 6 = xxxLarge, 7 = AX1 … 11 = AX5).
    public init(dynamicTypeIndex index: Int) {
        switch index {
        case ..<7: self = .standard
        case 7...8: self = .large
        default: self = .huge
        }
    }

    public static func < (lhs: TypeBand, rhs: TypeBand) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum PixelPitch {
    /// Allowed glyph pitches (`06-Pixel-Identity.md` §1 table, plus 2.2 for
    /// header buttons and 1.6/1.8 used on the board's toolbars and pills).
    public static let glyph: [Double] = [1.4, 1.6, 1.8, 2, 2.2, 2.6, 3, 4, 5, 6, 10]

    /// Allowed dot-matrix pitches (§2): badges 1.3–1.4, counters 1.6,
    /// strips 2, large counters 3, the PRO mark 5.
    public static let dotMatrix: [Double] = [1.3, 1.4, 1.6, 1.8, 2, 2.2, 2.6, 3, 5]

    /// Named glyph pitches by role.
    public static let badge: Double = 1.4
    public static let chip: Double = 2
    public static let header: Double = 2.2
    public static let tabBar: Double = 2.6
    public static let key: Double = 3
    public static let emptyState: Double = 6
    public static let hero: Double = 10

    /// Side of a 9 × 9 glyph at `pitch`.
    public static func glyphSide(_ pitch: Double) -> Double {
        pitch * Double(GlyphBitmap.size)
    }

    /// A pitch stepped for the type band: at AX1+ dot-matrix text and small
    /// glyphs step up one size (1.4 → 2, 2 → 2.6), never continuously.
    public static func stepped(_ pitch: Double, for band: TypeBand) -> Double {
        guard band != .standard else { return pitch }
        switch pitch {
        case ..<1.5: return 2
        case ..<2.1: return 2.6
        case ..<2.7: return 3
        default: return pitch
        }
    }
}
