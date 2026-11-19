//
//  ShortcutStore.swift
//  DeckHandiOS
//

import Combine
import Foundation

/// The chips' view of the deck: per-app shortcut bindings (curated presets
/// plus custom and imported ones, minus hidden presets) for the Quick
/// Actions bar and the app shortcuts sheet.
///
/// Since Deck 2 (D1) it stores nothing itself. It reads and edits the app
/// pages of `DeckStore`'s document (Core's `DeckDocument+Chips`), and the
/// data it used to keep in `UserDefaults` was migrated there on first
/// launch. Its API is unchanged, so the chip views work as before until the
/// Deck 2 UI replaces them.
@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    /// Custom and imported bindings per app.
    @Published private(set) var customBindings: [String: [AppShortcutBinding]] = [:]
    /// Hidden curated preset IDs per app.
    @Published private(set) var hiddenCuratedIDs: [String: Set<String>] = [:]

    private let deck: DeckStore
    private var observation: AnyCancellable?

    init(deck: DeckStore = .shared) {
        self.deck = deck
        refresh(from: deck.document)
        observation = deck.$document
            .dropFirst()
            .sink { [weak self] document in
                MainActor.assumeIsolated { self?.refresh(from: document) }
            }
    }

    private func refresh(from document: DeckDocument) {
        let custom = document.customChipBindings
        let hidden = document.hiddenCuratedIDsByApp
        if custom != customBindings { customBindings = custom }
        if hidden != hiddenCuratedIDs { hiddenCuratedIDs = hidden }
    }

    // MARK: - Reads

    /// All bindings (curated + custom minus hidden) to show for `bundleID`.
    /// Curated come first, then user-added in insertion order.
    func bindings(for bundleID: String) -> [AppShortcutBinding] {
        deck.document.chipBindings(for: bundleID)
    }

    /// Does this app have any visible shortcuts (curated or custom)?
    func hasShortcuts(for bundleID: String) -> Bool {
        !bindings(for: bundleID).isEmpty
    }

    // MARK: - Writes

    func addCustom(_ binding: AppShortcutBinding) {
        deck.update { $0.addChip(binding) }
    }

    func updateCustom(_ binding: AppShortcutBinding) {
        deck.update { $0.updateChip(binding) }
    }

    /// Deletes a custom binding; hides a curated one (curated are immutable so
    /// the user can always get them back by calling `restoreCurated`).
    func delete(_ binding: AppShortcutBinding) {
        deck.update { $0.deleteChip(binding) }
    }

    /// Re-reveals all curated bindings for `bundleID`.
    func restoreCurated(for bundleID: String) {
        deck.update { $0.restoreCurated(for: bundleID) }
    }

    /// Merges AX-discovered bindings into `bundleID`'s app page. Dedupe is
    /// by deterministic `id` (so re-importing is idempotent) *and* by
    /// display name + key combo (so an imported "File › New Tab ⌘T" doesn't
    /// stack on top of a curated "New Tab ⌘T").
    ///
    /// Returns the number of truly new bindings that were added.
    @discardableResult
    func importBindings(_ incoming: [AppShortcutBinding], for bundleID: String) -> Int {
        var added = 0
        deck.update { added = $0.importChips(incoming, for: bundleID) }
        return added
    }
}
