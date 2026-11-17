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

@Suite struct DeckDocumentTests {

    private func key(_ id: String, _ action: Action, label: String = "Key") -> DeckKey {
        DeckKey(id: id, label: label, symbol: "star", action: action)
    }

    private var sample: DeckDocument {
        DeckDocument(pages: [
            DeckPage(id: "main", title: "Main", keys: [
                key("k1", .system(action: .missionControl)),
                key("k2", .media(key: .playPause)),
            ]),
            DeckPage(id: "xcode", title: "Xcode", appBundleID: "com.apple.dt.Xcode", keys: [
                key("k3", .appShortcut(bundleID: "com.apple.dt.Xcode", keys: ["cmd", "b"])),
            ]),
        ])
    }

    @Test("A deck round-trips through JSON")
    func roundTrip() throws {
        let data = try ControlMessageCoding.encoder.encode(sample)
        #expect(try ControlMessageCoding.decoder.decode(DeckDocument.self, from: data) == sample)
        #expect(sample.version == DeckDocument.currentVersion)
    }

    @Test("The frontmost app's page wins, else the first general page")
    func pageForFrontmostApp() {
        #expect(sample.page(forFrontmostApp: "com.apple.dt.Xcode")?.id == "xcode")
        #expect(sample.page(forFrontmostApp: "com.apple.Safari")?.id == "main")
        #expect(sample.page(forFrontmostApp: nil)?.id == "main")
        #expect(DeckDocument(pages: []).page(forFrontmostApp: nil) == nil)
    }

    @Test("A valid deck has no issues")
    func validDeck() {
        #expect(DeckValidation.issues(in: sample).isEmpty)
    }

    @Test("Validation finds every kind of problem")
    func invalidDecks() {
        let tooMany = (0...DeckValidation.maxKeysPerPage).map { key("many\($0)", .media(key: .next)) }
        let deck = DeckDocument(version: 99, pages: [
            DeckPage(id: "a", title: "A", keys: [
                key("dup", .shortcut(keys: [])),
                key("dup", .contextAction(id: "rev|0|OK"), label: "  "),
                key("long", .shortcut(keys: Array(repeating: "a", count: ProtocolLimits.maxChordKeys + 1)),
                    label: String(repeating: "L", count: DeckValidation.maxLabelLength + 1)),
            ]),
            DeckPage(id: "a", title: "Again", keys: tooMany),
        ])
        let issues = DeckValidation.issues(in: deck)
        #expect(issues.contains(.unsupportedVersion(99)))
        #expect(issues.contains(.duplicatePageID("a")))
        #expect(issues.contains(.duplicateKeyID("dup")))
        #expect(issues.contains(.emptyChord(keyID: "dup")))
        #expect(issues.contains(.emptyLabel(keyID: "dup")))
        #expect(issues.contains(.contextActionNotStorable(keyID: "dup")))
        #expect(issues.contains(.tooManyChordKeys(keyID: "long")))
        #expect(issues.contains(.labelTooLong(keyID: "long")))
        #expect(issues.contains(.tooManyKeys(pageID: "a", count: DeckValidation.maxKeysPerPage + 1)))
    }

    @Test("Too many pages is an issue")
    func tooManyPages() {
        let pages = (0...DeckValidation.maxPages).map { DeckPage(id: "p\($0)", title: "P", keys: []) }
        #expect(DeckValidation.issues(in: DeckDocument(pages: pages)) == [.tooManyPages(DeckValidation.maxPages + 1)])
    }
}
