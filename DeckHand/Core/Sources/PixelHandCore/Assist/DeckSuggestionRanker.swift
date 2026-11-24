//
//  DeckSuggestionRanker.swift
//  PixelHandCore
//
//  "Suggest a deck" (UX-021, D7): which of the front app's menu shortcuts
//  to offer as ghost keys under the deck. The Mac walks the app's real
//  menus (`deck.requestAppMenuShortcuts`, S9-hardened); this ranks what
//  came back.
//
//  The deterministic ranking is the feature: it always runs, and it is
//  what a device without Apple Intelligence shows. An on-device model
//  (Foundation Models, on the remote) may reorder the candidates, but only
//  by picking from them (`applyingModelPicks`), so it can never invent a
//  key. No cloud (DECISIONS.md).
//
//  Signals, in order of weight:
//  - well-known commands for decks (Build, Run, New Tab, Show Sidebar…)
//    score up; generic text editing (Copy, Paste, Undo…) scores down, the
//    keyboard already does those; Quit, Hide and Minimize never show;
//  - menu frequency: the menus the user's own keys for this app came from,
//    then a prior per menu (the app's own menus over File / Edit / View
//    over Window / Help / the app menu);
//  - shortcut weight: chords with more modifiers are harder to remember,
//    so a key helps more.
//  Candidates already on the page (same ID, same name and chord, or same
//  chord) are dropped, and the list is capped (`maxSuggestions`).
//  Spec: `04-Interaction-Model.md` (Apple Intelligence: suggested decks).
//

import Foundation

/// One ghost key the deck offers.
public struct DeckSuggestion: Sendable, Equatable, Identifiable {
    public let binding: AppShortcutBinding
    /// Higher is better. Only meaningful within one ranking.
    public let score: Double

    public init(binding: AppShortcutBinding, score: Double) {
        self.binding = binding
        self.score = score
    }

    public var id: String { binding.id }

    /// The key that "Keep" stores: an app shortcut labelled with the menu
    /// item's own name ("Show Minimap", not "Editor › Show Minimap"), its
    /// menu kept as the key's category.
    public var key: DeckKey {
        var key = DeckKey(binding: binding)
        let label = binding.shortDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        key.appearance.label = String((label.isEmpty ? binding.displayName : label).prefix(DeckValidation.maxLabelLength))
        return key
    }
}

public enum DeckSuggestionRanker {
    /// At most this many ghost keys (spec: max 24).
    public static let maxSuggestions = 24

    // MARK: Ranking

    /// The suggestions for `bundleID` from the Mac's menu shortcuts, best
    /// first, without what `existing` (the keys the page already shows)
    /// covers, capped at `limit`. Deterministic: ties keep menu order.
    public static func rank(
        _ discovered: [AppShortcutBinding],
        bundleID: String,
        existing: [DeckKey],
        limit: Int = maxSuggestions
    ) -> [DeckSuggestion] {
        let menuCounts = menuFrequency(of: existing)
        let scored = candidates(discovered, bundleID: bundleID, existing: existing)
            .enumerated()
            .map { index, binding in (index, DeckSuggestion(binding: binding, score: score(binding, menuCounts: menuCounts))) }
        return scored
            .sorted { $0.1.score != $1.1.score ? $0.1.score > $1.1.score : $0.0 < $1.0 }
            .prefix(max(0, limit))
            .map(\.1)
    }

    /// What may be suggested at all: this app's bindings that make a valid
    /// key, aren't excluded commands, aren't on the page already, and
    /// aren't repeats of each other. Menu order is kept.
    public static func candidates(
        _ discovered: [AppShortcutBinding],
        bundleID: String,
        existing: [DeckKey]
    ) -> [AppShortcutBinding] {
        var seenIDs = Set(existing.map(\.id))
        var seenNames = Set(existing.map { nameFingerprint(label: $0.label, keys: chordKeys(of: $0.action)) })
        var seenChords = Set(existing.compactMap { key -> String? in
            guard let keys = chordKeys(of: key.action) else { return nil }
            return chordFingerprint(keys)
        })
        var out: [AppShortcutBinding] = []
        for binding in discovered where binding.bundleID == bundleID {
            guard !binding.keys.isEmpty, !isExcluded(binding) else { continue }
            let chord = chordFingerprint(binding.keys)
            let name = nameFingerprint(label: binding.shortDisplayName, keys: binding.keys)
            guard !seenIDs.contains(binding.id), !seenNames.contains(name), !seenChords.contains(chord) else { continue }
            guard DeckValidation.keyIssues(DeckSuggestion(binding: binding, score: 0).key).isEmpty else { continue }
            seenIDs.insert(binding.id)
            seenNames.insert(name)
            seenChords.insert(chord)
            out.append(binding)
        }
        return out
    }

