//
//  TypePanelLayoutTests.swift
//  PixelHandCoreTests
//
//  The Type panel uses all its space (owner testing, build 26, OT-11):
//  every block sizes to the panel's width and height, with no dead areas.
//

import Foundation
import Testing
@testable import PixelHandCore

/// Checks that a layout's blocks tile its body: bands stacked from the top
/// with one gap between them, and in each band the blocks running from
/// the leading edge to the trailing edge with one gap between them.
private func expectTiles(_ layout: TypePanelLayout, _ note: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let inner = layout.panelWidth - 2 * TypePanelLayout.padding
    let gap = TypePanelLayout.blockGap
    let rects = layout.blocks.values.map(\.rect)
    // Group the blocks by their top edge (a band).
    let tops = Set(rects.map { ($0.minY * 100).rounded() / 100 }).sorted()
    var y = 0.0
    for top in tops {
        #expect(abs(top - y) < 0.01, "band starts after one gap: \(note)", sourceLocation: sourceLocation)
        let band = rects.filter { abs($0.minY - top) < 0.01 }.sorted { $0.minX < $1.minX }
        var x = 0.0
        for rect in band {
            #expect(abs(rect.minX - x) < 0.01, "no hole before a block: \(note)", sourceLocation: sourceLocation)
            #expect(rect.width > 0 && rect.height > 0, "\(note)", sourceLocation: sourceLocation)
            x = rect.maxX + gap
        }
        #expect(abs((band.last?.maxX ?? 0) - inner) < 0.01, "band fills the width: \(note)", sourceLocation: sourceLocation)
        let heights = Set(band.map { ($0.height * 100).rounded() })
        #expect(heights.count == 1, "blocks in a band share its height: \(note)", sourceLocation: sourceLocation)
        y = (band.map(\.maxY).max() ?? 0) + gap
    }
    // The panel wraps the body exactly.
    let chrome = 2 * TypePanelLayout.padding + Double(layout.headerRows) * (TypePanelLayout.headerHeight + TypePanelLayout.headerSpacing)
    #expect(abs(layout.panelHeight - (chrome + layout.bodySize.height)) <= 0.5, "\(note)", sourceLocation: sourceLocation)
}

@Suite("Type panel layout fills the panel (OT-11)")
struct TypePanelLayoutTests {
    static let widths: [Double] = Array(stride(from: 304.0, through: 760, by: 8))

    @Test("A hardware keyboard gives the keys-only body, without the action column")
    func hardware() {
        let hardware = TypePanelLayout(width: 1180, height: 820, keyboard: .hardware, panelWidth: 720)
        #expect(hardware.body == .keysOnly)
        #expect(!hardware.shows(.actions))
        #expect(hardware.actionCells.isEmpty)
        #expect(TypePanelLayout(width: 1180, height: 820, keyboard: .software, keyboardOverlap: 400).body == .full)
    }

    @Test("Every width, height, mode and numpad state tiles the body with no dead areas")
    func noDeadAreas() {
        for width in Self.widths {
            for numpad in [false, true] {
                for mode in TypeMode.allCases {
                    for keyboard in [KeyboardKind.none, .hardware] {
                        let probe = TypePanelLayout(width: 1180, height: 820, keyboard: keyboard, panelWidth: width, showsNumpad: numpad, mode: mode)
                        let range = probe.heightRange
                        for height in stride(from: range.lowerBound, through: range.upperBound, by: 6) {
                            let layout = TypePanelLayout(width: 1180, height: 820, keyboard: keyboard, panelWidth: width, panelHeight: height, showsNumpad: numpad, mode: mode)
                            let note = "w\(width) h\(height) \(mode) numpad \(numpad) \(keyboard)"
                            expectTiles(layout, note)
                            #expect(abs(layout.panelHeight - height) <= 1, "the body fills the height: \(note)")
                        }
                    }
                }
            }
        }
    }

