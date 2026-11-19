//
//  DeckModelTests.swift
//  PixelHandCoreTests
//
//  Deck 2 model (D1): the document, its validation and repair, migration
//  from schema 1 and from the chips' stored data (fixtures in
//  `Fixtures/deck`), hostile input, the chip adapter, follow-front-app,
//  pixel glyphs, menu paths, Shortcuts runs, and the new actions' rules
//  in `RemoteInputValidation` and the lock gate.
//

import Foundation
import PixelHandCore
import Testing

private enum DeckFixtures {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/deck", isDirectory: true)

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }

    static func legacy() throws -> DeckMigration.LegacyChips {
        DeckMigration.LegacyChips.decode(
            customShortcuts: try data("legacy.customShortcuts.v1.json"),
            hiddenCurated: try data("legacy.hiddenCuratedShortcuts.v1.json"),
            pinnedApps: try data("legacy.pinnedBundleIDs.json"),
            hiddenApps: try data("legacy.hiddenBundleIDs.json")
        )
    }
}

private func key(_ id: String, _ action: Action, label: String = "Key") -> DeckKey {
    DeckKey(id: id, label: label, symbol: "star", action: action)
}

private var sampleDeck: DeckDocument {
    DeckDocument(pages: [
        DeckPage(id: "home", title: "Home", kind: .home, keys: [
            key("k1", .system(action: .missionControl)),
            key("k2", .media(key: .playPause)),
            DeckKey(
                id: "k5",
                appearance: KeyAppearance(label: "Ship", glyph: .custom(bitmap: PixelGlyphData(size: 8, rows: [0, 0x18, 0x24, 0x42, 0x24, 0x18, 0, 0], accent: GlyphDot(x: 3, y: 1))), tint: "mint"),
                action: .sequence(steps: [
                    .run(action: .menuCommand(bundleID: "com.apple.dt.Xcode", path: ["Product", "Archive"])),
                    .delay(milliseconds: 500),
                    .run(action: .macShortcut(name: "Upload build")),
                ]),
                confirm: true,
                pinnedToFirstRow: true
            ),
        ]),
        DeckPage(id: "xcode", title: "Xcode", kind: .app(bundleID: "com.apple.dt.Xcode"), keys: [
            key("k3", .appShortcut(bundleID: "com.apple.dt.Xcode", keys: ["cmd", "b"])),
            DeckKey(id: "k4", appearance: KeyAppearance(label: "Build", glyph: .pixel(id: "build")), action: .menuCommand(bundleID: "com.apple.dt.Xcode", path: ["Product", "Build"])),
        ], hiddenCuratedIDs: ["curated.xcode.run"]),
        DeckPage(id: "shortcuts", title: "Shortcuts", kind: .shortcuts, keys: [
            key("k6", .macShortcut(name: "Morning")),
        ]),
    ], pinnedPageID: nil)
}

// MARK: - Document

@Suite struct DeckDocumentTests {
    @Test("A deck round-trips through JSON and the stored encoding")
    func roundTrip() throws {
        let data = try ControlMessageCoding.encoder.encode(sampleDeck)
        #expect(try ControlMessageCoding.decoder.decode(DeckDocument.self, from: data) == sampleDeck)
        #expect(try DeckMigration.decode(try DeckMigration.encode(sampleDeck)) == sampleDeck)
        #expect(sampleDeck.schemaVersion == DeckDocument.currentVersion)
    }

    @Test("Stored encoding is stable: the same deck writes the same bytes")
    func stableEncoding() throws {
        #expect(try DeckMigration.encode(sampleDeck) == DeckMigration.encode(sampleDeck))
    }

    @Test("The frontmost app's page wins, else Home")
    func pageForFrontmostApp() {
        #expect(sampleDeck.page(forFrontmostApp: "com.apple.dt.Xcode")?.id == "xcode")
        #expect(sampleDeck.page(forFrontmostApp: "com.apple.Safari")?.id == "home")
        #expect(sampleDeck.page(forFrontmostApp: nil)?.id == "home")
        #expect(DeckDocument(pages: []).page(forFrontmostApp: nil) == nil)
        #expect(DeckDocument.empty.pages.map(\.kind) == [.home])
    }

