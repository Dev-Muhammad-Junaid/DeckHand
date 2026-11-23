//
//  MirrorTilePlacementTests.swift
//  PixelHandCoreTests
//
//  The floating screen tile over the Pointer surface: anchored to the pad's
//  top-trailing corner, and never over the click strip, the caption or the
//  keyboard button, however it's dragged or pinched.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct MirrorTilePlacementTests {
    // iPhone 17 Pro portrait canvas: 402 wide, a 16 pt margin, the pad
    // ending 8 pt above the canvas foot.
    static let canvas = MirrorRect(x: 0, y: 0, width: 402, height: 600)
    static let pad = MirrorRect(x: 16, y: 0, width: 370, height: 592)
    static let strip = MirrorRect(x: 16, y: 540, width: 370, height: 52)
    static let caption = MirrorRect(x: 28, y: 504, width: 130, height: 24)
    static let keyboard = MirrorRect(x: 28, y: 12, width: 44, height: 44)

    static var keepOut: [MirrorRect] {
        MirrorTilePlacement.pointerKeepOut(pad: pad, clickStrip: strip, caption: caption, keyboard: keyboard)
    }

    static func intersects(_ a: MirrorRect, _ b: MirrorRect, gap: Double = MirrorTilePlacement.keepOutGap) -> Bool {
        a.x < b.x + b.width + gap - 1e-6 && b.x - gap < a.x + a.width - 1e-6
            && a.y < b.y + b.height + gap - 1e-6 && b.y - gap < a.y + a.height - 1e-6
    }

    static func assertClear(_ tile: MirrorRect, sourceLocation: SourceLocation = #_sourceLocation) {
        for area in keepOut {
            #expect(!intersects(tile, area), "tile \(tile) overlaps \(area)", sourceLocation: sourceLocation)
        }
        let m = MirrorTilePlacement.edgeMargin
        #expect(tile.x >= canvas.x + m - 1e-6, sourceLocation: sourceLocation)
        #expect(tile.y >= canvas.y + m - 1e-6, sourceLocation: sourceLocation)
        #expect(tile.x + tile.width <= canvas.width - m + 1e-6, sourceLocation: sourceLocation)
        #expect(tile.y + tile.height <= canvas.height - m + 1e-6, sourceLocation: sourceLocation)
    }

    @Test("The caption row is reserved across the whole pad, so a longer caption never moves the tile")
    func captionRowSpansPad() {
        let areas = Self.keepOut
        #expect(areas.count == 3)
        #expect(areas.contains(MirrorRect(x: 16, y: 504, width: 370, height: 24)))
        #expect(areas.contains(Self.strip))
        #expect(areas.contains(Self.keyboard))
    }

    @Test("Missing parts are simply not reserved (strip hidden, no pad)")
    func missingParts() {
        #expect(MirrorTilePlacement.pointerKeepOut(pad: nil, clickStrip: nil, caption: nil, keyboard: nil).isEmpty)
        #expect(MirrorTilePlacement.pointerKeepOut(pad: nil, clickStrip: nil, caption: Self.caption, keyboard: nil) == [Self.caption])
    }

    @Test("Home is the pad's top-trailing corner, 12 pt in, and is already clear")
    func homeIsTopTrailing() {
        let home = MirrorTilePlacement.home(width: 176, height: 110, anchor: Self.pad)
        #expect(home == MirrorRect(x: 386 - 12 - 176, y: 12, width: 176, height: 110))
        let placed = MirrorTilePlacement.place(home, in: Self.canvas, avoiding: Self.keepOut)
        #expect(placed == home)
    }

    @Test("A clear spot is left exactly where it was dropped")
    func clearSpotUnchanged() {
        let tile = MirrorRect(x: 150, y: 250, width: 200, height: 125)
        #expect(MirrorTilePlacement.place(tile, in: Self.canvas, avoiding: Self.keepOut) == tile)
    }

    @Test("Dragged onto the click strip, the tile stops just above the caption row")
    func draggedOntoStrip() {
        let tile = MirrorRect(x: 180, y: 520, width: 200, height: 125)
        let placed = MirrorTilePlacement.place(tile, in: Self.canvas, avoiding: Self.keepOut)
        #expect(placed.x == 180)
        #expect(placed.y == 504 - 8 - 125)
        Self.assertClear(placed)
    }

    @Test("Dragged into the bottom-trailing corner, the tile parks above the strip and caption")
    func bottomTrailingCorner() {
        let tile = MirrorRect(x: 400, y: 700, width: 200, height: 125)
        let placed = MirrorTilePlacement.place(tile, in: Self.canvas, avoiding: Self.keepOut)
        #expect(placed.x == 402 - 8 - 200)
        #expect(placed.y == 504 - 8 - 125)
        Self.assertClear(placed)
    }

    @Test("Dragged onto the keyboard button, the tile slides off to its nearest side")
    func draggedOntoKeyboard() {
        let tile = MirrorRect(x: 20, y: 20, width: 200, height: 125)
        let placed = MirrorTilePlacement.place(tile, in: Self.canvas, avoiding: Self.keepOut)
        Self.assertClear(placed)
        // Below the button (y 64) is nearer than right of it (x 80).
        #expect(placed == MirrorRect(x: 20, y: 64, width: 200, height: 125))
    }

    @Test("Every drag position across the canvas ends clear of the reserved areas")
    func sweep() {
        for x in stride(from: -100.0, through: 500, by: 23) {
            for y in stride(from: -100.0, through: 700, by: 19) {
                let tile = MirrorRect(x: x, y: y, width: 176, height: 110)
                Self.assertClear(MirrorTilePlacement.place(tile, in: Self.canvas, avoiding: Self.keepOut))
            }
        }
    }

    @Test("A pinch can't grow the tile past the space above the caption row")
    func pinchIsCapped() {
        let aspect = 10.0 / 16.0
        let width = MirrorTilePlacement.fittingWidth(
            proposed: 2000, minimum: 200, aspect: aspect, extraHeight: 24,
            in: Self.canvas, avoiding: Self.keepOut
        )
        // Canvas width less margins: 386. Height 386 × 0.625 + 24 = 265 fits.
        #expect(width == 386)

        // A short pad (keyboard open): 300 tall, strip and caption at its foot.
        let short = MirrorRect(x: 0, y: 0, width: 402, height: 300)
        let keep = MirrorTilePlacement.pointerKeepOut(
            pad: MirrorRect(x: 16, y: 0, width: 370, height: 292),
            clickStrip: MirrorRect(x: 16, y: 240, width: 370, height: 52),
            caption: MirrorRect(x: 28, y: 204, width: 130, height: 24),
            keyboard: Self.keyboard
        )
        let fitted = MirrorTilePlacement.fittingWidth(
            proposed: 2000, minimum: 200, aspect: aspect, extraHeight: 0,
            in: short, avoiding: keep
        )
        #expect(fitted < 386)
        #expect(fitted >= 200)
        let height = fitted * aspect
        #expect(MirrorTilePlacement.fits(width: fitted, height: height, in: short, avoiding: keep))
        #expect(!MirrorTilePlacement.fits(width: fitted + 2, height: (fitted + 2) * aspect, in: short, avoiding: keep))
        let placed = MirrorTilePlacement.place(
            MirrorRect(x: 100, y: 100, width: fitted, height: height), in: short, avoiding: keep
        )
        for area in keep { #expect(!Self.intersects(placed, area)) }
    }

    @Test("With no reserved areas (Deck), the tile is only kept on the canvas")
    func noKeepOut() {
        let tile = MirrorRect(x: 380, y: -40, width: 200, height: 125)
        let placed = MirrorTilePlacement.place(tile, in: Self.canvas, avoiding: [])
        #expect(placed == MirrorRect(x: 194, y: 8, width: 200, height: 125))
    }

    @Test("Too big to fit anywhere: least overlap wins, and the tile stays on the canvas")
    func tooBig() {
        let tiny = MirrorRect(x: 0, y: 0, width: 300, height: 200)
        let keep = [MirrorRect(x: 0, y: 150, width: 300, height: 50)]
        #expect(!MirrorTilePlacement.fits(width: 250, height: 160, in: tiny, avoiding: keep))
        #expect(MirrorTilePlacement.fittingWidth(proposed: 250, minimum: 250, aspect: 0.64, in: tiny, avoiding: keep) == 250)
        let placed = MirrorTilePlacement.place(MirrorRect(x: 20, y: 30, width: 250, height: 160), in: tiny, avoiding: keep)
        #expect(placed.y == 8)
        #expect(placed.x == 20)
    }
}
