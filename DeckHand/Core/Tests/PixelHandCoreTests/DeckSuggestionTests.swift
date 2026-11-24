//
//  DeckSuggestionTests.swift
//  PixelHandCoreTests
//
//  "Suggest a deck" (UX-021): the deterministic ranker, model picks that
//  can only reorder, the panel's copy and Keep.
//

import Foundation
import PixelHandCore
import Testing

private let xcode = "com.apple.dt.Xcode"

private func menu(_ path: String, _ keys: [String], app: String = xcode) -> AppShortcutBinding {
    let category = path.components(separatedBy: " › ").first
    return AppShortcutBinding(
        id: "imported.\(app).\(path.lowercased().replacingOccurrences(of: " ", with: "-"))",
        bundleID: app,
        displayName: path,
        keys: keys,
        sfSymbol: "keyboard",
        category: category
    )
}

private let xcodeMenus: [AppShortcutBinding] = [
    menu("Xcode › Settings", ["cmd", ","]),
    menu("Xcode › Hide Xcode", ["cmd", "h"]),
    menu("Xcode › Quit Xcode", ["cmd", "q"]),
    menu("File › New", ["cmd", "n"]),
    menu("File › Open Quickly", ["cmd", "shift", "o"]),
    menu("Edit › Copy", ["cmd", "c"]),
    menu("Edit › Paste", ["cmd", "v"]),
    menu("Edit › Undo", ["cmd", "z"]),
    menu("Editor › Show Minimap", ["ctrl", "shift", "cmd", "m"]),
    menu("Product › Build", ["cmd", "b"]),
    menu("Product › Run", ["cmd", "r"]),
    menu("Product › Test", ["cmd", "u"]),
    menu("Window › Minimize", ["cmd", "m"]),
    menu("Help › Xcode Help", ["cmd", "shift", "/"]),
]

@Suite("Deck suggestion ranker")
struct DeckSuggestionRankerTests {
    @Test("Well-known app commands rank above generic editing and the Window menu")
    func ranksWellKnownFirst() {
        let ranked = DeckSuggestionRanker.rank(xcodeMenus, bundleID: xcode, existing: [])
        let titles = ranked.map(\.binding.shortDisplayName)
        #expect(Array(titles.prefix(3)) == ["Build", "Run", "Test"])
        let build = titles.firstIndex(of: "Build")!
        let copy = titles.firstIndex(of: "Copy")!
        let help = titles.firstIndex(of: "Xcode Help")!
        #expect(build < copy)
        #expect(titles.firstIndex(of: "Show Minimap")! < help)
    }

    @Test("Quit, Hide and Minimize are never suggested")
    func excludesDangerousCommands() {
        let titles = DeckSuggestionRanker.rank(xcodeMenus, bundleID: xcode, existing: []).map(\.binding.shortDisplayName)
        #expect(!titles.contains("Quit Xcode"))
        #expect(!titles.contains("Hide Xcode"))
        #expect(!titles.contains("Minimize"))
    }

    @Test("Hiding a pane is still a useful command")
    func keepsHidePaneCommands() {
        let hideSidebar = menu("View › Hide Sidebar", ["cmd", "ctrl", "s"])
        let ranked = DeckSuggestionRanker.rank([hideSidebar], bundleID: xcode, existing: [])
        #expect(ranked.count == 1)
    }

    @Test("Keys already on the page are dropped by ID, name and chord, and chords match in any order")
    func dedupesAgainstExisting() {
        let existing = [
            DeckKey(binding: xcodeMenus[9]), // Build, same ID
            DeckKey(id: "mine", label: "Run", action: .appShortcut(bundleID: xcode, keys: ["cmd", "r"])),
            DeckKey(id: "chord", label: "Open Fast", action: .appShortcut(bundleID: xcode, keys: ["shift", "cmd", "o"])),
        ]
        let titles = DeckSuggestionRanker.rank(xcodeMenus, bundleID: xcode, existing: existing).map(\.binding.shortDisplayName)
        #expect(!titles.contains("Build"))
        #expect(!titles.contains("Run"))
        #expect(!titles.contains("Open Quickly"))
        #expect(titles.contains("Test"))
    }

