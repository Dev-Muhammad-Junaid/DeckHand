//
//  DeckUITests.swift
//  PixelHandCoreTests
//
//  The Deck 2 UI's logic (UX-020): which keys a page shows, glyph
//  resolution, the grid by type size, editor changes, undo, the action
//  library and the pixel glyph editor's operations.
//

import Foundation
import PixelHandCore
import Testing

private let safari = "com.apple.Safari"

private func deck() -> DeckDocument {
    DeckDocument(pages: [
        DeckPage(id: "home", title: "Home", kind: .home, keys: [
            DeckKey(id: "k.mission", label: "Mission Control", action: .system(action: .missionControl)),
        ]),
        DeckPage(id: "ctx", title: "Context", kind: .context, keys: []),
        DeckPage(id: DeckPage.appPageID(for: safari), title: "Safari", kind: .app(bundleID: safari), keys: [
            DeckKey(id: "k.a", label: "A", action: .appShortcut(bundleID: safari, keys: ["cmd", "a"])),
            DeckKey(id: "k.b", label: "B", action: .appShortcut(bundleID: safari, keys: ["cmd", "b"])),
            DeckKey(id: "k.c", label: "C", action: .appShortcut(bundleID: safari, keys: ["cmd", "c"])),
        ]),
    ])
}

private var safariPageID: String { DeckPage.appPageID(for: safari) }

@Suite("Deck pages show the right keys")
struct DeckShownKeysTests {
    @Test("An app page shows its curated presets, then its stored keys")
    func appPageShowsCuratedThenStored() throws {
        let doc = deck()
        let page = try #require(doc.page(id: safariPageID))
        let shown = doc.shownKeys(on: page, frontBundleID: nil)
        let curatedCount = CuratedShortcuts.bindings(for: safari).count
        #expect(curatedCount > 0)
        #expect(shown.prefix(curatedCount).allSatisfy { $0.source == .curated })
        #expect(shown.suffix(3).map(\.id) == ["k.a", "k.b", "k.c"])
    }

    @Test("A hidden curated preset doesn't show")
    func hiddenCuratedIsHidden() throws {
        var doc = deck()
        let first = try #require(CuratedShortcuts.bindings(for: safari).first)
        doc.removeKey(id: first.id, fromPage: safariPageID)
        let page = try #require(doc.page(id: safariPageID))
        #expect(page.hiddenCuratedIDs == [first.id])
        #expect(!doc.shownKeys(on: page, frontBundleID: nil).contains { $0.id == first.id })
    }

    @Test("The Context page shows the front app's keys after its own")
    func contextFollowsFrontApp() throws {
        let doc = deck()
        let ctx = try #require(doc.page(id: "ctx"))
        #expect(doc.shownKeys(on: ctx, frontBundleID: nil).isEmpty)
        let shown = doc.shownKeys(on: ctx, frontBundleID: safari)
        #expect(shown.allSatisfy { $0.source == .frontApp })
        #expect(shown.contains { $0.id == "k.b" })
        // An app with no page still gets its curated presets.
        let finder = doc.shownKeys(on: ctx, frontBundleID: "com.apple.finder")
        #expect(finder.count == CuratedShortcuts.bindings(for: "com.apple.finder").count)
    }

    @Test("Keys pinned to the first row come first")
    func pinnedFirst() throws {
        var doc = deck()
        var key = try #require(doc.page(id: safariPageID)?.keys.last)
        key.pinnedToFirstRow = true
        doc.updateKey(key, onPage: safariPageID)
        let shown = doc.shownKeys(on: try #require(doc.page(id: safariPageID)), frontBundleID: nil)
        #expect(shown.first?.id == "k.c")
    }

    @Test("Pages page Home, Context, then the rest")
    func pageOrder() {
        var doc = deck()
        doc.pages.reverse()
        #expect(doc.orderedPages.map(\.id) == ["home", "ctx", safariPageID])
    }
}

@Suite("Deck key glyphs")
struct DeckGlyphResolutionTests {
    @Test("A custom glyph draws the user's dots in the top-left 8 × 8")
    func customGlyph() {
        let data = PixelGlyphData.blank(size: 8).setting(x: 7, y: 7, on: true).setting(x: 0, y: 0, on: true)
        let bitmap = data.bitmap()
        #expect(bitmap.isOn(0, 0))
        #expect(bitmap.isOn(7, 7))
        #expect(!bitmap.isOn(8, 8))
        #expect(bitmap.litPoints.count == 2)
    }

    @Test("A malformed custom glyph draws blank instead of trapping")
    func malformedGlyph() {
        let bad = PixelGlyphData(size: 8, rows: [0xFFFF])
        #expect(bad.bitmap().litPoints.isEmpty)
    }

