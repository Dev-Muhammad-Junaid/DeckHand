//
//  ShellChromePlanTests.swift
//  PixelHandCoreTests
//
//  Build 18 visual QA fitting rules: the header folds its circles before
//  the Mac pill truncates, the deck header goes to two rows before a
//  button wraps, the dock shows whole icons, and the mirror strip drops
//  whole segments (name first).
//

import Foundation
import PixelHandCore
import Testing

@Suite struct ShellChromePlanTests {
    // MARK: Header

    @Test("Wide windows keep every header circle")
    func headerFull() {
        #expect(ShellHeaderPlan.actions(width: 1180, horizontalPadding: 0, circles: 3, reserved: 400) == .full)
        #expect(ShellHeaderPlan.actions(width: 820, horizontalPadding: 20, circles: 4, reserved: 200) == .full)
    }

    @Test("iPhone portrait keeps the pill, capture and More (VQ-032)")
    func headerPhone() {
        #expect(ShellHeaderPlan.actions(width: 402, horizontalPadding: 16, circles: 4) == .captureAndMore)
        #expect(ShellHeaderPlan.actions(width: 375, horizontalPadding: 16, circles: 4) == .captureAndMore)
    }

    @Test("A Stage Manager window at iPhone width folds the circles (VQ-081)")
    func headerStageManager() {
        #expect(ShellHeaderPlan.actions(width: 375, horizontalPadding: 16, circles: 3, reserved: 40) == .captureAndMore)
        #expect(ShellHeaderPlan.actions(width: 300, horizontalPadding: 16, circles: 3) == .moreOnly)
    }

    @Test("The pill always keeps its minimum width beside the circles that stay")
    func headerPillMinimum() {
        for width in stride(from: 280.0, through: 1200, by: 7) {
            for circles in 0...4 {
                let plan = ShellHeaderPlan.actions(width: width, horizontalPadding: 16, circles: circles)
                let shown: Int = switch plan {
                case .full: circles + 1
                case .captureAndMore: 2
                case .moreOnly: 1
                }
                if plan != .moreOnly {
                    #expect(width - 32 - Double(shown) * ShellHeaderPlan.circleSlot >= ShellHeaderPlan.pillMinimumWidth)
                }
            }
        }
    }

    @Test("At the Huge band the header is the Mac pill and one menu (VQ-065)")
    func headerHuge() {
        #expect(ShellHeaderPlan.actions(width: 1180, horizontalPadding: 0, circles: 3, band: .huge) == .moreOnly)
        #expect(ShellHeaderPlan.pillNameLines(band: .huge) == 2)
        #expect(ShellHeaderPlan.pillNameLines(band: .large) == 1)
        #expect(ShellHeaderPlan.pillNameLines(band: .standard) == 1)
    }

