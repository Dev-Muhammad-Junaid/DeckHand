//
//  SystemMacroTests.swift
//  PixelHandCoreTests
//
//  "Show Desktop" in the Quick Actions bar never worked: the remote sent
//  `macroButton("showdesktop")`, and the host only matched default-deck ids,
//  which are prefixed `shortcut-`. Protocol 2 sends system actions typed
//  (`SystemMessage.run(action:)`), so there are no ids to drift; these tests
//  pin the typed wire values and that every old id still resolves (for
//  importing old decks).
//

import Foundation
import PixelHandCore
import Testing

@Suite struct SystemMacroTests {

    @Test func canonicalIDsRoundTrip() {
        for macro in SystemMacro.allCases {
            #expect(SystemMacro(macroID: macro.macroID) == macro, "\(macro)")
        }
    }

    @Test func showDesktopResolvesUnderEverySpelling() {
        // "showdesktop" is what builds before this fix send from the Quick
        // Actions bar; "shortcut-showdesktop" is the default deck's id.
        for id in ["showdesktop", "showdesktop_trigger", "shortcut-showdesktop"] {
            #expect(SystemMacro(macroID: id) == .showDesktop, "\(id)")
        }
    }

    @Test("Old deck ids for system actions resolve to them")
    func oldDeckIDsResolve() {
        #expect(SystemMacro(macroID: "shortcut-showdesktop") == .showDesktop)
        #expect(SystemMacro(macroID: "shortcut-missioncontrol") == .missionControl)
    }

    @Test("Launchpad never maps to Spotlight")
    func launchpadNeverMapsToSpotlight() {
        // The old default deck's Launchpad entry posted ⌘Space, which opens
        // Spotlight. Every spelling resolves to the real Launchpad action.
        for id in ["launchpad", "launchpad_trigger", "shortcut-launchpad"] {
            #expect(SystemMacro(macroID: id) == .launchpad, "\(id)")
        }
        #expect(Action.system(action: .launchpad).message == .system(.run(action: .launchpad)))
    }

    @Test("System actions travel typed, by their raw value")
    func wireValuesArePinned() throws {
        let expected: [SystemMacro: String] = [
            .locateCursor: "locateCursor",
            .missionControl: "missionControl",
            .appExpose: "appExpose",
            .showDesktop: "showDesktop",
            .launchpad: "launchpad",
        ]
        #expect(expected.count == SystemMacro.allCases.count)
        for macro in SystemMacro.allCases {
            let data = try ControlMessageCoding.encode(.system(.run(action: macro)))
            #expect(String(decoding: data, as: UTF8.self).contains("\"\(expected[macro] ?? "?")\""), "\(macro)")
            #expect(try ControlMessageCoding.decode(data) == .system(.run(action: macro)))
        }
    }

    @Test func iDsTheRemoteSendsAllResolve() {
        // Literals protocol 1 remotes sent.
        let sent = ["locate_cursor", "missioncontrol_trigger", "expose_trigger", "launchpad_trigger", "showdesktop_trigger"]
        for id in sent {
            #expect(SystemMacro(macroID: id) != nil, "\(id)")
        }
    }

    @Test func nonSystemIDsDontResolve() {
        for id in ["app-safari", "media-playpause", "shortcut-unknown", "", "SHOWDESKTOP"] {
            #expect(SystemMacro(macroID: id) == nil, "\(id)")
        }
    }
}
