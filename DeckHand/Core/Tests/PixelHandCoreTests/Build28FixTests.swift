//
//  Build28FixTests.swift
//  PixelHandCoreTests
//
//  The rules behind the build 28 fix round
//  (`Integration/LANE-build28-fixes.md`): the Type panel kept above the
//  keyboard in every orientation and on rotation (bug 6), numpad mode with
//  only the arrows and the numpad (bug 7), Accept in Live with a hardware
//  keyboard (bug 1), the rail's stack fitting the window (bug 2), and the
//  key editor's "Ask before running" line (bug 8).
//

import Foundation
import Testing
@testable import PixelHandCore

/// The windows the walks run in: full screen, safe area top inset, the
/// keyboard's height in that orientation.
private struct Window {
    let name: String
    let width: Double
    let height: Double
    let safeTop: Double
    let safeBottom: Double
    let keyboard: Double

    var keyboardFrame: PanelRect {
        PanelRect(x: 0, y: height - keyboard, width: width, height: keyboard)
    }

    var container: PanelRect {
        PanelRect(x: 0, y: safeTop, width: width, height: height - safeTop - safeBottom)
    }

    func geometry(keyboardTop: Double?) -> TypePanelGeometry {
        TypePanelGeometry(container: container, windowWidth: width, windowHeight: height, keyboardMinY: keyboardTop)
    }

    static let iPadPortrait = Window(name: "iPad Pro 11 portrait", width: 834, height: 1210, safeTop: 24, safeBottom: 20, keyboard: 380)
    static let iPadLandscape = Window(name: "iPad Pro 11 landscape", width: 1210, height: 834, safeTop: 24, safeBottom: 20, keyboard: 398)
    static let iPadAirLandscape = Window(name: "iPad Air 11 landscape", width: 1180, height: 820, safeTop: 24, safeBottom: 20, keyboard: 398)
    static let iPhonePortrait = Window(name: "iPhone 17 Pro portrait", width: 402, height: 874, safeTop: 62, safeBottom: 34, keyboard: 336)
    static let iPhoneLandscape = Window(name: "iPhone 17 Pro landscape", width: 874, height: 402, safeTop: 0, safeBottom: 21, keyboard: 209)

    static let all = [iPadPortrait, iPadLandscape, iPadAirLandscape, iPhonePortrait, iPhoneLandscape]
}

/// A frame turned a quarter: what a conversion against the wrong space
/// gives (x ↔ y, width ↔ height).
private func turned(_ rect: PanelRect) -> PanelRect {
    PanelRect(x: rect.y, y: rect.x, width: rect.height, height: rect.width)
}