    @Test("Repeats inside the menus count once, and other apps' bindings are ignored")
    func dedupesWithinMenus() {
        let menus = [
            menu("Product › Build", ["cmd", "b"]),
            menu("Product › Build Again", ["cmd", "b"]),
            menu("File › New Tab", ["cmd", "t"], app: "com.apple.Safari"),
        ]
        let ranked = DeckSuggestionRanker.rank(menus, bundleID: xcode, existing: [])
        #expect(ranked.map(\.binding.shortDisplayName) == ["Build"])
    }

    @Test("The list is capped, at 24 by default")
    func caps() {
        let many = (0..<40).map { menu("Tools › Tool \($0)", ["cmd", "option", "\($0 % 10)"]).withID("t\($0)") }
        let ranked = DeckSuggestionRanker.rank(many, bundleID: xcode, existing: [])
        // Chords repeat every 10, so only 10 survive de-duplication.
        #expect(ranked.count == 10)
        let distinct = (0..<40).map { menu("Tools › Tool \($0)", ["cmd", "option", "f\($0)"]).withID("d\($0)") }
        #expect(DeckSuggestionRanker.rank(distinct, bundleID: xcode, existing: []).count == DeckSuggestionRanker.maxSuggestions)
        #expect(DeckSuggestionRanker.rank(distinct, bundleID: xcode, existing: [], limit: 3).count == 3)
    }

    @Test("Ranking is deterministic: equal scores keep menu order")
    func deterministic() {
        let menus = (0..<6).map { menu("Tools › Thing \($0)", ["cmd", "option", "\($0)"]).withID("x\($0)") }
        let first = DeckSuggestionRanker.rank(menus, bundleID: xcode, existing: [])
        let second = DeckSuggestionRanker.rank(menus, bundleID: xcode, existing: [])
        #expect(first == second)
        #expect(first.map(\.id) == menus.map(\.id))
    }

    @Test("Menus the user already keeps keys from rank higher")
    func menuFrequency() {
        let a = menu("Navigate › Jump Somewhere", ["cmd", "option", "j"])
        let b = menu("Debug › Step Somewhere", ["cmd", "option", "k"])
        let plain = DeckSuggestionRanker.rank([a, b], bundleID: xcode, existing: [])
        #expect(plain.first?.binding.shortDisplayName == "Jump Somewhere")
        var mine = DeckKey(id: "mine", label: "Step Over", action: .appShortcut(bundleID: xcode, keys: ["f6"]))
        mine.category = "Debug"
        let weighted = DeckSuggestionRanker.rank([a, b], bundleID: xcode, existing: [mine])
        #expect(weighted.first?.binding.shortDisplayName == "Step Somewhere")
    }

    @Test("A suggestion keeps the menu item's own name as its label and its menu as category")
    func suggestionKey() {
        let suggestion = DeckSuggestion(binding: xcodeMenus[8], score: 1)
        let key = suggestion.key
        #expect(key.label == "Show Minimap")
        #expect(key.category == "Editor")
        #expect(key.action == .appShortcut(bundleID: xcode, keys: ["ctrl", "shift", "cmd", "m"]))
        #expect(key.id == xcodeMenus[8].id)
        #expect(DeckValidation.keyIssues(key).isEmpty)
    }
}

@Suite("Deck suggestion model picks")
struct DeckSuggestionModelPickTests {
    private var ranked: [DeckSuggestion] {
        DeckSuggestionRanker.rank(xcodeMenus, bundleID: xcode, existing: [])
    }

    @Test("Model picks go first in the model's order; the rest follow in ranked order")
    func reorders() {
        let base = ranked
        let out = DeckSuggestionRanker.applyingModelPicks([3, 0], to: base)
        #expect(out.first == base[3])
        #expect(out[1] == base[0])
        #expect(out.count == base.count)
        #expect(Set(out.map(\.id)) == Set(base.map(\.id)))
    }

    @Test("Indices that don't exist and repeats are ignored, so a model can't add keys")
    func constrained() {
        let base = ranked
        let out = DeckSuggestionRanker.applyingModelPicks([99, -1, 2, 2], to: base)
        #expect(out.count == base.count)
        #expect(out.first == base[2])
    }

