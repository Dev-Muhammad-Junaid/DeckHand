//
//  DeckDocument+Chips.swift
//  PixelHandCore
//
//  Today's chips and shortcut sheet, read and edited through the deck: an
//  app's chips are its app page's `appShortcut` keys plus the curated
//  presets not hidden on that page. `ShortcutStore` (iOS) is a thin
//  adapter over these, so the chip views keep working unchanged until the
//  Deck 2 UI replaces them.
//

import Foundation

extension DeckKey {
    /// A key for a chip binding (custom or imported), keeping its ID, so
    /// re-imports stay idempotent.
    public init(binding: AppShortcutBinding) {
        self.init(
            id: binding.id,
            appearance: KeyAppearance(label: binding.displayName, glyph: .symbol(name: binding.sfSymbol)),
            action: .appShortcut(bundleID: binding.bundleID, keys: binding.keys),
            category: binding.category
        )
    }

    /// The chip binding this key shows as on `bundleID`'s page, or `nil`
    /// for keys a chip can't show (other actions, another app's shortcut).
    public func chipBinding(for bundleID: String) -> AppShortcutBinding? {
        guard case let .appShortcut(keyBundleID, keys) = action, keyBundleID == bundleID else { return nil }
        let symbol: String
        if case let .symbol(name)? = appearance.glyph { symbol = name } else { symbol = "keyboard" }
        return AppShortcutBinding(
            id: id,
            bundleID: bundleID,
            displayName: appearance.label,
            keys: keys,
            sfSymbol: symbol,
            isCurated: false,
            category: category
        )
    }
}

extension DeckDocument {
    // MARK: Reads

    /// The chips for `bundleID`: curated presets not hidden, then the app
    /// page's shortcut keys in order.
    public func chipBindings(for bundleID: String) -> [AppShortcutBinding] {
        let page = appPage(for: bundleID)
        let hidden = Set(page?.hiddenCuratedIDs ?? [])
        let curated = CuratedShortcuts.bindings(for: bundleID).filter { !hidden.contains($0.id) }
        let custom = page?.keys.compactMap { $0.chipBinding(for: bundleID) } ?? []
        return curated + custom
    }

    /// Custom and imported chip bindings per app (no curated presets).
    public var customChipBindings: [String: [AppShortcutBinding]] {
        var out: [String: [AppShortcutBinding]] = [:]
        for page in pages {
            guard let bundleID = page.appBundleID else { continue }
            let bindings = page.keys.compactMap { $0.chipBinding(for: bundleID) }
            if !bindings.isEmpty { out[bundleID] = bindings }
        }
        return out
    }

    /// Hidden curated preset IDs per app.
    public var hiddenCuratedIDsByApp: [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        for page in pages {
            guard let bundleID = page.appBundleID, !page.hiddenCuratedIDs.isEmpty else { continue }
            out[bundleID] = Set(page.hiddenCuratedIDs)
        }
        return out
    }

    // MARK: Writes

    /// The index of `bundleID`'s app page, making one (titled `title`, or
    /// the bundle ID's last part) at the end when it has none and the deck
    /// has room. `nil` when the deck is full.
    public mutating func ensureAppPage(for bundleID: String, title: String? = nil) -> Int? {
        if let index = pages.firstIndex(where: { $0.appBundleID == bundleID }) { return index }
        guard pages.count < DeckValidation.maxPages, ActionValidation.isBundleID(bundleID) else { return nil }
        let fallback = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        pages.append(DeckPage(
            id: uniquePageID(DeckPage.appPageID(for: bundleID)),
            title: String((title ?? fallback).prefix(DeckValidation.maxTitleLength)),
            kind: .app(bundleID: bundleID),
            keys: []
        ))
        return pages.count - 1
    }