@Suite("The keyboard's frame is read in the window as it is now (build 28 bug 6)")
struct KeyboardFrameReadingTests {
    @Test("A keyboard frame turned a quarter is not a keyboard; the right one is picked")
    func turnedIsRejected() {
        for window in Window.all {
            let right = window.keyboardFrame
            let wrong = turned(right)
            #expect(!KeyboardFrameReading.isPlausible(wrong, windowWidth: window.width, windowHeight: window.height), "\(window.name)")
            #expect(KeyboardFrameReading.isPlausible(right, windowWidth: window.width, windowHeight: window.height), "\(window.name)")
            let picked = KeyboardFrameReading.pick([wrong, right], windowWidth: window.width, windowHeight: window.height)
            #expect(picked == right, "\(window.name)")
            #expect(KeyboardFrameReading.read([wrong, right], windowWidth: window.width, windowHeight: window.height)
                == .covers(top: window.height - window.keyboard, overlap: window.keyboard), "\(window.name)")
        }
    }

    @Test("The landscape iPad keyboard, read wrong first, still puts its top at 436")
    func iPadLandscape() {
        let window = Window.iPadLandscape
        let reading = KeyboardFrameReading.read([turned(window.keyboardFrame), window.keyboardFrame], windowWidth: window.width, windowHeight: window.height)
        #expect(reading == .covers(top: 436, overlap: 398))
    }

    @Test("A hidden keyboard (below the window) and a floating one read as clear")
    func clear() {
        let window = Window.iPadLandscape
        let hidden = PanelRect(x: 0, y: window.height, width: window.width, height: 398)
        #expect(KeyboardFrameReading.read([hidden], windowWidth: window.width, windowHeight: window.height) == .clear)
        let floating = PanelRect(x: 400, y: 300, width: 320, height: 260)
        #expect(KeyboardFrameReading.read([floating], windowWidth: window.width, windowHeight: window.height) == .clear)
    }

    @Test("The slim keyboard bar is read as a short overlap (the dock's lift)")
    func bar() {
        let window = Window.iPadLandscape
        let bar = PanelRect(x: 0, y: window.height - 66, width: window.width, height: 66)
        #expect(KeyboardFrameReading.read([bar], windowWidth: window.width, windowHeight: window.height) == .covers(top: window.height - 66, overlap: 66))
        #expect(KeyboardKind.barLift(overlap: 66, bottomInset: 20) == 46)
    }

    @Test("Nothing that reads as a keyboard keeps the last reading")
    func nothing() {
        let window = Window.iPadLandscape
        #expect(KeyboardFrameReading.read([], windowWidth: window.width, windowHeight: window.height) == nil)
        #expect(KeyboardFrameReading.read([turned(window.keyboardFrame)], windowWidth: window.width, windowHeight: window.height) == nil)
        let nan = PanelRect(x: .nan, y: 0, width: 10, height: 1)
        #expect(KeyboardFrameReading.read([nan], windowWidth: window.width, windowHeight: window.height) == nil)
        #expect(KeyboardFrameReading.read([window.keyboardFrame], windowWidth: 0, windowHeight: 0) == nil)
        let above = PanelRect(x: 0, y: -500, width: window.width, height: 398)
        #expect(KeyboardFrameReading.read([above], windowWidth: window.width, windowHeight: window.height) == nil)
    }

    @Test("A portrait frame arriving after the window turned isn't read as a full keyboard in landscape")
    func staleOrientation() {
        // The portrait keyboard's Will notification read against the
        // landscape window: nearly all below it, so at most a sliver (not
        // a software keyboard) until the Did comes with the real frame.
        let portrait = Window.iPadPortrait.keyboardFrame
        let landscape = Window.iPadLandscape
        let reading = KeyboardFrameReading.read([portrait], windowWidth: landscape.width, windowHeight: landscape.height)
        switch reading {
        case let .covers(_, overlap)?:
            #expect(KeyboardKind.classify(overlap: overlap, hardwareAttached: false) == .none)
        case .clear?, nil:
            break
        }
    }
}

@Suite("The Type panel stays above the keyboard in every orientation (build 28 bug 6)")
struct TypePanelAboveKeyboardTests {
    static let places: [TypePanelPlacement] = [0.0, 0.5, 1.0].flatMap { x in
        [0.0, 0.5, 1.0].map { y in TypePanelPlacement(x: x, y: y) }
    }

    /// The panel's layout height for a window with the keyboard up.
    fileprivate static func panelHeight(_ window: Window, geometry: TypePanelGeometry, place: TypePanelPlacement, numpad: Bool = false) -> Double {
        TypePanelLayout(
            width: window.width, height: window.height,
            keyboard: .software, keyboardOverlap: window.keyboard,
            panelWidth: geometry.width(for: place), panelHeight: geometry.height(for: place),
            roomHeight: geometry.room.height, showsNumpad: numpad
        ).panelHeight
    }

