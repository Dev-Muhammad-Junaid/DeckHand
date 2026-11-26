//
//  Owner27Tests.swift
//  PixelHandCoreTests
//
//  Owner testing, build 27 (OT-14 to OT-18): badge placement, the Send
//  sheet's cards sized to the names, one sheet size for both tabs, the
//  floating card on iPad, and the header's ⌘K button.
//

import Foundation
import Testing
@testable import PixelHandCore

@Suite("Control badge placement (OT-14)")
struct ControlBadgePlacementTests {
    typealias P = ControlBadgePlacement

    @Test("Every badge kind is sized on the 4 pt grid")
    func sizesOnGrid() {
        let kinds: [ControlBadgeKind] = [.dot, .live, .needsYou, .offLight, .proLock, .proLockSmall, .proLabel, .count(3), .count(42), .count(250)]
        for kind in kinds {
            #expect(kind.size.width.truncatingRemainder(dividingBy: 4) == 0, "\(kind)")
            #expect(kind.size.height.truncatingRemainder(dividingBy: 4) == 0, "\(kind)")
        }
        #expect(ControlBadgeKind.countText(250) == "99+")
        #expect(ControlBadgeKind.countText(7) == "7")
    }

    @Test("Frames land on the 4 pt grid for every shape, corner and anchor")
    func framesOnGrid() {
        let shapes: [P.Shape] = [.circle, .capsule, .roundedRect(radius: 14), .roundedRect(radius: 24), .rect]
        let controls = [P.Size(width: 44, height: 44), P.Size(width: 36, height: 36), P.Size(width: 80, height: 44), P.Size(width: 175, height: 44)]
        let kinds: [ControlBadgeKind] = [.dot, .proLock, .proLabel, .count(12)]
        for shape in shapes {
            for control in controls {
                for corner in P.Corner.allCases {
                    for anchor in [P.Anchor.rim, .inset(4), .inset(6)] {
                        for kind in kinds {
                            let f = P.frame(kind, control: control, shape: shape, corner: corner, anchor: anchor)
                            #expect(f.x.truncatingRemainder(dividingBy: 4) == 0)
                            #expect(f.y.truncatingRemainder(dividingBy: 4) == 0)
                        }
                    }
                }
            }
        }
    }

    @Test("The header circle's unseen dot straddles the rim, top trailing (build 27's Send dot)")
    func dotOnCircleRim() {
        let control = P.Size(width: 44, height: 44)
        let f = P.frame(.dot, control: control, shape: .circle, corner: .topTrailing)
        #expect(f == .init(x: 32, y: 4, width: 8, height: 8))
        let rim = P.rimPoint(control: control, shape: .circle, corner: .topTrailing)
        #expect(f.contains(x: rim.x, y: rim.y), "the dot covers the rim, so it reads as on the button's edge")
        // Part of it is off the glass: a corner of the dot lies outside the circle.
        let dx = f.maxX - 22
        let dy = 22 - f.y
        #expect((dx * dx + dy * dy).squareRoot() > 22)
    }

    @Test("The Pro lock sits on a circle's bottom-trailing rim and hangs past the glass")
    func lockOnCircleRim() {
        let f = P.frame(.proLock, control: .init(width: 44, height: 44), shape: .circle, corner: .bottomTrailing)
        #expect(f == .init(x: 28, y: 28, width: 20, height: 20))
        #expect(f.maxX > 44 && f.maxY > 44, "outside the clip shape, so nothing may clip it")
    }

