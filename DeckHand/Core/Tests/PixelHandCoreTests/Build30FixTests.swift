//
//  Build30FixTests.swift
//  PixelHandCoreTests
//
//  The rules behind the build 30 fix round
//  (`Integration/LANE-build30-fixes.md`): the Type panel kept above the
//  keyboard in iPad portrait, including when Live's field takes focus
//  (bug 1, P1: a second reading from the keyboard layout guide, merged
//  with the notifications'), the arrows and numpad filling the card
//  (bug 2), and a docked iPhone panel that docks to the leading edge
//  (bug 3).
//

import Foundation
import Testing
@testable import PixelHandCore

/// Portrait iPad windows (full screen) and the keyboard heights a portrait
/// iPad shows: the shortcut bar alone (hardware or minimised keyboard),
/// the keys without and with the predictive bar, and the tallest with
/// a larger text size.
private struct PortraitPad {
    let name: String
    let width: Double
    let height: Double
    let safeTop: Double = 24
    let safeBottom: Double = 20

    var container: PanelRect {
        PanelRect(x: 0, y: safeTop, width: width, height: height - safeTop - safeBottom)
    }

    func keyboardFrame(_ height: Double) -> PanelRect {
        PanelRect(x: 0, y: self.height - height, width: width, height: height)
    }

    static let all = [
        PortraitPad(name: "iPad Pro 11 (M4) portrait", width: 834, height: 1210),
        PortraitPad(name: "iPad Pro 11 portrait", width: 834, height: 1194),
        PortraitPad(name: "iPad Air 11 portrait", width: 820, height: 1180),
        PortraitPad(name: "iPad Pro 13 portrait", width: 1032, height: 1376),
        PortraitPad(name: "iPad mini portrait", width: 744, height: 1133),
    ]

    /// Shortcut bar (hardware keyboard), the bar a little taller, keys
    /// without the predictive row, keys with it (Live's synced field turns
    /// predictions on), and a large text size.
    static let keyboardHeights: [Double] = [55, 69, 313, 330, 368, 380, 398, 420]
}

@Suite("The Type panel stays above the keyboard in iPad portrait (build 30 bug 1)")
struct PortraitKeyboardTests {
    private static let places: [TypePanelPlacement] = {
        var places: [TypePanelPlacement] = []
        for x in [0.0, 0.5, 1] {
            for y in [0.0, 0.5, 1] {
                for height in [nil, 300, 2000] as [Double?] {
                    places.append(TypePanelPlacement(x: x, y: y, width: nil, height: height))
                }
            }
        }
        places.append(TypePanelPlacement(x: 0, y: 1, width: TypePanelGeometry.minimumWidth))
        places.append(TypePanelPlacement(x: 1, y: 1, width: 760, height: 520))
        return places
    }()

    @Test("Every place, mode, numpad and portrait keyboard height: the whole panel ends a gap above the keyboard")
    func everyPlaceAboveKeyboard() {
        for pad in PortraitPad.all {
            for keyboard in PortraitPad.keyboardHeights {
                let top = pad.height - keyboard
                let reading = KeyboardFrameReading.read([pad.keyboardFrame(keyboard)], windowWidth: pad.width, windowHeight: pad.height)
                #expect(reading == .covers(top: top, overlap: keyboard), "\(pad.name) kb\(keyboard)")
                let kind = KeyboardKind.classify(overlap: keyboard, hardwareAttached: keyboard < 100)
                let geometry = TypePanelGeometry(container: pad.container, windowWidth: pad.width, windowHeight: pad.height, keyboardMinY: top)
                #expect(geometry.style == .floating)
                #expect(geometry.room.maxY == top - TypePanelGeometry.gap, "\(pad.name) kb\(keyboard)")
                for place in Self.places {
                    for numpad in [false, true] {
                        for mode in TypeMode.allCases {
                            let width = geometry.width(for: place)
                            let layout = TypePanelLayout(
                                width: pad.width, height: pad.height, keyboard: kind, keyboardOverlap: keyboard,
                                panelWidth: width, panelHeight: geometry.height(for: place),
                                roomHeight: geometry.room.height, showsNumpad: numpad, mode: mode
                            )
                            let note = "\(pad.name) kb\(keyboard) \(place) numpad \(numpad) \(mode)"
                            #expect(layout.panelHeight <= geometry.room.height + 0.5, "\(note): \(layout.panelHeight) in \(geometry.room.height)")
                            let frame = geometry.kept(geometry.frame(for: place, size: (width, layout.panelHeight)))
                            #expect(geometry.fitsAbove(frame), "\(note): \(frame)")
                            #expect(frame.maxY <= top - TypePanelGeometry.gap + 1, "\(note): \(frame) over the keyboard at \(top)")
                            #expect(frame.minX >= pad.container.minX && frame.maxX <= pad.container.maxX, "\(note)")
                            // The field is in the panel, so it's above the keyboard too.
                            if let field = layout.grid(.field) {
                                #expect(frame.minY + field.rect.maxY < top, "\(note)")
                            }
                        }
                    }
                }
            }
        }
    }

