//
//  RightColumnTests.swift
//  PixelHandCoreTests
//
//  OR-06: the right column collapses to an edge handle, remembers that per
//  arrangement, and switches Deck | Ask; Ask (⌘K) opens in place wherever
//  the column exists and in its sheet elsewhere.
//

import Testing
@testable import PixelHandCore

@Suite("Right column")
struct RightColumnTests {
    private let landscape = CanvasPlan(width: 1180, height: 820)
    private let portrait = CanvasPlan(width: 820, height: 1180)
    private let phoneLandscape = CanvasPlan(width: 756, height: 381)

    @Test("Arrangement keys: form plus preset where the form has presets")
    func arrangementKeys() {
        #expect(ArrangementPreset(plan: landscape, preset: .split).key == "columns|split")
        #expect(ArrangementPreset(plan: landscape, preset: .pointer).key == "columns|pointer")
        #expect(ArrangementPreset(plan: portrait, preset: .screen).key == "sideBySide|screen")
        #expect(ArrangementPreset(plan: landscape, preset: nil).key == "columns|split")
        // No presets on the rail or compact forms: one key per form.
        #expect(ArrangementPreset(plan: phoneLandscape, preset: .screen).key == "rail")
        #expect(ArrangementPreset(plan: CanvasPlan(width: 402, height: 874), preset: .pointer).key == "single")
    }

    @Test("Which arrangements have the column, and which collapse it")
    func columnPerForm() {
        let wide = RightColumnPlan(plan: landscape, preset: .split, collapsed: false)
        #expect(wide.exists && wide.canCollapse && wide.offersAsk)
        #expect(wide.width == 336)
        #expect(wide.askRoute == .column)

        // iPad portrait: Split and Pointer have the column; Screen has none.
        #expect(RightColumnPlan(plan: portrait, preset: .split, collapsed: false).width == 300)
        #expect(RightColumnPlan(plan: portrait, preset: .pointer, collapsed: false).canCollapse)
        let screen = RightColumnPlan(plan: portrait, preset: .screen, collapsed: true)
        #expect(!screen.exists && !screen.isCollapsed)
        #expect(screen.width == 0)
        #expect(screen.askRoute == .sheet)

        // iPhone landscape: the column holds the header, so it never collapses.
        let rail = RightColumnPlan(plan: phoneLandscape, preset: nil, collapsed: true)
        #expect(rail.exists && rail.offersAsk)
        #expect(!rail.canCollapse && !rail.isCollapsed)
        #expect(rail.width == 264)
        // iPhone SE landscape: no column, the deck is a tab and Ask a sheet.
        #expect(RightColumnPlan(plan: CanvasPlan(width: 667, height: 375), preset: nil, collapsed: false).askRoute == .sheet)

        // Compact, ½ Split View and Stage Manager down to iPhone width keep today's sheet.
        for (w, h) in [(402.0, 874.0), (375, 820), (590, 820), (320, 1180)] {
            let plan = RightColumnPlan(plan: CanvasPlan(width: w, height: h), preset: .split, collapsed: true)
            #expect(!plan.exists, "\(w) × \(h)")
            #expect(plan.askRoute == .sheet, "\(w) × \(h)")
            #expect(plan.width == 0, "\(w) × \(h)")
        }
    }

    @Test("Collapsed: the slim edge handle")
    func collapsedWidth() {
        let wide = RightColumnPlan(plan: landscape, preset: .split, collapsed: true)
        #expect(wide.isCollapsed)
        #expect(wide.width == RightColumnPlan.handleWidth)
        #expect(wide.expandedWidth == 336)
        // Ask still opens in the column (it expands first).
        #expect(wide.askRoute == .column)
        #expect(RightColumnPlan.handleHitWidth >= 44)
        #expect(RightColumnPlan(plan: portrait, preset: .pointer, collapsed: true).width == RightColumnPlan.handleWidth)
    }

    @Test("Memory per arrangement survives JSON and opening Ask expands")
    func memory() {
        let landSplit = ArrangementPreset(plan: landscape, preset: .split)
        let landPointer = ArrangementPreset(plan: landscape, preset: .pointer)
        let portSplit = ArrangementPreset(plan: portrait, preset: .split)

        var memory = RightColumnMemory()
        #expect(!memory.isCollapsed(landSplit))
        memory.set(true, for: landSplit)
        memory.set(true, for: portSplit)
        #expect(memory.isCollapsed(landSplit))
        #expect(!memory.isCollapsed(landPointer))
        #expect(memory.json == #"["columns|split","sideBySide|split"]"#)

        let restored = RightColumnMemory(json: memory.json)
        #expect(restored == memory)

        var opened = restored
        opened.expandForAsk(RightColumnPlan(plan: landscape, preset: .split, collapsed: true))
        #expect(!opened.isCollapsed(landSplit))
        #expect(opened.isCollapsed(portSplit))

        memory.set(false, for: portSplit)
        #expect(memory.json == #"["columns|split"]"#)
    }

    @Test("Memory: damaged data reads as nothing collapsed, size is capped")
    func memoryHostile() {
        #expect(RightColumnMemory(json: "").collapsed.isEmpty)
        #expect(RightColumnMemory(json: "{}").collapsed.isEmpty)
        #expect(RightColumnMemory(json: #"{"a":1}"#).collapsed.isEmpty)

        // Setting the same arrangement twice stores it once.
        var memory = RightColumnMemory()
        for _ in 0..<3 {
            memory.set(true, for: ArrangementPreset(form: .columns, preset: nil))
            memory.set(true, for: ArrangementPreset(form: .rail, preset: nil))
        }
        #expect(memory.collapsed.count == 2)

        var many = RightColumnMemory(collapsed: Set((0..<RightColumnMemory.maximumEntries).map { "k\($0)" }))
        many.set(true, for: ArrangementPreset(form: .columns, preset: .screen))
        #expect(many.collapsed.count == RightColumnMemory.maximumEntries)
        #expect(!many.isCollapsed(ArrangementPreset(form: .columns, preset: .screen)))

        let long = "[" + (0..<50).map { "\"k\($0)\"" }.joined(separator: ",") + "]"
        #expect(RightColumnMemory(json: long).collapsed.count == RightColumnMemory.maximumEntries)
    }

    @Test("Mode titles for the Deck | Ask switch")
    func modes() {
        #expect(RightColumnMode.allCases.map(\.title) == ["Deck", "Ask"])
        #expect(RightColumnMode(rawValue: "ask") == .ask)
        #expect(RightColumnMode(rawValue: "nope") == nil)
    }
}