    @Test("Glyph preference: custom, set ID (unknown falls back), app icon, symbol, action")
    func preferenceOrder() {
        func key(_ glyph: KeyGlyph?, _ action: Action = .shortcut(keys: ["cmd", "s"])) -> DeckKey {
            DeckKey(id: "k", appearance: KeyAppearance(label: "K", glyph: glyph), action: action)
        }
        #expect(DeckGlyphs.resolve(key(.pixel(id: "build"))) == .pixel(PixelGlyphs.build))
        #expect(DeckGlyphs.resolve(key(.pixel(id: "nope"))) == .pixel(PixelGlyphs.keyboard))
        #expect(DeckGlyphs.resolve(key(.appIcon(bundleID: safari))) == .appIcon(bundleID: safari))
        #expect(DeckGlyphs.resolve(key(.symbol(name: "magnifyingglass"))) == .pixel(PixelGlyphs.find))
        #expect(DeckGlyphs.resolve(key(.symbol(name: "weird.symbol"))) == .pixel(PixelGlyphs.keyboard))
        #expect(DeckGlyphs.resolve(key(nil, .launchApp(bundleID: safari))) == .appIcon(bundleID: safari))
        #expect(DeckGlyphs.resolve(key(nil, .system(action: .showDesktop))) == .pixel(PixelGlyphs.showDesktop))
    }

    @Test("Every curated preset's symbol resolves to a set glyph or the keyboard")
    func curatedSymbolsDraw() {
        for bundleID in CuratedShortcuts.curatedBundleIDs {
            for binding in CuratedShortcuts.bindings(for: bundleID) {
                if case let .pixel(bitmap) = DeckGlyphs.resolve(DeckKey(binding: binding)) {
                    #expect(PixelGlyphs.named(bitmap.name) != nil)
                } else {
                    Issue.record("\(binding.id) didn't resolve to a pixel glyph")
                }
            }
        }
    }
}

@Suite("Deck text and grid")
struct DeckTextAndGridTests {
    @Test("Chords and summaries read plainly")
    func text() {
        #expect(Action.shortcut(keys: ["cmd", "shift", "k"]).chordText == "⇧⌘K")
        #expect(Action.system(action: .missionControl).chordText == nil)
        let sequence = Action.sequence(steps: [.run(action: .media(key: .next)), .delay(milliseconds: 100), .run(action: .media(key: .next))])
        #expect(sequence.chordText == "2 steps")
        #expect(Action.menuCommand(bundleID: safari, path: ["File", "New Tab"]).summary { _ in "Safari" } == "Menu › File › New Tab in Safari")
        #expect(Action.macShortcut(name: "Tidy").summary() == "Run the Shortcut “Tidy”")
    }

    @Test("The grid keeps the class's columns, 3 at AX1–AX2, rows at AX3+")
    func gridByBand() {
        let phone = LayoutMetrics(width: 402, height: 874)
        #expect(phone.deckStyle(for: .standard) == .grid(columns: 4))
        #expect(phone.deckStyle(for: .large) == .grid(columns: 3))
        #expect(phone.deckStyle(for: .huge) == .rows)
        #expect(phone.deckGrid(for: .standard) == phone.deckGrid)
        let large = phone.deckGrid(for: .large)
        #expect(large.columns == 3)
        #expect(large.keySize > phone.deckGrid.keySize)
        #expect(large.keySize == large.keySize.rounded(.down))
        let wide = LayoutMetrics(width: 1366, height: 1024)
        #expect(wide.deckGrid(for: .large) == LayoutMetrics.deckColumnGrid)
    }

    @Test("A narrow pane is the deck column: 3 keys of 96 at 336 pt")
    func paneGrid() {
        #expect(DeckGrid.pane(width: 336, height: 900, band: .standard) == LayoutMetrics.deckColumnGrid)
        #expect(DeckGrid.pane(width: 336, height: 900, band: .standard).keySize == 96)
        #expect(DeckGrid.pane(width: 402, height: 700, band: .standard).columns == 4)
        #expect(DeckGrid.pane(width: 700, height: 900, band: .standard).columns == 6)
    }
}

@Suite("Deck editor changes")
struct DeckEditingTests {
    @Test("Pages: add, no second Home or app page, rename, delete clears the pin, Home stays")
    func pages() throws {
        var doc = deck()
        let added = doc.addPage(title: "  Writing  ")
        let id = try #require(added)
        #expect(doc.page(id: id)?.title == "Writing")
        let secondHome = doc.addPage(title: "Home 2", kind: .home)
        let secondSafari = doc.addPage(title: "Safari", kind: .app(bundleID: safari))
        #expect(secondHome == nil)
        #expect(secondSafari == nil)
        doc.renamePage(id: id, to: "Notes")
        #expect(doc.page(id: id)?.title == "Notes")
        doc.renamePage(id: id, to: "   ")
        #expect(doc.page(id: id)?.title == "Notes")
        doc.togglePin(pageID: id)
        #expect(doc.pinnedPageID == id)
        doc.deletePage(id: id)
        #expect(doc.page(id: id) == nil)
        #expect(doc.pinnedPageID == nil)
        doc.deletePage(id: "home")
        #expect(doc.page(id: "home") != nil)
        #expect(DeckValidation.isValid(doc))
    }

