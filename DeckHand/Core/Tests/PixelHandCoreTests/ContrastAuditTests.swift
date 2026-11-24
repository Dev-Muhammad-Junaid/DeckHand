//
//  ContrastAuditTests.swift
//  PixelHandCoreTests
//

import Testing
@testable import PixelHandCore

@Suite("Contrast audit (WCAG 2 AA)")
struct ContrastAuditTests {

    @Test("Every pair the app draws meets its WCAG AA minimum in every appearance")
    func everyPairPasses() {
        for pair in ContrastAudit.all {
            for appearance in pair.appearances {
                let ratio = pair.ratio(appearance)
                #expect(ratio >= pair.use.minimum, "\(pair.name), \(appearance): \(ratio)")
            }
        }
        #expect(ContrastAudit.failures.isEmpty)
    }

    @Test("Phosphor reads as body text on every navy surface")
    func phosphorOnNavy() {
        let phosphor = ContrastAudit.navy.filter { $0.name.hasPrefix("phosphor on") }
        #expect(phosphor.count == 6)
        for pair in phosphor {
            #expect(pair.use == .text)
            #expect(pair.worstRatio >= 4.5, "\(pair.name): \(pair.worstRatio)")
        }
    }

    @Test("Cobalt on navy holds 3:1 as a non-text colour on the base screen")
    func cobaltOnNavy() throws {
        let cobalt = try #require(ContrastAudit.navy.first { $0.name == "cobalt on screen" })
        #expect(cobalt.use == .nonText)
        #expect(cobalt.worstRatio >= 3)
        let high = try #require(ContrastAudit.navy.first { $0.name == "cobaltHigh on screenRaised" })
        #expect(high.worstRatio >= 3)
    }

    @Test("Status text on its own tint is body-text readable in light mode")
    func statusOnTint() {
        for name in ["success on successTint", "warning on warningTint", "danger on dangerTint"] {
            let pair = ContrastAudit.semantic.first { $0.name == name }
            #expect(pair?.passes == true, "\(name): \(pair?.worstRatio ?? 0)")
        }
        // The light danger and warning tokens were darkened in UX-013 to clear 4.5:1.
        let light = ContrastAppearance(isDark: false, highContrast: false)
        let danger = ContrastPair("", .token(PaletteTokens.danger), on: .token(PaletteTokens.canvas), use: .text)
        #expect(danger.ratio(light) >= 4.5)
    }

    @Test("Documented limits stay below body-text contrast, so the rules around them still matter")
    func documentedLimits() {
        for pair in ContrastAudit.documentedLimits {
            #expect(pair.worstRatio < 4.5, "\(pair.name) now passes; move it into the audit")
        }
        // accentInk is the accent text colour and clears 4.5:1 everywhere.
        let accentText = ContrastAudit.semantic.filter { $0.name.hasPrefix("accentInk") }
        #expect(!accentText.isEmpty)
        #expect(accentText.allSatisfy { $0.passes })
    }

    @Test("Fixed brand pairs resolve once; token pairs in all four appearances")
    func appearances() {
        let fixed = ContrastPair("", .brand(PaletteTokens.Brand.phosphor), on: .brand(PaletteTokens.Brand.screen), use: .text)
        let token = ContrastPair("", .token(PaletteTokens.ink), on: .token(PaletteTokens.canvas), use: .text)
        #expect(fixed.appearances.count == 1)
        #expect(token.appearances.count == 4)
        #expect(ContrastPair.Use.text.minimum == 4.5)
        #expect(ContrastPair.Use.largeText.minimum == 3)
        #expect(ContrastPair.Use.nonText.minimum == 3)
        #expect(Set(ContrastAudit.all.map(\.name)).count == ContrastAudit.all.count)
    }
}