    @Test("The pill name breaks only between words, best split first, never mid-word (build 19, VQ-065)")
    func pillNameBreaksAtWords() {
        let name = "Muhammad’s MacBook Pro"
        #expect(ShellHeaderPlan.pillNameCandidates(name, lines: 1) == [[name]])
        let two = ShellHeaderPlan.pillNameCandidates(name, lines: 2)
        #expect(two == [
            [name],
            ["Muhammad’s MacBook", "Pro"],
            ["Muhammad’s", "MacBook Pro"],
        ])
        // Every line is made of whole words of the name, in order.
        let words = name.split(separator: " ").map(String.init)
        for candidate in two {
            #expect(candidate.joined(separator: " ") == name)
            for line in candidate {
                #expect(line.split(separator: " ").allSatisfy { words.contains(String($0)) })
                #expect(!line.hasSuffix("-"))
            }
        }
        // The fallback (last) keeps the first word whole on its own line.
        #expect(two.last?.first == "Muhammad’s")
    }

    @Test("Odd names: one word, extra spaces, hyphens kept inside a word")
    func pillNameOddNames() {
        #expect(ShellHeaderPlan.pillNameCandidates("Studio", lines: 2) == [["Studio"]])
        #expect(ShellHeaderPlan.pillNameCandidates("  Office   iMac ", lines: 2) == [["Office iMac"], ["Office", "iMac"]])
        #expect(ShellHeaderPlan.pillNameCandidates("Jean-Luc’s Mac", lines: 2) == [["Jean-Luc’s Mac"], ["Jean-Luc’s", "Mac"]])
        #expect(ShellHeaderPlan.pillNameCandidates("", lines: 2) == [[""]])
    }

    // MARK: Deck header

    @Test("The iPad deck columns get two header rows (VQ-024)")
    func deckHeaderColumns() {
        // iPad portrait: 300 column, 12 inset each side.
        #expect(!DeckHeaderPlan(width: 276, band: .standard, pageCount: 2).isOneRow)
        // iPad landscape: 336 column, 12 inset each side.
        #expect(!DeckHeaderPlan(width: 312, band: .standard, pageCount: 2).isOneRow)
        // iPhone portrait Deck tab.
        #expect(DeckHeaderPlan(width: 402, band: .standard, pageCount: 2).isOneRow)
    }

    @Test("Large and Huge bands always use two header rows (VQ-065)")
    func deckHeaderBands() {
        #expect(!DeckHeaderPlan(width: 1000, band: .large, pageCount: 1).isOneRow)
        let huge = DeckHeaderPlan(width: 1000, band: .huge, pageCount: 3)
        #expect(!huge.isOneRow)
        #expect(huge.undoIsGlyphOnly)
        #expect(!DeckHeaderPlan(width: 402, band: .standard, pageCount: 1).undoIsGlyphOnly)
    }

    @Test("The counter shows only with two or more pages")
    func deckHeaderCounter() {
        #expect(!DeckHeaderPlan(width: 402, band: .standard, pageCount: 1).showsCounter)
        #expect(DeckHeaderPlan(width: 402, band: .standard, pageCount: 2).showsCounter)
    }

    @Test("The subtitle never repeats the page number (VQ-082)")
    func deckHeaderSubtitle() {
        #expect(DeckHeaderPlan.subtitle(isPinned: true, followsApp: true, followingOn: true) == "Pinned")
        #expect(DeckHeaderPlan.subtitle(isPinned: false, followsApp: true, followingOn: true) == "Follows the front app")
        #expect(DeckHeaderPlan.subtitle(isPinned: false, followsApp: false, followingOn: false) == "Following off")
        #expect(DeckHeaderPlan.subtitle(isPinned: false, followsApp: false, followingOn: true) == nil)
        for pinned in [true, false] {
            for follows in [true, false] {
                for on in [true, false] {
                    let text = DeckHeaderPlan.subtitle(isPinned: pinned, followsApp: follows, followingOn: on) ?? ""
                    #expect(!text.lowercased().contains("page"))
                }
            }
        }
    }

    // MARK: Dock

    @Test("The dock row holds whole slots only (VQ-039)")
    func dockWholeSlots() {
        for available in stride(from: 60.0, through: 900, by: 13) {
            let row = AppDockFit.row(available: available, count: 40)
            let content = row.width - 2 * AppDockFit.inset
            let slots = (content + AppDockFit.spacing) / (AppDockFit.slot + AppDockFit.spacing)
            #expect(slots == slots.rounded())
            #expect(row.width <= max(available, 2 * AppDockFit.inset + AppDockFit.slot))
            #expect(row.overflows)
        }
    }

    @Test("A short app list neither overflows nor stretches")
    func dockFewApps() {
        let row = AppDockFit.row(available: 600, count: 3)
        #expect(row.slots == 3)
        #expect(!row.overflows)
        let expected: Double = 24 + 132 + 16
        #expect(row.width == expected)
    }

    @Test("iPad mini portrait: the dock's last icon is whole")
    func dockIPadMini() {
        // 744 wide, 20 margins, Ask circle 44 + 12 gap, keyboard 44 + hairline 9 + 12.
        let available: Double = 744 - 161
        let row = AppDockFit.row(available: available, count: 14)
        #expect(row.slots == 10)
        #expect(row.overflows)
    }

    // MARK: Mirror strip

    @Test("The mirror strip drops the Mac's name before its status (VQ-038)")
    func stripCandidates() {
        let candidates = MirrorPaneChrome.stripCandidates(["MUHAMMADS MACBOOK", "DESK 1/2", "20 FPS"])
        #expect(candidates == [
            ["MUHAMMADS MACBOOK", "DESK 1/2", "20 FPS"],
            ["MUHAMMADS", "DESK 1/2", "20 FPS"],
            ["DESK 1/2", "20 FPS"],
            ["DESK 1/2"],
        ])
        #expect(MirrorPaneChrome.stripCandidates(["AIR"]) == [["AIR"]])
        #expect(MirrorPaneChrome.stripCandidates([]) == [])
    }

    @Test("Before the first frame the strip says CONNECTING, never 0 FPS (VQ-062)")
    func stripConnecting() {
        let strip = MirrorPaneChrome.paneStrip(
            macName: "Studio", displays: [], mirroredDisplayID: nil, windowTitle: nil,
            mirroringWindow: false, spaces: .unknown, host: nil,
            client: MirrorClientStats(receivedFPS: 0, displayedFPS: 0, droppedFrames: 0, decodeMilliseconds: 0, kilobitsPerSecond: 0),
            hasFrame: false
        )
        #expect(strip.items == ["STUDIO", "CONNECTING"])
        #expect(!strip.items.contains { $0.contains("FPS") })
    }
}
