//
//  DuoLayoutTests.swift
//  PixelHandCoreTests
//
//  UX-040 iPhone Duo: the pose from the system's division or from size,
//  the crease keep-out band, the panes either side and the plan forms
//  (`Product/Design/03-Layout-Strategy.md`, `07-Polish-Spec.md` §1, §7).
//

import Testing
@testable import PixelHandCore

@Suite("Duo layout")
struct DuoLayoutTests {
    // QA sizes: cover 466 × 678, book 951 × 669, laptop 669 × 951.

    @Test("Inference: the inner display on a phone is book or laptop, the cover is not open")
    func inferredPoses() {
        let book = DuoPoseMachine.band(for: DuoPoseInput(width: 951, height: 669, isPhone: true))
        #expect(book?.axis == .vertical)
        #expect(book?.start == 455.5)
        #expect(book?.end == 495.5)
        #expect(book?.fromSystem == false)

        let laptop = DuoPoseMachine.band(for: DuoPoseInput(width: 669, height: 951, isPhone: true))
        #expect(laptop?.axis == .horizontal)
        #expect(laptop?.width == DuoPoseMachine.minimumBandWidth)

        // Cover, iPhone portrait, iPhone landscape (short): no crease.
        for (w, h) in [(466.0, 678.0), (402, 874), (440, 956), (874, 402), (956, 440)] {
            #expect(DuoPoseMachine.band(for: DuoPoseInput(width: w, height: h, isPhone: true)) == nil, "\(w) × \(h)")
        }
    }

    @Test("Inference never runs on iPad windows of the same size")
    func noInferenceOnIPad() {
        for (w, h) in [(951.0, 669.0), (669, 951), (1180, 820), (820, 1180)] {
            #expect(DuoPoseMachine.band(for: DuoPoseInput(width: w, height: h, isPhone: false)) == nil)
        }
    }

    @Test("The inferred crease follows the window's centre, not the safe area's")
    func windowCentre() {
        // Laptop inside the safe area: 54 pt status bar, 34 pt home indicator.
        let input = DuoPoseInput(width: 669, height: 863, windowCentre: (x: 334.5, y: 475.5 - 54), isPhone: true)
        let band = DuoPoseMachine.band(for: input)
        #expect(band?.axis == .horizontal)
        #expect(band?.centre == 421.5)
    }

    @Test("The system's division wins and is widened to the 40 pt band")
    func systemDivision() {
        // A 2 pt hairline: widened to 20 pt each side of its centre line.
        let thin = DuoPoseInput(width: 951, height: 669, division: DuoRect(x: 474.5, y: 0, width: 2, height: 669), isPhone: true)
        let band = DuoPoseMachine.band(for: thin)
        #expect(band?.fromSystem == true)
        #expect(band?.start == 455.5)
        #expect(band?.end == 495.5)

        // A wider division (frame plus margins) is kept as is.
        let wide = DuoPoseInput(width: 951, height: 669, division: DuoRect(x: 445, y: 0, width: 61, height: 669), isPhone: true)
        #expect(DuoPoseMachine.band(for: wide)?.start == 445)
        #expect(DuoPoseMachine.band(for: wide)?.end == 506)

        // Horizontal division → laptop, even off-phone (system is authoritative).
        let flat = DuoPoseInput(width: 669, height: 951, division: DuoRect(x: 0, y: 455, width: 669, height: 41), isPhone: false)
        #expect(DuoPoseMachine.band(for: flat)?.axis == .horizontal)
    }

    @Test("Hinge closed means the cover display, whatever the size")
    func hingeClosed() {
        let input = DuoPoseInput(width: 951, height: 669, hingeStatus: .closed, isPhone: true)
        #expect(DuoPoseMachine.band(for: input) == nil)
    }

    @Test("A crease that leaves a pane under 320 pt is ignored")
    func paneTooSmall() {
        let input = DuoPoseInput(width: 951, height: 669, division: DuoRect(x: 200, y: 0, width: 40, height: 669), isPhone: true)
        #expect(DuoPoseMachine.band(for: input) == nil)
    }