    @Test("A valid deck has no issues")
    func validDeck() {
        #expect(DeckValidation.issues(in: sampleDeck).isEmpty)
        #expect(DeckValidation.isValid(DeckDocument.empty))
    }

    @Test("Validation finds every kind of problem")
    func invalidDecks() {
        let tooMany = (0...DeckValidation.maxKeysPerPage).map { key("many\($0)", .media(key: .next)) }
        let deck = DeckDocument(schemaVersion: 99, pages: [
            DeckPage(id: "a", title: "A", kind: .home, keys: [
                key("dup", .shortcut(keys: [])),
                key("dup", .contextAction(id: "rev|0|OK"), label: "  "),
                key("long", .shortcut(keys: Array(repeating: "a", count: ProtocolLimits.maxChordKeys + 1)),
                    label: String(repeating: "L", count: DeckValidation.maxLabelLength + 1)),
                DeckKey(id: "glyph", appearance: KeyAppearance(label: "G", glyph: .pixel(id: "no spaces"), tint: "bad tint"), action: .media(key: .next)),
            ]),
            DeckPage(id: "a", title: "Again", kind: .home, keys: tooMany),
            DeckPage(id: "", title: "Bad\u{0007}", kind: .app(bundleID: "not a bundle"), keys: []),
        ], pinnedPageID: "gone")
        let issues = DeckValidation.issues(in: deck)
        #expect(issues.contains(.unsupportedVersion(99)))
        #expect(issues.contains(.duplicatePageID("a")))
        #expect(issues.contains(.duplicatePageKind(pageID: "a")))
        #expect(issues.contains(.duplicateKeyID("dup")))
        #expect(issues.contains(.badAction(keyID: "dup", .emptyChord)))
        #expect(issues.contains(.emptyLabel(keyID: "dup")))
        #expect(issues.contains(.badAction(keyID: "dup", .contextActionNotStorable)))
        #expect(issues.contains(.badAction(keyID: "long", .tooManyChordKeys)))
        #expect(issues.contains(.labelTooLong(keyID: "long")))
        #expect(issues.contains(.badGlyph(keyID: "glyph")))
        #expect(issues.contains(.badTint(keyID: "glyph")))
        #expect(issues.contains(.tooManyKeys(pageID: "a", count: DeckValidation.maxKeysPerPage + 1)))
        #expect(issues.contains(.badPageID("")))
        #expect(issues.contains(.badPageTitle(pageID: "")))
        #expect(issues.contains(.badPageKind(pageID: "")))
        #expect(issues.contains(.unknownPinnedPage("gone")))
    }

    @Test("Too many pages is an issue")
    func tooManyPages() {
        let pages = (0...DeckValidation.maxPages).map { DeckPage(id: "p\($0)", title: "P", keys: []) }
        #expect(DeckValidation.issues(in: DeckDocument(pages: pages)) == [.tooManyPages(DeckValidation.maxPages + 1)])
    }

    @Test("Repair keeps the good parts and always yields a valid deck")
    func repairKeepsGoodParts() {
        let tooMany = (0..<(DeckValidation.maxKeysPerPage + 5)).map { key("many\($0)", .media(key: .next)) }
        let deck = DeckDocument(schemaVersion: 1, pages: [
            DeckPage(id: "a", title: String(repeating: "T", count: 200), kind: .home, keys: [
                key("ok", .media(key: .next)),
                key("ok", .media(key: .previous)),
                key("bad", .shortcut(keys: [])),
                key("long", .media(key: .next), label: String(repeating: "L", count: 300)),
                DeckKey(id: "glyph", appearance: KeyAppearance(label: "G", glyph: .custom(bitmap: PixelGlyphData(size: 12, rows: []))), action: .media(key: .next)),
            ]),
            DeckPage(id: "b", title: "Second home", kind: .home, keys: []),
            DeckPage(id: "c", title: "Big", keys: tooMany),
        ], pinnedPageID: "b")
        let fixed = DeckValidation.repaired(deck)
        #expect(DeckValidation.isValid(fixed))
        #expect(fixed.pages.map(\.id) == ["a", "c"])
        #expect(fixed.pages[0].keys.map(\.id) == ["ok", "long", "glyph"])
        #expect(fixed.pages[0].keys[1].label.count == DeckValidation.maxLabelLength)
        #expect(fixed.pages[0].keys[2].appearance.glyph == nil)
        #expect(fixed.pages[0].title.count == DeckValidation.maxTitleLength)
        #expect(fixed.pages[1].keys.count == DeckValidation.maxKeysPerPage)
        #expect(fixed.pinnedPageID == nil)
        #expect(fixed.schemaVersion == DeckDocument.currentVersion)
    }
}

