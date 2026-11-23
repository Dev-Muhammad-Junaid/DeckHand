//
//  DeckEditing.swift
//  PixelHandCore
//
//  The deck editor's changes (UX-020, D3) as plain mutations on
//  `DeckDocument`, so add / edit / remove / reorder and page changes are
//  tested on Linux. `DeckStore.update(_:)` applies them and repairs the
//  result; `DeckUndoHistory` keeps the snapshots for Undo.
//

import Foundation

public enum DeckIDs {
    /// A new key ID, unique enough for one deck.
    public static func newKeyID() -> String { "key." + UUID().uuidString.lowercased() }
    /// A new page ID.
    public static func newPageID() -> String { "page." + UUID().uuidString.lowercased() }
}

extension DeckDocument {
    // MARK: Pages

    /// Adds a page and returns its ID, or `nil` when the deck is full or
    /// the page would be a second Home, Context, Shortcuts or app page.
    @discardableResult
    public mutating func addPage(title: String, kind: DeckPageKind = .custom, id: String = DeckIDs.newPageID()) -> String? {
        guard pages.count < DeckValidation.maxPages else { return nil }
        switch kind {
        case .home, .context, .shortcuts:
            if pages.contains(where: { $0.kind == kind }) { return nil }
        case let .app(bundleID):
            if appPage(for: bundleID) != nil { return nil }
        case .custom:
            break
        }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        pages.append(DeckPage(id: id, title: String(trimmed.prefix(DeckValidation.maxTitleLength)), kind: kind, keys: []))
        return id
    }

    public mutating func renamePage(id: String, to title: String) {
        guard let index = pageIndex(id: id) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || pages[index].appBundleID != nil else { return }
        pages[index].title = String(trimmed.prefix(DeckValidation.maxTitleLength))
    }

    /// Deletes a page (never Home). A pin on it goes too.
    public mutating func deletePage(id: String) {
        guard let index = pageIndex(id: id), pages[index].isDeletable else { return }
        pages.remove(at: index)
        if pinnedPageID == id { pinnedPageID = nil }
    }

    /// Pins `id` (stops following the front app), or unpins when it is
    /// already pinned.
    public mutating func togglePin(pageID id: String) {
        pinnedPageID = pinnedPageID == id ? nil : (page(id: id) != nil ? id : nil)
    }

    // MARK: Keys

    /// Appends `key` to the page. Returns `false` when the page is full or
    /// missing.
    @discardableResult
    public mutating func addKey(_ key: DeckKey, toPage pageID: String) -> Bool {
        guard let index = pageIndex(id: pageID), pages[index].keys.count < DeckValidation.maxKeysPerPage else { return false }
        var key = key
        if pages[index].keys.contains(where: { $0.id == key.id }) { key.id = DeckIDs.newKeyID() }
        pages[index].keys.append(key)
        return true
    }

    /// Replaces the stored key with `key.id` on the page. A curated preset
    /// that is edited becomes a stored key in its place and the preset is
    /// hidden, so the edit sticks.
    public mutating func updateKey(_ key: DeckKey, onPage pageID: String) {
        guard let index = pageIndex(id: pageID) else { return }
        if let keyIndex = pages[index].keys.firstIndex(where: { $0.id == key.id }) {
            pages[index].keys[keyIndex] = key
        } else if isCurated(keyID: key.id, onPageAt: index) {
            if !pages[index].hiddenCuratedIDs.contains(key.id) { pages[index].hiddenCuratedIDs.append(key.id) }
            var copy = key
            copy.id = DeckIDs.newKeyID()
            pages[index].keys.insert(copy, at: 0)
        }
    }

    /// Removes a key: a stored key is deleted, a curated preset is hidden.
    public mutating func removeKey(id: String, fromPage pageID: String) {
        guard let index = pageIndex(id: pageID) else { return }
        if let keyIndex = pages[index].keys.firstIndex(where: { $0.id == id }) {
            pages[index].keys.remove(at: keyIndex)
        } else if isCurated(keyID: id, onPageAt: index), !pages[index].hiddenCuratedIDs.contains(id) {
            pages[index].hiddenCuratedIDs.append(id)
        }
    }