    @Test("Rim points: circle, capsule and rounded rectangle corners")
    func rimPoints() {
        let c = P.rimPoint(control: .init(width: 44, height: 44), shape: .circle, corner: .topLeading)
        #expect(abs(c.x - (22 - 22 / 2.0.squareRoot())) < 0.001)
        #expect(abs(c.y - c.x) < 0.001)
        // A capsule's trailing end.
        let cap = P.rimPoint(control: .init(width: 100, height: 44), shape: .capsule, corner: .topTrailing)
        #expect(abs(cap.x - (78 + 22 / 2.0.squareRoot())) < 0.001)
        // A rect's corner is the corner.
        let r = P.rimPoint(control: .init(width: 40, height: 20), shape: .rect, corner: .bottomTrailing)
        #expect(r.x == 40 && r.y == 20)
        // A circle in a wide frame is centred in it.
        let wide = P.rimPoint(control: .init(width: 64, height: 44), shape: .circle, corner: .topTrailing)
        #expect(abs(wide.x - (32 + 22 / 2.0.squareRoot())) < 0.001)
    }

    @Test("Inset badges stay inside the tile, a step from the corner")
    func insetStaysInside() {
        let tile = P.Size(width: 44, height: 44)
        let f = P.frame(.proLabel, control: tile, shape: .roundedRect(radius: 14), corner: .topTrailing, anchor: .inset(4))
        #expect(f.x >= 0 && f.maxX <= 44 && f.y >= 0)
        #expect(f == .init(x: 0, y: 4, width: 40, height: 20))
        let lock = P.frame(.proLock, control: .init(width: 44, height: 28), shape: .roundedRect(radius: 8), corner: .bottomTrailing, anchor: .inset(0))
        #expect(lock.maxX == 44 && lock.maxY <= 28)
    }
}

@Suite("Send cards sized to the names (OT-16)")
struct SendCardGridTests {
    typealias L = SendSheetLayout

    /// About 7.6 pt a character in subheadline semibold, 4 pt a space.
    private func name(_ text: String) -> L.NameMeasure {
        .init(words: text.split(separator: " ").map { Double($0.count) * 7.6 }, space: 4)
    }

    @Test("Short names keep three columns of one-line, 64 pt cards on a wide sheet")
    func shortNames() {
        let grid = L.cardGrid(width: 560, names: [name("Mini"), name("Air")])
        #expect(grid.columns == 3)
        #expect(grid.cardHeight == 64)
        #expect(grid.nameLines == 1)
    }

    @Test("Build 27's \"Muhammad Junaid's MacBook Pro\" gets a card wide enough for the whole name on two lines")
    func longNameWraps() {
        let long = name("Muhammad Junaid's MacBook Pro")
        let grid = L.cardGrid(width: 512, names: [long, name("Studio")])
        #expect(grid.columns < 3)
        let textWidth = L.cardTextWidth(cardWidth: grid.cardWidth)
        #expect(L.nameLines(long, textWidth: textWidth) <= 2)
        #expect(grid.cardHeight == 80, "two-line names make the cards 80 tall")
        #expect(grid.cardHeight.truncatingRemainder(dividingBy: 4) == 0)
    }

    @Test("Cards stay in the column grid: whole points, gaps included, never wider than the row")
    func withinGrid() {
        for width in stride(from: 200.0, through: 560, by: 13) {
            for names in [[name("Studio")], [name("AH's Mac mini")], [name("Muhammad Junaid's MacBook Pro"), name("AH's Mac mini")]] {
                let grid = L.cardGrid(width: width, names: names)
                #expect(grid.columns >= 1 && grid.columns <= L.columns(width: width))
                #expect(grid.cardWidth == grid.cardWidth.rounded(.down))
                let used = grid.cardWidth * Double(grid.columns) + L.cardGap * Double(grid.columns - 1)
                #expect(used <= width)
                #expect(width - used < Double(grid.columns))
            }
        }
    }

    @Test("Offline Macs count: their names decide the grid too")
    func offlineNamesCount() {
        let live = L.cardGrid(width: 512, names: [name("Studio")])
        let both = L.cardGrid(width: 512, names: [name("Studio"), name("Muhammad Junaid's MacBook Pro")])
        #expect(both.columns <= live.columns)
    }