    @Test("Live's field takes focus: the notification reading is lost, the guide's keeps the panel above the keyboard")
    func fieldFocusWithLostNotification() {
        for pad in PortraitPad.all {
            for keyboard in PortraitPad.keyboardHeights {
                let top = pad.height - keyboard
                // The guide, measured in a full-window view.
                let guide = KeyboardFrameReading.guideReading(pad.keyboardFrame(keyboard), viewMaxY: pad.height, windowHeight: pad.height)
                #expect(guide == .covers(top: top, overlap: keyboard), "\(pad.name) kb\(keyboard)")
                // The notification reading lost (nil), read as clear (a stale
                // hidden frame), or turned (picked nothing, so still nil).
                let turned = PanelRect(x: top, y: 0, width: keyboard, height: pad.width)
                let lost = KeyboardFrameReading.read([turned], windowWidth: pad.width, windowHeight: pad.height)
                for notification in [nil, .clear, lost] as [KeyboardFrameReading.Reading?] {
                    let merged = KeyboardFrameReading.merged([notification, guide])
                    #expect(merged == .covers(top: top, overlap: keyboard), "\(pad.name) kb\(keyboard) \(String(describing: notification))")
                    guard case let .covers(mergedTop, _)? = merged else { continue }
                    let geometry = TypePanelGeometry(container: pad.container, windowWidth: pad.width, windowHeight: pad.height, keyboardMinY: mergedTop)
                    // The default place: bottom centre, riding on the keyboard.
                    let layout = TypePanelLayout(width: pad.width, height: pad.height, keyboard: .software, keyboardOverlap: keyboard,
                                                 panelWidth: geometry.width(for: .initial), roomHeight: geometry.room.height, mode: .live)
                    let frame = geometry.kept(geometry.frame(for: .initial, size: (geometry.width(for: .initial), layout.panelHeight)))
                    #expect(frame.maxY == top - TypePanelGeometry.gap, "\(pad.name) kb\(keyboard)")
                }
            }
        }
    }

    @Test("Without the guide the build 30 failure shows: the panel's body under the keyboard, only its header above")
    func lostReadingIsTheBug() {
        let pad = PortraitPad.all[1]
        let keyboard = 380.0
        let geometry = TypePanelGeometry(container: pad.container, windowWidth: pad.width, windowHeight: pad.height, keyboardMinY: nil)
        let layout = TypePanelLayout(width: pad.width, height: pad.height, keyboard: .none, panelWidth: geometry.width(for: .initial), roomHeight: geometry.room.height, mode: .live)
        let frame = geometry.frame(for: .initial, size: (geometry.width(for: .initial), layout.panelHeight))
        #expect(frame.maxY > pad.height - keyboard, "the regression the merge prevents")
    }

    @Test("Guide readings: covering, clear, unusable")
    func guideReadings() {
        let pad = PortraitPad.all[0]
        #expect(KeyboardFrameReading.guideReading(PanelRect(x: 0, y: pad.height, width: pad.width, height: 0), viewMaxY: pad.height, windowHeight: pad.height) == .clear)
        // A view that doesn't reach the window's bottom says nothing.
        #expect(KeyboardFrameReading.guideReading(PanelRect(x: 0, y: 900, width: pad.width, height: 0), viewMaxY: 900, windowHeight: pad.height) == nil)
        #expect(KeyboardFrameReading.guideReading(PanelRect(x: 0, y: .nan, width: pad.width, height: 380), viewMaxY: pad.height, windowHeight: pad.height) == nil)
        #expect(KeyboardFrameReading.guideReading(PanelRect(x: 0, y: -10, width: pad.width, height: pad.height + 10), viewMaxY: pad.height, windowHeight: pad.height) == nil)
        // The shortcut bar alone: a short cover (the dock's lift).
        #expect(KeyboardFrameReading.guideReading(pad.keyboardFrame(55), viewMaxY: pad.height, windowHeight: pad.height) == .covers(top: pad.height - 55, overlap: 55))
    }