    @Test("Every remembered place, both modes, numpad on and off: the panel ends above the keyboard")
    func everyPlace() {
        for window in Window.all {
            let top = window.height - window.keyboard
            let geometry = window.geometry(keyboardTop: top)
            for place in Self.places {
                for numpad in [false, true] {
                    let height = Self.panelHeight(window, geometry: geometry, place: place, numpad: numpad)
                    let frame = geometry.kept(geometry.frame(for: place, height: height))
                    let note = "\(window.name) \(place) numpad \(numpad) h\(height) room \(geometry.room)"
                    // The header (or, without one, the field row) is always in view.
                    #expect(frame.minY + 44 <= top, "\(note)")
                    if height <= geometry.room.height {
                        #expect(frame.maxY <= top - TypePanelGeometry.gap + 0.5, "\(note)")
                        #expect(geometry.fitsAbove(frame), "\(note)")
                    } else {
                        #expect(frame.minY == geometry.room.minY, "\(note)")
                    }
                }
            }
        }
    }

    @Test("A remembered place with a tall height shrinks to the room in landscape")
    func tallRemembered() {
        let window = Window.iPadLandscape
        let geometry = window.geometry(keyboardTop: window.height - window.keyboard)
        let place = TypePanelPlacement(x: 0.5, y: 1, width: 720, height: 600)
        let height = Self.panelHeight(window, geometry: geometry, place: place)
        #expect(height <= geometry.room.height)
        let frame = geometry.kept(geometry.frame(for: place, height: height))
        #expect(frame.maxY <= 436 - TypePanelGeometry.gap + 0.5)
    }

    @Test("A frame from before the keyboard came up, or before the window turned, is moved above it")
    func keptMovesNotResizes() {
        let window = Window.iPadLandscape
        let noKeyboard = window.geometry(keyboardTop: nil)
        let place = TypePanelPlacement.initial
        let before = noKeyboard.frame(for: place, height: 180)
        // Built with no keyboard: on the window's bottom, under where the
        // keyboard comes up.
        #expect(before.maxY > 436)
        let withKeyboard = window.geometry(keyboardTop: 436)
        let kept = withKeyboard.kept(before)
        #expect(kept.width == before.width && kept.height == before.height)
        #expect(kept.x == before.x)
        #expect(kept.maxY <= 436 - TypePanelGeometry.gap)
        // The rotation: a portrait frame kept in the landscape room.
        let portrait = Window.iPadPortrait.geometry(keyboardTop: nil).frame(for: place, height: 180)
        let turnedKept = withKeyboard.kept(portrait)
        #expect(withKeyboard.fitsAbove(turnedKept))
        #expect(turnedKept.minX >= withKeyboard.room.minX && turnedKept.maxX <= withKeyboard.room.maxX)
    }

    @Test("A panel taller than the room keeps its header in view")
    func tallerThanRoom() {
        let window = Window.iPhoneLandscape
        let geometry = window.geometry(keyboardTop: window.height - window.keyboard)
        let kept = geometry.kept(PanelRect(x: 100, y: 300, width: 600, height: 400))
        #expect(kept.minY == geometry.room.minY)
        #expect(kept.height == 400)
    }

    @Test("Docked panels are kept centred; NaN frames go to the room's corner")
    func dockedAndNaN() {
        let window = Window.iPhonePortrait
        let geometry = window.geometry(keyboardTop: window.height - window.keyboard)
        #expect(geometry.style == .docked)
        let kept = geometry.kept(PanelRect(x: 0, y: 900, width: 300, height: 200))
        #expect(abs(kept.midX - geometry.room.midX) <= 0.5)
        #expect(geometry.fitsAbove(kept))
        let nan = geometry.kept(PanelRect(x: .nan, y: .nan, width: 300, height: 200))
        #expect(nan.x == geometry.room.minX && nan.y == geometry.room.minY)
    }

    @Test("The remembered place itself is never rewritten by the keyboard")
    func placeUnchanged() {
        // `frame(for:)` and `kept` read the place; nothing writes it back,
        // so the corner comes back when the keyboard goes.
        let window = Window.iPadLandscape
        let place = TypePanelPlacement(x: 1, y: 1, width: 500)
        let up = window.geometry(keyboardTop: 436).kept(window.geometry(keyboardTop: 436).frame(for: place, height: 200))
        let down = window.geometry(keyboardTop: nil).frame(for: place, height: 200)
        #expect(up.maxX == down.maxX)
        #expect(up.maxY < down.maxY)
    }
}

