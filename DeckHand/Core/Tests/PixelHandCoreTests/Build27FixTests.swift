//
//  Build27FixTests.swift
//  PixelHandCoreTests
//
//  The rules behind the build 26 and 27 fix round
//  (`Integration/LANE-build27-fixes.md`): the Type panel grows on the
//  keyboard and its arrows widen with it, the target shows once without a
//  header, the rail's keyboard button, the Send sheet's equal chips, the
//  connect toast at AX3 and the launch reconnect's redial, Ask's keyboard
//  margin, and the pair sheet's line under the code field.
//

import Foundation
import Testing
@testable import PixelHandCore

/// The Type panel on the keyboard, as `test22` found it: the corner drag
/// had no room below the panel, so nothing grew (build 27 bug 2).
@Suite("The Type panel grows from its corner while it rides on the keyboard (build 27 bug 2)")
struct TypePanelGrowsOnKeyboardTests {
    /// The panel's free room above a keyboard whose top is at `keyboardTop`.
    static func geometry(width: Double, height: Double, keyboardTop: Double, safeTop: Double = 24) -> TypePanelGeometry {
        TypePanelGeometry(
            container: PanelRect(x: 0, y: safeTop, width: width, height: height - safeTop),
            windowWidth: width,
            windowHeight: height,
            keyboardMinY: keyboardTop
        )
    }

    static func layout(width: Double, height: Double, overlap: Double, panelWidth: Double, panelHeight: Double?, room: Double) -> TypePanelLayout {
        TypePanelLayout(
            width: width, height: height, keyboard: .software, keyboardOverlap: overlap,
            panelWidth: panelWidth, panelHeight: panelHeight, roomHeight: room
        )
    }

    /// Drags the trailing corner of a panel parked on the keyboard by
    /// (dx, dy) and returns the new frame and its layout.
    static func drag(
        window: (width: Double, height: Double), keyboardTop: Double,
        dx: Double, dy: Double
    ) -> (start: PanelRect, end: PanelRect, before: TypePanelLayout, after: TypePanelLayout, room: PanelRect) {
        let geometry = geometry(width: window.width, height: window.height, keyboardTop: keyboardTop)
        let overlap = window.height - keyboardTop
        let width = geometry.width(for: .initial)
        let before = layout(width: window.width, height: window.height, overlap: overlap, panelWidth: width, panelHeight: nil, room: geometry.room.height)
        let start = geometry.frame(for: .initial, height: before.panelHeight)
        let heights: (Double) -> ClosedRange<Double> = { w in
            layout(width: window.width, height: window.height, overlap: overlap, panelWidth: w, panelHeight: nil, room: geometry.room.height).heightRange
        }
        let end = geometry.resized(start, edge: .trailing, translation: dx, dy, heights: heights)
        let after = layout(width: window.width, height: window.height, overlap: overlap, panelWidth: end.width, panelHeight: end.height, room: geometry.room.height)
        return (start, end, before, after, geometry.room)
    }

    @Test("iPad portrait, panel on the keyboard: dragging the corner down grows the arrows past 48 pt, the top rises")
    func iPadPortrait() {
        // iPad Pro 11" portrait (834 × 1210), keyboard top at 830.
        let run = Self.drag(window: (834, 1210), keyboardTop: 830, dx: -200, dy: 400)
        #expect(abs(run.start.maxY - run.room.maxY) < 1, "the panel starts on the keyboard")
        #expect(run.end.height > run.start.height + 100)
        #expect(abs(run.end.maxY - run.room.maxY) < 1, "the bottom stays on the keyboard")
        #expect(run.end.minY >= run.room.minY)
        let before = try! #require(run.before.grid(.arrows))
        let after = try! #require(run.after.grid(.arrows))
        #expect(before.cellHeight < 48)
        #expect(after.cellHeight > 48, "arrows \(after.cellHeight) pt tall after the drag")
    }

