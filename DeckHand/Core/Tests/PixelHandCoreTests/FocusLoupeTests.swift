//
//  FocusLoupeTests.swift
//  PixelHandCoreTests
//
//  OT-12: the Type panel's loupe crop from the Mac's focused field.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct FocusLoupeTests {
    // A 1512 × 982 pt display (MacBook Pro 14") and a 360 × 120 pt loupe.
    static let displayW = 1512.0
    static let displayH = 982.0
    static let loupeW = 360.0
    static let loupeH = 120.0

    static func snapshot(
        displayID: UInt32 = 1,
        field: FocusRect? = nil,
        caret: FocusRect? = nil,
        pointer: FocusRect? = FocusRect(x: 700, y: 400, width: 24, height: 24),
        source: FocusedFieldSnapshot.Source = .accessibility,
        role: FocusedFieldSnapshot.Role = .textField,
        width: Double = displayW,
        height: Double = displayH
    ) -> FocusedFieldSnapshot {
        FocusedFieldSnapshot(
            displayID: displayID, displayWidth: width, displayHeight: height,
            field: field, caret: caret, pointer: pointer, source: source,
            app: "TextEdit", role: role, text: nil
        )
    }

    static func crop(_ s: FocusedFieldSnapshot, mirrored: UInt32? = 1, previous: FocusLoupeCrop? = nil,
                     loupeW: Double = loupeW, loupeH: Double = loupeH) -> FocusLoupeCrop? {
        FocusLoupe.crop(for: s, mirroredDisplayID: mirrored, loupeWidth: loupeW, loupeHeight: loupeH, previous: previous)
    }

    /// The crop's rect back in display points.
    static func points(_ c: FocusLoupeCrop, width: Double = displayW, height: Double = displayH) -> FocusRect {
        FocusRect(x: c.rect.x * width, y: c.rect.y * height, width: c.rect.width * width, height: c.rect.height * height)
    }

    static func near(_ a: Double, _ b: Double, _ e: Double = 1e-6) -> Bool { abs(a - b) <= e }

    // MARK: Display mapping

    @Test("Points map to normalized display coordinates")
    func normalizes() throws {
        let r = try #require(FocusLoupe.normalized(FocusRect(x: 756, y: 491, width: 151.2, height: 98.2), displayWidth: 1512, displayHeight: 982))
        #expect(Self.near(r.x, 0.5) && Self.near(r.y, 0.5) && Self.near(r.width, 0.1) && Self.near(r.height, 0.1))
        #expect(FocusLoupe.normalized(FocusRect(x: 0, y: 0, width: 1, height: 1), displayWidth: 0, displayHeight: 982) == nil)
        #expect(FocusLoupe.normalized(FocusRect(x: .nan, y: 0, width: 1, height: 1), displayWidth: 10, displayHeight: 10) == nil)
    }

    @Test("A snapshot for another display than the mirrored one gives no crop")
    func wrongDisplay() {
        let s = Self.snapshot(displayID: 2, field: FocusRect(x: 100, y: 100, width: 200, height: 22))
        #expect(Self.crop(s, mirrored: 1) == nil)
        #expect(Self.crop(s, mirrored: 2) != nil)
        #expect(Self.crop(s, mirrored: nil) != nil)
    }

    @Test("The same field on a second, larger display maps into that display's space")
    func secondDisplay() throws {
        let s = Self.snapshot(displayID: 2, field: FocusRect(x: 2000, y: 1200, width: 200, height: 22), width: 2560, height: 1440)
        let c = try #require(Self.crop(s, mirrored: 2))
        let p = Self.points(c, width: 2560, height: 1440)
        #expect(p.minX <= 2000 && p.maxX >= 2200)
        #expect(p.minY <= 1200 && p.maxY >= 1222)
        #expect(c.rect.x + c.rect.width <= 1 + 1e-9 && c.rect.y + c.rect.height <= 1 + 1e-9)
    }

    @Test("Nothing to show gives no crop: .none, no rects, bad sizes")
    func nothing() {
        #expect(Self.crop(.nothing(displayID: 1, displayWidth: Self.displayW, displayHeight: Self.displayH)) == nil)
        #expect(Self.crop(Self.snapshot(pointer: nil)) == nil)
        #expect(Self.crop(Self.snapshot(field: FocusRect(x: 1, y: 1, width: 10, height: 10)), loupeW: 0) == nil)
        #expect(Self.crop(Self.snapshot(field: FocusRect(x: 1, y: 1, width: 10, height: 10), width: .infinity)) == nil)
    }

    // MARK: Zoom

    @Test("Zoom fits the field's width with padding")
    func zoomFitsWidth() throws {
        let wide = try #require(Self.crop(Self.snapshot(field: FocusRect(x: 100, y: 100, width: 164, height: 22))))
        // 164 + 16 = 180 → zoom 2.
        #expect(Self.near(wide.zoom, 2))
        #expect(wide.mode == .field)
        let p = Self.points(wide)
        #expect(Self.near(p.width, 180) && Self.near(p.height, 60))
        // Centred on the field.
        #expect(Self.near(p.midX, 182) && Self.near(p.midY, 111))
    }

    @Test("Zoom stays between 1.5× and 6×")
    func zoomClamped() throws {
        let tiny = try #require(Self.crop(Self.snapshot(field: FocusRect(x: 300, y: 300, width: 20, height: 18))))
        #expect(Self.near(tiny.zoom, 6))
        let huge = try #require(Self.crop(Self.snapshot(field: FocusRect(x: 0, y: 300, width: 1400, height: 22))))
        #expect(Self.near(huge.zoom, 1.5))
    }

    @Test("A loupe larger than the display at minimum zoom zooms in until the crop fits")
    func zoomNeverShowsPastTheDisplay() throws {
        // 2400 pt loupe on a 1512 pt display: at least 1.587×.
        let c = try #require(Self.crop(Self.snapshot(field: FocusRect(x: 0, y: 0, width: 1500, height: 900)), loupeW: 2400, loupeH: 300))
        #expect(c.zoom >= 2400 / Self.displayW - 1e-9)
        #expect(c.rect.width <= 1 + 1e-9 && c.rect.x >= 0)
    }

    @Test("A small change in zoom keeps the previous zoom")
    func zoomHysteresis() throws {
        let first = try #require(Self.crop(Self.snapshot(field: FocusRect(x: 100, y: 100, width: 164, height: 22))))
        let grown = try #require(Self.crop(Self.snapshot(field: FocusRect(x: 100, y: 100, width: 170, height: 22)), previous: first))
        #expect(grown.zoom == first.zoom)
        let doubled = try #require(Self.crop(Self.snapshot(field: FocusRect(x: 100, y: 100, width: 344, height: 22)), previous: first))
        #expect(doubled.zoom < first.zoom)
    }

    // MARK: Caret following

    @Test("A tall text area follows the caret vertically")
    func tallAreaFollowsCaret() throws {
        let area = FocusRect(x: 200, y: 100, width: 164, height: 700)
        let c = try #require(Self.crop(Self.snapshot(field: area, caret: FocusRect(x: 250, y: 500, width: 1, height: 16), role: .textArea)))
        #expect(c.mode == .caret)
        let p = Self.points(c)
        // Field's width fits: centred horizontally on it.
        #expect(Self.near(p.midX, area.midX))
        // Caret centred vertically.
        #expect(Self.near(p.midY, 508))
    }

    @Test("The crop holds while the caret stays away from its edges, then recentres")
    func panHysteresis() throws {
        let area = FocusRect(x: 200, y: 100, width: 164, height: 700)
        let first = try #require(Self.crop(Self.snapshot(field: area, caret: FocusRect(x: 250, y: 500, width: 1, height: 16))))
        // One line down: still inside the middle 60 %.
        let next = try #require(Self.crop(Self.snapshot(field: area, caret: FocusRect(x: 250, y: 510, width: 1, height: 16)), previous: first))
        #expect(next.rect == first.rect)
        // Near the bottom edge (crop is 60 pt tall from 478; margin 12 → past 526).
        let far = try #require(Self.crop(Self.snapshot(field: area, caret: FocusRect(x: 250, y: 524, width: 1, height: 16)), previous: next))
        #expect(far.rect.y > next.rect.y)
        #expect(Self.near(Self.points(far).midY, 532))
    }

    @Test("A long single line follows the caret horizontally")
    func longLineFollowsCaret() throws {
        let line = FocusRect(x: 0, y: 400, width: 1400, height: 22)
        let c = try #require(Self.crop(Self.snapshot(field: line, caret: FocusRect(x: 900, y: 403, width: 1, height: 16))))
        #expect(c.mode == .caret)
        let p = Self.points(c)
        #expect(Self.near(p.midX, 900.5))
        #expect(Self.near(p.midY, line.midY))
    }

    @Test("Without a caret, a field larger than the crop shows its top-leading corner")
    func noCaretShowsCorner() throws {
        let area = FocusRect(x: 200, y: 100, width: 900, height: 700)
        let c = try #require(Self.crop(Self.snapshot(field: area, caret: nil)))
        #expect(c.mode == .field)
        let p = Self.points(c)
        #expect(Self.near(p.minX, 192) && Self.near(p.minY, 92))
    }

    @Test("A caret without a field zooms around the caret")
    func caretOnly() throws {
        let c = try #require(Self.crop(Self.snapshot(field: nil, caret: FocusRect(x: 600, y: 300, width: 1, height: 16), role: .webArea)))
        #expect(c.mode == .caret)
        #expect(Self.near(c.zoom, 3))
        #expect(Self.near(Self.points(c).midX, 600.5))
    }

    // MARK: Clamping

    @Test("The crop stays inside the display at every edge")
    func clamped() throws {
        let corners = [
            FocusRect(x: 0, y: 0, width: 40, height: 20),
            FocusRect(x: 1490, y: 0, width: 22, height: 20),
            FocusRect(x: 0, y: 970, width: 40, height: 12),
            FocusRect(x: 1490, y: 970, width: 22, height: 12),
        ]
        for field in corners {
            let c = try #require(Self.crop(Self.snapshot(field: field)))
            #expect(c.rect.x >= 0 && c.rect.y >= 0)
            #expect(c.rect.x + c.rect.width <= 1 + 1e-9)
            #expect(c.rect.y + c.rect.height <= 1 + 1e-9)
        }
    }

    // MARK: Pointer fallback

    @Test("Without a field frame the loupe zooms 3× around the pointer")
    func pointerFallback() throws {
        let s = Self.snapshot(field: nil, caret: nil, pointer: FocusRect(x: 700, y: 400, width: 24, height: 24), source: .pointer, role: .other)
        let c = try #require(Self.crop(s))
        #expect(c.mode == .pointer)
        #expect(Self.near(c.zoom, 3))
        let p = Self.points(c)
        #expect(Self.near(p.midX, 712) && Self.near(p.midY, 412))
        #expect(Self.near(p.width, 120) && Self.near(p.height, 40))
    }

    @Test("The pointer crop holds for small moves and recentres near an edge")
    func pointerHysteresis() throws {
        let first = try #require(Self.crop(Self.snapshot(field: nil, pointer: FocusRect(x: 700, y: 400, width: 24, height: 24), source: .pointer)))
        let small = try #require(Self.crop(Self.snapshot(field: nil, pointer: FocusRect(x: 720, y: 402, width: 24, height: 24), source: .pointer), previous: first))
        #expect(small.rect == first.rect)
        let big = try #require(Self.crop(Self.snapshot(field: nil, pointer: FocusRect(x: 760, y: 400, width: 24, height: 24), source: .pointer), previous: small))
        #expect(big.rect.x > small.rect.x)
    }

    @Test("A pointer crop never takes a field crop's place for hysteresis")
    func modesDontShareHysteresis() throws {
        let field = try #require(Self.crop(Self.snapshot(field: FocusRect(x: 100, y: 100, width: 164, height: 22))))
        let pointer = try #require(Self.crop(Self.snapshot(field: nil, pointer: FocusRect(x: 150, y: 100, width: 24, height: 24), source: .pointer), previous: field))
        #expect(Self.near(pointer.zoom, 3))
        #expect(Self.near(Self.points(pointer).midX, 162))
    }

    // MARK: Video

    @Test("The crop maps into the mirror video's pixels, which may be scaled")
    func videoMapping() {
        let crop = LoupeRect(x: 0.25, y: 0.5, width: 0.1, height: 0.05)
        let v = FocusLoupe.videoRect(for: crop, videoWidth: 1280, videoHeight: 832)
        #expect(Self.near(v.x, 320) && Self.near(v.y, 416) && Self.near(v.width, 128) && Self.near(v.height, 41.6))
        #expect(Self.near(FocusLoupe.videoPixelsPerLoupePoint(crop: crop, videoWidth: 1280, loupeWidth: 256), 0.5))
        // Sharp at 2× on a 360 pt loupe showing a tenth of the display: 7200 → capped.
        #expect(FocusLoupe.recommendedMirrorWidth(crop: crop, loupeWidth: 360, screenScale: 2) == 1920)
        #expect(FocusLoupe.recommendedMirrorWidth(crop: LoupeRect(x: 0, y: 0, width: 0.5, height: 0.5), loupeWidth: 360, screenScale: 2) == 1440)
    }

    @Test("A caret maps into the loupe's own 0…1 space")
    func caretInLoupe() throws {
        let crop = LoupeRect(x: 0.2, y: 0.4, width: 0.2, height: 0.1)
        let caret = LoupeRect(x: 0.3, y: 0.45, width: 0.001, height: 0.02)
        let p = try #require(FocusLoupe.position(of: caret, inCrop: crop))
        #expect(Self.near(p.x, 0.5) && Self.near(p.y, 0.5) && Self.near(p.height, 0.2))
        #expect(FocusLoupe.position(of: caret, inCrop: LoupeRect(x: 0, y: 0, width: 0, height: 1)) == nil)
    }
}