    /// Adds a custom chip. Returns `false` when the page is full, the
    /// binding is invalid, or its ID is taken.
    @discardableResult
    public mutating func addChip(_ binding: AppShortcutBinding) -> Bool {
        let key = DeckKey(binding: binding)
        guard DeckValidation.keyIssues(key).isEmpty, !containsKey(id: key.id),
              let index = ensureAppPage(for: binding.bundleID),
              pages[index].keys.count < DeckValidation.maxKeysPerPage else { return false }
        pages[index].keys.append(key)
        return true
    }

    /// Replaces the custom chip with `binding.id`, keeping the key's other
    /// settings (confirm, first-row pin, tint).
    @discardableResult
    public mutating func updateChip(_ binding: AppShortcutBinding) -> Bool {
        guard let p = pages.firstIndex(where: { $0.appBundleID == binding.bundleID }),
              let k = pages[p].keys.firstIndex(where: { $0.id == binding.id }) else { return false }
        var key = pages[p].keys[k]
        let fresh = DeckKey(binding: binding)
        key.appearance.label = fresh.appearance.label
        key.appearance.glyph = fresh.appearance.glyph
        key.action = fresh.action
        key.category = fresh.category
        guard DeckValidation.keyIssues(key).isEmpty else { return false }
        pages[p].keys[k] = key
        return true
    }

    /// Deletes a custom chip, or hides a curated preset on its app page.
    public mutating func deleteChip(_ binding: AppShortcutBinding) {
        if binding.isCurated {
            guard let index = ensureAppPage(for: binding.bundleID),
                  !pages[index].hiddenCuratedIDs.contains(binding.id),
                  pages[index].hiddenCuratedIDs.count < DeckValidation.maxHiddenCuratedPerPage else { return }
            pages[index].hiddenCuratedIDs.append(binding.id)
        } else if let p = pages.firstIndex(where: { $0.appBundleID == binding.bundleID }) {
            pages[p].keys.removeAll { $0.id == binding.id }
        }
    }

    /// Shows every curated preset for `bundleID` again.
    public mutating func restoreCurated(for bundleID: String) {
        guard let p = pages.firstIndex(where: { $0.appBundleID == bundleID }) else { return }
        pages[p].hiddenCuratedIDs = []
    }

    /// Merges menu-imported bindings into `bundleID`'s page. Skips one
    /// whose ID is already there, or whose name and keys match a chip
    /// already shown (custom or curated), so re-importing is idempotent.
    /// Returns how many were added; stops when the page is full.
    @discardableResult
    public mutating func importChips(_ incoming: [AppShortcutBinding], for bundleID: String) -> Int {
        guard !incoming.isEmpty else { return 0 }
        func fingerprint(_ b: AppShortcutBinding) -> String {
            "\(b.displayName.lowercased())|\(b.keys.map { $0.lowercased() }.joined(separator: "+"))"
        }
        var seen = Set(chipBindings(for: bundleID).map(fingerprint))
        seen.formUnion(CuratedShortcuts.bindings(for: bundleID).map(fingerprint))
        var added = 0
        var pageIndex: Int?
        for binding in incoming where binding.bundleID == bundleID {
            let fp = fingerprint(binding)
            let key = DeckKey(binding: binding)
            guard !seen.contains(fp), !containsKey(id: key.id), DeckValidation.keyIssues(key).isEmpty else { continue }
            if pageIndex == nil { pageIndex = ensureAppPage(for: bundleID) }
            guard let p = pageIndex, pages[p].keys.count < DeckValidation.maxKeysPerPage else { break }
            seen.insert(fp)
            pages[p].keys.append(key)
            added += 1
        }
        return added
    }

    // MARK: Helpers

    public func containsKey(id: String) -> Bool {
        pages.contains { $0.keys.contains { $0.id == id } }
    }

    private func uniquePageID(_ base: String) -> String {
        guard page(id: base) != nil else { return base }
        var n = 2
        while page(id: "\(base).\(n)") != nil { n += 1 }
        return "\(base).\(n)"
    }
}
