//
//  LayoutMetricsTests.swift
//  PixelHandCoreTests
//
//  Size classes, arrangements and whole-point deck keys
//  (`Product/Design/03-Layout-Strategy.md` §0, `07-Polish-Spec.md` §1).
//

import Testing
@testable import PixelHandCore

@Suite("Layout metrics")
struct LayoutMetricsTests {
    @Test("Width class boundaries: compact < 500 ≤ medium < 900 ≤ wide")
    func widthBoundaries() {
        #expect(LayoutMetrics(width: 320, height: 800).widthClass == .compact)
        #expect(LayoutMetrics(width: 499.9, height: 800).widthClass == .compact)
        #expect(LayoutMetrics(width: 500, height: 800).widthClass == .medium)
        #expect(LayoutMetrics(width: 899, height: 800).widthClass == .medium)
        #expect(LayoutMetrics(width: 900, height: 800).widthClass == .wide)
    }

    @Test("Height class boundary: short < 500 ≤ tall")
    func heightBoundaries() {
        #expect(LayoutMetrics(width: 874, height: 402).heightClass == .short)
        #expect(LayoutMetrics(width: 874, height: 499).heightClass == .short)
        #expect(LayoutMetrics(width: 874, height: 500).heightClass == .tall)
    }

    @Test("The QA sizes get the arrangement the layout strategy names")
    func arrangements() {
        let cases: [(Double, Double, LayoutMetrics.Arrangement)] = [
            (375, 667, .single),   // iPhone SE
            (402, 874, .single),   // iPhone 17 Pro
            (466, 678, .single),   // Duo cover
            (320, 1180, .single),  // Slide Over
            (874, 402, .rail),     // iPhone landscape
            (820, 1180, .split),   // iPad portrait
            (590, 820, .split),    // ½ Split View
            (669, 951, .split),    // Duo laptop
            (1180, 820, .columns), // iPad landscape
            (951, 669, .columns),  // Duo book
        ]
        for (w, h, expected) in cases {
            #expect(LayoutMetrics(width: w, height: h).arrangement == expected, "\(w) × \(h)")
        }
    }

    @Test("Grid columns, margins and gutters per class")
    func grid() {
        let compact = LayoutMetrics(width: 402, height: 874)
        #expect(compact.gridColumns == 4 && compact.margin == 16 && compact.gutter == 12)
        let medium = LayoutMetrics(width: 820, height: 1180)
        #expect(medium.gridColumns == 8 && medium.margin == 20 && medium.gutter == 12)
        let wide = LayoutMetrics(width: 1180, height: 820)
        #expect(wide.gridColumns == 12 && wide.margin == 24 && wide.gutter == 16)
    }

    @Test("Deck columns: 4 compact, 5–6 medium, 3 wide")
    func deckColumns() {
        #expect(LayoutMetrics(width: 375, height: 667).deckColumns == 4)
        #expect(LayoutMetrics(width: 590, height: 820).deckColumns == 5)
        #expect(LayoutMetrics(width: 820, height: 1180).deckColumns == 6)
        #expect(LayoutMetrics(width: 1180, height: 820).deckColumns == 3)
    }

    @Test("Whole-point keys with the remainder in the margins (polish spec examples)")
    func keySizes() {
        let g402 = LayoutMetrics(width: 402, height: 874).deckGrid
        #expect(g402.keySize == 83)
        #expect(g402.leadingMargin == 17 && g402.trailingMargin == 17)

        let g375 = LayoutMetrics(width: 375, height: 667).deckGrid
        #expect(g375.keySize == 76)
        #expect(g375.leadingMargin == 17 && g375.trailingMargin == 18)

        let g466 = LayoutMetrics(width: 466, height: 678).deckGrid
        #expect(g466.keySize == 99)
        #expect(g466.leadingMargin + g466.trailingMargin + g466.contentWidth == 466)

        let g820 = LayoutMetrics(width: 820, height: 1180).deckGrid
        #expect(g820.columns == 6)
        #expect(g820.keySize == 120)
        #expect(g820.leadingMargin + g820.trailingMargin + g820.contentWidth == 820)

        let g1180 = LayoutMetrics(width: 1180, height: 820).deckGrid
        #expect(g1180.columns == 3)
        #expect(g1180.keySize == 96)
        #expect(g1180.contentWidth + g1180.leadingMargin + g1180.trailingMargin == LayoutMetrics.deckColumnWidth)
    }