// MARK: - Migration

@Suite struct DeckMigrationTests {
    @Test("Schema 1 migrates: app pages keep their app, the first general page becomes Home")
    func schema1() throws {
        let deck = try DeckMigration.decode(try DeckFixtures.data("deck.v1.json"))
        #expect(deck.schemaVersion == DeckDocument.currentVersion)
        #expect(deck.pages.map(\.id) == ["main", "xcode", "extra"])
        #expect(deck.pages.map(\.kind) == [.home, .app(bundleID: "com.apple.dt.Xcode"), .custom])
        #expect(deck.pages[0].keys[0].appearance == KeyAppearance(label: "Mission Control", glyph: .symbol(name: "rectangle.3.group")))
        #expect(deck.pages[0].keys[1].appearance.glyph == nil)
        #expect(deck.pages[1].keys[0].action == .appShortcut(bundleID: "com.apple.dt.Xcode", keys: ["cmd", "b"]))
        #expect(deck.followFrontApp)
        #expect(DeckValidation.isValid(deck))
    }

    @Test("Existing chips survive migration: custom, imported, hidden presets, pinned and hidden apps")
    func legacyChips() throws {
        let legacy = try DeckFixtures.legacy()
        let names = ["com.apple.Safari": "Safari", "com.apple.dt.Xcode": "Xcode"]
        let deck = DeckMigration.fromLegacy(legacy, appName: { names[$0] })
        #expect(DeckValidation.isValid(deck))
        #expect(deck.pages.map(\.id) == ["home", "app.com.apple.Safari", "app.com.apple.Terminal", "app.com.apple.dt.Xcode"])

        // Home launches the pinned apps.
        #expect(deck.pages[0].keys.map(\.action) == [.launchApp(bundleID: "com.apple.Safari"), .launchApp(bundleID: "com.apple.dt.Xcode")])
        #expect(deck.pages[0].keys.map(\.label) == ["Safari", "Xcode"])
        #expect(deck.hiddenAppBundleIDs == ["com.apple.Chess"])

        // Every chip shows exactly as before, through the adapter.
        for (bundleID, bindings) in legacy.customBindings {
            let shown = deck.chipBindings(for: bundleID)
            let hidden = Set(legacy.hiddenCuratedIDs[bundleID] ?? [])
            let curated = CuratedShortcuts.bindings(for: bundleID).filter { !hidden.contains($0.id) }
            #expect(shown == curated + bindings)
        }
        // Terminal only had a hidden preset.
        #expect(!deck.chipBindings(for: "com.apple.Terminal").contains { $0.id == "curated.terminal.new-tab" })
        #expect(deck.chipBindings(for: "com.apple.Terminal").count == CuratedShortcuts.bindings(for: "com.apple.Terminal").count - 1)
        #expect(deck.hiddenCuratedIDsByApp["com.apple.Safari"] == ["curated.safari.private-window", "curated.safari.downloads"])
        #expect(deck.customChipBindings == legacy.customBindings)
    }

    @Test("Legacy migration is deterministic and survives a store round trip")
    func legacyDeterministic() throws {
        let legacy = try DeckFixtures.legacy()
        let a = DeckMigration.fromLegacy(legacy)
        let b = DeckMigration.fromLegacy(legacy)
        #expect(try DeckMigration.encode(a) == DeckMigration.encode(b))
        #expect(try DeckMigration.decode(try DeckMigration.encode(a)) == a)
    }