    @Test("Without a height the panel takes its shortest: the compact default")
    func defaultHeight() {
        let layout = TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: 720)
        #expect(layout.arrangement == .oneBlock)
        #expect(layout.panelHeight == layout.heightRange.lowerBound)
        // Padding, one header row and two 44 pt rows.
        #expect(layout.panelHeight == 24 + 52 + 88)
    }

    @Test("Field and arrows share their band's full height; a tall field shows two lines")
    func fieldAndArrows() {
        for height in [180.0, 240, 300, 360] {
            let layout = TypePanelLayout(width: 820, height: 1180, keyboard: .none, panelWidth: 600, panelHeight: height)
            let field = try! #require(layout.grid(.field))
            let arrows = try! #require(layout.grid(.arrows))
            #expect(field.rect.height == arrows.rect.height)
            #expect(field.rect.minY == arrows.rect.minY)
        }
        let tall = TypePanelLayout(width: 820, height: 1180, keyboard: .none, panelWidth: 600, panelHeight: 360)
        #expect(tall.fieldLines >= 2)
        #expect(TypePanelLayout.lines(forFieldHeight: 44) == 1)
        #expect(TypePanelLayout.lines(forFieldHeight: 88) == 3)
    }

    @Test("The arrows grow and shrink with the panel, from 44 to 72 pt rows")
    func arrowsScale() {
        let range = TypePanelLayout(width: 820, height: 1180, keyboard: .none, panelWidth: 600).heightRange
        var last = 0.0
        for height in stride(from: range.lowerBound, through: range.upperBound, by: 20) {
            let layout = TypePanelLayout(width: 820, height: 1180, keyboard: .none, panelWidth: 600, panelHeight: height)
            let arrows = try! #require(layout.grid(.arrows))
            #expect(arrows.cellHeight >= 44 - 0.001)
            #expect(arrows.cellHeight <= TypePanelLayout.maximumRowHeight + 0.001)
            #expect(arrows.cellWidth >= 44 - 0.001)
            if layout.arrowShape == .invertedT, last > 0 { #expect(arrows.cellHeight >= last - 0.001) }
            if layout.arrowShape == .invertedT { last = arrows.cellHeight }
        }
        let biggest = TypePanelLayout(width: 820, height: 1180, keyboard: .none, panelWidth: 600, panelHeight: range.upperBound)
        #expect(biggest.grid(.arrows)?.cellHeight == TypePanelLayout.maximumRowHeight)
        // Past the tallest the panel stops growing.
        #expect(TypePanelLayout(width: 820, height: 1180, keyboard: .none, panelWidth: 600, panelHeight: 2000).panelHeight == range.upperBound)
    }

    @Test("Keys mode: the modifier and special-key rows span the panel's width and scale with it")
    func keysSpanWidth() {
        for width in [360.0, 500, 600, 660] {
            let layout = TypePanelLayout(width: 820, height: 1180, keyboard: .none, panelWidth: width, panelHeight: 260)
            #expect(layout.arrangement == .stacked)
            let keys = try! #require(layout.grid(.keys))
            #expect(keys.rect.minX == 0)
            #expect(abs(keys.rect.width - (width - 24)) < 0.01)
            #expect(abs(keys.cellWidth - (width - 24) / 7) < 0.01)
            #expect(keys.cellHeight >= 44)
        }
        // In one block the keys end at the trailing edge.
        let wide = TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: 760)
        let keys = try! #require(wide.grid(.keys))
        #expect(wide.arrangement == .oneBlock)
        #expect(abs(keys.rect.maxX - (760 - 24)) < 0.01)
    }

    @Test("Numpad mode shows only the arrows and the numpad, filling the panel together")
    func numpadOnly() {
        for width in [360.0, 400, 560, 760] {
            let layout = TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: width, showsNumpad: true)
            #expect(layout.arrangement == .numpad)
            #expect(Set(layout.blocks.keys) == [.arrows, .numpad], "w\(width)")
            #expect(layout.actionCells.isEmpty)
            let pad = try! #require(layout.grid(.numpad))
            #expect(pad.cellWidth >= 44 - 0.001 && pad.cellHeight >= 44 - 0.001)
        }
        // Wide enough: side by side, the arrows as tall as the numpad.
        let beside = TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: 560, showsNumpad: true)
        #expect(beside.grid(.arrows)?.rect.height == beside.grid(.numpad)?.rect.height)
        #expect(beside.arrowShape == .invertedT)
        // Narrow: the arrows in one row across, the numpad under them.
        let narrow = TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: 360, showsNumpad: true)
        #expect(narrow.arrowShape == .row)
        #expect(narrow.grid(.arrows)?.rect.width == narrow.grid(.numpad)?.rect.width)
        // Compose keeps the draft the numpad writes into, with +⏎ and Send.
        let compose = TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: 560, showsNumpad: true, mode: .compose)
        #expect(Set(compose.blocks.keys) == [.field, .actions, .arrows, .numpad])
        #expect(compose.actionCells.map(\.action) == [.sendReturn, .send])
    }

    @Test("At its shortest the arrows go to one row; thresholds per width")
    func minimal() {
        // 600 wide: room for the field beside ← ↑ ↓ → and two actions.
        let short = TypePanelLayout(width: 820, height: 1180, keyboard: .none, panelWidth: 600, panelHeight: 0)
        #expect(short.arrangement == .stacked)
        #expect(short.arrowShape == .row)
        #expect(short.grid(.arrows)?.rows == 1)
        #expect(short.actionCells.map(\.row) == [0, 0])
        #expect(short.grid(.field)!.rect.width >= TypePanelLayout.fieldMinimumWidth)
        // Body: one row, a gap, two key rows.
        #expect(short.bodySize.height == 3 * 44 + 8)
        // From four rows of 44 the inverted T comes back.
        let t = TypePanelLayout(width: 820, height: 1180, keyboard: .none, panelWidth: 600, panelHeight: 24 + 52 + 4 * 44 + 8)
        #expect(t.arrowShape == .invertedT)
        // Under 448 the field wouldn't keep 144 pt beside a row of arrows:
        // the shortest keeps the T.
        let narrow = TypePanelLayout(width: 820, height: 1180, keyboard: .none, panelWidth: 440, panelHeight: 0)
        #expect(narrow.arrowShape == .invertedT)
        let justWide = TypePanelLayout(width: 820, height: 1180, keyboard: .none, panelWidth: 448, panelHeight: 0)
        #expect(justWide.arrowShape == .row)
        // Wide panels: the shortest is one block, two rows tall.
        let wide = TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: 700, panelHeight: 0)
        #expect(wide.arrangement == .oneBlock)
        #expect(wide.bodySize.height == 88)
        // Compose needs a little more width for one block (+⏎ and Send).
        #expect(TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: 676).arrangement == .oneBlock)
        #expect(TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: 668).arrangement == .stacked)
    }

    @Test("Live has Accept (Tab) and Paste beside the field; Compose has +⏎ and Send")
    func actions() {
        let live = TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: 720)
        #expect(live.actionCells.map(\.action) == [.accept, .paste])
        #expect(live.actionCells.map(\.row) == [0, 1])
        let compose = TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: 720, mode: .compose)
        #expect(compose.actionCells.map(\.action) == [.sendReturn, .send])
    }

    @Test("A panel taller than the free room shrinks to it, never under its shortest")
    func room() {
        let layout = TypePanelLayout(width: 1180, height: 820, keyboard: .software, keyboardOverlap: 400, panelWidth: 600, panelHeight: 400, roomHeight: 250)
        #expect(layout.panelHeight <= 250)
        let tiny = TypePanelLayout(width: 1180, height: 820, keyboard: .software, keyboardOverlap: 400, panelWidth: 600, panelHeight: 400, roomHeight: 50)
        #expect(tiny.panelHeight == tiny.heightRange.lowerBound)
    }

    @Test("The target shows once: the header carries the app, the field a neutral placeholder")
    func targetOnce() {
        #expect(!TypeMode.live.placeholder.contains("Typing into"))
        #expect(!TypeMode.compose.placeholder.contains("Typing into"))
        #expect(TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: 720).showsAppName)
        #expect(TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: 720).headerRows == 1)
        // Narrow: a second header row carries the mode switch and the name.
        let narrow = TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: 400)
        #expect(narrow.headerRows == 2)
        #expect(narrow.showsAppName)
        #expect(TypePanelLayout.oneRowHeaderMinimumWidth == 456)
        // A mid width, one row: the icon alone.
        let mid = TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: 500)
        #expect(mid.headerRows == 1)
        #expect(!mid.showsAppName)
    }

    @Test("Short room above the keyboard: no header; the dismissed keyboard brings it back")
    func shortRoom() {
        let landscape = TypePanelLayout(width: 874, height: 402, keyboard: .software, keyboardOverlap: 200)
        #expect(!landscape.showsHeader)
        #expect(landscape.headerRows == 0)
        #expect(TypePanelLayout(width: 874, height: 402, keyboard: .none).showsHeader)
    }

    @Test("A 320 pt Slide Over window: cells shrink only there, and everything fits")
    func slideOver() {
        let layout = TypePanelLayout(width: 320, height: 800, keyboard: .none, panelWidth: 304)
        let keys = try! #require(layout.grid(.keys))
        #expect(keys.cellWidth >= 32 && keys.cellWidth < 44)
        expectTiles(layout, "slide over")
        for width in stride(from: 360.0, through: 760, by: 20) {
            let other = TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: width)
            #expect((other.grid(.keys)?.cellHeight ?? 0) >= 44)
            #expect((other.grid(.arrows)?.cellWidth ?? 0) >= 44 - 0.001)
        }
    }

    @Test("Every test window gives a layout that fits it")
    func everyWindowFits() {
        for (name, width, height) in ShellKeyboardTests.windows {
            for numpad in [false, true] {
                let layout = TypePanelLayout(width: width, height: height, keyboard: .none, showsNumpad: numpad)
                #expect(layout.panelWidth <= width, "\(name)")
                expectTiles(layout, name)
            }
        }
    }

    @Test("The panel sits on the keyboard, or above the dock when nothing covers it")
    func bottomPadding() {
        #expect(TypePanelLayout.bottomPadding(containerMaxY: 800, keyboardMinY: 420, dockMinY: 740) == 388)
        #expect(TypePanelLayout.bottomPadding(containerMaxY: 800, keyboardMinY: nil, dockMinY: 740) == 68)
        #expect(TypePanelLayout.bottomPadding(containerMaxY: 800, keyboardMinY: nil, dockMinY: nil) == 8)
    }

    @Test("The arrows' one-row shape is ← ↑ ↓ →")
    func rowShape() {
        #expect(ArrowCluster.cells(for: .row).map(\.key) == [.remote(.left), .remote(.up), .remote(.down), .remote(.right)])
        #expect(ArrowCluster.cells(for: .row).map(\.column) == [0, 1, 2, 3])
        #expect(ArrowCluster.cells(for: .invertedT) == ArrowCluster.cells)
    }
}

