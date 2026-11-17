//
//  SystemMacroTests.swift
//  PixelHandCoreTests
//
//  "Show Desktop" in the Quick Actions bar never worked: the remote sent
//  `macroButton("showdesktop")`, and the host only matched default-deck ids,
//  which are prefixed `shortcut-`. These tests pin that every id a remote
//  sends for a system action resolves on the host.
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

    @Test func defaultDeckSystemEntriesResolveBeforeTheirKeyFallback() {
        // These default-deck entries are symbolic hot keys; their `keys`
        // never fire when posted, so the host must route them as system
        // actions instead.
        let ids = MacroItem.defaultDeck.map(\.id)
        #expect(ids.contains("shortcut-showdesktop"))
        #expect(SystemMacro(macroID: "shortcut-showdesktop") == .showDesktop)
        #expect(SystemMacro(macroID: "shortcut-missioncontrol") == .missionControl)
    }

    @Test func launchpadNeverMapsToSpotlight() throws {
        // The default deck's Launchpad entry used to post ⌘Space, which
        // opens Spotlight. It must resolve to the real Launchpad action
        // and carry no keys of its own.
        for id in ["launchpad", "launchpad_trigger", "shortcut-launchpad"] {
            #expect(SystemMacro(macroID: id) == .launchpad, "\(id)")
        }
        let entry = try #require(MacroItem.defaultDeck.first { $0.id == "shortcut-launchpad" })
        guard case let .shortcut(shortcut) = entry else { Issue.record("\(entry)"); return }
        #expect(shortcut.keys.map { $0.lowercased() }.sorted() != ["cmd", "space"])
        #expect(shortcut.keys.isEmpty)
    }

    @Test func iDsTheRemoteSendsAllResolve() {
        // Literals used in TrackpadSender, TrackpadView and QuickActionsBar.
        let sent = ["locate_cursor", "missioncontrol_trigger", "expose_trigger", "launchpad_trigger", "showdesktop_trigger"]
        for id in sent {
            #expect(SystemMacro(macroID: id) != nil, "\(id)")
        }
    }

    @Test func nonSystemIDsAreLeftForTheDefaultDeck() {
        for id in ["app-safari", "media-playpause", "shortcut-unknown", "", "SHOWDESKTOP"] {
            #expect(SystemMacro(macroID: id) == nil, "\(id)")
        }
    }
}
