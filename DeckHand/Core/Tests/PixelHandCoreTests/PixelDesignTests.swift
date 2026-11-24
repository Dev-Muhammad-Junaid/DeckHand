//
//  PixelDesignTests.swift
//  PixelHandCoreTests
//
//  The pixel identity as data: glyphs, the dot-matrix font, pitches and the
//  dot geometry (`Product/Design/06-Pixel-Identity.md`).
//

import Testing
@testable import PixelHandCore

@Suite("Pixel glyphs")
struct PixelGlyphTests {
    @Test("The set has the 40 glyphs from the spec, with unique names")
    func setIsComplete() {
        #expect(PixelGlyphs.all.count == 40)
        #expect(Set(PixelGlyphs.all.map(\.name)).count == 40)
        #expect(Set(PixelGlyphs.all.map(\.label)).count == 40)
        let labels = Set(PixelGlyphs.all.map(\.label))
        for label in [
            "Pointer", "Click", "Screen", "Deck", "Keyboard", "Capture", "Mission Control", "Show Desktop",
            "Play", "Pause", "Build", "Run", "Stop", "Test", "Find", "Console", "Lock", "Send", "Share", "Ask",
            "Mac", "iPhone", "Space left", "Space right", "Displays", "Wired", "VPN", "Sound on", "Sound off",
            "Paste", "Type", "Region", "Read text", "Pin", "Close", "Add", "Picture in Picture", "Wi-Fi",
            "Settings", "Wake",
        ] {
            #expect(labels.contains(label), "missing \(label)")
        }
    }

    @Test("Every glyph is 9 × 9 with at most one accent dot")
    func gridAndAccent() {
        for glyph in PixelGlyphs.all {
            #expect(glyph.rows.count == 9, "\(glyph.name)")
            #expect(glyph.rows.allSatisfy { $0 < (1 << 9) }, "\(glyph.name)")
            if let accent = glyph.accent {
                #expect(glyph.isOn(accent.x, accent.y), "\(glyph.name): accent must be lit")
            }
            #expect(!glyph.litPoints.isEmpty, "\(glyph.name)")
        }
    }

    /// Ported cell for cell from the board. Two board glyphs draw two-dot
    /// edges on purpose (Show Desktop's pushed-aside windows, the Mac's
    /// screen sitting on its base). Decided in UX-014: both stay as drawn
    /// (`06-Pixel-Identity.md`, stroke rule 1). They're listed here so any
    /// *new* violation fails.
    static let boardStrokeExceptions: Set<String> = ["desktop", "laptop"]

    @Test("Outline glyphs keep one-dot strokes: no 2 × 2 block unless solid")
    func strokeRule() {
        for glyph in PixelGlyphs.all where !glyph.isSolid {
            if Self.boardStrokeExceptions.contains(glyph.name) {
                #expect(!glyph.thickStrokeBlocks.isEmpty, "\(glyph.name) no longer needs its exception")
            } else {
                #expect(glyph.thickStrokeBlocks.isEmpty, "\(glyph.name): \(glyph.thickStrokeBlocks)")
            }
        }
    }

    @Test("Only the media-state glyphs are solid")
    func solids() {
        #expect(PixelGlyphs.all.filter(\.isSolid).map(\.name).sorted() == ["pause", "play"])
    }

    @Test("Patterns round-trip and match the board's pointer")
    func roundTrip() {
        for glyph in PixelGlyphs.all {
            let copy = GlyphBitmap(name: glyph.name, label: glyph.label, pattern: glyph.pattern, isSolid: glyph.isSolid)
            #expect(copy == glyph)
        }
        #expect(PixelGlyphs.pointer.pattern.first == "#........")
        #expect(PixelGlyphs.pointer.accent == nil)
        #expect(PixelGlyphs.click.accent == GlyphPoint(x: 4, y: 4))
        #expect(PixelGlyphs.named("mission") == PixelGlyphs.missionControl)
        #expect(PixelGlyphs.named("nope") == nil)
    }

    @Test("Ask is a 3 × 3 dot pattern with a lit centre")
    func askGlyph() {
        #expect(PixelGlyphs.ask.litPoints.count == 9)
        #expect(PixelGlyphs.ask.accent == GlyphPoint(x: 4, y: 4))
    }
}

@Suite("Dot-matrix font")
struct DotMatrixFontTests {
    @Test("Covers A–Z, 0–9 and the listed punctuation; every pattern is 35 cells")
    func coverage() {
        let expected = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ·:/%-.+<>")
        #expect(DotMatrixFont.characters == expected)
        for (character, pattern) in DotMatrixFont.table {
            #expect(pattern.count == 35, "\(character)")
            #expect(pattern.allSatisfy { $0 == "0" || $0 == "1" }, "\(character)")
        }
    }

