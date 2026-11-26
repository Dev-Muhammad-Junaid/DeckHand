//
//  TypePanelGeometryTests.swift
//  PixelHandCoreTests
//
//  OT-6 (owner testing, build 25): the Type panel moves, snaps, resizes,
//  avoids the keyboard and the dock, and remembers where it was.
//

import Foundation
import Testing
@testable import PixelHandCore

@Suite("Type panel geometry (OT-6)")
struct TypePanelGeometryTests {
    /// iPad Air 11" landscape, the shell's safe area (status bar above).
    static let padLandscape = PanelRect(x: 0, y: 24, width: 1180, height: 796)
    static let padPortrait = PanelRect(x: 0, y: 24, width: 820, height: 1156)

    func pad(keyboardMinY: Double? = nil, dockMinY: Double? = 740) -> TypePanelGeometry {
        TypePanelGeometry(container: Self.padLandscape, windowWidth: 1180, windowHeight: 820, keyboardMinY: keyboardMinY, dockMinY: dockMinY)
    }

    @Test("iPad floats; iPhone and narrow windows dock")
    func style() {
        #expect(pad().style == .floating)
        #expect(TypePanelGeometry(container: Self.padPortrait, windowWidth: 820, windowHeight: 1180).style == .floating)
        // iPhone portrait and landscape.
        #expect(TypePanelGeometry(container: PanelRect(x: 0, y: 59, width: 402, height: 781), windowWidth: 402, windowHeight: 874).style == .docked)
        #expect(TypePanelGeometry(container: PanelRect(x: 59, y: 0, width: 756, height: 381), windowWidth: 874, windowHeight: 402).style == .docked)
        // Slide Over / the narrowest Stage Manager window.
        #expect(TypePanelGeometry(container: PanelRect(x: 0, y: 0, width: 375, height: 800), windowWidth: 375, windowHeight: 800).style == .docked)
    }

    @Test("The free room stops above the dock, or above the keyboard when it's higher")
    func room() {
        let dock = pad()
        #expect(dock.room.minY == 32)
        #expect(dock.room.maxY == 740 - 8)
        #expect(dock.room.minX == 8 && dock.room.maxX == 1172)
        let keyboard = pad(keyboardMinY: 420)
        #expect(keyboard.room.maxY == 412)
        // A keyboard frame below the container (Stage Manager window above it).
        let below = TypePanelGeometry(container: PanelRect(x: 0, y: 0, width: 700, height: 600), windowWidth: 700, windowHeight: 600, keyboardMinY: 700)
        #expect(below.room.maxY == 592)
    }

    @Test("Width: 360 to 760, default 720, clamped to the room")
    func widths() {
        let geometry = pad()
        #expect(geometry.widthRange == 360...760)
        #expect(geometry.width(for: .initial) == TypePanelGeometry.defaultWidth)
        #expect(geometry.clampWidth(100) == 360)
        #expect(geometry.clampWidth(2000) == 760)
        #expect(geometry.clampWidth(500.4) == 500)
        #expect(geometry.canResize)
        // A Stage Manager window 520 wide: the room caps it.
        let small = TypePanelGeometry(container: PanelRect(x: 0, y: 0, width: 520, height: 700), windowWidth: 520, windowHeight: 700)
        #expect(small.widthRange == 360...504)
        // iPhone SE portrait: narrower than the minimum, so just the room.
        let se = TypePanelGeometry(container: PanelRect(x: 0, y: 20, width: 320, height: 548), windowWidth: 320, windowHeight: 568)
        #expect(se.widthRange == 304...304)
        #expect(!se.canResize)
        #expect(se.width(for: .initial) == 304)
    }

    @Test("Bottom centre by default, sitting on the dock")
    func initial() {
        let frame = pad().frame(for: .initial, height: 200)
        #expect(frame.width == 720)
        #expect(frame.midX == 590)
        #expect(frame.maxY == 732)
    }

    @Test("A bottom-parked panel rides on the keyboard, and returns to the dock when it goes")
    func keyboardAvoidance() {
        let place = TypePanelPlacement(x: 1, y: 1, width: 400)
        let up = pad(keyboardMinY: 420).frame(for: place, height: 200)
        #expect(up.maxY == 412)
        #expect(up.maxX == 1172)
        let down = pad().frame(for: place, height: 200)
        #expect(down.maxY == 732)
        // Top-parked stays at the top either way.
        let top = TypePanelPlacement(x: 0, y: 0, width: 400)
        #expect(pad(keyboardMinY: 420).frame(for: top, height: 200).minY == 32)
        #expect(pad().frame(for: top, height: 200).minY == 32)
    }

    @Test("A panel taller than the room keeps its header in view")
    func tooTall() {
        let frame = pad(keyboardMinY: 420).frame(for: .initial, height: 500)
        #expect(frame.minY == 32)
    }