    @Test("The state machine: none until a crease shows, then folded on the cover")
    func stateMachine() {
        var machine = DuoPoseMachine()
        #expect(machine.update(DuoPoseInput(width: 466, height: 678, isPhone: true)) == nil)
        #expect(machine.pose == .none)

        let open = machine.update(DuoPoseInput(width: 951, height: 669, isPhone: true))
        #expect(machine.pose == .book)
        #expect(open?.isFold == true)

        let rotate = machine.update(DuoPoseInput(width: 669, height: 951, isPhone: true))
        #expect(machine.pose == .laptop)
        #expect(rotate?.isRotation == true)
        #expect(rotate?.isFold == false)

        // Same pose again: no transition.
        #expect(machine.update(DuoPoseInput(width: 669, height: 951, isPhone: true)) == nil)

        let close = machine.update(DuoPoseInput(width: 466, height: 678, isPhone: true))
        #expect(machine.pose == .folded)
        #expect(close?.isFold == true)
        #expect(machine.band == nil)
        #expect(machine.hasSeenCrease)
    }

    @Test("Book panes meet the band: 455 | 40 crease | 455, nothing on the crease")
    func bookPanes() {
        let band = DuoPoseMachine.band(for: DuoPoseInput(width: 951, height: 669, isPhone: true))!
        let panes = DuoPanes(width: 951, height: 669, band: band)
        #expect(panes.pose == .book)
        #expect(panes.first == DuoRect(x: 0, y: 0, width: 455, height: 669))
        #expect(panes.second == DuoRect(x: 496, y: 0, width: 455, height: 669))
        #expect(panes.keepsClear(panes.first))
        #expect(panes.keepsClear(panes.second))
        // Each pane is its own compact grid (4 keys).
        #expect(panes.firstMetrics.widthClass == .compact)
        #expect(panes.secondMetrics.deckColumns == 4)
        // 20 pt clear each side of the crease's centre line.
        #expect(panes.crease.minX <= 475.5 - 20)
        #expect(panes.crease.maxX >= 475.5 + 20)
    }

    @Test("Laptop panes: screen above the crease, controls below")
    func laptopPanes() {
        let band = DuoPoseMachine.band(for: DuoPoseInput(width: 669, height: 951, isPhone: true))!
        let panes = DuoPanes(width: 669, height: 951, band: band)
        #expect(panes.pose == .laptop)
        #expect(panes.first.height == 455)
        #expect(panes.second.minY == 496)
        #expect(panes.second.height == 455)
        #expect(!panes.keepsClear(DuoRect(x: 0, y: 470, width: 100, height: 10)))
        // The bottom pane holds a pad above its click-strip minimum.
        #expect(panes.second.height > PointerSurfaceLayout.minimumPadHeightForStrip)
    }

    @Test("CanvasPlan with a crease becomes book or laptop instead of columns or stacked")
    func canvasPlanForms() {
        let bookBand = DuoPoseMachine.band(for: DuoPoseInput(width: 951, height: 669, isPhone: true))
        let book = CanvasPlan(width: 951, height: 669, crease: bookBand)
        #expect(book.form == .book)
        #expect(book.isDuoOpen)
        #expect(!book.showsSidebar)
        #expect(!book.usesPresets)
        #expect(book.showsTabBar)
        #expect(book.hasDeckColumn)
        #expect(!book.tabSurfacesIncludeDeck)
        #expect(book.deckColumnKeys == 4)

        let laptopBand = DuoPoseMachine.band(for: DuoPoseInput(width: 669, height: 951, isPhone: true))
        let laptop = CanvasPlan(width: 669, height: 951, crease: laptopBand)
        #expect(laptop.form == .laptop)
        #expect(laptop.foldsDockIntoStrip)
        #expect(!laptop.usesPresets)

        // Without a crease the old forms stay (iPad, older SDK fallbacks).
        #expect(CanvasPlan(width: 951, height: 669).form == .columns)
        #expect(CanvasPlan(width: 669, height: 951).form == .stacked)
        #expect(CanvasPlan(width: 951, height: 669).duoPanes == nil)
    }

    @Test("The selected tab picks the book's leading pane and the laptop's bottom")
    func arrangementChoices() {
        #expect(DuoArrangement.bookLead(selected: "screen") == .screenOverPointer)
        #expect(DuoArrangement.bookLead(selected: "pointer") == .pointer)
        #expect(DuoArrangement.bookLead(selected: "deck") == .pointer)
        #expect(DuoArrangement.laptopBottomShowsDeck(selected: "deck"))
        #expect(!DuoArrangement.laptopBottomShowsDeck(selected: "screen"))
    }
}
