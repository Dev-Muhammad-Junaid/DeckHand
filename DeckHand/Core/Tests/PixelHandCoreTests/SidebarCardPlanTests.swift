//
//  SidebarCardPlanTests.swift
//  PixelHandCoreTests
//
//  The Macs sidebar's compact card at AX3 (build 24, VQ-099).
//

import Foundation
import PixelHandCore
import Testing

@Suite struct SidebarCardPlanTests {
    @Test("The Huge band stacks the card and uses whole words on two lines")
    func huge() {
        #expect(SidebarCardPlan.arrangement(band: .huge) == .stacked)
        #expect(SidebarCardPlan.nameLines(band: .huge) == 2)
        #expect(SidebarCardPlan.statusLines(band: .huge) == 2)
        #expect(SidebarCardPlan.usesWholeWords(band: .huge))
    }

    @Test("Standard keeps the row with one line each")
    func standard() {
        #expect(SidebarCardPlan.arrangement(band: .standard) == .row)
        #expect(SidebarCardPlan.nameLines(band: .standard) == 1)
        #expect(SidebarCardPlan.statusLines(band: .standard) == 1)
        #expect(!SidebarCardPlan.usesWholeWords(band: .standard))
    }

    @Test("Large keeps the row but never cuts a word")
    func large() {
        #expect(SidebarCardPlan.arrangement(band: .large) == .row)
        #expect(SidebarCardPlan.usesWholeWords(band: .large))
    }

    @Test("Build 24: stacking gives the text half again the room it had beside the tile")
    func stackedRoom() {
        let width = LayoutMetrics.sidebarWidth
        let margin = LayoutMetrics.sidebarLeadingMargin
        let row = SidebarCardPlan.rowTextWidth(sidebarWidth: width, leadingMargin: margin, cardPadding: 6, tileWidth: 44, spacing: 8)
        let stacked = SidebarCardPlan.stackedTextWidth(sidebarWidth: width, leadingMargin: margin, cardPadding: 6)
        #expect(row == 96)
        #expect(stacked == 148)
        #expect(stacked >= row * 1.5)
    }
}