    /// A copy of the key after it, with a new ID.
    @discardableResult
    public mutating func duplicateKey(id: String, onPage pageID: String, frontBundleID: String? = nil) -> String? {
        guard let index = pageIndex(id: pageID), pages[index].keys.count < DeckValidation.maxKeysPerPage,
              let shown = shownKeys(on: pages[index], frontBundleID: frontBundleID).first(where: { $0.id == id })
        else { return nil }
        var copy = shown.key
        copy.id = DeckIDs.newKeyID()
        if let keyIndex = pages[index].keys.firstIndex(where: { $0.id == id }) {
            pages[index].keys.insert(copy, at: keyIndex + 1)
        } else {
            pages[index].keys.append(copy)
        }
        return copy.id
    }

    /// Moves the stored key `id` to where `targetID` is (drag to reorder).
    /// Curated presets don't move; dropping on one moves the key to the
    /// front of the stored keys.
    public mutating func moveKey(id: String, onto targetID: String, onPage pageID: String) {
        guard id != targetID, let index = pageIndex(id: pageID),
              let from = pages[index].keys.firstIndex(where: { $0.id == id }) else { return }
        let key = pages[index].keys.remove(at: from)
        if let to = pages[index].keys.firstIndex(where: { $0.id == targetID }) {
            // Dropping on a later key puts this one after it.
            pages[index].keys.insert(key, at: from <= to ? to + 1 : to)
        } else {
            pages[index].keys.insert(key, at: 0)
        }
    }

    /// Moves a stored key one place earlier or later (VoiceOver actions).
    public mutating func nudgeKey(id: String, by offset: Int, onPage pageID: String) {
        guard let index = pageIndex(id: pageID),
              let from = pages[index].keys.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(from + offset, 0), pages[index].keys.count - 1)
        guard to != from else { return }
        let key = pages[index].keys.remove(at: from)
        pages[index].keys.insert(key, at: to)
    }

    private func isCurated(keyID: String, onPageAt index: Int) -> Bool {
        guard let bundleID = pages[index].appBundleID else { return false }
        return CuratedShortcuts.bindings(for: bundleID).contains { $0.id == keyID }
    }
}

extension DeckKey {
    /// A new key for `action` with a sensible label and glyph, for the
    /// action library. `appName` names a bundle ID when known.
    public static func draft(for action: Action, label: String? = nil, appName: (String) -> String? = { _ in nil }) -> DeckKey {
        let title: String
        var glyph: KeyGlyph?
        switch action {
        case let .shortcut(keys):
            title = ChordText.glyphs(keys)
        case let .appShortcut(bundleID, keys):
            title = "\(ChordText.glyphs(keys)) in \(appName(bundleID) ?? "app")"
        case let .launchApp(bundleID):
            title = appName(bundleID) ?? "Open App"
            glyph = .appIcon(bundleID: bundleID)
        case let .system(macro):
            title = macro.title
        case let .media(key):
            title = key.title
        case .contextAction:
            title = "Dialog Button"
        case let .menuCommand(_, path):
            title = path.last?.trimmingCharacters(in: .whitespaces) ?? "Menu Item"
        case let .macShortcut(name):
            title = name.isEmpty ? "Shortcut" : name
        case .sequence:
            title = "Macro"
        }
        if glyph == nil { glyph = .pixel(id: DeckGlyphs.glyph(for: action).name) }
        let text = (label ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
        return DeckKey(
            id: DeckIDs.newKeyID(),
            appearance: KeyAppearance(label: String((text.isEmpty ? "Key" : text).prefix(DeckValidation.maxLabelLength)), glyph: glyph),
            action: action
        )
    }
}

// MARK: - Undo

/// Snapshots for the editor's Undo / Redo: `record` before each change,
/// `undo` hands back the state to restore. Bounded (`limit`), oldest
/// dropped first. A new change clears Redo.
public struct DeckUndoHistory<State: Equatable & Sendable>: Sendable {
    public let limit: Int
    private var past: [State] = []
    private var future: [State] = []

    public init(limit: Int = 50) {
        self.limit = max(1, limit)
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public var undoCount: Int { past.count }

    /// Call with the state *before* a change. Repeats of the last snapshot
    /// are ignored, so a no-op change doesn't cost an Undo.
    public mutating func record(_ before: State) {
        if past.last == before { return }
        past.append(before)
        if past.count > limit { past.removeFirst(past.count - limit) }
        future.removeAll()
    }

    /// The state to go back to, given the current one; `nil` when there is
    /// nothing to undo.
    public mutating func undo(current: State) -> State? {
        guard let previous = past.popLast() else { return nil }
        future.append(current)
        return previous
    }

    public mutating func redo(current: State) -> State? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        return next
    }

    public mutating func reset() {
        past.removeAll()
        future.removeAll()
    }
}
