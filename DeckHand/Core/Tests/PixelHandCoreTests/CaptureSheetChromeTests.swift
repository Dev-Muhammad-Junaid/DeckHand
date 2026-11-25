//
//  CaptureSheetChromeTests.swift
//  PixelHandCoreTests
//
//  The capture sheet (UX-009): its dot-matrix strips, error titles for the
//  locked-Mac refusal, the capture glyphs, and the maths that maps
//  drawings and selections onto the capture's pixels.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct CaptureSheetChromeTests {
    static func drawable(_ items: [String], sourceLocation: SourceLocation = #_sourceLocation) {
        for item in items {
            for character in item {
                #expect(DotMatrixFont.characters.contains(character), "\(item): \(character) can't be drawn", sourceLocation: sourceLocation)
            }
        }
    }

    @Test("Strips name the capture, its pixel size and whether it's marked, all drawable")
    func strips() {
        let full = CaptureSheetChrome.strip(kind: .fullScreen, pixelWidth: 3024, pixelHeight: 1964, annotated: false)
        #expect(full.items == ["FULL SCREEN", "3024X1964"])
        #expect(full.spoken == "Full screen capture, 3024 by 1964 pixels")

        let region = CaptureSheetChrome.strip(kind: .region, pixelWidth: 812, pixelHeight: 540, annotated: true)
        #expect(region.items == ["REGION", "812X540", "MARKED"])

        let window = CaptureSheetChrome.strip(kind: .window(appName: "Visual Studio Code — main.swift"), pixelWidth: 1440, pixelHeight: 900, annotated: false)
        #expect(window.items.first == "WINDOW")
        #expect(window.items[1].count <= CaptureSheetChrome.maxAppNameLength)
        #expect(window.items[1] == "VISUAL") // cut at a word, never mid-word
        #expect(window.spoken.hasPrefix("Window capture, Visual Studio Code"))

        let unnamed = CaptureSheetChrome.strip(kind: .window(appName: "日本"), pixelWidth: 0, pixelHeight: 0, annotated: false)
        #expect(unnamed.items == ["WINDOW"])

        for strip in [full, region, window, unnamed,
                      CaptureSheetChrome.annotateStrip(marks: 3),
                      CaptureSheetChrome.readTextStrip(lines: 12, characters: 340),
                      CaptureSheetChrome.readTextStrip(lines: nil, characters: nil)] {
            Self.drawable(strip.items)
        }
    }

    @Test("Annotate and read-text strips count marks, lines and characters")
    func stepStrips() {
        #expect(CaptureSheetChrome.annotateStrip(marks: 1).items == ["ANNOTATE", "1 MARK"])
        #expect(CaptureSheetChrome.annotateStrip(marks: 0).items == ["ANNOTATE", "0 MARKS"])
        #expect(CaptureSheetChrome.annotateStrip(marks: 3).spoken == "Annotate, 3 marks")
        #expect(CaptureSheetChrome.readTextStrip(lines: 1, characters: 9).items == ["READ TEXT", "1 LINE", "9 CHARS"])
        #expect(CaptureSheetChrome.readTextStrip(lines: nil, characters: nil).items == ["READ TEXT", "READING"])
    }

    @Test("The locked-Mac refusal gets its own title and tells the user to unlock")
    func lockedRefusal() {
        let locked = LockPolicy.lockedErrorMessage
        #expect(CaptureSheetChrome.isLockedRefusal(locked))
        #expect(CaptureSheetChrome.errorTitle(message: locked, isMirror: false) == "Mac is locked")
        #expect(CaptureSheetChrome.errorTitle(message: locked, isMirror: true) == "Mac is locked")
        #expect(CaptureSheetChrome.errorMessage(message: locked, isMirror: false).hasPrefix("Unlock the Mac"))
        #expect(CaptureSheetChrome.errorTitle(message: "Timeout", isMirror: false) == "Screenshot failed")
        #expect(CaptureSheetChrome.errorTitle(message: "Timeout", isMirror: true) == "Live screen unavailable")
        #expect(CaptureSheetChrome.errorMessage(message: "Timeout", isMirror: true) == "Timeout.")
        #expect(CaptureSheetChrome.emptyWindowsMessage(isMirror: false).contains("unlock"))
    }

    @Test("Pen widths and inks: four widths, phosphor first, unique labels")
    func tools() {
        #expect(CaptureSheetChrome.penWidths == [2, 4, 8, 14])
        #expect(CaptureSheetChrome.penWidths.contains(CaptureSheetChrome.defaultPenWidth))
        #expect(CaptureSheetChrome.Ink.allCases.first == .phosphor)
        #expect(Set(CaptureSheetChrome.Ink.allCases.map(\.label)).count == CaptureSheetChrome.Ink.allCases.count)
    }

    @Test("Capture glyphs follow the glyph rules: 9 × 9, one-dot strokes, lit accent, unique names")
    func glyphs() {
        #expect(Set(CaptureGlyphs.all.map(\.name)).count == CaptureGlyphs.all.count)
        let shared = Set(PixelGlyphs.all.map(\.name))
        for glyph in CaptureGlyphs.all {
            #expect(!shared.contains(glyph.name), "\(glyph.name) clashes with the shared set")
            #expect(glyph.rows.count == 9)
            #expect(glyph.thickStrokeBlocks.isEmpty, "\(glyph.name): \(glyph.thickStrokeBlocks)")
            #expect(!glyph.isSolid)
            if let accent = glyph.accent { #expect(glyph.isOn(accent.x, accent.y)) }
        }
    }

    // MARK: Geometry

    static let stage = MirrorRect(x: 0, y: 0, width: 400, height: 800)

    @Test("A wide capture fits the stage's width, centred vertically")
    func fit() {
        let fitted = CaptureGeometry.fittedRect(contentWidth: 3000, contentHeight: 2000, in: Self.stage)
        #expect(fitted == MirrorRect(x: 0, y: 400 - 400 * 2 / 3 / 2 * 1, width: 400, height: 400 * 2 / 3 * 1))
        #expect(CaptureGeometry.pixelsPerPoint(fitted: fitted, imageWidth: 3000) == 7.5)
        #expect(CaptureGeometry.fittedRect(contentWidth: 0, contentHeight: 10, in: Self.stage).width == 0)
    }

    @Test("Screen points map onto the capture's pixels")
    func mapPoints() {
        let fitted = CaptureGeometry.fittedRect(contentWidth: 3000, contentHeight: 2000, in: Self.stage)
        let topLeft = CaptureGeometry.imagePoint(x: fitted.x, y: fitted.y, fitted: fitted, imageWidth: 3000, imageHeight: 2000)
        #expect(topLeft.x == 0 && topLeft.y == 0)
        let centre = CaptureGeometry.imagePoint(x: 200, y: 400, fitted: fitted, imageWidth: 3000, imageHeight: 2000)
        #expect(abs(centre.x - 1500) < 1e-9 && abs(centre.y - 1000) < 1e-9)
    }

    @Test("A selection becomes the 0…1 crop, clamped to the picture; tiny ones are refused")
    func selection() {
        let fitted = MirrorRect(x: 0, y: 200, width: 400, height: 400)
        let n = CaptureGeometry.normalizedSelection(MirrorRect(x: 100, y: 300, width: 200, height: 100), fitted: fitted, minimumSide: 24)
        #expect(n == MirrorRect(x: 0.25, y: 0.25, width: 0.5, height: 0.25))

        // Hanging off the picture's top: clamped.
        let clamped = CaptureGeometry.normalizedSelection(MirrorRect(x: 0, y: 100, width: 400, height: 200), fitted: fitted, minimumSide: 24)
        #expect(clamped == MirrorRect(x: 0, y: 0, width: 1, height: 0.25))

        #expect(CaptureGeometry.normalizedSelection(MirrorRect(x: 10, y: 210, width: 20, height: 100), fitted: fitted, minimumSide: 24) == nil)
        #expect(CaptureGeometry.normalizedSelection(MirrorRect(x: 0, y: 0, width: 100, height: 100), fitted: fitted, minimumSide: 24) == nil)

        #expect(CaptureGeometry.selectionPixels(MirrorRect(x: 100, y: 300, width: 200, height: 100), fitted: fitted, imageWidth: 3000, imageHeight: 3000) == "1500X750")
    }
}