    @Test("Name lines wrap between words like the text: one, two, or too many")
    func nameLines() {
        #expect(L.nameLines(.init(words: [20, 26], space: 4), textWidth: 60) == 1)
        #expect(L.nameLines(.init(words: [40, 40], space: 4), textWidth: 60) == 2)
        #expect(L.nameLines(.init(words: [30, 30, 30, 30], space: 4), textWidth: 60) == 3, "four 30s: two a line only with no space")
        #expect(L.nameLines(.init(words: [28, 28, 28, 28], space: 4), textWidth: 60) == 2)
        #expect(L.nameLines(.init(words: [70], space: 4), textWidth: 60) == 3, "a word wider than the line")
        #expect(L.nameLines(.init(words: [10], space: 4), textWidth: 0) == 3)
        #expect(L.nameLines(.init(words: [], space: 4), textWidth: 60) == 1)
        #expect(L.NameMeasure(words: [10, 20], space: 4).width == 34)
    }

    @Test("A name too long for any column falls back to one column (and truncates there)")
    func tooLong() {
        let huge = L.NameMeasure(words: Array(repeating: 120, count: 16), space: 4)
        let grid = L.cardGrid(width: 343, names: [huge])
        #expect(grid.columns == 1)
        #expect(grid.nameLines == 2)
    }

    @Test("The estimate uses the name grid's height and columns")
    func estimateUsesGrid() {
        let content = L.SendContent(cardCount: 2, offlineCount: 1)
        let grid = L.cardGrid(width: 512, names: [name("Muhammad Junaid's MacBook Pro"), name("Studio"), name("AH's Mac mini")])
        let plain = L.estimatedSendHeight(content, width: 512)
        let sized = L.estimatedSendHeight(content, width: 512, grid: grid)
        #expect(sized > plain)
    }
}

@Suite("Send source chips look alike (OT-17)")
struct SendSourceChipStyleTests {
    typealias C = SendSheetLayout.SourceChip

    @Test("Icon and label share one colour, readable on the chip in light and dark, high contrast too")
    func readable() {
        for dark in [false, true] {
            for high in [false, true] {
                let bg = C.background.swatch(dark: dark, highContrast: high).color
                let fg = C.foreground.swatch(dark: dark, highContrast: high).resolved(over: bg)
                #expect(RGBColor.contrast(fg, bg) >= 4.5, "dark \(dark), high \(high)")
            }
        }
        #expect(C.foreground != PaletteTokens.accent, "no accent text: build 27's Paste chip was the odd one out")
    }

    @Test("Chip size and radius match the source chip spec")
    func size() {
        #expect(C.height == SendSheetLayout.chipHeight)
        #expect(C.height == 44)
        #expect(C.cornerRadius == 14)
        #expect(Set([C.photosSymbol, C.filesSymbol, C.pasteSymbol]).count == 3)
    }
}

@Suite("Send / Inbox sheet: one size, centred (OT-15)")
struct SendSheetFloatingTests {
    typealias L = SendSheetLayout

