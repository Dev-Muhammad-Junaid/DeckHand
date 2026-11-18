//
//  DisplayLayoutTests.swift
//  PixelHandCoreTests
//
//  The Spaces / displays / cursor snapshot (STATUS.md ticket "Mirror:
//  Spaces, displays and cursor awareness"): encoding, the edge rules for
//  ‹ ›, reading CGSCopyManagedDisplaySpaces, and the no-Spaces fallback.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct DisplayLayoutTests {
    static let hp = DisplayDescriptor(
        displayID: 2, name: "HP E273", isMain: true,
        bounds: DisplayBounds(x: 0, y: 0, width: 1920, height: 1080),
        uuid: "AAAA-HP"
    )
    static let builtIn = DisplayDescriptor(
        displayID: 1, name: "Built-in Retina Display", isMain: false,
        bounds: DisplayBounds(x: -1728, y: 0, width: 1728, height: 1117),
        uuid: "bbbb-builtin"
    )

    static func display(spaces: Int, current: Int?, fullScreenAt: Set<Int> = []) -> DisplaySpaces {
        DisplaySpaces(
            displayID: 1, name: "D", isMain: true,
            bounds: DisplayBounds(x: 0, y: 0, width: 100, height: 100),
            spaces: (0..<spaces).map { fullScreenAt.contains($0) ? SpaceInfo(kind: .fullScreen, appName: "App") : .desktop },
            currentSpaceIndex: current
        )
    }

    // MARK: Round trip

    @Test("A snapshot survives encoding, with and without Space data")
    func roundTrip() throws {
        let layout = DisplayLayoutBuilder.build(
            displays: [Self.builtIn, Self.hp],
            managed: [
                ManagedDisplaySpaces(identifier: "AAAA-HP", spaces: [.desktop], currentIndex: 0),
                ManagedDisplaySpaces(identifier: "BBBB-BUILTIN", spaces: [.desktop, .desktop, SpaceInfo(kind: .fullScreen, appName: "Safari")], currentIndex: 1),
            ],
            cursorDisplayID: 1
        )
        for value in [layout, layout.withoutSpaces] {
            let message = ControlMessage.system(.displayState(layout: value))
            #expect(try ControlMessageCoding.decode(ControlMessageCoding.encode(message)) == message)
        }
    }

    @Test("A stale or hostile current index decodes as unknown")
    func badIndexIsUnknown() throws {
        let json = #"{"bounds":{"height":1,"width":1,"x":0,"y":0},"currentSpaceIndex":7,"displayID":1,"isMain":true,"name":"D","spaces":[{"kind":"desktop"}]}"#
        let decoded = try ControlMessageCoding.decoder.decode(DisplaySpaces.self, from: Data(json.utf8))
        #expect(decoded.currentSpaceIndex == nil)
        #expect(Self.display(spaces: 2, current: -1).currentSpaceIndex == nil)
    }

    // MARK: Edge rules

    @Test("One desktop: both chevrons refused")
    func oneDesktop() {
        let d = Self.display(spaces: 1, current: 0)
        #expect(SpaceNavigation.decide(.previous, on: d) == .refused(.singleSpace))
        #expect(SpaceNavigation.decide(.next, on: d) == .refused(.singleSpace))
        #expect(!SpaceNavigation.canMove(.next, on: d))
    }

    @Test("Three desktops: refused past either end, allowed inside")
    func threeDesktops() {
        let first = Self.display(spaces: 3, current: 0)
        #expect(SpaceNavigation.decide(.previous, on: first) == .refused(.atFirstSpace))
        #expect(SpaceNavigation.decide(.next, on: first) == .switchTo(index: 1))
        let middle = Self.display(spaces: 3, current: 1)
        #expect(SpaceNavigation.decide(.previous, on: middle) == .switchTo(index: 0))
        #expect(SpaceNavigation.decide(.next, on: middle) == .switchTo(index: 2))
        let last = Self.display(spaces: 3, current: 2)
        #expect(SpaceNavigation.decide(.next, on: last) == .refused(.atLastSpace))
        #expect(SpaceNavigation.decide(.previous, on: last) == .switchTo(index: 1))
    }

    @Test("Full-screen Spaces sit in the same strip and count")
    func fullScreenSpacesCount() {
        let d = Self.display(spaces: 3, current: 1, fullScreenAt: [2])
        #expect(SpaceNavigation.decide(.next, on: d) == .switchTo(index: 2))
        #expect(d.fullScreenSpaces.map(\.index) == [2])
        #expect(d.fullScreenSpaces.first?.appName == "App")
        let onFullScreen = Self.display(spaces: 3, current: 2, fullScreenAt: [2])
        #expect(onFullScreen.currentSpace?.kind == .fullScreen)
        #expect(SpaceNavigation.decide(.next, on: onFullScreen) == .refused(.atLastSpace))
    }

    @Test("No Space data: unknown, so the Mac tries and the chevrons stay")
    func unknownSpaces() {
        let d = Self.display(spaces: 2, current: 0).withoutSpaces
        #expect(SpaceNavigation.decide(.next, on: d) == .unknown)
        #expect(SpaceNavigation.decide(.next, on: nil) == .unknown)
        #expect(SpaceNavigation.canMove(.previous, on: d))
        #expect(SpaceNavigation.decide(.missionControl, on: d) == .notASwitch)
    }

    // MARK: Parsing CGSCopyManagedDisplaySpaces

    static func rawTwoDisplays() -> [Any] { [
        [
            "Display Identifier": "AAAA-HP",
            "Current Space": ["ManagedSpaceID": 5, "type": 0],
            "Spaces": [["ManagedSpaceID": 5, "type": 0]],
        ] as [String: Any],
        [
            "Display Identifier": "BBBB-BUILTIN",
            "Current Space": ["ManagedSpaceID": 8],
            "Spaces": [
                ["ManagedSpaceID": 3, "type": 0],
                ["ManagedSpaceID": 8, "type": 0],
                ["ManagedSpaceID": 99, "type": 2],
                ["ManagedSpaceID": 12, "type": 4, "TileLayoutManager": ["TileSpaces": [["appName": "Safari"]]]] as [String: Any],
                ["ManagedSpaceID": 14, "type": 4, "pid": 4242] as [String: Any],
            ] as [Any],
        ] as [String: Any],
    ] }

    @Test("Two displays with uneven desktops, as on the owner's Mac")
    func parseTwoDisplays() throws {
        let parsed = try #require(ManagedSpacesParser.parse(Self.rawTwoDisplays()) { $0 == 4242 ? "Xcode" : nil })
        #expect(parsed.count == 2)
        #expect(parsed[0] == ManagedDisplaySpaces(identifier: "AAAA-HP", spaces: [.desktop], currentIndex: 0))
        #expect(parsed[1].spaces == [.desktop, .desktop, SpaceInfo(kind: .fullScreen, appName: "Safari"), SpaceInfo(kind: .fullScreen, appName: "Xcode")])
        #expect(parsed[1].currentIndex == 1)

        let layout = DisplayLayoutBuilder.build(displays: [Self.builtIn, Self.hp], managed: parsed, cursorPoint: (x: -10, y: 50))
        #expect(layout.spacesKnown && layout.separateSpaces)
        #expect(layout.displays.map(\.displayID) == [2, 1], "main first")
        #expect(layout.display(2)?.spaceCount == 1)
        #expect(layout.display(1)?.spaceCount == 4)
        #expect(layout.display(1)?.currentSpaceIndex == 1)
        #expect(layout.cursorDisplayID == 1, "found from the pointer's position")
        #expect(SpaceNavigation.decide(.next, on: layout.display(2)) == .refused(.singleSpace))
    }

    @Test("Split view names both apps")
    func splitView() throws {
        let raw: [Any] = [[
            "Display Identifier": "Main",
            "Current Space": ["ManagedSpaceID": 1],
            "Spaces": [["ManagedSpaceID": 1, "type": 4, "TileLayoutManager": ["TileSpaces": [["appName": "Notes"], ["appName": "Safari"]]]] as [String: Any]],
        ] as [String: Any]]
        let parsed = try #require(ManagedSpacesParser.parse(raw))
        #expect(parsed[0].spaces.first?.appName == "Notes & Safari")
    }

    @Test("\"Main\" matches the main display when no UUID matches")
    func mainIdentifier() {
        let managed = [
            ManagedDisplaySpaces(identifier: "Main", spaces: [.desktop, .desktop], currentIndex: 0),
            ManagedDisplaySpaces(identifier: "BBBB-BUILTIN", spaces: [.desktop], currentIndex: 0),
        ]
        let hpWithoutUUID = DisplayDescriptor(displayID: 2, name: "HP", isMain: true, bounds: Self.hp.bounds, uuid: nil)
        let layout = DisplayLayoutBuilder.build(displays: [hpWithoutUUID, Self.builtIn], managed: managed)
        #expect(layout.display(2)?.spaceCount == 2)
        #expect(layout.display(1)?.spaceCount == 1)
    }

    @Test("Displays without separate Spaces share one strip")
    func sharedStrip() {
        let managed = [ManagedDisplaySpaces(identifier: "Main", spaces: [.desktop, .desktop, .desktop], currentIndex: 2)]
        let layout = DisplayLayoutBuilder.build(displays: [Self.hp, Self.builtIn], managed: managed)
        #expect(!layout.separateSpaces)
        #expect(layout.displays.allSatisfy { $0.spaceCount == 3 && $0.currentSpaceIndex == 2 })
    }

    @Test("Symbol missing: displays without Space fields")
    func symbolMissing() {
        let layout = DisplayLayoutBuilder.build(displays: [Self.hp, Self.builtIn], managed: nil, cursorDisplayID: 2)
        #expect(!layout.spacesKnown)
        #expect(layout.displays.count == 2)
        #expect(layout.displays.allSatisfy { $0.spaces == nil && $0.currentSpaceIndex == nil })
        #expect(layout.cursorDisplay?.name == "HP E273")
        #expect(DisplayLayoutBuilder.build(displays: [Self.hp], managed: []).spacesKnown == false)
    }

    @Test("Garbage from the private call is skipped, never trapped on")
    func garbageIsSkipped() {
        #expect(ManagedSpacesParser.parse(nil) == nil)
        #expect(ManagedSpacesParser.parse("nope") == nil)
        let raw: [Any] = [
            42,
            ["Spaces": []] as [String: Any],
            ["Display Identifier": "X", "Spaces": [7, ["type": "weird"]] as [Any]] as [String: Any],
        ]
        let parsed = ManagedSpacesParser.parse(raw)
        #expect(parsed == [ManagedDisplaySpaces(identifier: "X", spaces: [.desktop], currentIndex: nil)])
    }
}