@Suite("Numpad mode shows only the arrows and the numpad (build 28 bug 7, OT-11)")
struct NumpadOnlyTests {
    @Test("No key rows, no actions in Live; the arrows' grid matches their shape (the joystick's cells)")
    func onlyArrowsAndNumpad() {
        for width in stride(from: 304.0, through: 760, by: 8) {
            for keyboard in [KeyboardKind.none, .software, .hardware] {
                let layout = TypePanelLayout(width: 1180, height: 820, keyboard: keyboard, keyboardOverlap: keyboard == .software ? 398 : 0, panelWidth: width, showsNumpad: true, mode: .live)
                let note = "w\(width) \(keyboard)"
                #expect(layout.arrangement == .numpad, "\(note)")
                #expect(Set(layout.blocks.keys) == [.arrows, .numpad], "\(note)")
                #expect(!layout.shows(.keys), "\(note)")
                #expect(layout.actionCells.isEmpty, "\(note)")
                let arrows = layout.grid(.arrows)
                #expect(arrows?.columns == layout.arrowShape.columns, "\(note)")
                #expect(arrows?.rows == layout.arrowShape.rows, "\(note)")
                for cell in ArrowCluster.cells(for: layout.arrowShape) {
                    #expect(cell.column < (arrows?.columns ?? 0) && cell.row < (arrows?.rows ?? 0), "\(note)")
                }
                // The numpad and the arrows fill the panel's inner width.
                let inner = width - 2 * TypePanelLayout.padding
                let numpad = layout.grid(.numpad)
                #expect(abs(max(numpad?.rect.maxX ?? 0, arrows?.rect.maxX ?? 0) - inner) < 0.5, "\(note)")
                #expect((numpad?.cellWidth ?? 0) >= TypePanelLayout.keyPitch - 0.01 || inner < 8 * TypePanelLayout.keyPitch, "\(note)")
            }
        }
    }

    @Test("A narrow panel (test20's 362 pt) puts the arrows in one row over the numpad")
    func narrow() {
        let layout = TypePanelLayout(width: 1210, height: 834, keyboard: .software, keyboardOverlap: 398, panelWidth: 362, showsNumpad: true)
        #expect(layout.arrowShape == .row)
        let arrows = layout.grid(.arrows), numpad = layout.grid(.numpad)
        #expect(arrows?.rect.width == numpad?.rect.width)
        #expect((numpad?.rect.minY ?? 0) > (arrows?.rect.maxY ?? 0))
    }
}

@Suite("Live keeps Accept ⇥ in every band, on screen or hardware keyboard (build 28 bug 1, OT-13)")
struct LiveAcceptEverywhereTests {
    @Test("iPhone and iPad widths, every height, both keyboards")
    func everyBand() {
        let windows: [(Double, Double, Double)] = [(402, 874, 336), (874, 402, 209), (375, 667, 260), (1210, 834, 398), (834, 1210, 380)]
        for (w, h, overlap) in windows {
            for keyboard in [KeyboardKind.software, .hardware, .none] {
                let probe = TypePanelLayout(width: w, height: h, keyboard: keyboard, keyboardOverlap: keyboard == .software ? overlap : 0, mode: .live)
                for height in stride(from: probe.heightRange.lowerBound, through: probe.heightRange.upperBound, by: 8) {
                    let layout = TypePanelLayout(width: w, height: h, keyboard: keyboard, keyboardOverlap: keyboard == .software ? overlap : 0, panelHeight: height, mode: .live)
                    let note = "\(w)×\(h) \(keyboard) h\(height) \(layout.arrangement)"
                    #expect(layout.actionCells.contains { $0.action == .accept }, "\(note)")
                    #expect(layout.shows(.actions), "\(note)")
                }
            }
        }
    }