    @Test("Missing or damaged legacy data reads as empty")
    func damagedLegacy() {
        let legacy = DeckMigration.LegacyChips.decode(customShortcuts: Data("nope".utf8), hiddenCurated: nil, pinnedApps: Data("{}".utf8), hiddenApps: nil)
        #expect(legacy.isEmpty)
        let deck = DeckMigration.fromLegacy(legacy)
        #expect(deck == DeckDocument.empty)
    }

    @Test("A newer schema is reported, not overwritten")
    func newerSchema() {
        #expect(throws: DeckMigration.Failure.newerVersion(3)) {
            try DeckMigration.decode(Data(#"{"schemaVersion":3,"pages":[],"anything":true}"#.utf8))
        }
    }
}

// MARK: - Hostile input

@Suite struct DeckHostileInputTests {
    @Test("Garbage, wrong shapes and unknown versions are unreadable, never a crash")
    func garbage() {
        let inputs = [
            "", "null", "[]", "42", "{", #"{"schemaVersion":"2"}"#, #"{"schemaVersion":0,"pages":[]}"#,
            #"{"schemaVersion":2}"#, #"{"schemaVersion":2,"pages":[{"id":"a"}]}"#,
            #"{"schemaVersion":-1,"pages":[]}"#, #"{"version":1,"pages":[{"id":"a","title":"A","keys":[{"id":"k","label":"L","action":{"warp":{}}}]}]}"#,
        ]
        for input in inputs {
            #expect(throws: DeckMigration.Failure.self) { try DeckMigration.decode(Data(input.utf8)) }
        }
    }

    @Test("An oversize document is refused before decoding")
    func oversize() {
        let data = Data(repeating: 0x20, count: DeckValidation.maxDocumentBytes + 1)
        #expect(throws: DeckMigration.Failure.tooLarge(bytes: data.count)) { try DeckMigration.decode(data) }
    }

