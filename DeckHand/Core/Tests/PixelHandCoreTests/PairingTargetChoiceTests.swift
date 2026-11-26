//
//  PairingTargetChoiceTests.swift
//  PixelHandCoreTests
//
//  Which Mac a typed pairing code goes to (build 24, VQ-100).
//

import Foundation
import PixelHandCore
import Testing

@Suite struct PairingTargetChoiceTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let mine = UUID()
    let theirs = UUID()
    let third = UUID()

    var ownMac: PairingTargetCandidate { .init(deviceID: mine, name: "Muhammad’s MacBook Pro") }
    var otherMac: PairingTargetCandidate { .init(deviceID: theirs, name: "AH’s Mac mini") }

    @Test("Build 24: two unknown Macs, the other person's listed first, gives no default")
    func build24NeverPicksFirst() {
        let candidates = [otherMac, ownMac]
        #expect(PairingTargetChoice.defaultTarget(among: candidates, askingDeviceID: nil, now: now) == nil)
        #expect(PairingTargetChoice.showsChooser(among: candidates))
        #expect(PairingTargetChoice.requiresChoice(among: candidates, askingDeviceID: nil, chosenDeviceID: nil, now: now))
    }

    @Test("The Mac that asked wins over list order, pairing and recency")
    func askingMacWins() {
        var paired = otherMac
        paired.isPaired = true
        let candidates = [paired, ownMac]
        #expect(PairingTargetChoice.defaultTarget(among: candidates, askingDeviceID: mine, now: now) == mine)
        #expect(!PairingTargetChoice.requiresChoice(among: candidates, askingDeviceID: mine, chosenDeviceID: nil, now: now))
    }

    @Test("The Mac tapped in the picker asks for ten minutes, then not")
    func askingWindow() {
        #expect(PairingTargetChoice.askingDeviceID(lastAttempt: mine, at: now.addingTimeInterval(-30), now: now) == mine)
        #expect(PairingTargetChoice.askingDeviceID(lastAttempt: mine, at: now.addingTimeInterval(-(PairingTargetChoice.askingWindow + 1)), now: now) == nil)
        #expect(PairingTargetChoice.askingDeviceID(lastAttempt: nil, at: now, now: now) == nil)
        #expect(PairingTargetChoice.askingDeviceID(lastAttempt: mine, at: nil, now: now) == nil)
    }

    @Test("Opened for one Mac with nothing listed: that Mac")
    func askingMacWithoutListing() {
        #expect(PairingTargetChoice.defaultTarget(among: [], askingDeviceID: mine, now: now) == mine)
    }

    @Test("A Mac that asked but is not in reach is not the default when others are")
    func askingMacOutOfReach() {
        let candidates = [otherMac, .init(deviceID: third, name: "Studio")]
        #expect(PairingTargetChoice.defaultTarget(among: candidates, askingDeviceID: mine, now: now) == nil)
    }

    @Test("The only Mac in reach is the default, with no chooser")
    func onlyMac() {
        #expect(PairingTargetChoice.defaultTarget(among: [otherMac], askingDeviceID: nil, now: now) == theirs)
        #expect(!PairingTargetChoice.showsChooser(among: [otherMac]))
        #expect(!PairingTargetChoice.requiresChoice(among: [otherMac], askingDeviceID: nil, chosenDeviceID: nil, now: now))
    }

    @Test("A Mac listed twice counts once")
    func duplicates() {
        #expect(PairingTargetChoice.defaultTarget(among: [ownMac, ownMac], askingDeviceID: nil, now: now) == mine)
        #expect(!PairingTargetChoice.showsChooser(among: [ownMac, ownMac]))
    }

    @Test("The only paired Mac is the default, whatever its place in the list")
    func onlyPaired() {
        var paired = ownMac
        paired.isPaired = true
        #expect(PairingTargetChoice.defaultTarget(among: [otherMac, paired], askingDeviceID: nil, now: now) == mine)
        #expect(PairingTargetChoice.defaultTarget(among: [paired, otherMac], askingDeviceID: nil, now: now) == mine)
    }

    @Test("The only recently used Mac is the default; an old one isn't recent")
    func onlyRecent() {
        var recent = ownMac
        recent.lastUsedAt = now.addingTimeInterval(-3600)
        var stale = otherMac
        stale.lastUsedAt = now.addingTimeInterval(-(PairingTargetChoice.recentWindow + 60))
        #expect(PairingTargetChoice.defaultTarget(among: [stale, recent], askingDeviceID: nil, now: now) == mine)
    }

    @Test("Two known Macs: the person chooses")
    func twoKnown() {
        var a = ownMac
        a.isPaired = true
        var b = otherMac
        b.lastUsedAt = now.addingTimeInterval(-60)
        #expect(PairingTargetChoice.defaultTarget(among: [a, b], askingDeviceID: nil, now: now) == nil)
        #expect(PairingTargetChoice.requiresChoice(among: [a, b], askingDeviceID: nil, chosenDeviceID: nil, now: now))
    }

    @Test("A choice clears the requirement; a choice of a Mac not in reach doesn't")
    func choiceClears() {
        let candidates = [otherMac, ownMac]
        #expect(!PairingTargetChoice.requiresChoice(among: candidates, askingDeviceID: nil, chosenDeviceID: mine, now: now))
        #expect(PairingTargetChoice.requiresChoice(among: candidates, askingDeviceID: nil, chosenDeviceID: third, now: now))
    }

    @Test("The row is labelled and names the Mac, or asks for a choice")
    func rowCopy() {
        #expect(PairingTargetChoice.rowLabel == "Pair with")
        #expect(PairingTargetChoice.rowValue(targetName: "Studio") == "Studio")
        #expect(PairingTargetChoice.rowValue(targetName: nil) == "Choose a Mac")
        #expect(PairingTargetChoice.rowValue(targetName: "") == "Choose a Mac")
        #expect(PairingTargetChoice.rowAccessibilityLabel(targetName: "Studio") == "Pair with, Studio")
        #expect(PairingTargetChoice.heading(targetName: nil) == "Type the code showing on your Mac")
        #expect(PairingTargetChoice.heading(targetName: "Studio") == "Type the code showing on Studio")
    }

    @Test("The keypad layout drops the lock tile and tightens only on a phone with the pad up")
    func keypadLayout() {
        #expect(!PairingSheetLayout.showsLockTile(isPhone: true, isKeypadUp: true))
        #expect(PairingSheetLayout.showsLockTile(isPhone: true, isKeypadUp: false))
        #expect(PairingSheetLayout.showsLockTile(isPhone: false, isKeypadUp: true))
        #expect(PairingSheetLayout.sectionSpacing(isPhone: true, isKeypadUp: true) == 16)
        #expect(PairingSheetLayout.sectionSpacing(isPhone: false, isKeypadUp: true) == 24)
        #expect(PairingSheetLayout.keepsFooterVisible(isKeypadUp: true, band: .standard))
        #expect(PairingSheetLayout.keepsFooterVisible(isKeypadUp: true, band: .large))
        #expect(!PairingSheetLayout.keepsFooterVisible(isKeypadUp: true, band: .huge))
        #expect(!PairingSheetLayout.keepsFooterVisible(isKeypadUp: false, band: .standard))
    }
}