    @Test("With a hardware keyboard Live has Accept alone, spanning the column; Compose has none")
    func hardware() {
        let live = TypePanelLayout(width: 402, height: 874, keyboard: .hardware, mode: .live)
        #expect(live.body == .keysOnly)
        #expect(live.actionCells.map(\.action) == [.accept])
        if live.arrowShape == .invertedT {
            #expect(live.actionCells.first?.rowSpan == 2)
        }
        let compose = TypePanelLayout(width: 402, height: 874, keyboard: .hardware, mode: .compose)
        #expect(compose.actionCells.isEmpty)
        #expect(!compose.shows(.actions))
        // On screen nothing changes: Accept and Paste, one row each.
        let screen = TypePanelLayout(width: 1180, height: 820, keyboard: .software, keyboardOverlap: 400, panelWidth: 720, mode: .live)
        #expect(screen.actionCells.map(\.action) == [.accept, .paste])
        #expect(screen.actionCells.allSatisfy { $0.rowSpan == 1 })
    }
}

@Suite("The rail's stack fits the window (build 28 bug 2, VQ-105)")
struct RailStackTests {
    @Test("Tabs, Ask and the keyboard circle at full size in every iPhone landscape window")
    func fits() {
        // Landscape safe heights: 17 Pro Max, 17 Pro, SE (no home indicator inset), mini.
        for (width, height, available) in [(956.0, 440.0, 419.0), (874, 402, 381), (667, 375, 375), (812, 375, 354)] {
            let plan = CanvasPlan(width: width, height: height)
            guard plan.form == .rail else { continue }
            #expect(plan.railCarriesKeyboard)
            #expect(plan.railFits(availableHeight: available), "\(width)×\(height)")
            let spacing = plan.railSpacing(availableHeight: available)
            let tabs = plan.tabSurfacesIncludeDeck ? 3 : 2
            #expect(CanvasPlan.railStackHeight(tabs: tabs, carriesKeyboard: true, spacing: spacing) <= available, "\(width)×\(height)")
            #expect(spacing >= CanvasPlan.railMinimumSpacing && spacing <= CanvasPlan.railSpacing)
        }
    }

    @Test("Spacing is 12 with room, tightens on short windows, never under 4")
    func spacing() {
        let plan = CanvasPlan(width: 874, height: 402)
        #expect(plan.railSpacing(availableHeight: 381) == 12)
        let tabs = plan.tabSurfacesIncludeDeck ? 3 : 2
        let tight = CanvasPlan.railStackHeight(tabs: tabs, carriesKeyboard: true, spacing: 6)
        #expect(plan.railSpacing(availableHeight: tight) == 6)
        #expect(plan.railSpacing(availableHeight: 100) == 4)
        #expect(plan.railSpacing(availableHeight: .nan) == 12)
        let expected: Double = 162 + 4 + 8 + 124 + 24 // three tabs, two gaps, padding, two circles, two spacings
        #expect(CanvasPlan.railStackHeight(tabs: 3, carriesKeyboard: true) == expected)
    }
}

@Suite("Ask before running in the key editor (build 28 bug 8, OT-8)")
struct KeyEditorAsksFirstTests {
    @Test("Typed keys ask first, locked, with why; other keys follow the switch")
    func typed() {
        let typed = DeckKey(id: "t", label: "YouTube", action: .typeText(text: "youtube"))
        #expect(typed.asksFirst)
        #expect(typed.asksFirstLockReason != nil)
        #expect(typed.asksFirstFootnote == typed.asksFirstLockReason)

        let sequence = DeckKey(id: "s", label: "Search", action: .sequence(steps: [
            .run(action: .launchApp(bundleID: "com.apple.Safari")),
            .run(action: .typeText(text: "youtube")),
        ]))
        #expect(sequence.asksFirst)
        #expect(sequence.asksFirstLockReason != nil)

        var plain = DeckKey(id: "c", label: "Copy", action: .shortcut(keys: ["cmd", "c"]))
        #expect(!plain.asksFirst)
        #expect(plain.asksFirstLockReason == nil)
        #expect(!plain.asksFirstFootnote.isEmpty)
        plain.confirm = true
        #expect(plain.asksFirst)
    }
}