    @Test("A nested sequence is refused while decoding, however deep")
    func nestedSequenceRefused() throws {
        var json = #"{"shortcut":{"keys":["a"]}}"#
        for _ in 0..<2_000 {
            json = #"{"sequence":{"steps":[{"run":{"action":\#(json)}}]}}"#
        }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Action.self, from: Data(json.utf8)) }
        let one = #"{"sequence":{"steps":[{"run":{"action":{"sequence":{"steps":[]}}}}]}}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Action.self, from: Data(one.utf8)) }
        let ok = #"{"sequence":{"steps":[{"run":{"action":{"shortcut":{"keys":["a"]}}}},{"delay":{"milliseconds":5}}]}}"#
        #expect(try JSONDecoder().decode(Action.self, from: Data(ok.utf8)) == .sequence(steps: [.run(action: .shortcut(keys: ["a"])), .delay(milliseconds: 5)]))
    }

    @Test("A step with two kinds, or none, is refused")
    func ambiguousStep() {
        for json in [#"{}"#, #"{"run":{"action":{"shortcut":{"keys":["a"]}}},"delay":{"milliseconds":1}}"#] {
            #expect(throws: (any Error).self) { try JSONDecoder().decode(SequenceStep.self, from: Data(json.utf8)) }
        }
    }

    @Test("A hostile stored deck is cut down to a valid one")
    func hostileDeckRepaired() throws {
        let hugeLabel = String(repeating: "💥", count: 10_000)
        let keys = (0..<500).map { i in
            DeckKey(id: "k\(i % 300)", appearance: KeyAppearance(label: hugeLabel, glyph: .symbol(name: "../../etc")), action: .launchApp(bundleID: "ok.app"))
        }
        let deck = DeckDocument(pages: (0..<80).map { DeckPage(id: "p\($0 % 60)", title: "P", keys: keys) }, hiddenAppBundleIDs: Array(repeating: "x y", count: 5_000))
        let data = try DeckMigration.encode(deck)
        guard data.count <= DeckValidation.maxDocumentBytes else {
            #expect(throws: DeckMigration.Failure.self) { try DeckMigration.decode(data) }
            return
        }
        let fixed = try DeckMigration.decode(data)
        #expect(DeckValidation.isValid(fixed))
        #expect(fixed.pages.count <= DeckValidation.maxPages)
        #expect(fixed.hiddenAppBundleIDs.isEmpty)
    }

    @Test("Hostile actions are invalid")
    func hostileActions() {
        let bad: [Action] = [
            .menuCommand(bundleID: "com.apple.Safari", path: []),
            .menuCommand(bundleID: "com.apple.Safari", path: Array(repeating: "File", count: ActionLimits.maxMenuPathComponents + 1)),
            .menuCommand(bundleID: "com.apple.Safari", path: ["File\n"]),
            .menuCommand(bundleID: "com.apple.Safari", path: ["   "]),
            .menuCommand(bundleID: "com.apple.Safari", path: [String(repeating: "x", count: ActionLimits.maxMenuTitleBytes + 1)]),
            .menuCommand(bundleID: "; rm -rf /", path: ["File"]),
            .macShortcut(name: ""),
            .macShortcut(name: "--help"),
            .macShortcut(name: "name\u{0000}"),
            .macShortcut(name: String(repeating: "x", count: ActionLimits.maxShortcutNameBytes + 1)),
            .sequence(steps: []),
            .sequence(steps: Array(repeating: .delay(milliseconds: 1), count: ActionLimits.maxSequenceSteps + 1)),
            .sequence(steps: [.delay(milliseconds: -1)]),
            .sequence(steps: [.delay(milliseconds: ActionLimits.maxDelayMilliseconds + 1)]),
            .sequence(steps: Array(repeating: .delay(milliseconds: ActionLimits.maxDelayMilliseconds), count: 4)),
            .sequence(steps: [.run(action: .sequence(steps: [.delay(milliseconds: 1)]))]),
            .sequence(steps: [.run(action: .contextAction(id: "rev|1|OK"))]),
            .sequence(steps: [.run(action: .shortcut(keys: []))]),
            .launchApp(bundleID: ""),
            .shortcut(keys: [String(repeating: "k", count: 33)]),
        ]
        for action in bad {
            #expect(!ActionValidation.isValid(action, storable: false), "\(action)")
            #expect(!RemoteInputValidation.isAcceptable(action), "\(action)")
            #expect(RemoteInputValidation.sanitize(.deck(.run(requestID: "r", action: action))) == nil, "\(action)")
        }
    }
}

// MARK: - Actions on the wire

@Suite struct Deck2ActionRuleTests {
    static let good: [Action] = [
        .menuCommand(bundleID: "com.apple.dt.Xcode", path: ["Product", "Build For", "Testing"]),
        .macShortcut(name: "Start “Focus” timer"),
        .sequence(steps: [
            .run(action: .launchApp(bundleID: "com.apple.Terminal")),
            .delay(milliseconds: ActionLimits.maxDelayMilliseconds),
            .run(action: .appShortcut(bundleID: "com.apple.Terminal", keys: ["cmd", "t"])),
            .run(action: .macShortcut(name: "x")),
        ]),
    ]

    @Test("Valid Deck 2 runs pass validation unchanged")
    func validRunsPass() {
        for action in Self.good {
            let run = ControlMessage.deck(.run(requestID: "r1", action: action))
            #expect(RemoteInputValidation.sanitize(run) == run)
            #expect(ActionValidation.isValid(action, storable: true))
        }
        // A dialog press is fine to send, but not to store.
        #expect(ActionValidation.isValid(.contextAction(id: "rev|1|OK"), storable: false))
        #expect(!ActionValidation.isValid(.contextAction(id: "rev|1|OK"), storable: true))
    }

    @Test("Locked: menu commands and Shortcuts are refused with a receipt")
    func lockedRefusesDeck2() {
        for state in [MacLockState.screenLocked, .offConsole] {
            for action in [Action.menuCommand(bundleID: "a.b", path: ["File"]), .macShortcut(name: "x")] {
                #expect(LockPolicy.decide(.deck(.run(requestID: "r", action: action)), state: state) == .refuse(reply: .receipt(requestID: "r")))
                #expect(!LockPolicy.allows(action, state: state))
            }
        }
        for action in Self.good {
            #expect(LockPolicy.decide(.deck(.run(requestID: "r", action: action)), state: .unlocked) == .allow)
        }
    }

