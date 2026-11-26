//
//  MirrorTileDeckEmptyTests.swift
//  PixelHandCoreTests
//
//  Build 24 (VQ-098): outside edit mode the floating screen tile covered
//  the empty deck's "No keys yet" at AX3 and most of the card at AX5.
//

import Foundation
import Testing
@testable import PixelHandCore

@Suite("MirrorTilePlacement: the tile keeps clear of the empty deck")
struct MirrorTileDeckEmptyTests {
    let phone = MirrorRect(x: 0, y: 0, width: 402, height: 690)
    let header = MirrorRect(x: 0, y: 4, width: 402, height: 60)
    /// AX5: the empty state's glyph, title, message and Add keys fill the
    /// page under the header.
    let ax5Empty = MirrorRect(x: 16, y: 76, width: 370, height: 600)
    /// Standard size: the empty state is a block in the middle of the page.
    let standardEmpty = MirrorRect(x: 40, y: 300, width: 322, height: 220)

    func clear(_ tile: MirrorRect, of area: MirrorRect) -> Bool {
        let gap = MirrorTilePlacement.keepOutGap - 1e-6
        return tile.y >= area.y + area.height + gap
            || tile.y + tile.height <= area.y - gap
            || tile.x >= area.x + area.width + gap
            || tile.x + tile.width <= area.x - gap
    }

    @Test("Build 24 AX5: no clear spot over the empty deck, so the tile steps aside")
    func ax5StepsAside() {
        let plan = MirrorTilePlacement.surfacePlan(bounds: phone, deckHeader: header, deckEmptyState: ax5Empty, band: .huge)
        #expect(plan.stepsAsideWhenCrowded)
        #expect(plan.keepOut == [header, ax5Empty])
        #expect(!MirrorTilePlacement.isShown(plan, minimumWidth: 200, aspect: 0.625, in: phone))
    }

    @Test("The Huge band with room left: the tile stays and sits clear of the empty state")
    func hugeWithRoom() throws {
        let plan = MirrorTilePlacement.surfacePlan(bounds: phone, deckHeader: header, deckEmptyState: standardEmpty, band: .huge)
        #expect(MirrorTilePlacement.isShown(plan, minimumWidth: 200, aspect: 0.625, in: phone))
        let anchor = try #require(plan.anchor)
        let home = MirrorTilePlacement.home(width: 200, height: 125, anchor: anchor)
        let placed = MirrorTilePlacement.place(home, in: phone, avoiding: plan.keepOut)
        #expect(clear(placed, of: header))
        #expect(clear(placed, of: standardEmpty))
    }

    @Test("Below the Huge band the tile never hides over an empty deck, but keeps clear when it can")
    func smallerBandsStay() throws {
        for band in [TypeBand.standard, .large] {
            let crowded = MirrorTilePlacement.surfacePlan(bounds: phone, deckHeader: header, deckEmptyState: ax5Empty, band: band)
            #expect(!crowded.stepsAsideWhenCrowded)
            #expect(MirrorTilePlacement.isShown(crowded, minimumWidth: 200, aspect: 0.625, in: phone))
            #expect(crowded.keepOut.contains(ax5Empty))
        }
        let roomy = MirrorTilePlacement.surfacePlan(bounds: phone, deckHeader: header, deckEmptyState: standardEmpty)
        let anchor = try #require(roomy.anchor)
        let home = MirrorTilePlacement.home(width: 200, height: 125, anchor: anchor)
        let placed = MirrorTilePlacement.place(home, in: phone, avoiding: roomy.keepOut)
        #expect(clear(placed, of: standardEmpty))
    }

    @Test("Only the Huge band steps aside")
    func bandRule() {
        #expect(!MirrorTilePlacement.emptyStateStepsAside(band: .standard))
        #expect(!MirrorTilePlacement.emptyStateStepsAside(band: .large))
        #expect(MirrorTilePlacement.emptyStateStepsAside(band: .huge))
    }

    @Test("Without an empty state nothing changes: the Huge band alone doesn't step aside")
    func noEmptyState() {
        let plan = MirrorTilePlacement.surfacePlan(bounds: phone, deckHeader: header, band: .huge)
        #expect(!plan.stepsAsideWhenCrowded)
        #expect(plan.keepOut == [header])
    }
}
