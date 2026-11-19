//
//  SymbolicHotKeyResolverTests.swift
//  PixelHandCoreTests
//
//  S7: the Mac posts the user's own Mission Control, App Exposé and Spaces
//  shortcuts, read from the window server, and falls back to Apple's
//  defaults when the private calls are missing.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct SymbolicHotKeyResolverTests {
    typealias Chord = SymbolicHotKey.Chord
    static let ctrlFn = SymbolicHotKey.control | SymbolicHotKey.function

    /// A table as macOS ships it: every hot key at its default, Show
    /// Launchpad off and unbound.
    static var shippedTable: [SymbolicHotKey: HotKeyBinding] {
        var table: [SymbolicHotKey: HotKeyBinding] = [:]
        for key in SymbolicHotKey.allCases {
            if let chord = key.defaultChord {
                table[key] = HotKeyBinding(keyCode: chord.keyCode, modifiers: chord.modifiers, isEnabled: true)
            } else {
                table[key] = HotKeyBinding(keyCode: SymbolicHotKey.unboundKeyCode, modifiers: 0, isEnabled: false)
            }
        }
        return table
    }

    @Test("Ids and Apple's default bindings match com.apple.symbolichotkeys")
    func defaultTable() {
        #expect(SymbolicHotKey.missionControl.rawValue == 32)
        #expect(SymbolicHotKey.applicationWindows.rawValue == 33)
        #expect(SymbolicHotKey.moveLeftSpace.rawValue == 79)
        #expect(SymbolicHotKey.moveRightSpace.rawValue == 81)
        #expect(SymbolicHotKey.missionControlKey.rawValue == 108)
        #expect(SymbolicHotKey.launchpadKey.rawValue == 173)
        #expect(SymbolicHotKey.missionControl.defaultChord == Chord(keyCode: 126, modifiers: Self.ctrlFn))
        #expect(SymbolicHotKey.applicationWindows.defaultChord == Chord(keyCode: 125, modifiers: Self.ctrlFn))
        #expect(SymbolicHotKey.moveLeftSpace.defaultChord == Chord(keyCode: 123, modifiers: Self.ctrlFn))
        #expect(SymbolicHotKey.moveRightSpace.defaultChord == Chord(keyCode: 124, modifiers: Self.ctrlFn))
        #expect(SymbolicHotKey.showDesktop.defaultChord == Chord(keyCode: 103, modifiers: SymbolicHotKey.function))
        #expect(SymbolicHotKey.missionControlKey.defaultChord?.keyCode == 160)
        #expect(SymbolicHotKey.showLaunchpad.defaultChord == nil)
    }

    @Test("Every action has a candidate with a default, and its primary is readable")
    func everyActionHasADefault() {
        for action in HotKeyAction.allCases {
            #expect(action.candidates.contains { $0.defaultChord != nil }, "\(action)")
            #expect(SymbolicHotKeyResolver.hotKeysToRead(for: action).contains(action.primary), "\(action)")
        }
    }

    @Test("A shipped Mac posts the dedicated key first, where there is one")
    func shippedTablePrefersDedicatedKeys() {
        let table = Self.shippedTable
        #expect(SymbolicHotKeyResolver.resolve(.missionControl, table: table)
            == .post(.missionControlKey, Chord(keyCode: 160, modifiers: SymbolicHotKey.function)))
        #expect(SymbolicHotKeyResolver.resolve(.applicationWindows, table: table)
            == .post(.applicationWindowsKey, Chord(keyCode: 160, modifiers: Self.ctrlFn)))
        #expect(SymbolicHotKeyResolver.resolve(.launchpad, table: table)
            == .post(.launchpadKey, Chord(keyCode: 131, modifiers: SymbolicHotKey.function)))
        #expect(SymbolicHotKeyResolver.resolve(.showDesktop, table: table)
            == .post(.showDesktop, Chord(keyCode: 103, modifiers: SymbolicHotKey.function)))
        #expect(SymbolicHotKeyResolver.resolve(.previousSpace, table: table)
            == .post(.moveLeftSpace, Chord(keyCode: 123, modifiers: Self.ctrlFn)))
        #expect(SymbolicHotKeyResolver.resolve(.nextSpace, table: table)
            == .post(.moveRightSpace, Chord(keyCode: 124, modifiers: Self.ctrlFn)))
    }

    @Test("A rebound shortcut is followed: the user's chord is posted")
    func reboundShortcutIsFollowed() {
        var table = Self.shippedTable
        table[.missionControlKey]?.isEnabled = false
        // Mission Control moved to ⌥⌘M.
        table[.missionControl] = HotKeyBinding(keyCode: 46, modifiers: SymbolicHotKey.option | SymbolicHotKey.command, isEnabled: true)
        #expect(SymbolicHotKeyResolver.resolve(.missionControl, table: table)
            == .post(.missionControl, Chord(keyCode: 46, modifiers: SymbolicHotKey.option | SymbolicHotKey.command)))
    }

    @Test("Stray device bits in a stored value are dropped before posting")
    func strayModifierBitsAreMasked() {
        var table = Self.shippedTable
        table[.moveRightSpace] = HotKeyBinding(keyCode: 124, modifiers: Self.ctrlFn | 0x0000_0101, isEnabled: true)
        #expect(SymbolicHotKeyResolver.resolve(.nextSpace, table: table).chord.modifiers == Self.ctrlFn)
    }

    @Test("Every shortcut off: the primary is switched on for a moment with its own binding")
    func everyCandidateOffEnablesThePrimary() {
        var table = Self.shippedTable
        table[.showDesktop]?.isEnabled = false
        table[.showDesktopKey]?.isEnabled = false
        #expect(SymbolicHotKeyResolver.resolve(.showDesktop, table: table)
            == .enableTemporarily(.showDesktop, Chord(keyCode: 103, modifiers: SymbolicHotKey.function), needsBinding: false))

        table[.moveLeftSpace]?.isEnabled = false
        #expect(SymbolicHotKeyResolver.resolve(.previousSpace, table: table)
            == .enableTemporarily(.moveLeftSpace, Chord(keyCode: 123, modifiers: Self.ctrlFn), needsBinding: false))
    }

    @Test("Unbound and off: a spare chord is bound for a moment, never ⌘Space")
    func unboundPrimaryGetsASpareChord() {
        var table = Self.shippedTable
        table[.launchpadKey]?.isEnabled = false
        let resolution = SymbolicHotKeyResolver.resolve(.launchpad, table: table)
        guard case let .enableTemporarily(key, chord, needsBinding) = resolution else {
            Issue.record("got \(resolution)")
            return
        }
        #expect(key == .showLaunchpad)
        #expect(needsBinding)
        #expect(chord.keyCode == 80)
        #expect(chord.keyCode != 49 && chord.modifiers != 0)
    }

    @Test("A hot key that couldn't be read counts as off and unbound")
    func unreadableKeysCountAsOff() {
        let resolution = SymbolicHotKeyResolver.resolve(.applicationWindows, table: [:])
        #expect(resolution == .enableTemporarily(.applicationWindows, Chord(keyCode: 125, modifiers: Self.ctrlFn), needsBinding: true))
    }

    @Test("Symbols missing: Apple's default chords are posted")
    func symbolsMissingFallsBackToDefaults() {
        #expect(SymbolicHotKeyResolver.resolve(.missionControl, table: nil)
            == .postDefault(.missionControlKey, Chord(keyCode: 160, modifiers: SymbolicHotKey.function)))
        #expect(SymbolicHotKeyResolver.resolve(.nextSpace, table: nil)
            == .postDefault(.moveRightSpace, Chord(keyCode: 124, modifiers: Self.ctrlFn)))
        #expect(SymbolicHotKeyResolver.resolve(.previousSpace, table: nil).chord.keyCode == 123)
        // Show Launchpad has no default; the Launchpad key does.
        #expect(SymbolicHotKeyResolver.resolve(.launchpad, table: nil)
            == .postDefault(.launchpadKey, Chord(keyCode: 131, modifiers: SymbolicHotKey.function)))
        for action in HotKeyAction.allCases {
            guard case .postDefault = SymbolicHotKeyResolver.resolve(action, table: nil) else {
                Issue.record("\(action) should post a default")
                continue
            }
        }
    }

    @Test("Actions map from system actions and Space directions")
    func actionMapping() {
        #expect(HotKeyAction(SystemMacro.missionControl) == .missionControl)
        #expect(HotKeyAction(SystemMacro.appExpose) == .applicationWindows)
        #expect(HotKeyAction(SystemMacro.showDesktop) == .showDesktop)
        #expect(HotKeyAction(SystemMacro.launchpad) == .launchpad)
        #expect(HotKeyAction(SystemMacro.locateCursor) == nil)
        #expect(HotKeyAction(SpaceDirection.previous) == .previousSpace)
        #expect(HotKeyAction(SpaceDirection.next) == .nextSpace)
        #expect(HotKeyAction(SpaceDirection.missionControl) == .missionControl)
    }

    @Test func chordDescription() {
        #expect(Chord(keyCode: 126, modifiers: Self.ctrlFn).description == "⌃ fn key 126")
    }
}