@Suite("The iPadOS keyboard bar lifts the dock (OT-11)")
struct KeyboardBarLiftTests {
    @Test("The slim bar of a hardware or minimised keyboard lifts the dock; a full keyboard doesn't")
    func lift() {
        #expect(KeyboardKind.barLift(overlap: 0) == 0)
        #expect(KeyboardKind.barLift(overlap: 55) == 55)
        #expect(KeyboardKind.barLift(overlap: 69.5) == 70)
        #expect(KeyboardKind.barLift(overlap: 400) == 0)
        #expect(KeyboardKind.barLift(overlap: .nan) == 0)
        // The dock already clears the home indicator: only the rest lifts.
        #expect(KeyboardKind.barLift(overlap: 69, bottomInset: 20) == 49)
        #expect(KeyboardKind.barLift(overlap: 15, bottomInset: 20) == 0)
    }
}

@Suite("Type panel resizes in both directions (OT-11)")
struct TypePanelHeightResizeTests {
    let geometry = TypePanelGeometry(
        container: PanelRect(x: 0, y: 24, width: 1180, height: 796),
        windowWidth: 1180,
        windowHeight: 820,
        dockMinY: 740
    )

    func heights(_ width: Double) -> ClosedRange<Double> {
        TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: width).heightRange
    }

    @Test("Dragging a corner down makes the panel taller, inside the layout's range and the room")
    func taller() {
        let start = PanelRect(x: 200, y: 300, width: 600, height: 200)
        let taller = geometry.resized(start, edge: .trailing, translation: 0, 60, heights: heights)
        #expect(taller.height == 260)
        #expect(taller.minY == 300)
        let tallest = geometry.resized(start, edge: .trailing, translation: 0, 2000, heights: heights)
        #expect(tallest.height == min(heights(600).upperBound, geometry.room.maxY - 300))
        let shortest = geometry.resized(start, edge: .leading, translation: 0, -2000, heights: heights)
        #expect(shortest.height == heights(600).lowerBound)
    }

    @Test("A resize stores the height; a drag keeps it; junk heights are dropped")
    func stored() {
        let frame = PanelRect(x: 200, y: 300, width: 600, height: 250)
        let place = geometry.placement(resizedTo: frame, keeping: .initial, keepsHeight: true)
        #expect(place.height == 250)
        #expect(place.width == 600)
        let moved = geometry.placement(droppedAt: 10, 10, size: (600, 250), keeping: place)
        #expect(moved.height == 250)
        #expect(TypePanelPlacement.restored(place.stored) == place)
        let junk = Data(#"{"x":0.5,"y":1,"width":600,"height":-3}"#.utf8)
        #expect(TypePanelPlacement.restored(junk)?.height == nil)
        #expect(TypePanelPlacement.restored(junk)?.width == 600)
        // Build 25's stored places (no height) still read.
        let old = Data(#"{"x":0.25,"y":1,"width":500}"#.utf8)
        #expect(TypePanelPlacement.restored(old) == TypePanelPlacement(x: 0.25, y: 1, width: 500))
    }
}

@Suite("The loupe is attached to the Type panel (OT-12)")
struct TypePanelLoupePlacementTests {
    let geometry = TypePanelGeometry(
        container: PanelRect(x: 0, y: 24, width: 1180, height: 796),
        windowWidth: 1180,
        windowHeight: 820,
        keyboardMinY: 420
    )

    @Test("Above the panel when there's room, as wide as it")
    func above() {
        let panel = PanelRect(x: 230, y: 250, width: 720, height: 160)
        let loupe = try! #require(geometry.loupeFrame(panel: panel))
        #expect(loupe.width == 720 && loupe.minX == 230)
        #expect(loupe.maxY == panel.minY - 8)
        #expect(loupe.height == 200)
        #expect(TypePanelGeometry.loupeHeight(panelWidth: 360) == 108)
        #expect(TypePanelGeometry.loupeHeight(panelWidth: 200) == 96)
    }

    @Test("Below a panel parked at the top; squeezed, never under 96 pt, when short")
    func belowAndSqueezed() {
        let top = PanelRect(x: 230, y: 32, width: 720, height: 160)
        let below = try! #require(geometry.loupeFrame(panel: top))
        #expect(below.minY == top.maxY + 8)
        let tall = PanelRect(x: 230, y: 120, width: 720, height: 280)
        let squeezed = try! #require(geometry.loupeFrame(panel: tall))
        #expect(squeezed.height >= TypePanelGeometry.loupeMinimumHeight)
        #expect(squeezed.minY >= geometry.room.minY)
    }
}