    @Test("Merging: either source covering wins, up to the higher top; clear only when all say clear")
    func merging() {
        #expect(KeyboardFrameReading.merged([nil, nil]) == nil)
        #expect(KeyboardFrameReading.merged([]) == nil)
        #expect(KeyboardFrameReading.merged([.clear, nil]) == .clear)
        #expect(KeyboardFrameReading.merged([.clear, .clear]) == .clear)
        #expect(KeyboardFrameReading.merged([.covers(top: 830, overlap: 380), .clear]) == .covers(top: 830, overlap: 380))
        #expect(KeyboardFrameReading.merged([.covers(top: 842, overlap: 368), .covers(top: 830, overlap: 380)]) == .covers(top: 830, overlap: 380))
        #expect(KeyboardFrameReading.merged([.covers(top: .nan, overlap: 380), .clear]) == .clear)
    }

    @Test("Scroll views keep their rows above every portrait keyboard (KeyboardAvoidance)")
    func avoidance() {
        for pad in PortraitPad.all {
            for keyboard in PortraitPad.keyboardHeights {
                let top = pad.height - keyboard
                let viewMaxY = pad.height - pad.safeBottom
                let inset = KeyboardAvoidance.bottomInset(viewMaxY: viewMaxY, keyboardMinY: top)
                #expect(inset == (viewMaxY - top + 8).rounded(.up) || (viewMaxY <= top && inset == 0), "\(pad.name) kb\(keyboard)")
                #expect(viewMaxY - inset <= top - 8 + 0.5, "\(pad.name) kb\(keyboard)")
            }
        }
    }
}

@Suite("The arrows and the numpad fill the card (build 30 bug 2)")
struct NumpadFillTests {
    @Test("test20's narrow widths: arrows and numpad span the inner width exactly")
    func narrowWidths() {
        for width in [360.0, 362, 372, 384, 400, 456] {
            for (w, h, overlap) in [(1210.0, 834.0, 398.0), (834, 1210, 380)] {
                let layout = TypePanelLayout(width: w, height: h, keyboard: .software, keyboardOverlap: overlap, panelWidth: width, showsNumpad: true)
                let inner = width - 2 * TypePanelLayout.padding
                let arrows = layout.grid(.arrows)?.rect, numpad = layout.grid(.numpad)?.rect
                let minX = min(arrows?.minX ?? .infinity, numpad?.minX ?? .infinity)
                let maxX = max(arrows?.maxX ?? 0, numpad?.maxX ?? 0)
                #expect(minX == 0, "w\(width)")
                #expect(abs(maxX - inner) < 0.5, "w\(width): \(maxX) of \(inner)")
                #expect(maxX - minX > width - 2 * 12 - 4, "w\(width): the walk's check")
                #expect(layout.panelWidth == width)
            }
        }
    }
}

@Suite("A docked panel narrower than its room docks to an edge or the centre (build 30 bug 3)")
struct DockedSlotTests {
    /// iPhone 17 Pro landscape: the safe area leaves 62 pt each side.
    private let landscape = TypePanelGeometry(container: PanelRect(x: 62, y: 0, width: 750, height: 381), windowWidth: 874, windowHeight: 402)
    private let portrait = TypePanelGeometry(container: PanelRect(x: 0, y: 62, width: 402, height: 778), windowWidth: 402, windowHeight: 874, keyboardMinY: 538)