    /// The score of one candidate; see the file header for the signals.
    public static func score(_ binding: AppShortcutBinding, menuCounts: [String: Int] = [:]) -> Double {
        var score = 0.0
        let title = normalizedTitle(binding.shortDisplayName)
        if let boost = wellKnownCommands[title] {
            score += boost
        } else if wellKnownWords.contains(where: { title.contains($0) }) {
            score += 1.5
        }
        if genericEditing.contains(title) { score -= 3 }

        let menu = normalizedTitle(binding.category ?? "")
        // Menu frequency: menus the user already keeps keys from.
        if let count = menuCounts[menu], count > 0 { score += min(2.5, 1 + Double(count) * 0.5) }
        score += menuPrior(menu)

        // Shortcut weight: modifiers beyond ⌘ are harder to remember.
        let modifiers = binding.keys.filter { modifierNames.contains($0.lowercased()) }.count
        score += Double(max(0, modifiers - 1)) * 0.4
        // Function and arrow keys without letters are usually navigation.
        if binding.keys.contains(where: { ["up", "down", "left", "right", "pageup", "pagedown", "home", "end"].contains($0.lowercased()) }) {
            score -= 0.5
        }
        return score
    }

    /// How many of `keys` came from each menu (normalised menu name).
    public static func menuFrequency(of keys: [DeckKey]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for key in keys {
            guard let menu = key.category, !menu.isEmpty else { continue }
            counts[normalizedTitle(menu), default: 0] += 1
        }
        return counts
    }

    // MARK: Model picks

    /// The ranking after an on-device model picked from `ranked`: the
    /// model's picks first, in its order, keeping only indices that exist
    /// (0-based into `ranked`) and each once, then the rest of `ranked` in
    /// its own order, capped at `limit`. A model can reorder, never add.
    public static func applyingModelPicks(_ picks: [Int], to ranked: [DeckSuggestion], limit: Int = maxSuggestions) -> [DeckSuggestion] {
        var used = Set<Int>()
        var out: [DeckSuggestion] = []
        for index in picks where ranked.indices.contains(index) && !used.contains(index) {
            used.insert(index)
            out.append(ranked[index])
        }
        for (index, suggestion) in ranked.enumerated() where !used.contains(index) {
            out.append(suggestion)
        }
        return Array(out.prefix(max(0, limit)))
    }

    /// One line per candidate for a model prompt: "3. Product › Build (⌘B)".
    /// The number is the index `applyingModelPicks` takes.
    public static func promptLines(for ranked: [DeckSuggestion]) -> [String] {
        ranked.enumerated().map { index, suggestion in
            let chord = ChordText.glyphs(suggestion.binding.keys)
            return "\(index). \(suggestion.binding.displayName)" + (chord.isEmpty ? "" : " (\(chord))")
        }
    }

    // MARK: Tables

    static let modifierNames: Set<String> = ["cmd", "command", "shift", "option", "alt", "ctrl", "control", "fn"]

    /// Commands people put on a deck, by normalised title.
    static let wellKnownCommands: [String: Double] = [
        // Developer tools
        "build": 4, "run": 4, "test": 3.5, "stop": 3, "clean build folder": 3, "analyze": 2,
        "show minimap": 2.5, "open quickly": 3.5, "find in project": 3, "jump to definition": 2.5,
        "show debug area": 2.5, "show navigator": 2, "show inspectors": 2, "scheme": 2,
        "discard changes": 2, "commit": 3, "command palette": 3.5, "toggle terminal": 3,
        // Browsers
        "new tab": 3.5, "new private window": 3, "reload page": 3.5, "reload this page": 3.5,
        "show all tabs": 3, "show tab overview": 3, "reopen last closed tab": 3.5, "add bookmark": 2.5,
        "show reader": 2.5, "show history": 2, "show downloads": 2.5, "show sidebar": 3,
        "show web inspector": 2.5, "developer tools": 2.5,
        // Finder and documents
        "new folder": 3.5, "new finder window": 3, "get info": 3, "go to folder": 3.5,
        "show path bar": 2, "show preview": 2, "move to trash": 2.5, "duplicate": 2.5,
        "connect to server": 2, "airdrop": 2, "downloads": 2, "applications": 2, "home": 1.5,
        "export": 2.5, "export as pdf": 3, "share": 2,
        // Common app actions
        "new": 2.5, "new window": 2.5, "new document": 2.5, "open": 2, "save": 2, "save as": 1.5,
        "find": 2, "print": 1.5, "close tab": 2, "enter full screen": 2.5, "toggle full screen": 2.5,
        "zoom in": 2, "zoom out": 2, "actual size": 1.5,
        "send": 3, "reply": 3, "reply all": 2.5, "forward": 2.5, "new message": 3, "mark as read": 2,
        "play": 2.5, "pause": 2.5, "next": 2, "previous": 2, "mute": 2,
    ]

    /// Words that make an unlisted command likely deck-worthy.
    static let wellKnownWords: [String] = ["toggle", "show", "hide sidebar", "sidebar", "inspector", "panel", "terminal", "console", "debug", "preview"]