    @Test("Picks respect the cap")
    func capped() {
        #expect(DeckSuggestionRanker.applyingModelPicks([1, 2, 3], to: ranked, limit: 2).count == 2)
    }

    @Test("Prompt lines number candidates from 0 with name and chord")
    func promptLines() {
        let lines = DeckSuggestionRanker.promptLines(for: ranked)
        #expect(lines.first == "0. Product › Build (⌘B)")
    }
}

@Suite("Deck suggestion copy and Keep")
struct DeckSuggestionKeepTests {
    @Test("Board copy")
    func copy() {
        #expect(DeckSuggestionCopy.title(count: 3, appName: "Xcode") == "3 suggestions from Xcode’s menus")
        #expect(DeckSuggestionCopy.title(count: 1, appName: "Finder") == "1 suggestion from Finder’s menus")
        #expect(DeckSuggestionCopy.kept(count: 1) == "Kept 1 key")
    }

    @Test("Keep all makes the app page when missing and adds every key once")
    func keepAllMakesPage() {
        var document = DeckDocument.empty
        let keys = DeckSuggestionRanker.rank(xcodeMenus, bundleID: xcode, existing: []).prefix(3).map(\.key)
        let added = document.keepSuggestions(Array(keys), forApp: xcode, title: "Xcode")
        #expect(added == 3)
        let page = document.appPage(for: xcode)
        #expect(page?.title == "Xcode")
        #expect(page?.keys.map(\.label) == ["Build", "Run", "Test"])
        #expect(document.keepSuggestions(Array(keys), forApp: xcode) == 0)
        #expect(DeckValidation.isValid(document))
    }

    @Test("Keep stops at a full page")
    func keepFullPage() {
        var document = DeckDocument.empty
        let filler = (0..<DeckValidation.maxKeysPerPage - 1).map {
            DeckKey(id: "f\($0)", label: "F\($0)", action: .appShortcut(bundleID: xcode, keys: ["cmd", "option", "f\($0 % 12 + 1)"]))
        }
        _ = document.ensureAppPage(for: xcode)
        for key in filler { _ = document.addKey(key, toPage: document.appPage(for: xcode)!.id) }
        let keys = DeckSuggestionRanker.rank(xcodeMenus, bundleID: xcode, existing: []).prefix(3).map(\.key)
        #expect(document.keepSuggestions(Array(keys), forApp: xcode) == 1)
    }

    @Test("Keep and its undo are one step in the editor's history")
    func undoKeep() {
        var history = DeckUndoHistory<DeckDocument>()
        var document = DeckDocument.empty
        let before = document
        let keys = DeckSuggestionRanker.rank(xcodeMenus, bundleID: xcode, existing: []).map(\.key)
        document.keepSuggestions(keys, forApp: xcode, title: "Xcode")
        history.record(before)
        #expect(history.undoCount == 1)
        #expect(history.undo(current: document) == before)
    }

    @Test("Suggested keys are not editable in place")
    func suggestedSource() {
        let shown = DeckShownKey(key: DeckSuggestion(binding: xcodeMenus[9], score: 0).key, source: .suggested)
        #expect(!shown.isEditable)
    }
}

private extension AppShortcutBinding {
    func withID(_ id: String) -> AppShortcutBinding {
        AppShortcutBinding(id: id, bundleID: bundleID, displayName: displayName, keys: keys, sfSymbol: sfSymbol, category: category)
    }
}

@Suite("Deck suggestion existing keys")
struct DeckSuggestionExistingTests {
    @Test("Existing keys are the app page's shown keys, or the curated presets without a page")
    func existing() {
        var document = DeckDocument.empty
        let curated = CuratedShortcuts.bindings(for: "com.apple.Safari").map(\.id)
        #expect(document.existingKeys(forApp: "com.apple.Safari").map(\.id) == curated)
        let key = DeckSuggestion(binding: xcodeMenus[9], score: 0).key
        document.keepSuggestions([key], forApp: xcode)
        #expect(document.existingKeys(forApp: xcode).map(\.id).contains(key.id))
    }
}