    @Test("Every visible character lights at least one dot; space lights none")
    func visible() {
        for character in DotMatrixFont.characters where character != " " {
            #expect((DotMatrixFont.pattern(for: character) ?? 0) != 0, "\(character)")
        }
        #expect(DotMatrixFont.pattern(for: " ") == 0)
    }

    @Test("Lowercase is uppercased; unknown characters draw as spaces")
    func normalization() {
        #expect(DotMatrixFont.pattern(for: "a") == DotMatrixFont.pattern(for: "A"))
        #expect(DotMatrixFont.normalized("fps!") == Array("FPS "))
        #expect(DotMatrixFont.litCells("live") == DotMatrixFont.litCells("LIVE"))
    }

    @Test("Advance is 6 cells; width drops the trailing tracking")
    func widths() {
        #expect(DotMatrixFont.widthInCells("") == 1)
        #expect(DotMatrixFont.widthInCells("A") == 5)
        #expect(DotMatrixFont.widthInCells("60 FPS") == 35)
        let cells = DotMatrixFont.litCells("11")
        #expect(cells.allSatisfy { $0.y < 7 })
        #expect(cells.map(\.x).max() == 6 + 3) // "1" is widest at column 3
    }

    @Test("Lit and unlit cells partition each character box")
    func partition() {
        let text = "01/03"
        let lit = DotMatrixFont.litCells(text).count
        let unlit = DotMatrixFont.unlitCells(text).count
        #expect(lit + unlit == text.count * 35)
    }

    @Test("Board pattern for 0 is the oval with the slash")
    func zero() {
        #expect(DotMatrixFont.isOn("0", column: 1, row: 0))
        #expect(!DotMatrixFont.isOn("0", column: 0, row: 0))
        #expect(DotMatrixFont.isOn("0", column: 2, row: 3))
    }
}

@Suite("Pixel pitch and dot geometry")
struct PixelPitchTests {
    @Test("Glyph sizes follow the pitch table")
    func sizes() {
        #expect(PixelPitch.glyphSide(2) == 18)
        #expect(PixelPitch.glyphSide(3) == 27)
        #expect(PixelPitch.glyphSide(6) == 54)
        #expect(PixelPitch.glyphSide(10) == 90)
        #expect(abs(PixelPitch.glyphSide(2.6) - 23.4) < 0.0001)
        for pitch in [PixelPitch.badge, PixelPitch.chip, PixelPitch.header, PixelPitch.tabBar, PixelPitch.key, PixelPitch.emptyState, PixelPitch.hero] {
            #expect(PixelPitch.glyph.contains(pitch))
        }
    }

    @Test("Large type steps pitch one size; standard keeps it")
    func stepping() {
        #expect(PixelPitch.stepped(1.4, for: .standard) == 1.4)
        #expect(PixelPitch.stepped(1.4, for: .large) == 2)
        #expect(PixelPitch.stepped(2, for: .large) == 2.6)
        #expect(PixelPitch.stepped(2, for: .huge) == 2.6)
        #expect(PixelPitch.stepped(3, for: .huge) == 3)
    }

    @Test("Type bands: standard to xxxLarge, large AX1–AX2, huge AX3–AX5")
    func bands() {
        #expect(TypeBand(dynamicTypeIndex: 0) == .standard)
        #expect(TypeBand(dynamicTypeIndex: 6) == .standard)
        #expect(TypeBand(dynamicTypeIndex: 7) == .large)
        #expect(TypeBand(dynamicTypeIndex: 8) == .large)
        #expect(TypeBand(dynamicTypeIndex: 9) == .huge)
        #expect(TypeBand(dynamicTypeIndex: 11) == .huge)
    }

    @Test("One dot: 78 % of the pitch for glyphs, 80 % for type, centred")
    func dot() {
        let g = DotGeometry.glyph.frame(x: 1, y: 2, pitch: 10)
        #expect(abs(g.side - 7.8) < 0.0001)
        #expect(abs(g.x - 11.1) < 0.0001)
        #expect(abs(g.y - 21.1) < 0.0001)
        #expect(abs(DotGeometry.glyph.cornerRadius(pitch: 10) - 2.34) < 0.0001)
        #expect(abs(DotGeometry.type.dotSide(pitch: 2) - 1.6) < 0.0001)
    }
}
