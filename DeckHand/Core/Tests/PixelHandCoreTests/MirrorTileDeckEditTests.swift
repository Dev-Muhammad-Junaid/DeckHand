//
//  MirrorTileDeckEditTests.swift
//  PixelHandCoreTests
//
//  Build 23 (VQ-083): on iPhone, in deck edit mode, the floating screen
//  tile covered the header's Done and three key slots.
//

import Foundation
import Testing
@testable import PixelHandCore

@Suite("MirrorTilePlacement: the tile keeps clear of the deck editor")
struct MirrorTileDeckEditTests {
    /// iPhone 17 Pro's surface under the shell header.
    let phone = MirrorRect(x: 0, y: 0, width: 402, height: 690)
    let header = MirrorRect(x: 0, y: 4, width: 402, height: 44)
    /// The pager under the header: the edit grid fills it.
    let phoneGrid = MirrorRect(x: 0, y: 64, width: 402, height: 600)

    func clear(_ tile: MirrorRect, of area: MirrorRect) -> Bool {
        let gap = MirrorTilePlacement.keepOutGap - 1e-6
        return tile.y >= area.y + area.height + gap
            || tile.y + tile.height <= area.y - gap
            || tile.x >= area.x + area.width + gap
            || tile.x + tile.width <= area.x - gap
    }

    @Test("iPhone edit mode: no room beside the header and grid, so the tile steps aside")
    func phoneEditStepsAside() {
        let plan = MirrorTilePlacement.surfacePlan(bounds: phone, deckHeader: header, deckEditGrid: phoneGrid)
        #expect(plan.stepsAsideWhenCrowded)
        #expect(plan.keepOut == [header, phoneGrid])
        #expect(!MirrorTilePlacement.isShown(plan, minimumWidth: 200, aspect: 0.625, in: phone))
    }

    @Test("Outside edit mode the tile is always shown, under the header")
    func phoneNotEditing() throws {
        let plan = MirrorTilePlacement.surfacePlan(bounds: phone, deckHeader: header)
        #expect(!plan.stepsAsideWhenCrowded)
        #expect(MirrorTilePlacement.isShown(plan, minimumWidth: 200, aspect: 0.625, in: phone))
        let anchor = try #require(plan.anchor)
        let home = MirrorTilePlacement.home(width: 200, height: 125, anchor: anchor)
        #expect(clear(home, of: header))
    }

    @Test("iPad edit mode: the pad stays the anchor and the tile moves clear of the deck column")
    func padEditMovesClear() throws {
        let canvas = MirrorRect(x: 0, y: 0, width: 1210, height: 760)
        let pad = MirrorRect(x: 16, y: 16, width: 800, height: 600)
        let deckHeader = MirrorRect(x: 840, y: 16, width: 354, height: 44)
        let grid = MirrorRect(x: 840, y: 72, width: 354, height: 670)
        let plan = MirrorTilePlacement.surfacePlan(bounds: canvas, pad: pad, deckHeader: deckHeader, deckEditGrid: grid)
        #expect(plan.anchor == pad)
        #expect(MirrorTilePlacement.isShown(plan, minimumWidth: 200, aspect: 0.625, in: canvas))
        // Dragged onto the deck's Done: moved off the header and the grid.
        let dragged = MirrorRect(x: 980, y: 10, width: 200, height: 125)
        let placed = MirrorTilePlacement.place(dragged, in: canvas, avoiding: plan.keepOut)
        #expect(clear(placed, of: deckHeader))
        #expect(clear(placed, of: grid))
    }

    @Test("surfaceLayout keeps its shape and includes the edit grid")
    func layoutWrapper() {
        let layout = MirrorTilePlacement.surfaceLayout(bounds: phone, deckHeader: header, deckEditGrid: phoneGrid)
        #expect(layout.keepOut == [header, phoneGrid])
        #expect(layout.anchor?.y == header.y + header.height)
    }

    @Test("Every tile size and edit grid either fits clear or steps aside, never covers Done")
    func neverCoversHeader() {
        for gridTop in stride(from: 56.0, through: 400.0, by: 24.0) {
            let grid = MirrorRect(x: 0, y: gridTop, width: 402, height: 664 - gridTop)
            let plan = MirrorTilePlacement.surfacePlan(bounds: phone, deckHeader: header, deckEditGrid: grid)
            for width in stride(from: 120.0, through: 380.0, by: 20.0) {
                guard MirrorTilePlacement.isShown(plan, minimumWidth: width, aspect: 0.625, in: phone) else { continue }
                let anchor = plan.anchor ?? phone
                let home = MirrorTilePlacement.home(width: width, height: width * 0.625, anchor: anchor)
                let placed = MirrorTilePlacement.place(home, in: phone, avoiding: plan.keepOut)
                #expect(clear(placed, of: header))
                #expect(clear(placed, of: grid))
            }
        }
    }
}

@Suite("MirrorTileKeepOutRegistry: a late withdrawal never wipes a newer report")
struct MirrorTileKeepOutRegistryTests {
    typealias Registry = MirrorTileKeepOutRegistry<Int, String, MirrorRect>
    let header = MirrorRect(x: 0, y: 4, width: 402, height: 44)
    let editHeader = MirrorRect(x: 0, y: 4, width: 402, height: 52)

    @Test("Build 23: the edit header appears before the normal header disappears")
    func editHeaderAppearsFirst() {
        var registry = Registry()
        let normal = UUID()
        let edit = UUID()
        registry.report(header, for: "deckHeader", owner: 1, reporter: normal)
        // Tap Edit: the edit header reports first, then the old one leaves.
        registry.report(editHeader, for: "deckHeader", owner: 1, reporter: edit)
        #expect(!registry.withdraw("deckHeader", owner: 1, reporter: normal))
        #expect(registry.frame("deckHeader", owner: 1) == editHeader)
        // Tap Done: the same race the other way.
        registry.report(header, for: "deckHeader", owner: 1, reporter: normal)
        registry.withdraw("deckHeader", owner: 1, reporter: edit)
        #expect(registry.frame("deckHeader", owner: 1) == header)
    }

    @Test("A reporter's own withdrawal clears its part, and the owner when empty")
    func ownWithdrawal() {
        var registry = Registry()
        let id = UUID()
        registry.report(header, for: "deckHeader", owner: 1, reporter: id)
        #expect(registry.hasParts(owner: 1))
        #expect(registry.withdraw("deckHeader", owner: 1, reporter: id))
        #expect(registry.frame("deckHeader", owner: 1) == nil)
        #expect(!registry.hasParts(owner: 1))
    }

    @Test("Owners don't see each other's parts, and unchanged reports are no-ops")
    func ownersAreSeparate() {
        var registry = Registry()
        let id = UUID()
        #expect(registry.report(header, for: "pad", owner: 1, reporter: id))
        #expect(!registry.report(header, for: "pad", owner: 1, reporter: id))
        #expect(registry.frame("pad", owner: 2) == nil)
        #expect(!registry.withdraw("pad", owner: 2, reporter: id))
        #expect(registry.frame("pad", owner: 1) == header)
    }
}