    @Test("iPad landscape, panel on the keyboard: the same drag grows the arrows")
    func iPadLandscape() {
        // iPad Pro 11" landscape (1210 × 834), keyboard top at 440.
        let run = Self.drag(window: (1210, 834), keyboardTop: 440, dx: -200, dy: 400)
        #expect(run.end.height > run.start.height)
        let after = try! #require(run.after.grid(.arrows))
        #expect(after.cellHeight > 48)
        #expect(run.end.maxY <= run.room.maxY + 0.5)
    }

    @Test("iPhone portrait, docked above the keyboard: the drag grows the arrows")
    func iPhoneDocked() {
        // iPhone 17 Pro portrait (402 × 874), keyboard top at 538.
        let geometry = Self.geometry(width: 402, height: 874, keyboardTop: 538, safeTop: 62)
        #expect(geometry.style == .docked)
        let run = Self.drag(window: (402, 874), keyboardTop: 538, dx: -200, dy: 400)
        #expect(run.end.height > run.start.height)
        let after = try! #require(run.after.grid(.arrows))
        #expect(after.cellHeight > 48, "arrows \(after.cellHeight) pt tall after the drag")
        #expect(run.end.maxY <= run.room.maxY + 0.5)
    }

    @Test("Room below the panel: the top holds and the bottom moves, as before")
    func roomBelow() {
        let geometry = Self.geometry(width: 1180, height: 820, keyboardTop: 900)
        let heights: (Double) -> ClosedRange<Double> = { w in
            TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: w).heightRange
        }
        let start = PanelRect(x: 200, y: 100, width: 600, height: 200)
        let end = geometry.resized(start, edge: .trailing, translation: 0, 80, heights: heights)
        #expect(end.minY == 100)
        #expect(end.height == 280)
    }

    @Test("Never taller than the room, never above its top")
    func clampedToRoom() {
        let geometry = Self.geometry(width: 874, height: 402, keyboardTop: 230, safeTop: 0)
        let heights: (Double) -> ClosedRange<Double> = { _ in 100...600 }
        let start = PanelRect(x: 20, y: 100, width: 600, height: 114)
        let end = geometry.resized(start, edge: .trailing, translation: 0, 2000, heights: heights)
        #expect(end.height == geometry.room.height)
        #expect(end.minY == geometry.room.minY)
    }

    @Test("Shrinking a panel on the keyboard keeps it on the keyboard")
    func shrinking() {
        let run = Self.drag(window: (834, 1210), keyboardTop: 830, dx: 0, dy: 300)
        let geometry = Self.geometry(width: 834, height: 1210, keyboardTop: 830)
        let heights: (Double) -> ClosedRange<Double> = { w in
            Self.layout(width: 834, height: 1210, overlap: 380, panelWidth: w, panelHeight: nil, room: geometry.room.height).heightRange
        }
        let back = geometry.resized(run.end, edge: .trailing, translation: 0, -100, heights: heights)
        #expect(back.height == run.end.height - 100)
        #expect(abs(back.maxY - geometry.room.maxY) < 1, "the bottom stays on the keyboard")
        #expect(back.minY == run.end.minY + 100)
    }

    @Test("A resize on the keyboard ends at the bottom of the room, and the stored place stays there")
    func storedAtBottom() {
        let run = Self.drag(window: (834, 1210), keyboardTop: 830, dx: 0, dy: 300)
        let geometry = Self.geometry(width: 834, height: 1210, keyboardTop: 830)
        let place = geometry.placement(resizedTo: run.end, keeping: .initial, keepsHeight: true)
        #expect(place.y == 1)
        #expect(place.height == run.end.height)
        let redrawn = geometry.frame(for: place, height: run.end.height)
        #expect(abs(redrawn.maxY - geometry.room.maxY) < 1)
    }
}

