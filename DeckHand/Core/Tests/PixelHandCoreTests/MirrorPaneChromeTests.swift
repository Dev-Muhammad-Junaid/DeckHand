//
//  MirrorPaneChromeTests.swift
//  PixelHandCoreTests
//
//  The mirror's pixel chrome (UX-006, UX-016): status strips, the display
//  counter, the cursor badge, link badges and the display picker's
//  arrangement.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct MirrorPaneChromeTests {
    static let builtIn = DisplayInfo(displayID: 1, name: "Built-in Retina Display", isMain: true, width: 1512, height: 982)
    static let hp = DisplayInfo(displayID: 2, name: "HP 24", isMain: false, width: 1920, height: 1080)
    static let above = DisplayInfo(displayID: 3, name: "Studio Display", isMain: false, width: 2560, height: 1440)

    static func spaces(_ id: UInt32, x: Double, y: Double, w: Double, h: Double, main: Bool = false, count: Int = 1, current: Int = 0, fullScreenAt: Set<Int> = []) -> DisplaySpaces {
        DisplaySpaces(
            displayID: id, name: "D\(id)", isMain: main,
            bounds: DisplayBounds(x: x, y: y, width: w, height: h),
            spaces: (0..<count).map { fullScreenAt.contains($0) ? SpaceInfo(kind: .fullScreen, appName: "Keynote") : .desktop },
            currentSpaceIndex: current
        )
    }

    static let layout = DisplayLayout(
        displays: [
            spaces(1, x: 0, y: 0, w: 1512, h: 982, main: true, count: 3, current: 1, fullScreenAt: [2]),
            spaces(2, x: 1512, y: 0, w: 1920, h: 1080),
        ],
        cursorDisplayID: 2, spacesKnown: true, separateSpaces: true
    )

    static let host = MirrorHostStats(codec: .hevc, width: 1920, height: 1200, capturedFPS: 60, sentFPS: 59.6, droppedFrames: 1, encodeMilliseconds: 4, kilobitsPerSecond: 18_400)
    static let client = MirrorClientStats(receivedFPS: 60, displayedFPS: 59.7, droppedFrames: 1, decodeMilliseconds: 6.6, kilobitsPerSecond: 18_000)

    @Test("Names become dot-matrix safe: uppercased, unknown characters dropped, cut at a word within 12")
    func dotMatrixSafeNames() {
        #expect(MirrorPaneChrome.dotMatrixSafe("Studio") == "STUDIO")
        #expect(MirrorPaneChrome.dotMatrixSafe("Junaid’s  MacBook Pro") == "JUNAID’S")
        #expect(MirrorPaneChrome.dotMatrixSafe("Muhammads MacBook Pro") == "MUHAMMADS")
        #expect(MirrorPaneChrome.dotMatrixSafe("Supercalifragilistic") == "SUPERCALIFRA")
        #expect(MirrorPaneChrome.dotMatrixSafe("Mac  mini (2)") == "MAC MINI (2)")
        #expect(MirrorPaneChrome.dotMatrixSafe("ab cdefghijk lmn") == "AB CDEFGHIJK")
        let safe = MirrorPaneChrome.dotMatrixSafe("Ünïcode Mac é")
        #expect(safe.allSatisfy { DotMatrixFont.characters.contains($0) })
    }

    @Test("The docked strip reads Mac, display, desktop, fps in drop order")
    func paneStrip() {
        let strip = MirrorPaneChrome.paneStrip(
            macName: "Studio",
            displays: [Self.builtIn, Self.hp],
            mirroredDisplayID: 1,
            windowTitle: nil,
            mirroringWindow: false,
            spaces: MirrorSpaceStrip.make(layout: Self.layout, mirroredDisplayID: 1),
            host: Self.host,
            client: Self.client
        )
        #expect(strip.items == ["STUDIO", "D1/2", "DESK 2/3", "60 FPS"])
        #expect(strip.spoken == "Studio, display 1 of 2, desktop 2 of 3, 60 frames per second")
    }

    @Test("One display and one desktop: only the Mac and fps")
    func paneStripMinimal() {
        let strip = MirrorPaneChrome.paneStrip(
            macName: "Air", displays: [Self.builtIn], mirroredDisplayID: nil, windowTitle: nil,
            mirroringWindow: false, spaces: .unknown, host: nil, client: nil
        )
        #expect(strip.items == ["AIR"])
    }

    @Test("A window mirror says WINDOW instead of display and desktop")
    func paneStripWindow() {
        let strip = MirrorPaneChrome.paneStrip(
            macName: "Studio", displays: [Self.builtIn, Self.hp], mirroredDisplayID: 1, windowTitle: "Safari",
            mirroringWindow: true, spaces: .window, host: nil, client: Self.client
        )
        #expect(strip.items == ["STUDIO", "WINDOW", "60 FPS"])
        #expect(strip.spoken.contains("window Safari"))
    }

    @Test("Unconfirmed mirrored display counts as the main one")
    func counterDefaultsToMain() {
        #expect(MirrorPaneChrome.displayCounter(displays: [Self.hp, Self.builtIn], mirroredDisplayID: nil, mirroringWindow: false) == "2/2")
        #expect(MirrorPaneChrome.displayCounter(displays: [Self.builtIn, Self.hp], mirroredDisplayID: 2, mirroringWindow: false) == "2/2")
        #expect(MirrorPaneChrome.displayCounter(displays: [Self.builtIn], mirroredDisplayID: 1, mirroringWindow: false) == nil)
        #expect(MirrorPaneChrome.displayCounter(displays: [Self.builtIn], mirroredDisplayID: 1, mirroringWindow: true) == "WIN")
    }

    @Test("The tile strip is LIVE, display, fps")
    func tileStrip() {
        let strip = MirrorPaneChrome.tileStrip(displays: [Self.builtIn, Self.hp], mirroredDisplayID: 1, mirroringWindow: false, host: nil, client: Self.client)
        #expect(strip.items == ["LIVE", "D1", "60"])
        let single = MirrorPaneChrome.tileStrip(displays: [Self.builtIn], mirroredDisplayID: 1, mirroringWindow: false, host: nil, client: nil)
        #expect(single.items == ["LIVE"])
    }

    @Test("The stats strip carries fps, decode, codec, rate, drops and the link")
    func statsStrip() {
        let items = MirrorPaneChrome.statsStrip(host: Self.host, client: Self.client, link: .wired)
        #expect(items == ["60 FPS", "7 MS", "HEVC 1920", "18 MB/S", "2 DROP", "WIRED"])
        #expect(MirrorPaneChrome.statsStrip(host: nil, client: nil, link: nil) == ["WAITING"])
        let slow = MirrorHostStats(codec: .jpeg, width: 1024, height: 640, capturedFPS: 20, sentFPS: 20, droppedFrames: 0, encodeMilliseconds: 6, kilobitsPerSecond: 2_400)
        #expect(MirrorPaneChrome.statsStrip(host: slow, client: nil, link: .wifi) == ["20 FPS", "JPEG 1024", "2.4 MB/S", "WI-FI"])
    }

    @Test("Every strip string uses only dot-matrix characters")
    func stripsAreDrawable() {
        let all = MirrorPaneChrome.statsStrip(host: Self.host, client: Self.client, link: .tunnel)
            + MirrorPaneChrome.paneStrip(macName: "José’s iMac", displays: [Self.builtIn, Self.hp], mirroredDisplayID: 2, windowTitle: nil, mirroringWindow: false, spaces: .unknown, host: Self.host, client: nil).items
        for item in all {
            #expect(item.uppercased().allSatisfy { DotMatrixFont.characters.contains($0) }, "\(item)")
        }
    }

    @Test("Link badges: header only for cable and VPN, cards for every named link")
    func linkBadges() {
        #expect(LinkBadgeKind.header(for: .wired) == .wired)
        #expect(LinkBadgeKind.header(for: .ethernet) == .wired)
        #expect(LinkBadgeKind.header(for: .tunnel) == .vpn)
        #expect(LinkBadgeKind.header(for: .wifi) == nil)
        #expect(LinkBadgeKind.header(for: nil) == nil)
        #expect(LinkBadgeKind.card(for: .wifi) == .wifi)
        #expect(LinkBadgeKind.card(for: .peerToPeer) == .direct)
        #expect(LinkBadgeKind.card(for: .unknown) == nil)
    }

    @Test("The cursor badge points toward the cursor's display")
    func cursorBadge() {
        let chrome = MirrorDisplayChrome.make(displays: [Self.builtIn, Self.hp], mirroredDisplayID: 1, cursorDisplayID: 2, followsCursor: false)
        let badge = MirrorPaneChrome.cursorBadge(chrome: chrome, displays: [Self.builtIn, Self.hp], mirroredDisplayID: 1, layout: Self.layout)
        #expect(badge?.text == "ON 2")
        #expect(badge?.arrow == .right)
        #expect(badge?.displayID == 2)
        #expect(badge?.spoken == "The pointer is on HP 24, to the right. Double-tap to show it.")

        let back = MirrorDisplayChrome.make(displays: [Self.builtIn, Self.hp], mirroredDisplayID: 2, cursorDisplayID: 1, followsCursor: false)
        #expect(MirrorPaneChrome.cursorBadge(chrome: back, displays: [Self.builtIn, Self.hp], mirroredDisplayID: 2, layout: Self.layout)?.arrow == .left)
    }

    @Test("No badge when the cursor is on the mirrored display or Follow cursor is on")
    func noCursorBadge() {
        let same = MirrorDisplayChrome.make(displays: [Self.builtIn, Self.hp], mirroredDisplayID: 2, cursorDisplayID: 2, followsCursor: false)
        #expect(MirrorPaneChrome.cursorBadge(chrome: same, displays: [Self.builtIn, Self.hp], mirroredDisplayID: 2, layout: Self.layout) == nil)
        let following = MirrorDisplayChrome.make(displays: [Self.builtIn, Self.hp], mirroredDisplayID: 1, cursorDisplayID: 2, followsCursor: true)
        #expect(MirrorPaneChrome.cursorBadge(chrome: following, displays: [Self.builtIn, Self.hp], mirroredDisplayID: 1, layout: Self.layout) == nil)
    }

    @Test("Arrow: vertical arrangements point up or down; unknown layout points right")
    func arrowDirections() {
        let stacked = DisplayLayout(
            displays: [Self.spaces(1, x: 0, y: 0, w: 1512, h: 982, main: true), Self.spaces(3, x: 0, y: -1440, w: 2560, h: 1440)],
            cursorDisplayID: 3, spacesKnown: true, separateSpaces: true
        )
        #expect(MirrorPaneChrome.arrowDirection(from: 1, to: 3, layout: stacked) == .up)
        #expect(MirrorPaneChrome.arrowDirection(from: 3, to: 1, layout: stacked) == .down)
        #expect(MirrorPaneChrome.arrowDirection(from: 1, to: 3, layout: nil) == .right)
    }

    @Test("The picker draws displays to scale, fitted and centred in the box")
    func arrangementToScale() {
        let arranged = MirrorPaneChrome.arrangement(
            displays: [Self.builtIn, Self.hp], layout: Self.layout, mirroredDisplayID: 1, cursorDisplayID: 2,
            boxWidth: 340, boxHeight: 140, gap: 8
        )
        #expect(arranged.count == 2)
        let a = arranged[0], b = arranged[1]
        // Side by side, the HP to the right, inside the box.
        #expect(a.x < b.x)
        #expect(a.x >= 0 && b.x + b.width <= 340)
        #expect(a.y >= 0 && max(a.y + a.height, b.y + b.height) <= 140)
        // To scale: the HP is wider and taller than the built-in.
        #expect(b.width > a.width)
        #expect(b.height > a.height)
        // Gap between the touching edges.
        #expect(b.x - (a.x + a.width) >= 7)
        #expect(a.isMirrored && !b.isMirrored)
        #expect(b.hasCursor && !a.hasCursor)
        #expect(a.spaceCount == 3 && a.currentSpaceIndex == 1 && a.fullScreenIndexes == [2])
        #expect(b.spaceCount == 1)
        #expect(a.number == 1 && b.number == 2)
    }

    @Test("Without a layout the picker lays displays out in a row, no desktop dots")
    func arrangementWithoutLayout() {
        let arranged = MirrorPaneChrome.arrangement(
            displays: [Self.builtIn, Self.hp, Self.above], layout: nil, mirroredDisplayID: nil, cursorDisplayID: nil,
            boxWidth: 340, boxHeight: 140
        )
        #expect(arranged.count == 3)
        #expect(arranged[0].x < arranged[1].x && arranged[1].x < arranged[2].x)
        #expect(arranged.allSatisfy { $0.spaceCount == nil })
        // Unconfirmed: the main display is the mirrored one.
        #expect(arranged[0].isMirrored)
        #expect(arranged.last.map { $0.x + $0.width } ?? 0 <= 340)
    }

    @Test("Subtitles count desktops")
    func subtitles() {
        #expect(MirrorPaneChrome.displaySubtitle(number: 1, spaceCount: 3) == "Display 1 · 3 desktops")
        #expect(MirrorPaneChrome.displaySubtitle(number: 2, spaceCount: 1) == "Display 2 · 1 desktop")
        #expect(MirrorPaneChrome.displaySubtitle(number: 2, spaceCount: nil) == "Display 2")
    }
}
