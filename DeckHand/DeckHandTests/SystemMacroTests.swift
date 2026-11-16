//
//  SystemMacroTests.swift
//  DeckHandTests
//
//  "Show Desktop" in the Quick Actions bar never worked: the remote sent
//  `macroButton("showdesktop")`, and the host only matched default-deck ids,
//  which are prefixed `shortcut-`. These tests pin that every id a remote
//  sends for a system action resolves on the host.
//

import XCTest

final class SystemMacroTests: XCTestCase {

    func testCanonicalIDsRoundTrip() {
        for macro in SystemMacro.allCases {
            XCTAssertEqual(SystemMacro(macroID: macro.macroID), macro, "\(macro)")
        }
    }

    func testShowDesktopResolvesUnderEverySpelling() {
        // "showdesktop" is what builds before this fix send from the Quick
        // Actions bar; "shortcut-showdesktop" is the default deck's id.
        for id in ["showdesktop", "showdesktop_trigger", "shortcut-showdesktop"] {
            XCTAssertEqual(SystemMacro(macroID: id), .showDesktop, id)
        }
    }

    func testDefaultDeckSystemEntriesResolveBeforeTheirKeyFallback() {
        // These default-deck entries are symbolic hot keys; their `keys`
        // never fire when posted, so the host must route them as system
        // actions instead.
        let ids = MacroItem.defaultDeck.map(\.id)
        XCTAssertTrue(ids.contains("shortcut-showdesktop"))
        XCTAssertEqual(SystemMacro(macroID: "shortcut-showdesktop"), .showDesktop)
        XCTAssertEqual(SystemMacro(macroID: "shortcut-missioncontrol"), .missionControl)
    }

    func testLaunchpadNeverMapsToSpotlight() throws {
        // The default deck's Launchpad entry used to post ⌘Space, which
        // opens Spotlight. It must resolve to the real Launchpad action
        // and carry no keys of its own.
        for id in ["launchpad", "launchpad_trigger", "shortcut-launchpad"] {
            XCTAssertEqual(SystemMacro(macroID: id), .launchpad, id)
        }
        let entry = try XCTUnwrap(MacroItem.defaultDeck.first { $0.id == "shortcut-launchpad" })
        guard case let .shortcut(shortcut) = entry else { return XCTFail("\(entry)") }
        XCTAssertNotEqual(shortcut.keys.map { $0.lowercased() }.sorted(), ["cmd", "space"])
        XCTAssertTrue(shortcut.keys.isEmpty)
    }

    func testIDsTheRemoteSendsAllResolve() {
        // Literals used in TrackpadSender, TrackpadView and QuickActionsBar.
        let sent = ["locate_cursor", "missioncontrol_trigger", "expose_trigger", "launchpad_trigger", "showdesktop_trigger"]
        for id in sent {
            XCTAssertNotNil(SystemMacro(macroID: id), id)
        }
    }

    func testNonSystemIDsAreLeftForTheDefaultDeck() {
        for id in ["app-safari", "media-playpause", "shortcut-unknown", "", "SHOWDESKTOP"] {
            XCTAssertNil(SystemMacro(macroID: id), id)
        }
    }
}