    @Test("Dropped near the leading edge, it docks there (x = the room's leading edge, not 257)")
    func leading() {
        #expect(landscape.style == .docked)
        let size = (width: 360.0, height: 200.0)
        let start = landscape.frame(for: .initial, size: size)
        #expect(start.minX == 257, "build 30 saw it centred at 257")
        // test20 drags the grip to 2 % across the window.
        let place = landscape.placement(droppedAt: 17, 32, size: size, keeping: .initial)
        #expect(place.x == 0)
        #expect(place.y == 0)
        let frame = landscape.kept(landscape.frame(for: place, size: size))
        #expect(frame.minX == landscape.room.minX)
        #expect(frame.minX == 70)
        #expect(frame.minX - 0 < 90, "the walk's allowance for the safe area")
    }

    @Test("Trailing and centre too; the nearest of the three wins, the centre on a tie")
    func trailingAndCentre() {
        let size = (width: 360.0, height: 200.0)
        let room = landscape.room
        let trailing = landscape.placement(droppedAt: room.maxX - 360 - 20, 100, size: size, keeping: .initial)
        #expect(trailing.x == 1)
        #expect(landscape.frame(for: trailing, size: size).maxX == room.maxX)
        let centre = landscape.placement(droppedAt: room.midX - 180 + 30, 100, size: size, keeping: .initial)
        #expect(centre.x == 0.5)
        #expect(abs(landscape.frame(for: centre, size: size).midX - room.midX) <= 0.5)
        // A third of the way: nearer the leading edge than the centre.
        let third = landscape.placement(droppedAt: room.minX + 60, 100, size: size, keeping: .initial)
        #expect(third.x == 0)
    }

    @Test("Spanning the room (iPhone portrait) it stays centred; a drag sideways changes nothing")
    func fullWidth() {
        let size = (width: portrait.room.width, height: 160.0)
        let place = portrait.placement(droppedAt: 0, 400, size: size, keeping: .initial)
        #expect(place.x == 0.5)
        #expect(portrait.frame(for: place, size: size).minX == portrait.room.minX)
        #expect(portrait.clamped(origin: -50, 200, size: size).minX == portrait.room.minX)
    }

    @Test("Docked fractions: stored 0.5 stays centred, the old data reads the same")
    func slots() {
        #expect(TypePanelGeometry.dockedSlot(0) == 0)
        #expect(TypePanelGeometry.dockedSlot(0.2) == 0)
        #expect(TypePanelGeometry.dockedSlot(0.5) == 0.5)
        #expect(TypePanelGeometry.dockedSlot(0.8) == 1)
        #expect(TypePanelGeometry.dockedSlot(1) == 1)
        #expect(TypePanelGeometry.dockedSlot(.nan) == 0.5)
        let size = (width: 360.0, height: 200.0)
        #expect(abs(landscape.frame(for: .initial, size: size).midX - landscape.room.midX) <= 0.5)
    }

    @Test("kept() leaves a leading docked panel at the leading edge, above the keyboard")
    func keptLeading() {
        let withKeyboard = TypePanelGeometry(container: PanelRect(x: 62, y: 0, width: 750, height: 381), windowWidth: 874, windowHeight: 402, keyboardMinY: 402 - 209)
        let place = TypePanelPlacement(x: 0, y: 1)
        let frame = withKeyboard.kept(withKeyboard.frame(for: place, size: (360, 120)))
        #expect(frame.minX == withKeyboard.room.minX)
        #expect(withKeyboard.fitsAbove(frame))
    }

    @Test("Resizing a panel docked to an edge holds that edge; a centred one resizes from the centre")
    func resize() {
        let room = landscape.room
        let leading = PanelRect(x: room.minX, y: 100, width: 400, height: 200)
        let wider = landscape.resized(leading, edge: .trailing, translation: 60)
        #expect(wider.minX == room.minX && wider.width == 460)
        let narrower = landscape.resized(leading, edge: .leading, translation: 30)
        #expect(narrower.minX == room.minX && narrower.width == 370)
        #expect(landscape.placement(resizedTo: wider, keeping: TypePanelPlacement(x: 0, y: 0)).x == 0)
        let trailing = PanelRect(x: room.maxX - 400, y: 100, width: 400, height: 200)
        let t = landscape.resized(trailing, edge: .leading, translation: -50)
        #expect(t.maxX == room.maxX && t.width == 450)
        let centred = PanelRect(x: room.midX - 200, y: 100, width: 400, height: 200)
        let c = landscape.resized(centred, edge: .trailing, translation: 20)
        #expect(c.width == 440 && abs(c.midX - room.midX) <= 0.5)
    }
}