    @Test("Keys: add, update, duplicate, remove, and the page limit")
    func keys() throws {
        var doc = deck()
        let key = DeckKey.draft(for: .menuCommand(bundleID: safari, path: ["File", "New Private Window"]))
        #expect(key.label == "New Private Window")
        let didAdd = doc.addKey(key, toPage: "home")
        #expect(didAdd)
        var edited = key
        edited.appearance.label = "Private"
        doc.updateKey(edited, onPage: "home")
        #expect(doc.page(id: "home")?.keys.last?.label == "Private")
        let duplicated = doc.duplicateKey(id: key.id, onPage: "home")
        let copy = try #require(duplicated)
        #expect(doc.page(id: "home")?.keys.map(\.id) == ["k.mission", key.id, copy])
        doc.removeKey(id: key.id, fromPage: "home")
        #expect(doc.page(id: "home")?.keys.map(\.id) == ["k.mission", copy])
        for _ in 0..<DeckValidation.maxKeysPerPage { doc.addKey(DeckKey.draft(for: .media(key: .next)), toPage: "home") }
        #expect(doc.page(id: "home")?.keys.count == DeckValidation.maxKeysPerPage)
        #expect(DeckValidation.isValid(doc))
    }

    @Test("Editing a curated preset stores a copy and hides the preset")
    func editCurated() throws {
        var doc = deck()
        let preset = try #require(CuratedShortcuts.bindings(for: safari).first)
        var key = DeckKey(binding: preset)
        key.appearance.label = "Mine"
        doc.updateKey(key, onPage: safariPageID)
        let page = try #require(doc.page(id: safariPageID))
        #expect(page.hiddenCuratedIDs.contains(preset.id))
        #expect(page.keys.first?.label == "Mine")
        #expect(page.keys.first?.id != preset.id)
    }

    @Test("Drag to reorder moves stored keys; dropping on a preset moves to the front")
    func reorder() throws {
        var doc = deck()
        doc.moveKey(id: "k.a", onto: "k.c", onPage: safariPageID)
        #expect(doc.page(id: safariPageID)?.keys.map(\.id) == ["k.b", "k.c", "k.a"])
        doc.moveKey(id: "k.a", onto: "k.b", onPage: safariPageID)
        #expect(doc.page(id: safariPageID)?.keys.map(\.id) == ["k.a", "k.b", "k.c"])
        let preset = try #require(CuratedShortcuts.bindings(for: safari).first)
        doc.moveKey(id: "k.c", onto: preset.id, onPage: safariPageID)
        #expect(doc.page(id: safariPageID)?.keys.map(\.id) == ["k.c", "k.a", "k.b"])
        doc.nudgeKey(id: "k.c", by: 1, onPage: safariPageID)
        #expect(doc.page(id: safariPageID)?.keys.map(\.id) == ["k.a", "k.c", "k.b"])
        doc.nudgeKey(id: "k.a", by: -1, onPage: safariPageID)
        #expect(doc.page(id: safariPageID)?.keys.map(\.id) == ["k.a", "k.c", "k.b"])
    }

    @Test("Every library kind's template and every draft key is storable")
    func draftsAreValid() {
        for kind in ActionKind.allCases {
            let action = kind.template(frontBundleID: safari)
            #expect(ActionKind(action) == kind)
            var key = DeckKey.draft(for: action) { _ in "Safari" }
            if kind == .macShortcut {
                // An empty Shortcut name isn't storable; the inspector asks for one.
                #expect(!DeckValidation.keyIssues(key).isEmpty)
                key.action = .macShortcut(name: "Tidy Desktop")
            }
            #expect(DeckValidation.keyIssues(key).isEmpty, "\(kind)")
        }
    }

    @Test("Converting between kinds keeps the app and the keys")
    func convert() {
        let action = Action.appShortcut(bundleID: safari, keys: ["cmd", "t"])
        #expect(action.converted(to: .shortcut, frontBundleID: nil) == .shortcut(keys: ["cmd", "t"]))
        #expect(action.converted(to: .launchApp, frontBundleID: nil) == .launchApp(bundleID: safari))
        #expect(action.converted(to: .appShortcut, frontBundleID: nil) == action)
    }