    /// Text editing the keyboard already covers.
    static let genericEditing: Set<String> = [
        "copy", "paste", "cut", "select all", "undo", "redo", "delete", "paste and match style",
        "bold", "italic", "underline", "find next", "find previous", "use selection for find",
        "jump to selection", "spelling and grammar", "check spelling", "emoji & symbols", "start dictation",
    ]

    /// Never suggested: they end the app or hide it, or do nothing useful
    /// from a key.
    static let excluded: Set<String> = [
        "quit", "hide", "hide others", "minimize", "minimise", "close window", "close all",
        "force quit", "log out", "emoji & symbols", "start dictation", "show all",
    ]

    static func isExcluded(_ binding: AppShortcutBinding) -> Bool {
        let title = normalizedTitle(binding.shortDisplayName)
        if excluded.contains(title) { return true }
        // "Quit Xcode", "Hide Safari": the app menu's names carry the app.
        if title.hasPrefix("quit ") { return true }
        if title.hasPrefix("hide ") {
            let panes = ["sidebar", "toolbar", "panel", "inspector", "navigator", "debug", "tab bar", "status bar", "path bar", "preview"]
            return !panes.contains { title.contains($0) }
        }
        return false
    }

    /// The prior per top-level menu (normalised). The app's own menus
    /// (Product, Debug, History, Go…) score highest because they hold what
    /// is special about the app.
    static func menuPrior(_ menu: String) -> Double {
        switch menu {
        case "": return 0
        case "window", "help": return -1.5
        case "edit", "format": return -0.5
        case "file", "view": return 0.5
        default: return 1
        }
    }

    static func normalizedTitle(_ title: String) -> String {
        title.replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func chordKeys(of action: Action) -> [String]? {
        switch action {
        case let .shortcut(keys), let .appShortcut(_, keys): keys
        default: nil
        }
    }

    /// A chord with its modifiers in a fixed order, so ⇧⌘K and ⌘⇧K match.
    static func chordFingerprint(_ keys: [String]) -> String {
        keys.map { $0.lowercased() }.sorted().joined(separator: "+")
    }

    static func nameFingerprint(label: String, keys: [String]?) -> String {
        normalizedTitle(label) + "|" + (keys.map(chordFingerprint) ?? "")
    }
}

// MARK: - Copy

public enum DeckSuggestionCopy {
    /// The panel's title: "3 suggestions from Xcode’s menus".
    public static func title(count: Int, appName: String) -> String {
        "\(count) \(count == 1 ? "suggestion" : "suggestions") from \(appName)’s menus"
    }

    /// While the Mac reads the menus.
    public static func reading(appName: String) -> String {
        "Reading \(appName)’s menus…"
    }

    /// When every menu shortcut is already on the deck, or there are none.
    public static func nothingNew(appName: String) -> String {
        "No new keys in \(appName)’s menus"
    }

    /// When the Mac didn't answer in time.
    public static let noAnswer = "The Mac didn’t send the menus. Try again."

    /// After Keep: "Kept 3 keys".
    public static func kept(count: Int) -> String {
        "Kept \(count) \(count == 1 ? "key" : "keys")"
    }
}

// MARK: - Keep

extension DeckDocument {
    /// Stores `keys` on `bundleID`'s app page (made when missing, titled
    /// `title`), skipping keys already there and stopping when the page is
    /// full. Returns how many were added. One call is one Undo step for the
    /// editor (`DeckSurfaceModel.edit`).
    @discardableResult
    public mutating func keepSuggestions(_ keys: [DeckKey], forApp bundleID: String, title: String? = nil) -> Int {
        guard !keys.isEmpty, let index = ensureAppPage(for: bundleID, title: title) else { return 0 }
        var added = 0
        var usedIDs = Set(pages.flatMap { $0.keys.map(\.id) })
        for var key in keys {
            guard pages[index].keys.count < DeckValidation.maxKeysPerPage else { break }
            guard !pages[index].keys.contains(where: { $0.id == key.id }),
                  DeckValidation.keyIssues(key).isEmpty else { continue }
            // Key IDs are unique across the deck; the same menu item on
            // another page keeps its ID there.
            if usedIDs.contains(key.id) { key.id = DeckIDs.newKeyID() }
            usedIDs.insert(key.id)
            pages[index].keys.append(key)
            added += 1
        }
        return added
    }
}

extension DeckDocument {
    /// The keys suggestions for `bundleID` must not repeat: what its app
    /// page shows (curated presets and stored keys), or the curated presets
    /// alone when it has no page yet.
    public func existingKeys(forApp bundleID: String) -> [DeckKey] {
        if let page = appPage(for: bundleID) {
            return shownKeys(on: page, frontBundleID: nil).map(\.key)
        }
        return CuratedShortcuts.bindings(for: bundleID).map(DeckKey.init(binding:))
    }
}