    @Test("Drags clamp into the room; drops snap to edges, the centre and corners within the magnet")
    func snapping() {
        let geometry = pad()
        let size = (width: 400.0, height: 200.0)
        // Dragged past the leading edge: clamped.
        let clamped = geometry.clamped(origin: -50, -50, size: size)
        #expect(clamped.minX == 8 && clamped.minY == 32)
        // Dropped 20 pt from the top-trailing corner: snaps to the corner.
        let corner = geometry.placement(droppedAt: 1172 - 400 - 20, 32 + 20, size: size, keeping: .initial)
        #expect(corner.x == 1 && corner.y == 0)
        // Dropped near the centre line, mid-height: centred, height kept.
        let centred = geometry.placement(droppedAt: 590 - 200 + 10, 300, size: size, keeping: .initial)
        #expect(centred.x == 0.5)
        #expect(centred.y > 0 && centred.y < 1)
        // Dropped somewhere free: stays there.
        let free = geometry.placement(droppedAt: 200, 250, size: size, keeping: .initial)
        let frame = geometry.frame(for: TypePanelPlacement(x: free.x, y: free.y, width: 400), height: 200)
        #expect(abs(frame.minX - 200) <= 1 && abs(frame.minY - 250) <= 1)
        // The width is kept through a drag.
        let sized = geometry.placement(droppedAt: 200, 250, size: size, keeping: TypePanelPlacement(x: 0, y: 0, width: 400))
        #expect(sized.width == 400)
    }

    @Test("Resizing holds the other edge and stays within the range and the room")
    func resizing() {
        let geometry = pad()
        let start = PanelRect(x: 400, y: 300, width: 500, height: 200)
        let wider = geometry.resized(start, edge: .trailing, translation: 120)
        #expect(wider.minX == 400 && wider.width == 620)
        // Can't grow past the room's trailing edge.
        let capped = geometry.resized(start, edge: .trailing, translation: 1000)
        #expect(capped.maxX <= geometry.room.maxX)
        #expect(capped.width <= 760)
        // Leading edge: the trailing edge holds.
        let fromLeading = geometry.resized(start, edge: .leading, translation: -100)
        #expect(fromLeading.maxX == 900 && fromLeading.width == 600)
        // Never under the minimum.
        let tiny = geometry.resized(start, edge: .leading, translation: 400)
        #expect(tiny.width == 360 && tiny.maxX == 900)
        // Ending the resize keeps the frame where it was, with its width.
        let place = geometry.placement(resizedTo: wider, keeping: .initial)
        #expect(place.width == 620)
        let again = geometry.frame(for: place, height: 200)
        #expect(abs(again.minX - wider.minX) <= 1 && abs(again.minY - wider.minY) <= 1)
    }

    @Test("Docked (iPhone): full width, top or bottom; a drag moves it between them")
    func docked() {
        let phone = TypePanelGeometry(container: PanelRect(x: 0, y: 59, width: 402, height: 781), windowWidth: 402, windowHeight: 874, keyboardMinY: 538)
        #expect(phone.style == .docked)
        let bottom = phone.frame(for: .initial, height: 160)
        #expect(bottom.width == 386)
        #expect(bottom.maxY == 530)
        let up = phone.placement(droppedAt: 8, 150, size: (386, 160), keeping: .initial)
        #expect(up.y == 0 && up.x == 0.5)
        #expect(phone.frame(for: up, height: 160).minY == 67)
        let backDown = phone.placement(droppedAt: 8, 330, size: (386, 160), keeping: up)
        #expect(backDown.y == 1)
        // Dragging sideways does nothing: docked panels stay centred.
        #expect(phone.clamped(origin: 100, 200, size: (300, 160)).midX == phone.room.midX)
    }

    @Test("Docked in landscape: resizable from the centre where there's room")
    func dockedLandscape() {
        let landscape = TypePanelGeometry(container: PanelRect(x: 59, y: 0, width: 756, height: 381), windowWidth: 874, windowHeight: 402)
        #expect(landscape.canResize)
        let start = landscape.frame(for: .initial, height: 120)
        #expect(start.width == 740)
        let narrower = landscape.resized(start, edge: .trailing, translation: -100)
        #expect(narrower.width == 540)
        #expect(abs(narrower.midX - landscape.room.midX) <= 1)
    }

    @Test("Places are remembered per arrangement and orientation")
    func persistence() {
        #expect(TypePanelPlacement.storageKey(arrangement: "columns", orientation: .landscape) == "pixelhand.type.place.columns.landscape")
        #expect(TypePanelPlacement.storageKey(arrangement: "stacked", orientation: .portrait) == "pixelhand.type.place.stacked.portrait")
        #expect(PanelOrientation(width: 1180, height: 820) == .landscape)
        #expect(PanelOrientation(width: 820, height: 1180) == .portrait)
        #expect(PanelOrientation(width: 800, height: 800) == .portrait)
        let place = TypePanelPlacement(x: 1, y: 0, width: 480)
        #expect(TypePanelPlacement.restored(place.stored) == place)
        #expect(TypePanelPlacement.restored(nil) == nil)
        #expect(TypePanelPlacement.restored(Data("junk".utf8)) == nil)
        #expect(TypePanelPlacement.restored(Data(#"{"x":4,"y":0}"#.utf8)) == nil)
        #expect(TypePanelPlacement.restored(Data(#"{"x":0.25,"y":1,"width":-3}"#.utf8)) == TypePanelPlacement(x: 0.25, y: 1))
    }

