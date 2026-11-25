//
//  MirrorTileDeckTests.swift
//  PixelHandCoreTests
//
//  Build 19: on iPhone (Deck tab, mirror running) the floating screen tile
//  sat over the deck header's counter, pin and Edit.
//

import Testing
@testable import PixelHandCore

@Suite("MirrorTilePlacement: the tile keeps clear of the deck header")
struct MirrorTileDeckTests {
    /// iPhone 17 Pro's surface under the shell header.
    let canvas = MirrorRect(x: 0, y: 0, width: 402, height: 690)
    /// The deck header row at the Standard band (one row, 44 pt) and at
    /// AX3 (name, then counter / pin / Edit: two rows).
    let standardHeader = MirrorRect(x: 0, y: 4, width: 402, height: 44)
    let ax3Header = MirrorRect(x: 0, y: 4, width: 402, height: 124)

    func clear(_ tile: MirrorRect, of area: MirrorRect) -> Bool {
        let gap = MirrorTilePlacement.keepOutGap - 1e-6
        return tile.y >= area.y + area.height + gap
            || tile.y + tile.height <= area.y - gap
            || tile.x >= area.x + area.width + gap
            || tile.x + tile.width <= area.x - gap
    }

    @Test("Home sits under the header, inset like the pad's corner, clear of it")
    func homeUnderHeader() throws {
        for header in [standardHeader, ax3Header] {
            let layout = MirrorTilePlacement.surfaceLayout(bounds: canvas, deckHeader: header)
            #expect(layout.keepOut == [header])
            let anchor = try #require(layout.anchor)
            #expect(anchor.y == header.y + header.height)
            #expect(anchor.x == canvas.x && anchor.width == canvas.width)
            let home = MirrorTilePlacement.home(width: 160, height: 100, anchor: anchor)
            #expect(home.y == header.y + header.height + MirrorTilePlacement.homeInset)
            #expect(home.x + home.width == canvas.width - MirrorTilePlacement.homeInset)
            #expect(clear(home, of: header))
            // Home is already a clear spot: placing it doesn't move it.
            #expect(MirrorTilePlacement.place(home, in: canvas, avoiding: layout.keepOut) == home)
        }
    }

    @Test("A tile dragged or remembered over the header is moved clear of it")
    func draggedOntoHeader() {
        for header in [standardHeader, ax3Header] {
            let layout = MirrorTilePlacement.surfaceLayout(bounds: canvas, deckHeader: header)
            // Where build 19 put it: the canvas's top-trailing corner.
            let old = MirrorTilePlacement.home(width: 160, height: 100, anchor: canvas)
            #expect(!clear(old, of: header))
            let placed = MirrorTilePlacement.place(old, in: canvas, avoiding: layout.keepOut)
            #expect(clear(placed, of: header))
            #expect(placed.x == old.x)
            // A big tile is narrowed until it fits clear of the header.
            let width = MirrorTilePlacement.fittingWidth(
                proposed: 380, minimum: 120, aspect: 0.625,
                in: canvas, avoiding: layout.keepOut
            )
            let big = MirrorRect(x: 8, y: 8, width: width, height: width * 0.625)
            #expect(clear(MirrorTilePlacement.place(big, in: canvas, avoiding: layout.keepOut), of: header))
        }
    }

    @Test("With the pad on screen too (iPad), the pad stays the anchor and the header is still avoided")
    func padAndDeck() {
        let bounds = MirrorRect(x: 0, y: 0, width: 1180, height: 760)
        let pad = MirrorRect(x: 176, y: 0, width: 668, height: 600)
        let header = MirrorRect(x: 844, y: 4, width: 336, height: 44)
        let layout = MirrorTilePlacement.surfaceLayout(bounds: bounds, pad: pad, deckHeader: header)
        #expect(layout.anchor == pad)
        #expect(layout.keepOut.contains(header))
    }

    @Test("Pointer only: unchanged (pad anchor, its own keep-outs)")
    func pointerUnchanged() {
        let pad = MirrorRect(x: 16, y: 0, width: 370, height: 500)
        let strip = MirrorRect(x: 16, y: 508, width: 370, height: 44)
        let layout = MirrorTilePlacement.surfaceLayout(bounds: canvas, pad: pad, clickStrip: strip)
        #expect(layout.anchor == pad)
        #expect(layout.keepOut == MirrorTilePlacement.pointerKeepOut(pad: pad, clickStrip: strip, caption: nil, keyboard: nil))
        #expect(MirrorTilePlacement.surfaceLayout(bounds: canvas).anchor == nil)
    }
}