    @Test("Key sizes are whole points and margins never shrink below the class margin")
    func wholePoints() {
        var width = 320.0
        while width <= 1366 {
            let m = LayoutMetrics(width: width, height: 800)
            let grid = m.deckGrid
            #expect(grid.keySize == grid.keySize.rounded(), "\(width)")
            #expect(grid.trailingMargin - grid.leadingMargin == 0 || grid.trailingMargin - grid.leadingMargin == 1, "\(width)")
            if m.widthClass != .wide {
                #expect(grid.leadingMargin >= m.margin, "\(width)")
            }
            width += 1
        }
    }

    @Test("Two-column pages: wide, or medium and short")
    func twoColumns() {
        #expect(LayoutMetrics(width: 1180, height: 820).usesTwoColumnPages)
        #expect(LayoutMetrics(width: 874, height: 402).usesTwoColumnPages)
        #expect(!LayoutMetrics(width: 820, height: 1180).usesTwoColumnPages)
        #expect(!LayoutMetrics(width: 402, height: 874).usesTwoColumnPages)
    }
}

@Suite("Palette tokens")
struct PaletteTokenTests {
    private func resolved(_ token: ColorToken, dark: Bool, highContrast: Bool = false) -> RGBColor {
        let canvas = PaletteTokens.canvas.swatch(dark: dark).color
        return token.swatch(dark: dark, highContrast: highContrast).resolved(over: canvas)
    }

    @Test("Ink on canvas is at least 4.5:1 in both appearances")
    func inkOnCanvas() {
        for dark in [false, true] {
            let ratio = RGBColor.contrast(resolved(PaletteTokens.ink, dark: dark), PaletteTokens.canvas.swatch(dark: dark).color)
            #expect(ratio >= 4.5, "dark=\(dark): \(ratio)")
        }
    }

    @Test("White on accent: ≥ 4.5:1 light (about 6:1), ≥ 4.4:1 dark")
    func whiteOnAccent() {
        let light = RGBColor.contrast(.white, PaletteTokens.accent.light.color)
        let dark = RGBColor.contrast(.white, PaletteTokens.accent.dark.color)
        #expect(light >= 4.5)
        #expect(light > 5.9)
        #expect(dark >= 4.4)
    }

    @Test("Success text on the light canvas is at least 4.5:1")
    func successOnCanvas() {
        let ratio = RGBColor.contrast(PaletteTokens.success.light.color, PaletteTokens.canvas.light.color)
        #expect(ratio >= 4.5)
    }

    @Test("Secondary ink stays readable, and Increase Contrast raises it")
    func secondaryInk() {
        for dark in [false, true] {
            let canvas = PaletteTokens.canvas.swatch(dark: dark).color
            let normal = RGBColor.contrast(resolved(PaletteTokens.ink2, dark: dark), canvas)
            let high = RGBColor.contrast(resolved(PaletteTokens.ink2, dark: dark, highContrast: true), canvas)
            #expect(normal >= 4.5, "dark=\(dark): \(normal)")
            #expect(high > normal)
        }
        #expect(PaletteTokens.hairline.lightHighContrast.opacity == 0.2)
    }

    @Test("Glow is a navy-only colour: it fails as text on the light canvas")
    func glowNavyOnly() {
        let onLight = RGBColor.contrast(PaletteTokens.Brand.glow, PaletteTokens.canvas.light.color)
        let onNavy = RGBColor.contrast(PaletteTokens.Brand.glow, PaletteTokens.Brand.screen)
        #expect(onLight < 3)
        #expect(onNavy > 7)
    }

    @Test("Contrast maths matches WCAG reference values")
    func reference() {
        #expect(abs(RGBColor.contrast(.white, .black) - 21) < 0.001)
        #expect(abs(RGBColor.contrast(.white, .white) - 1) < 0.001)
        #expect(PaletteTokens.all.count == 19)
        #expect(Set(PaletteTokens.all.map(\.name)).count == PaletteTokens.all.count)
    }
}