    @Test("A remembered place survives a window resize: parked bottom right stays bottom right")
    func survivesResize() {
        let place = TypePanelPlacement(x: 1, y: 1, width: 480)
        let large = pad().frame(for: place, height: 200)
        let small = TypePanelGeometry(container: PanelRect(x: 0, y: 0, width: 700, height: 600), windowWidth: 700, windowHeight: 600)
            .frame(for: place, height: 200)
        #expect(large.maxX == 1172 && small.maxX == 692)
        #expect(small.maxY == 592)
    }
}

@Suite("Key legends (OT-7)")
struct TypeKeyLegendTests {
    @Test("Word keys draw in the dot-matrix font and fit a 40 pt cap at pitch 1.4")
    func legends() {
        let keys = TypeKeyBlock.cells.compactMap { cell -> TypeKey? in
            if case let .key(key) = cell.item { return key }
            return nil
        } + TypeKeysRow.functionKeys
        for key in keys {
            guard let legend = key.dotMatrixLegend else { continue }
            for character in legend {
                #expect(DotMatrixFont.characters.contains(character), "\(key): \(character)")
            }
            #expect(Double(DotMatrixFont.widthInCells(legend)) * 1.4 <= TypePanelLayout.keyCap - 4, "\(legend)")
        }
        #expect(TypeKey.remote(.delete).dotMatrixLegend == nil)
        #expect(TypeKey.remote(.return).dotMatrixLegend == nil)
        #expect(TypeKey.remote(.up).dotMatrixLegend == nil)
        #expect(TypeKey.function(12).dotMatrixLegend == "F12")
    }
}

@Suite("The collapsed pill (OT-6)")
struct TypePanelPillGeometryTests {
    @Test("The pill sits in the corner the panel was parked in")
    func pill() {
        let geometry = TypePanelGeometry(container: PanelRect(x: 0, y: 24, width: 1180, height: 796), windowWidth: 1180, windowHeight: 820, dockMinY: 740)
        let place = TypePanelPlacement(x: 1, y: 0, width: 500)
        let panel = geometry.frame(for: place, height: 240)
        let pill = geometry.frame(for: place, size: (180, 44))
        #expect(panel.maxX == pill.maxX && panel.minY == pill.minY)
        #expect(pill.width == 180)
    }
}

@Suite("The panel stays above the keyboard in every orientation (build 25 bug 1)")
struct TypePanelKeyboardRotationTests {
    @Test("Every window, keyboard and place: the panel ends above the keyboard and its header is in view")
    func aboveKeyboard() {
        let places = [TypePanelPlacement.initial, .init(x: 0, y: 0), .init(x: 1, y: 1, width: 360), .init(x: 0.3, y: 0.7, width: 600)]
        for (name, width, height) in ShellKeyboardTests.windows {
            for keyboard in ShellKeyboardTests.keyboards where keyboard >= KeyboardKind.softwareMinimumOverlap {
                let geometry = TypePanelGeometry(
                    container: PanelRect(x: 0, y: 0, width: width, height: height),
                    windowWidth: width, windowHeight: height,
                    keyboardMinY: height - keyboard
                )
                for place in places {
                    for panelHeight in [44.0, 200, 320] {
                        let frame = geometry.frame(for: place, height: panelHeight)
                        // The top (grip, close) is always above the keyboard.
                        #expect(frame.minY + 44 <= height - keyboard || frame.minY == geometry.room.minY, "\(name) kb \(keyboard)")
                        if panelHeight <= geometry.room.height {
                            #expect(frame.maxY <= height - keyboard - TypePanelGeometry.gap, "\(name) kb \(keyboard) h \(panelHeight)")
                        }
                    }
                }
            }
        }
    }

    @Test("Rotating to portrait with the keyboard up: bottom-parked rides on the portrait keyboard")
    func rotation() {
        let place = TypePanelPlacement.initial
        let landscape = TypePanelGeometry(container: PanelRect(x: 0, y: 24, width: 1180, height: 796), windowWidth: 1180, windowHeight: 820, keyboardMinY: 420)
        #expect(landscape.frame(for: place, height: 240).maxY == 412)
        let portrait = TypePanelGeometry(container: PanelRect(x: 0, y: 24, width: 820, height: 1156), windowWidth: 820, windowHeight: 1180, keyboardMinY: 1180 - 320)
        let frame = portrait.frame(for: place, height: 240)
        #expect(frame.maxY == 852)
        #expect(frame.minY > 24)
    }
}