@Suite("The arrows widen with the panel's width too (build 27 bug 2, OT-11)")
struct TypePanelArrowsWidenTests {
    @Test("At the shortest height a wider stacked panel gives wider arrows, up to 72 pt")
    func widerPanelWiderArrows() {
        var last = 0.0
        for width in stride(from: 360.0, through: 760, by: 20) {
            // The shortest stacked panel with the inverted T: 44 pt rows.
            let probe = TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: width)
            let chrome = probe.panelHeight - probe.bodySize.height
            let layout = TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: width, panelHeight: chrome + 4 * 44 + 8)
            #expect(layout.arrangement == .stacked && layout.arrowShape == .invertedT, "w\(width)")
            #expect(abs((layout.grid(.arrows)?.cellHeight ?? 0) - 44) < 0.5, "w\(width)")
            let arrows = try! #require(layout.grid(.arrows))
            #expect(arrows.cellWidth >= last - 0.001, "w\(width)")
            #expect(arrows.cellWidth <= TypePanelLayout.maximumRowHeight + 0.001)
            last = arrows.cellWidth
        }
        #expect(last > 60)
        let narrow = TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: 360, panelHeight: 0)
        #expect(abs((narrow.grid(.arrows)?.cellWidth ?? 0) - 44) < 0.5)
    }

    @Test("The field keeps at least half the band (or its minimum) beside wider arrows")
    func fieldKeepsHalf() {
        for width in stride(from: 360.0, through: 760, by: 10) {
            for height in [0.0, 300, 400] {
                let layout = TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: width, panelHeight: height)
                guard let field = layout.grid(.field), let arrows = layout.grid(.arrows),
                      layout.arrangement != .oneBlock else { continue }
                let inner = width - 2 * TypePanelLayout.padding
                #expect(field.rect.width >= TypePanelLayout.fieldMinimumWidth - 0.5, "w\(width) h\(height)")
                // Arrows wider than their row only ever take the field's
                // spare half.
                if arrows.cellWidth > arrows.cellHeight + 0.5 {
                    #expect(field.rect.width >= inner * TypePanelLayout.fieldShare - 0.5, "w\(width) h\(height)")
                }
            }
        }
    }

    @Test("A taller row makes the arrows at least square with it")
    func tallRowsSquare() {
        let layout = TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: 520, panelHeight: 400)
        let arrows = try! #require(layout.grid(.arrows))
        #expect(arrows.cellWidth >= arrows.cellHeight - 0.001)
    }
}

@Suite("The target shows once, with or without a header (build 27 bug 5)")
struct TypePanelTargetPlaceTests {
    @Test("No header (iPhone landscape, keyboard up): the field's row carries the target")
    func fieldRow() {
        let landscape = TypePanelLayout(width: 874, height: 402, keyboard: .software, keyboardOverlap: 200)
        #expect(!landscape.showsHeader)
        #expect(landscape.targetPlace == .fieldRow)
        #expect(TypePanelLayout(width: 874, height: 402, keyboard: .none).targetPlace == .header)
        #expect(TypePanelLayout(width: 1180, height: 820, keyboard: .none, panelWidth: 720).targetPlace == .header)
    }
}

@Suite("iPhone landscape's rail carries the keyboard button (VQ-105)")
struct RailKeyboardButtonTests {
    @Test("Only the rail")
    func rail() {
        let phoneLandscape = CanvasPlan(width: 874, height: 402)
        #expect(phoneLandscape.form == .rail)
        #expect(phoneLandscape.railCarriesKeyboard)
        #expect(!CanvasPlan(width: 402, height: 874).railCarriesKeyboard)
        #expect(!CanvasPlan(width: 1180, height: 820).railCarriesKeyboard)
        #expect(!CanvasPlan(width: 820, height: 1180).railCarriesKeyboard)
    }
}

@Suite("The Send sheet's source chips share one width (build 27 bug 3, OT-9)")
struct SendChipWidthTests {
    @Test("Three whole-point chips that fit the row")
    func equal() {
        for row in stride(from: 280.0, through: 900, by: 0.5) {
            let width = SendSheetLayout.chipWidth(rowWidth: row)
            #expect(width == width.rounded(.down))
            #expect(3 * width + 2 * SendSheetLayout.chipGap <= row + 0.001, "row \(row)")
            #expect(row - (3 * width + 2 * SendSheetLayout.chipGap) < 3, "row \(row)")
        }
        // The build 27 iPad row: 174.5 / 175 / 173.5 measured, now 174 each.
        #expect(SendSheetLayout.chipWidth(rowWidth: 539) == 174)
        #expect(SendSheetLayout.chipWidth(rowWidth: 0) == 44)
        #expect(SendSheetLayout.chipWidth(rowWidth: .nan) == 44)
        #expect(SendSheetLayout.chipHeight == 44)
    }
}