    @Test("Both tabs use the taller content, so switching never resizes the sheet")
    func sharedHeight() {
        let send = 236.0
        let inbox = L.estimatedInboxHeight(arriving: 0, items: 0)
        let shared = L.sharedContentHeight(send: send, inbox: inbox)
        #expect(shared == max(send, inbox))
        #expect(L.sheetHeight(content: L.sharedContentHeight(send: send, inbox: inbox), container: 820)
            == L.sheetHeight(content: L.sharedContentHeight(send: inbox, inbox: send), container: 820))
        #expect(L.sharedContentHeight(send: .nan, inbox: 100) == 100)
    }

    @Test("iPad Air 11\" landscape: the card is centred on the window, 560 wide, on the grid")
    func centredLandscape() {
        let f = L.floatingFrame(content: 280, containerWidth: 1180, containerHeight: 820)
        #expect(f.width == 560)
        #expect(f.height == 340)
        #expect(f.x == 310 && f.y == 240)
        #expect(abs((f.x + f.width / 2) - 590) <= 0.5)
        #expect(abs((f.y + f.height / 2) - 410) <= 0.5)
        #expect(f.height.truncatingRemainder(dividingBy: 4) == 0)
    }

    @Test("Centred and clear of the edges in every window, keyboard up or not")
    func centredEverywhere() {
        let windows: [(Double, Double)] = [(1180, 820), (820, 1180), (1180, 420), (834, 1194), (1366, 1024), (507, 820), (320, 700), (1024, 380)]
        for (w, h) in windows {
            for content in [0.0, 200, 280, 600, 2000] {
                let f = L.floatingFrame(content: content, containerWidth: w, containerHeight: h)
                #expect(abs((f.x + f.width / 2) - w / 2) <= 1, "centred across \(w)")
                #expect(abs((f.y + f.height / 2) - h / 2) <= 1, "centred down \(h)")
                #expect(f.width <= L.floatingWidth)
                #expect(f.height >= L.minimumHeight)
                if w >= L.minimumHeight + 2 * L.floatingClearance {
                    #expect(f.x >= L.floatingClearance - 1)
                }
                if h >= L.minimumHeight + 2 * L.floatingClearance {
                    #expect(f.y >= L.floatingClearance - 1)
                }
                #expect(f.width.truncatingRemainder(dividingBy: 4) == 0)
                #expect(f.height.truncatingRemainder(dividingBy: 4) == 0)
            }
        }
    }

    @Test("Tall content stops at the window less its clearance and scrolls")
    func overflow() {
        let f = L.floatingFrame(content: 2000, containerWidth: 1180, containerHeight: 820)
        #expect(f.height == 772)
        #expect(L.floatingOverflows(content: 2000, containerHeight: 820))
        #expect(!L.floatingOverflows(content: 280, containerHeight: 820))
    }
}

@Suite("Header ⌘K button (OT-18)")
struct HeaderAskButtonTests {
    @Test("Idle, open in the column, lit while its field has focus")
    func states() {
        #expect(HeaderAskButton.state(columnShowsAsk: false, fieldFocused: false) == .idle)
        #expect(HeaderAskButton.state(columnShowsAsk: false, fieldFocused: true) == .idle, "a focused field elsewhere isn't Ask")
        #expect(HeaderAskButton.state(columnShowsAsk: true, fieldFocused: false) == .open)
        #expect(HeaderAskButton.state(columnShowsAsk: true, fieldFocused: true) == .active)
        #expect(HeaderAskButton.State.active.isLit)
        #expect(!HeaderAskButton.State.open.isLit)
        #expect(HeaderAskButton.State.open.isSelected)
        #expect(!HeaderAskButton.State.idle.isSelected)
        #expect(HeaderAskButton.State.idle.spokenValue.isEmpty)
    }

    @Test("⌘K still runs Ask; tooltip and chord; sizes on the grid")
    func shortcut() {
        #expect(HeaderAskButton.command == .ask)
        #expect(HeaderAskButton.key == "k")
        #expect(HeaderAskButton.tooltip == "Ask (⌘K)")
        #expect(HeaderAskButton.chord == "⌘K")
        #expect(HeaderAskButton.width.truncatingRemainder(dividingBy: 4) == 0)
        #expect(HeaderAskButton.width < 120, "compact: far narrower than the field it replaces")
    }

    @Test("The header with the ⌘K button keeps every circle on an iPad Air 11\" landscape centre column")
    func headerFits() {
        // Centre column of the columns layout: about 1180 − sidebar − right column.
        let reserved = 168 + HeaderAskButton.reservedWidth
        let fit = ShellHeaderPlan.actions(width: 620, horizontalPadding: 0, circles: 2, reserved: reserved)
        #expect(fit == .full)
    }
}
