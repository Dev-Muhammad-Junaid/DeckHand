//
//  MirrorSpaceStripTests.swift
//  PixelHandCoreTests
//
//  The desktop dots under the mirror and the ‹ › states, from the Mac's
//  display snapshot; and where the "Cursor on …" badge reads the pointer's
//  display from.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct MirrorSpaceStripTests {
    static func display(_ id: UInt32, main: Bool = false, spaces: [SpaceInfo]?, current: Int?) -> DisplaySpaces {
        DisplaySpaces(
            displayID: id, name: "D\(id)", isMain: main,
            bounds: DisplayBounds(x: Double(id) * 100, y: 0, width: 100, height: 100),
            spaces: spaces, currentSpaceIndex: current
        )
    }

    static func layout(_ displays: [DisplaySpaces], known: Bool = true, cursor: UInt32? = nil) -> DisplayLayout {
        DisplayLayout(displays: displays, cursorDisplayID: cursor, spacesKnown: known, separateSpaces: true)
    }

    static let twoDisplays = layout([
        display(2, main: true, spaces: [.desktop], current: 0),
        display(1, spaces: [.desktop, .desktop, SpaceInfo(kind: .fullScreen, appName: "Safari")], current: 1),
    ], cursor: 1)

    @Test("One dot per Space of the mirrored display, the current one marked")
    func dotsForMirroredDisplay() {
        let strip = MirrorSpaceStrip.make(layout: Self.twoDisplays, mirroredDisplayID: 1)
        #expect(strip.dots.map(\.isCurrent) == [false, true, false])
        #expect(strip.dots.map(\.kind) == [.desktop, .desktop, .fullScreen(label: "Safari")])
        #expect(strip.previous == .enabled)
        #expect(strip.next == .enabled)
        #expect(strip.accessibilitySummary == "Space 2 of 3")
    }

    @Test("A single Space: one dot, both chevrons hidden")
    func singleSpace() {
        let strip = MirrorSpaceStrip.make(layout: Self.twoDisplays, mirroredDisplayID: 2)
        #expect(strip.dots.count == 1)
        #expect(strip.previous == .hidden)
        #expect(strip.next == .hidden)
    }

    @Test("At either end the chevron past it is dimmed, matching the Mac's refusal")
    func edges() {
        let spaces: [SpaceInfo] = [.desktop, .desktop, .desktop]
        let first = MirrorSpaceStrip.make(layout: Self.layout([Self.display(1, main: true, spaces: spaces, current: 0)]), mirroredDisplayID: 1)
        #expect(first.previous == .dimmed)
        #expect(first.next == .enabled)
        let last = MirrorSpaceStrip.make(layout: Self.layout([Self.display(1, main: true, spaces: spaces, current: 2)]), mirroredDisplayID: 1)
        #expect(last.previous == .enabled)
        #expect(last.next == .dimmed)
        for current in 0..<3 {
            let display = Self.display(1, main: true, spaces: spaces, current: current)
            let strip = MirrorSpaceStrip.make(layout: Self.layout([display]), mirroredDisplayID: 1)
            #expect((strip.previous == .enabled) == SpaceNavigation.canMove(.previous, on: display))
            #expect((strip.next == .enabled) == SpaceNavigation.canMove(.next, on: display))
        }
    }

    @Test("Spaces not known: no dots, chevrons stay usable")
    func unknownSpaces() {
        let noSpaces = Self.twoDisplays.withoutSpaces
        #expect(MirrorSpaceStrip.make(layout: noSpaces, mirroredDisplayID: 1) == .unknown)
        #expect(MirrorSpaceStrip.make(layout: nil, mirroredDisplayID: 1) == .unknown)
        #expect(MirrorSpaceStrip.unknown.dots.isEmpty)
        #expect(MirrorSpaceStrip.unknown.previous == .enabled)
        #expect(MirrorSpaceStrip.unknown.accessibilitySummary == nil)
        // spacesKnown false even if a display carries a list.
        let lying = Self.layout([Self.display(1, main: true, spaces: [.desktop, .desktop], current: 0)], known: false)
        #expect(MirrorSpaceStrip.make(layout: lying, mirroredDisplayID: 1) == .unknown)
    }

    @Test("Mirrored display not confirmed yet: the main display; unknown display: nothing")
    func mirroredDisplayFallback() {
        let strip = MirrorSpaceStrip.make(layout: Self.twoDisplays, mirroredDisplayID: nil)
        #expect(strip.dots.count == 1) // main display (2) has one Space
        #expect(MirrorSpaceStrip.make(layout: Self.twoDisplays, mirroredDisplayID: 99) == .unknown)
    }

    @Test("A current index the Mac didn't know marks no dot")
    func noCurrent() {
        let strip = MirrorSpaceStrip.make(
            layout: Self.layout([Self.display(1, main: true, spaces: [.desktop, .desktop], current: nil)]),
            mirroredDisplayID: 1
        )
        #expect(strip.dots.allSatisfy { !$0.isCurrent })
        #expect(strip.previous == .enabled) // unknown: try
        #expect(strip.accessibilitySummary == "2 Spaces")
    }

    @Test("Full-screen labels are short")
    func labels() {
        #expect(MirrorSpaceStrip.shortAppLabel("Safari") == "Safari")
        #expect(MirrorSpaceStrip.shortAppLabel("Safari & Notes") == "Safari")
        #expect(MirrorSpaceStrip.shortAppLabel(nil) == "Full Screen")
        #expect(MirrorSpaceStrip.shortAppLabel("   ") == "Full Screen")
        let long = MirrorSpaceStrip.shortAppLabel("Microsoft PowerPoint")
        #expect(long.count == MirrorSpaceStrip.maxLabelLength)
        #expect(long.hasSuffix("…"))
        let current = MirrorSpaceStrip.make(
            layout: Self.layout([Self.display(1, main: true, spaces: [.desktop, SpaceInfo(kind: .fullScreen, appName: "Xcode")], current: 1)]),
            mirroredDisplayID: 1
        )
        #expect(current.accessibilitySummary == "Xcode, Space 2 of 2")
    }

    @Test("The badge reads the cursor stream first, then the snapshot")
    func cursorDisplaySource() {
        #expect(MirrorDisplayChrome.cursorDisplayID(stream: 3, layout: Self.twoDisplays) == 3)
        #expect(MirrorDisplayChrome.cursorDisplayID(stream: nil, layout: Self.twoDisplays) == 1)
        #expect(MirrorDisplayChrome.cursorDisplayID(stream: 0, layout: Self.twoDisplays) == 1)
        #expect(MirrorDisplayChrome.cursorDisplayID(stream: nil, layout: nil) == nil)
    }
}