    @Test("Locked: a sequence runs only when every step may")
    func lockedSequence() {
        let typing = Action.sequence(steps: [.run(action: .shortcut(keys: ["cmd", "a"])), .delay(milliseconds: 100), .run(action: .media(key: .next))])
        let launching = Action.sequence(steps: [.run(action: .shortcut(keys: ["cmd", "a"])), .run(action: .launchApp(bundleID: "a.b"))])
        let pauses = Action.sequence(steps: [.delay(milliseconds: 1)])
        #expect(LockPolicy.allows(typing, state: .screenLocked))
        #expect(!LockPolicy.allows(typing, state: .offConsole))
        #expect(!LockPolicy.allows(launching, state: .screenLocked))
        #expect(LockPolicy.allows(pauses, state: .offConsole))
        #expect(LockPolicy.decide(.deck(.run(requestID: "r", action: launching)), state: .screenLocked) == .refuse(reply: .receipt(requestID: "r")))
    }

    @Test("Old actions keep their lock rules through allows")
    func oldActionsUnchanged() {
        for action in ActionTests.allKinds where action.message != nil {
            for state in MacLockState.allCases {
                #expect(LockPolicy.allows(action, state: state) == (LockPolicy.decide(action.message!, state: state) == .allow))
            }
        }
    }

    @Test("A deck run is a person's action for display wake")
    func deckRunWakes() {
        #expect(DisplayWakePolicy.isPersonAction(.deck(.run(requestID: "r", action: .macShortcut(name: "x")))))
    }
}

// MARK: - Menu paths and Shortcuts runs

@Suite struct MenuPathTests {
    @Test("Titles match ignoring case, ellipses, spacing and diacritics")
    func matching() {
        #expect(MenuPath.matches("Export…", "export"))
        #expect(MenuPath.matches("Export...", "Export…"))
        #expect(MenuPath.matches("  Café ", "cafe"))
        #expect(!MenuPath.matches("Export as PDF", "Export"))
        #expect(!MenuPath.matches("", ""))
    }

    @Test("An exact title beats an earlier loose match")
    func exactFirst() {
        #expect(MenuPath.index(of: "Save…", in: ["save", "Save…"]) == 1)
        #expect(MenuPath.index(of: "Save", in: ["Open", "Save…"]) == 1)
        #expect(MenuPath.index(of: "Quit", in: ["Open"]) == nil)
    }

    @Test("An imported chip's name gives its menu path")
    func pathFromName() {
        #expect(MenuPath.path(fromDisplayName: "File › New Tab") == ["File", "New Tab"])
        #expect(MenuPath.path(fromDisplayName: "New Tab") == nil)
        #expect(MenuPath.path(fromDisplayName: " › x") == nil)
    }
}

@Suite struct MacShortcutRunTests {
    @Test("The name is one argument, never an option")
    func arguments() {
        #expect(MacShortcutRun.arguments(name: "Say \"hi\"; rm -rf ~") == ["run", "Say \"hi\"; rm -rf ~"])
        #expect(MacShortcutRun.arguments(name: "-i") == nil)
        #expect(MacShortcutRun.arguments(name: "a\nb") == nil)
    }

    @Test("Exit status, timeout and a missing tool become receipts")
    func outcomes() {
        #expect(MacShortcutRun.outcome(.exited(status: 0), name: "x") == .completed)
        #expect(!MacShortcutRun.outcome(.exited(status: 1), name: "x").isSuccess)
        #expect(!MacShortcutRun.outcome(.timedOut, name: "x").isSuccess)
        #expect(!MacShortcutRun.outcome(.couldNotStart, name: "x").isSuccess)
    }
}

// MARK: - Chips adapter

@Suite struct DeckChipAdapterTests {
    private let safari = "com.apple.Safari"