    @Test("Chords build in the Mac's modifier order and split back")
    func chords() {
        #expect(ChordParsing.chord(modifiers: ["shift", "cmd"], key: " T ") == ["cmd", "shift", "t"])
        #expect(ChordParsing.chord(modifiers: ["cmd"], key: "") == nil)
        let split = ChordParsing.split(["command", "alt", "f5"])
        #expect(split.modifiers == ["cmd", "option"])
        #expect(split.key == "f5")
    }
}

@Suite("Deck undo")
struct DeckUndoTests {
    @Test("Undo and redo walk the snapshots; a new change clears redo")
    func undoRedo() {
        var history = DeckUndoHistory<Int>(limit: 3)
        var state = 0
        for next in 1...4 {
            history.record(state)
            state = next
        }
        #expect(history.undoCount == 3)
        state = history.undo(current: state) ?? state
        #expect(state == 3)
        state = history.undo(current: state) ?? state
        #expect(state == 2)
        #expect(history.canRedo)
        state = history.redo(current: state) ?? state
        #expect(state == 3)
        history.record(state)
        state = 9
        #expect(!history.canRedo)
        history.record(state)
        history.record(state)
        #expect(history.undoCount == 3)
        history.reset()
        #expect(!history.canUndo)
        #expect(history.undo(current: 1) == nil)
    }

    @Test("Undo restores a deleted key")
    func undoDelete() {
        var history = DeckUndoHistory<DeckDocument>()
        var doc = deck()
        history.record(doc)
        doc.removeKey(id: "k.b", fromPage: safariPageID)
        #expect(doc.page(id: safariPageID)?.keys.count == 2)
        doc = history.undo(current: doc) ?? doc
        #expect(doc.page(id: safariPageID)?.keys.map(\.id) == ["k.a", "k.b", "k.c"])
    }
}

@Suite("Action library")
struct ActionLibraryTests {
    @Test("The library lists the front app's presets, Mac actions and media keys")
    func sections() {
        let sections = ActionLibrary.sections(frontBundleID: safari, frontAppName: "Safari")
        #expect(sections.map(\.id) == ["app", "mac", "media"])
        #expect(sections[0].title == "Safari")
        #expect(sections[1].presets.count == SystemMacro.allCases.count)
        #expect(ActionLibrary.sections(frontBundleID: nil, frontAppName: nil).map(\.id) == ["mac", "media"])
        let filtered = ActionLibrary.filter(sections, query: "mission")
        #expect(filtered.map(\.id) == ["mac"])
        #expect(filtered[0].presets.map(\.title) == ["Mission Control"])
    }

    @Test("Every storable action kind is in the library")
    func everyKind() {
        let kinds = Set(ActionKind.allCases.map { $0.template(frontBundleID: nil).kindName })
        #expect(kinds == ["shortcut", "appShortcut", "menuCommand", "launchApp", "system", "media", "macShortcut", "sequence"])
        #expect(ActionKind(.contextAction(id: "x")) == nil)
        #expect(ActionKind.allCases.allSatisfy { PixelGlyphs.named($0.glyphName) != nil })
    }
}

@Suite("Pixel glyph editor")
struct PixelGlyphEditorTests {
    @Test("Toggle, accent, mirror, shift and clear")
    func operations() {
        var glyph = PixelGlyphData.blank(size: 8)
        glyph = glyph.toggling(x: 1, y: 2)
        #expect(glyph.isOn(x: 1, y: 2))
        glyph = glyph.togglingAccent(x: 3, y: 3)
        #expect(glyph.accent == GlyphDot(x: 3, y: 3))
        #expect(glyph.isWellFormed)
        glyph = glyph.toggling(x: 3, y: 3)
        #expect(glyph.accent == nil)
        glyph = glyph.togglingAccent(x: 1, y: 2)
        let mirrored = glyph.mirrored
        #expect(mirrored.isOn(x: 6, y: 2))
        #expect(mirrored.accent == GlyphDot(x: 6, y: 2))
        let shifted = glyph.shifted(dx: 1, dy: 0)
        #expect(shifted.isOn(x: 2, y: 2))
        #expect(shifted.accent == GlyphDot(x: 2, y: 2))
        #expect(glyph.shifted(dx: -2, dy: 0).litCount == 0)
        #expect(glyph.cleared.litCount == 0)
        #expect(glyph.litCount == 1)
    }

    @Test("Starting from a set glyph crops it to 8 × 8")
    func fromSetGlyph() {
        let glyph = PixelGlyphData(bitmap: PixelGlyphs.build)
        #expect(glyph.size == 8)
        #expect(glyph.isWellFormed)
        #expect(glyph.litCount > 0)
    }
}
