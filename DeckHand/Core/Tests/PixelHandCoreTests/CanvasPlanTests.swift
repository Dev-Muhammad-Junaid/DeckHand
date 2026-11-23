//
//  CanvasPlanTests.swift
//  PixelHandCoreTests
//
//  UX-007 arrangements: the form per window size, column widths, the
//  sidebar's collapse point, pane splits and remembered presets
//  (`Product/Design/03-Layout-Strategy.md` Option A, `07-Polish-Spec.md` §1).
//

import Testing
@testable import PixelHandCore

@Suite("Canvas plan")
struct CanvasPlanTests {
    @Test("The QA sizes get the form the layout strategy names")
    func formsAtQASizes() {
        // iPhone portrait, SE, Duo cover, ⅓ Split View, Slide Over.
        for (w, h) in [(402.0, 874.0), (375, 667), (466, 678), (320, 1180), (375, 820)] {
            #expect(CanvasPlan(width: w, height: h).form == .single, "\(w) × \(h)")
        }
        // iPhone landscape, inside the safe area and edge to edge.
        #expect(CanvasPlan(width: 756, height: 381).form == .rail)
        #expect(CanvasPlan(width: 874, height: 402).form == .rail)
        // ½ Split View (and Duo laptop) stack; iPad portrait sits side by side.
        #expect(CanvasPlan(width: 590, height: 820).form == .stacked)
        #expect(CanvasPlan(width: 669, height: 951).form == .stacked)
        #expect(CanvasPlan(width: 820, height: 1180).form == .sideBySide)
        #expect(CanvasPlan(width: 699, height: 1000).form == .stacked)
        #expect(CanvasPlan(width: 700, height: 1000).form == .sideBySide)
        // iPad landscape, large Stage Manager.
        #expect(CanvasPlan(width: 1180, height: 820).form == .columns)
        #expect(CanvasPlan(width: 900, height: 700).form == .columns)
    }

    @Test("iPhone landscape: a deck column of 264–320 pt while the pad keeps 300 pt")
    func railDeckColumn() {
        let pro = CanvasPlan(width: 756, height: 381)
        #expect(pro.deckColumnWidth == 264)
        #expect(pro.hasDeckColumn)
        #expect(pro.stripInDeckColumn)
        #expect(pro.foldsDockIntoStrip)
        #expect(!pro.tabSurfacesIncludeDeck)
        #expect(pro.showsTabBar)

        let edge = CanvasPlan(width: 874, height: 402)
        #expect(edge.deckColumnWidth == 304)

        let huge = CanvasPlan(width: 1000, height: 420)
        #expect(huge.form == .rail)
        #expect(huge.deckColumnWidth == 320)

        // iPhone SE landscape: the pad would drop under 300, so the deck is a tab.
        let se = CanvasPlan(width: 667, height: 375)
        #expect(se.form == .rail)
        #expect(se.deckColumnWidth == 0)
        #expect(se.tabSurfacesIncludeDeck)
        #expect(!se.stripInDeckColumn)
        #expect(se.foldsDockIntoStrip)
    }

    @Test("Rail pad width never drops under the minimum when a deck column shows")
    func railPadMinimum() {
        for width in stride(from: 500.0, through: 1000, by: 1) {
            let plan = CanvasPlan(width: width, height: 400)
            guard plan.hasDeckColumn else { continue }
            let pad = width - CanvasPlan.railWidth - 8 - 2 * plan.metrics.gutter - plan.metrics.margin - plan.deckColumnWidth
            #expect(pad >= CanvasPlan.minimumPadWidth, "\(width)")
            #expect(plan.deckColumnWidth == plan.deckColumnWidth.rounded())
        }
    }

    @Test("iPad: presets replace the tab bar on side-by-side and columns")
    func presetsOnIPad() {
        let portrait = CanvasPlan(width: 820, height: 1180)
        #expect(portrait.usesPresets)
        #expect(!portrait.showsTabBar)
        #expect(portrait.deckColumnWidth == 300)
        #expect(!portrait.asksInToolbar)
        #expect(!portrait.stripInDeckColumn)

        let split = CanvasPlan(width: 590, height: 820)
        #expect(!split.usesPresets)
        #expect(split.showsTabBar)
        #expect(split.tabSurfacesIncludeDeck)
        #expect(split.deckColumnKeys == 5)

        let land = CanvasPlan(width: 1180, height: 820)
        #expect(land.usesPresets)
        #expect(land.asksInToolbar)
        #expect(land.floatsDock)
        #expect(land.stripInDeckColumn)
        #expect(land.deckColumnWidth == 336)
        #expect(land.deckColumnKeys == 3)
    }

    @Test("Wide: the Macs sidebar shows until the centre would drop under 480 pt")
    func sidebarCollapse() {
        let land = CanvasPlan(width: 1180, height: 820)
        #expect(land.showsSidebar)
        #expect(land.centreWidth == 556)  // board: 1180 − 232 − 16 − 16 − 336 − 24; without the sidebar, 24 leading

        #expect(CanvasPlan(width: 1104, height: 820).showsSidebar)
        let narrow = CanvasPlan(width: 1103, height: 820)
        #expect(!narrow.canShowSidebar)
        #expect(!narrow.showsSidebar)
        #expect(narrow.centreWidth == 687)

        let collapsed = CanvasPlan(width: 1366, height: 1024, sidebarCollapsed: true)
        #expect(collapsed.canShowSidebar)
        #expect(!collapsed.showsSidebar)
        #expect(collapsed.centreWidth == 950)

        // Never on smaller forms, collapsed or not.
        #expect(!CanvasPlan(width: 820, height: 1180).canShowSidebar)
        #expect(!CanvasPlan(width: 874, height: 402).canShowSidebar)
    }