    @Test("Add, update, delete and import chips through the deck")
    func editing() {
        var deck = DeckDocument.empty
        let custom = AppShortcutBinding(id: "c1", bundleID: safari, displayName: "Tabs", keys: ["cmd", "shift", "\\"], sfSymbol: "square.grid.2x2")
        let r1 = deck.addChip(custom)
        #expect(r1)
        let again = deck.addChip(custom)
        #expect(!again) // same ID
        #expect(deck.appPage(for: safari)?.id == "app.com.apple.Safari")
        #expect(deck.chipBindings(for: safari).last == custom)

        let renamed = AppShortcutBinding(id: "c1", bundleID: safari, displayName: "Tab Overview", keys: ["cmd", "shift", "\\"], sfSymbol: "square.grid.2x2")
        let r2 = deck.updateChip(renamed)
        #expect(r2)
        #expect(deck.chipBindings(for: safari).last == renamed)

        let curated = CuratedShortcuts.bindings(for: safari)[0]
        deck.deleteChip(curated)
        #expect(!deck.chipBindings(for: safari).contains(curated))
        deck.restoreCurated(for: safari)
        #expect(deck.chipBindings(for: safari).contains(curated))

        deck.deleteChip(renamed)
        #expect(!deck.chipBindings(for: safari).contains { $0.id == "c1" })
        #expect(DeckValidation.isValid(deck))
    }

    @Test("Importing is idempotent and skips chips already shown")
    func importing() {
        var deck = DeckDocument.empty
        let curated = CuratedShortcuts.bindings(for: safari)[0]
        let incoming = [
            AppShortcutBinding(id: "imported.a", bundleID: safari, displayName: "File › Export", keys: ["cmd", "e"], category: "File"),
            AppShortcutBinding(id: "imported.dupe", bundleID: safari, displayName: curated.displayName, keys: curated.keys),
            AppShortcutBinding(id: "imported.other", bundleID: "com.other", displayName: "X", keys: ["cmd", "x"]),
        ]
        let r3 = deck.importChips(incoming, for: safari)
        #expect(r3 == 1)
        let r4 = deck.importChips(incoming, for: safari)
        #expect(r4 == 0)
        #expect(deck.chipBindings(for: safari).last?.category == "File")
    }

    @Test("Keys that aren't chips stay on the page but out of the chip row")
    func otherKeysHidden() {
        var deck = DeckDocument.empty
        _ = deck.ensureAppPage(for: safari)
        let index = deck.pageIndex(id: "app.com.apple.Safari")!
        deck.pages[index].keys.append(DeckKey(id: "m", label: "Export", action: .menuCommand(bundleID: safari, path: ["File", "Export"])))
        #expect(deck.chipBindings(for: safari) == CuratedShortcuts.bindings(for: safari))
    }

    @Test("A full page refuses more chips")
    func fullPage() {
        var deck = DeckDocument.empty
        for i in 0..<DeckValidation.maxKeysPerPage {
            let added = deck.addChip(AppShortcutBinding(id: "c\(i)", bundleID: safari, displayName: "C\(i)", keys: ["cmd", "\(i % 10)"]))
            #expect(added)
        }
        let r5 = deck.addChip(AppShortcutBinding(id: "over", bundleID: safari, displayName: "Over", keys: ["cmd", "o"]))
        #expect(!r5)
    }
}

// MARK: - Follow front app

