//
//  ActionTests.swift
//  PixelHandCoreTests
//
//  The typed action model: each action maps to exactly one domain message
//  (so the Mac has one code path per command), outcomes say whether the
//  remote shows success, and decks validate before they are stored.
//

import Foundation
import PixelHandCore
import Testing

@Suite struct ActionTests {

    static let allKinds: [Action] = [
        .shortcut(keys: ["cmd", "c"]),
        .appShortcut(bundleID: "com.apple.Safari", keys: ["cmd", "t"]),
        .launchApp(bundleID: "com.apple.Terminal"),
        .system(action: .showDesktop),
        .media(key: .previous),
        .contextAction(id: "rev|1|Cancel"),
        .menuCommand(bundleID: "com.apple.Safari", path: ["File", "Export as PDF…"]),
        .macShortcut(name: "Morning"),
        .sequence(steps: [.run(action: .shortcut(keys: ["cmd", "c"])), .delay(milliseconds: 200)]),
    ]

    @Test("Each action maps to the untracked message that does the same")
    func actionsMapToMessages() {
        #expect(Action.shortcut(keys: ["cmd", "c"]).message == .input(.keyboardShortcut(keys: ["cmd", "c"])))
        #expect(Action.appShortcut(bundleID: "b", keys: ["k"]).message == .apps(.appShortcut(bundleID: "b", keys: ["k"])))
        #expect(Action.launchApp(bundleID: "b").message == .apps(.launchApp(bundleID: "b")))
        #expect(Action.system(action: .appExpose).message == .system(.run(action: .appExpose)))
        #expect(Action.media(key: .playPause).message == .input(.media(key: .playPause)))
        #expect(Action.contextAction(id: "x").message == .apps(.triggerContextAction(id: "x")))
    }

    @Test("Deck 2 actions have no untracked message")
    func deck2ActionsRunOnlyTracked() {
        #expect(Action.menuCommand(bundleID: "b", path: ["File"]).message == nil)
        #expect(Action.macShortcut(name: "x").message == nil)
        #expect(Action.sequence(steps: []).message == nil)
    }

    @Test("A Shortcuts run needs no Accessibility; a sequence needs it when a step does")
    func accessibilityNeeds() {
        #expect(!Action.macShortcut(name: "x").needsAccessibility)
        #expect(Action.menuCommand(bundleID: "b", path: ["File"]).needsAccessibility)
        #expect(!Action.sequence(steps: [.run(action: .macShortcut(name: "x")), .delay(milliseconds: 5)]).needsAccessibility)
        #expect(Action.sequence(steps: [.run(action: .macShortcut(name: "x")), .run(action: .media(key: .next))]).needsAccessibility)
    }

    @Test("No action maps to a run, so runs can't nest")
    func noActionMapsToARun() {
        for action in Self.allKinds {
            if case .deck(.run) = action.message { Issue.record("\(action) maps to a run") }
        }
    }

    @Test("Actions round-trip through JSON")
    func actionsRoundTrip() throws {
        for action in Self.allKinds {
            let data = try ControlMessageCoding.encoder.encode(action)
            #expect(try ControlMessageCoding.decoder.decode(Action.self, from: data) == action)
        }
    }

    @Test("Only delivered and completed read as success")
    func outcomeSuccess() {
        #expect(ActionOutcome.delivered.isSuccess)
        #expect(ActionOutcome.completed.isSuccess)
        #expect(!ActionOutcome.refused(reason: .accessibilityMissing).isSuccess)
        #expect(!ActionOutcome.refused(reason: .staleContext).isSuccess)
        #expect(!ActionOutcome.failed(reason: "x").isSuccess)
    }

    @Test("Media keys keep their protocol 1 names on the wire")
    func mediaKeyRawValues() {
        #expect(MediaKey.playPause.rawValue == "playpause")
        #expect(MediaKey.next.rawValue == "next")
        #expect(MediaKey.previous.rawValue == "prev")
    }
}