@Suite("Connecting… at every text size (VQ-107)")
struct ConnectToastPlanTests {
    @Test("Stacked at the accessibility sizes, inline otherwise; stacked wraps without a limit")
    func arrangement() {
        #expect(ConnectToastPlan.arrangement(band: .standard) == .inline)
        #expect(ConnectToastPlan.arrangement(band: .large) == .stacked)
        #expect(ConnectToastPlan.arrangement(band: .huge) == .stacked)
        #expect(ConnectToastPlan.lineLimit(.inline) == 2)
        #expect(ConnectToastPlan.lineLimit(.stacked) == nil)
    }

    @Test("On the picker the toast sits under the Pair and Settings bar")
    func topInset() {
        #expect(ConnectToastPlan.topInset(hasSession: true, headerClearance: 68) == 68)
        let picker = ConnectToastPlan.topInset(hasSession: false, headerClearance: 68)
        #expect(picker >= ConnectToastPlan.pickerBarHeight)
        #expect(picker == 60)
    }
}

@Suite("A failed launch reconnect redials (VQ-107)")
struct LaunchRedialTests {
    @Test("Launch reconnects and redials retry; a person's own dial reports and stops")
    func redials() {
        #expect(MacReconnectPolicy.redialsFailedDial(isEnabled: true, isRedial: false, isLaunchReconnect: true))
        #expect(MacReconnectPolicy.redialsFailedDial(isEnabled: true, isRedial: true, isLaunchReconnect: false))
        #expect(!MacReconnectPolicy.redialsFailedDial(isEnabled: true, isRedial: false, isLaunchReconnect: false))
        #expect(!MacReconnectPolicy.redialsFailedDial(isEnabled: false, isRedial: true, isLaunchReconnect: true))
        // The schedule it follows stops after four tries.
        #expect(MacReconnectPolicy.redialDelay(isEnabled: true, attempt: 1, endedByVerdict: false, endedByUser: false) == 2)
        #expect(MacReconnectPolicy.redialDelay(isEnabled: true, attempt: 4, endedByVerdict: false, endedByUser: false) == nil)
    }
}

@Suite("Ask keeps its rows above the keyboard (VQ-104)")
struct KeyboardAvoidanceTests {
    @Test("The overlap plus a gap, or nothing")
    func inset() {
        // iPad portrait column ending at 1180, keyboard top at 830.
        #expect(KeyboardAvoidance.bottomInset(viewMaxY: 1180, keyboardMinY: 830) == 358)
        // A sheet the system already lifted above the keyboard.
        #expect(KeyboardAvoidance.bottomInset(viewMaxY: 820, keyboardMinY: 830) == 0)
        #expect(KeyboardAvoidance.bottomInset(viewMaxY: 1180, keyboardMinY: nil) == 0)
        #expect(KeyboardAvoidance.bottomInset(viewMaxY: .nan, keyboardMinY: 830) == 0)
        #expect(KeyboardAvoidance.bottomInset(viewMaxY: 900.2, keyboardMinY: 830, gap: 0) == 71)
    }
}

@Suite("The pair sheet repeats the Mac under the code field on iPad (VQ-108)")
struct PairingFieldCaptionTests {
    @Test("iPad with the pad up only")
    func caption() {
        #expect(PairingSheetLayout.showsFieldCaption(isPhone: false, isKeypadUp: true))
        #expect(!PairingSheetLayout.showsFieldCaption(isPhone: false, isKeypadUp: false))
        #expect(!PairingSheetLayout.showsFieldCaption(isPhone: true, isKeypadUp: true))
        #expect(PairingSheetLayout.fieldCaption(targetName: "Studio") == "The code showing on Studio")
        #expect(PairingSheetLayout.fieldCaption(targetName: nil) == "Choose the Mac that shows the code.")
        #expect(PairingSheetLayout.fieldCaption(targetName: "") == "Choose the Mac that shows the code.")
    }
}
