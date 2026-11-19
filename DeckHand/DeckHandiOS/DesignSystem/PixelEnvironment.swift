//
//  PixelEnvironment.swift
//  DeckHandiOS – Design system
//
//  What the dot art needs to know about where it is drawn: on navy (glyph
//  accents and dot-matrix text glow cyan) or on a light surface (accents
//  are cobalt, nothing glows), and which Dynamic Type band is active.
//

import SwiftUI

private struct PixelOnNavyKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside navy surfaces (`PixelSurface`, the status strip, the
    /// mirror). Glyph accents become `glow` and dot-matrix text glows.
    var pixelOnNavy: Bool {
        get { self[PixelOnNavyKey.self] }
        set { self[PixelOnNavyKey.self] = newValue }
    }
}

extension View {
    /// Marks this subtree as drawn on navy: forces the dark appearance and
    /// switches pixel accents to `glow`.
    func pixelOnNavy() -> some View {
        environment(\.pixelOnNavy, true)
            .environment(\.colorScheme, .dark)
    }
}

extension DynamicTypeSize {
    /// The polish spec's band for this size (`07-Polish-Spec.md` §6).
    var typeBand: TypeBand {
        TypeBand(dynamicTypeIndex: DynamicTypeSize.allCases.firstIndex(of: self) ?? 3)
    }
}

extension PixelHandTheme {
    /// A glyph's accent dot: `glow` on navy, `accent` on light surfaces
    /// (`06-Pixel-Identity.md` §1, rule 4).
    static func pixelAccent(onNavy: Bool) -> Color {
        onNavy ? Brand.glow : accent
    }
}