@Suite struct DeckFollowerTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    @Test("Follows the front app after the debounce, and returns when it goes")
    func follows() {
        var follower = DeckFollower(shownPageID: "home")
        follower.frontAppChanged(to: "com.apple.dt.Xcode", at: t0)
        let r6 = follower.update(document: sampleDeck, now: t0.addingTimeInterval(0.2))
        #expect(!r6)
        #expect(follower.shownPageID == "home")
        let r7 = follower.update(document: sampleDeck, now: t0.addingTimeInterval(0.4))
        #expect(r7)
        #expect(follower.shownPageID == "xcode")
        #expect(follower.followedBundleID == "com.apple.dt.Xcode")

        follower.frontAppChanged(to: "com.apple.Finder", at: t0.addingTimeInterval(1))
        let r8 = follower.update(document: sampleDeck, now: t0.addingTimeInterval(1.5))
        #expect(r8)
        #expect(follower.shownPageID == "home")
    }

    @Test("Cmd-Tab cycling inside the debounce doesn't switch")
    func debounced() {
        var follower = DeckFollower(shownPageID: "home")
        follower.frontAppChanged(to: "com.apple.dt.Xcode", at: t0)
        follower.frontAppChanged(to: "com.apple.Safari", at: t0.addingTimeInterval(0.1))
        follower.frontAppChanged(to: "com.apple.Finder", at: t0.addingTimeInterval(0.2))
        let r9 = follower.update(document: sampleDeck, now: t0.addingTimeInterval(0.7))
        #expect(!r9)
        #expect(follower.shownPageID == "home")
    }

    @Test("A pin or Follow off stops switching")
    func pinned() {
        var deck = sampleDeck
        deck.pinnedPageID = "shortcuts"
        var follower = DeckFollower(shownPageID: "home")
        follower.frontAppChanged(to: "com.apple.dt.Xcode", at: t0)
        let r10 = follower.update(document: deck, now: t0.addingTimeInterval(1))
        #expect(!r10)
        #expect(follower.effectivePageID(in: deck) == "shortcuts")

        deck.pinnedPageID = nil
        deck.followFrontApp = false
        follower.frontAppChanged(to: "com.apple.dt.Xcode", at: t0)
        let r11 = follower.update(document: deck, now: t0.addingTimeInterval(1))
        #expect(!r11)
        #expect(follower.effectivePageID(in: deck) == "home")
    }

    @Test("The user's own choice is where it returns to")
    func userChoice() {
        var follower = DeckFollower(shownPageID: "home")
        follower.userSelected(pageID: "shortcuts")
        follower.frontAppChanged(to: "com.apple.dt.Xcode", at: t0)
        follower.update(document: sampleDeck, now: t0.addingTimeInterval(0.5))
        #expect(follower.shownPageID == "xcode")
        follower.frontAppChanged(to: nil, at: t0.addingTimeInterval(1))
        follower.update(document: sampleDeck, now: t0.addingTimeInterval(1.5))
        #expect(follower.shownPageID == "shortcuts")
        #expect(follower.nextDeadline == nil)
    }
}

// MARK: - Pixel glyphs

@Suite struct PixelGlyphDataTests {
    @Test("Well formed: allowed size, one row per line, nothing past the edge, accent on a lit dot")
    func wellFormed() {
        #expect(PixelGlyphData.blank(size: 8).isWellFormed)
        #expect(PixelGlyphData.blank(size: 9).isWellFormed)
        #expect(!PixelGlyphData.blank(size: 7).isWellFormed)
        #expect(!PixelGlyphData(size: 8, rows: [0]).isWellFormed)
        #expect(!PixelGlyphData(size: 8, rows: [0x100, 0, 0, 0, 0, 0, 0, 0]).isWellFormed)
        #expect(!PixelGlyphData(size: 8, rows: Array(repeating: 0, count: 8), accent: GlyphDot(x: 0, y: 0)).isWellFormed)
        let lit = PixelGlyphData.blank(size: 9).setting(x: 8, y: 8, on: true)
        #expect(lit.isOn(x: 8, y: 8))
        #expect(PixelGlyphData(size: 9, rows: lit.rows, accent: GlyphDot(x: 8, y: 8)).isWellFormed)
        #expect(!lit.isOn(x: 9, y: 8))
        #expect(lit.setting(x: 20, y: -1, on: true) == lit)
    }

    @Test("A 2 × 2 block is flagged as a thick stroke")
    func thickStroke() {
        let line = PixelGlyphData.blank(size: 8).setting(x: 1, y: 1, on: true).setting(x: 2, y: 1, on: true)
        #expect(!line.hasThickStroke)
        #expect(line.setting(x: 1, y: 2, on: true).setting(x: 2, y: 2, on: true).hasThickStroke)
    }
}