    @Test("Screen over pad: picture height by default, clamped, nil when both can't fit")
    func paneSplit() {
        // iPad landscape centre: 556 wide, 16:10 picture.
        #expect(PaneSplit.screenHeight(total: 632, width: 556, aspect: 1.6, fraction: nil) == 347)
        // A tall picture is capped at 62 %.
        #expect(PaneSplit.screenHeight(total: 800, width: 800, aspect: 1.0, fraction: nil) == 496)
        // A drag is honoured but leaves the pad its minimum.
        #expect(PaneSplit.screenHeight(total: 700, width: 556, aspect: 1.6, fraction: 0.9) == 448)
        #expect(PaneSplit.screenHeight(total: 700, width: 556, aspect: 1.6, fraction: 0.05) == 200)
        // Too short for both.
        #expect(PaneSplit.screenHeight(total: 451, width: 556, aspect: 1.6, fraction: nil) == nil)
        #expect(PaneSplit.screenHeight(total: 452, width: 556, aspect: 1.6, fraction: nil) == 200)
        // Fraction round trip, clamped.
        #expect(PaneSplit.fraction(screenHeight: 350, total: 700) == 0.5)
        #expect(PaneSplit.fraction(screenHeight: 700, total: 700) == 0.9)
        #expect(PaneSplit.fraction(screenHeight: 10, total: 0) == PaneSplit.defaultScreenShare)
    }

    @Test("Stacked deck panel: one row by default, never squeezing the pad")
    func deckPanel() {
        // ½ Split View: 590 wide → 5 keys of 100 pt.
        let key = CanvasPlan(width: 590, height: 820).metrics.deckGrid.keySize
        #expect(key == 100)
        let oneRow = DeckPanelSplit.panelHeight(rows: 1, keySize: key)
        #expect(oneRow == 152)
        #expect(DeckPanelSplit.panelHeight(rows: 2, keySize: key) == 264)
        #expect(DeckPanelSplit.height(total: 480, requested: 0, keySize: key) == 152)
        #expect(DeckPanelSplit.height(total: 480, requested: 1000, keySize: key) == 228)
        #expect(DeckPanelSplit.height(total: 403, requested: 0, keySize: key) == nil)
        #expect(DeckPanelSplit.height(total: 404, requested: 0, keySize: key) == 152)
    }

    @Test("Presets: titles, panes, and memory per Mac and form")
    func presetMemory() {
        #expect(LayoutPreset.allCases.map(\.title) == ["Split", "Screen", "Pointer"])
        #expect(LayoutPreset.split.showsDockedScreen && LayoutPreset.split.showsPointer)
        #expect(LayoutPreset.screen.showsDockedScreen && !LayoutPreset.screen.showsPointer)
        #expect(!LayoutPreset.pointer.showsDockedScreen && LayoutPreset.pointer.showsPointer)

        let land = CanvasPlan(width: 1180, height: 820)
        let port = CanvasPlan(width: 820, height: 1180)
        #expect(land.presetKey(macName: "Studio") == "Studio|columns")
        #expect(port.presetKey(macName: "Studio") == "Studio|sideBySide")

        var memory = LayoutPresetMemory()
        #expect(memory.preset(for: land.presetKey(macName: "Studio")) == .split)
        memory.set(.screen, for: land.presetKey(macName: "Studio"))
        memory.set(.pointer, for: port.presetKey(macName: "Studio"))
        #expect(memory.preset(for: land.presetKey(macName: "Studio")) == .screen)
        #expect(memory.preset(for: port.presetKey(macName: "Studio")) == .pointer)
        #expect(memory.preset(for: land.presetKey(macName: "MacBook Air")) == .split)

        let restored = LayoutPresetMemory(json: memory.json)
        #expect(restored == memory)
        #expect(memory.json == #"{"Studio|columns":"screen","Studio|sideBySide":"pointer"}"#)
    }

    @Test("Preset memory: damaged data reads as empty, unknown values drop, size is capped")
    func presetMemoryHostile() {
        #expect(LayoutPresetMemory(json: "").presets.isEmpty)
        #expect(LayoutPresetMemory(json: "[1,2]").presets.isEmpty)
        #expect(LayoutPresetMemory(json: #"{"a":"split","b":"modules"}"#).presets == ["a": .split])

        var memory = LayoutPresetMemory()
        for i in 0..<40 { memory.set(.screen, for: "Mac \(i)|columns") }
        #expect(memory.presets.count == LayoutPresetMemory.maximumEntries)
        #expect(memory.preset(for: "Mac 39|columns") == .screen)
    }

    @Test("Layout glyphs: 9 × 9, lit, unique names, outside the spec's 40")
    func layoutGlyphs() {
        for glyph in PixelGlyphs.layout {
            #expect(glyph.rows.count == 9, "\(glyph.name)")
            #expect(!glyph.litPoints.isEmpty, "\(glyph.name)")
            #expect(PixelGlyphs.named(glyph.name) == nil, "\(glyph.name)")
        }
        #expect(PixelGlyphs.layoutSplit.accent != nil)
        #expect(PixelGlyphs.all.count == 40)
    }
}