@Suite struct MenuReadBudgetTests {
    @Test("Stops at the node limit")
    func nodeLimit() {
        var budget = MenuReadBudget(limits: MenuReadLimits(maxNodes: 3), start: Date(timeIntervalSince1970: 0))
        let now = Date(timeIntervalSince1970: 0)
        let visits = (0..<4).map { _ in budget.visitNode(now: now) }
        #expect(visits == [true, true, true, false])
        #expect(budget.stopReason == .nodeLimit)
        #expect(!budget.mayDescend(toDepth: 0))
    }

    @Test("Stops at the item limit without keeping the extra item")
    func itemLimit() {
        var budget = MenuReadBudget(limits: MenuReadLimits(maxItems: 2))
        let adds = (0..<3).map { _ in budget.addItem() }
        #expect(adds == [true, true, false])
        #expect(budget.itemsCollected == 2)
        #expect(budget.stopReason == .itemLimit)
    }

    @Test("Stops at the time limit")
    func timeLimit() {
        let t0 = Date(timeIntervalSince1970: 0)
        var budget = MenuReadBudget(limits: MenuReadLimits(timeLimit: 1), start: t0)
        let early = budget.visitNode(now: t0.addingTimeInterval(0.5))
        let late = budget.visitNode(now: t0.addingTimeInterval(1))
        #expect(early && !late)
        #expect(budget.stopReason == .timeLimit)
    }

    @Test("An app that keeps timing out is given up on; one success resets the count")
    func timeouts() {
        var budget = MenuReadBudget(limits: MenuReadLimits(maxConsecutiveTimeouts: 2))
        budget.noteRead(timedOut: true)
        budget.noteRead(timedOut: false)
        budget.noteRead(timedOut: true)
        #expect(!budget.isExhausted)
        budget.noteRead(timedOut: true)
        #expect(budget.stopReason == .appNotAnswering)
    }

    @Test("Depth and children are capped")
    func depthAndChildren() {
        var budget = MenuReadBudget(limits: MenuReadLimits(maxDepth: 2, maxChildrenPerMenu: 10))
        #expect(budget.mayDescend(toDepth: 2))
        #expect(!budget.mayDescend(toDepth: 3))
        let counts = [4, 500, -1].map { budget.childrenToRead(of: $0) }
        #expect(counts == [4, 10, 0])
        #expect(budget.truncatedMenus == 1)
    }
}
